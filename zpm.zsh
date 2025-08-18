#!/usr/bin/env zsh

# ZPM - Modern Zsh Plugin Manager
# High-performance plugin manager with async operations, caching, and speed optimizations
# Author: Taylor K.
# Version: 1.0.0

# Global configuration
typeset -g ZPM_DIR="${ZPM_DIR:-${ZDOTDIR:-$HOME/.config/zsh}/.zpm}"
typeset -g ZPM_CACHE_DIR="${ZPM_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zpm}"
typeset -g ZPM_PLUGINS_DIR="${ZPM_PLUGINS_DIR:-${ZDOTDIR:-$HOME/.config/zsh}/plugins}"
typeset -g ZPM_CONFIG_FILE="$ZPM_DIR/config"
typeset -g ZPM_LOCK_FILE="$ZPM_DIR/.lock"
typeset -g ZPM_LOG_FILE="$ZPM_DIR/zpm.log"
typeset -g ZPM_MAX_JOBS=8
typeset -g ZPM_TIMEOUT=30
typeset -g ZPM_VERBOSE=0

# Internal state
typeset -gA ZPM_PLUGINS
typeset -gA ZPM_LOADED_PLUGINS
typeset -gA ZPM_PLUGIN_DEPS
typeset -ga ZPM_LOAD_ORDER
typeset -ga ZPM_ASYNC_JOBS
typeset -gA ZPM_JOB_STATUS
typeset -g ZPM_STATUS_PID
typeset -g ZPM_PROGRESS_FILE="$ZPM_CACHE_DIR/progress"

# Colors for output
typeset -gA ZPM_COLORS
ZPM_COLORS=(
    reset     $'\033[0m'
    bold      $'\033[1m'
    red       $'\033[31m'
    green     $'\033[32m'
    yellow    $'\033[33m'
    blue      $'\033[34m'
    magenta   $'\033[35m'
    cyan      $'\033[36m'
)

# Initialize ZPM
zpm::init() {
    local dirs=("$ZPM_DIR" "$ZPM_CACHE_DIR" "$ZPM_PLUGINS_DIR")
    
    for dir in $dirs; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
    
    [[ ! -f "$ZPM_CONFIG_FILE" ]] && touch "$ZPM_CONFIG_FILE"
    
    # Load configuration
    zpm::load_config
    
    # Setup signal handlers
    trap 'zpm::cleanup' EXIT INT TERM
    
    zpm::log "info" "ZPM initialized at $ZPM_DIR"
}

# Logging system
zpm::log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$ZPM_LOG_FILE"
    
    if [[ "$ZPM_VERBOSE" == "1" ]] || [[ "$level" == "error" ]]; then
        case "$level" in
            error)   echo "${ZPM_COLORS[red]}[ERROR]${ZPM_COLORS[reset]} $message" ;;
            warn)    echo "${ZPM_COLORS[yellow]}[WARN]${ZPM_COLORS[reset]} $message" ;;
            success) echo "${ZPM_COLORS[green]}[SUCCESS]${ZPM_COLORS[reset]} $message" ;;
            info)    echo "${ZPM_COLORS[blue]}[INFO]${ZPM_COLORS[reset]} $message" ;;
            *)       echo "$message" ;;
        esac
    fi
}

# Background status logging system
zpm::status_monitor() {
    local update_interval="${1:-1}"
    local status_file="$ZPM_CACHE_DIR/status.log"
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local active_jobs=0
        local completed_jobs=0
        local failed_jobs=0
        
        # Count job statuses
        for pid in $ZPM_ASYNC_JOBS; do
            if kill -0 $pid 2>/dev/null; then
                ((active_jobs++))
            else
                local job_file="$ZPM_CACHE_DIR/job_${pid}"
                if [[ -f "$job_file" ]]; then
                    local job_result=$(cat "$job_file")
                    case "$job_result" in
                        SUCCESS:*) ((completed_jobs++)) ;;
                        FAILED:*)  ((failed_jobs++)) ;;
                    esac
                fi
            fi
        done
        
        # Generate status report
        local status_report=$(cat << EOF
[$timestamp] STATUS_UPDATE
  Active Jobs: $active_jobs
  Completed: $completed_jobs
  Failed: $failed_jobs
  Total Plugins: ${#ZPM_PLUGINS[@]}
  Loaded Plugins: ${#ZPM_LOADED_PLUGINS[@]}
  Cache Size: $(du -sh "$ZPM_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0B")
  Memory Usage: $(ps -p $$ -o rss= 2>/dev/null | awk '{print int($1/1024)"MB"}' || echo "N/A")
EOF
)
        
        echo "$status_report" >> "$status_file"
        zpm::log "debug" "Status monitor update: $active_jobs active, $completed_jobs completed, $failed_jobs failed"
        
        # Update progress file for external monitoring
        cat > "$ZPM_PROGRESS_FILE" << EOF
{
  "timestamp": "$timestamp",
  "active_jobs": $active_jobs,
  "completed_jobs": $completed_jobs,
  "failed_jobs": $failed_jobs,
  "total_plugins": ${#ZPM_PLUGINS[@]},
  "loaded_plugins": ${#ZPM_LOADED_PLUGINS[@]},
  "cache_dir": "$ZPM_CACHE_DIR",
  "status": "$(([[ $active_jobs -eq 0 ]] && echo "idle") || echo "busy")"
}
EOF
        
        # Break if no active jobs and not in continuous mode
        [[ $active_jobs -eq 0 && "$update_interval" != "continuous" ]] && break
        
        sleep "$update_interval"
    done
}

zmp::start_status_monitor() {
    local interval="${1:-2}"
    
    # Kill existing monitor if running
    [[ -n "$ZPM_STATUS_PID" ]] && kill "$ZPM_STATUS_PID" 2>/dev/null
    
    # Start background status monitor
    zpm::status_monitor "$interval" &
    ZPM_STATUS_PID=$!
    
    zpm::log "info" "Background status monitor started (PID: $ZPM_STATUS_PID)"
}

zpm::stop_status_monitor() {
    if [[ -n "$ZPM_STATUS_PID" ]]; then
        kill "$ZPM_STATUS_PID" 2>/dev/null
        ZPM_STATUS_PID=""
        zpm::log "info" "Background status monitor stopped"
    fi
}

zpm::detailed_job_log() {
    local job_id="$1"
    local operation="$2"
    local plugin="$3"
    local status="$4"
    local start_time="$5"
    local end_time="${6:-$(date '+%Y-%m-%d %H:%M:%S')}"
    
    local duration=""
    if [[ -n "$start_time" ]]; then
        local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
        local end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            duration=$((end_epoch - start_epoch))
        fi
    fi
    
    local job_log=$(cat << EOF
[$end_time] JOB_COMPLETE
  Job ID: $job_id
  Operation: $operation
  Plugin: $plugin
  Status: $status
  Duration: ${duration}s
  Start: $start_time
  End: $end_time
EOF
)
    
    echo "$job_log" >> "$ZPM_LOG_FILE"
    ZPM_JOB_STATUS["$job_id"]="$status:$end_time"
}

zpm::progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    local prefix="${4:-Progress}"
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r%s: [" "$prefix"
    printf "%*s" "$filled" | tr ' ' '█'
    printf "%*s" "$empty" | tr ' ' '░'
    printf "] %d/%d (%d%%)" "$current" "$total" "$percentage"
}

zpm::live_status() {
    local refresh_rate="${1:-0.5}"
    local status_file="$ZPM_CACHE_DIR/status.log"
    
    echo "${ZPM_COLORS[bold]}ZPM Live Status Monitor${ZPM_COLORS[reset]}"
    echo "Press Ctrl+C to exit"
    echo ""
    
    while true; do
        # Clear previous output (move cursor up and clear lines)
        printf "\033[H\033[J"
        
        echo "${ZPM_COLORS[bold]}ZPM Live Status - $(date '+%H:%M:%S')${ZPM_COLORS[reset]}"
        echo ""
        
        # Show current progress if progress file exists
        if [[ -f "$ZPM_PROGRESS_FILE" ]]; then
            local active_jobs=$(grep -o '"active_jobs": [0-9]*' "$ZPM_PROGRESS_FILE" | cut -d: -f2 | tr -d ' ')
            local completed_jobs=$(grep -o '"completed_jobs": [0-9]*' "$ZPM_PROGRESS_FILE" | cut -d: -f2 | tr -d ' ')
            local failed_jobs=$(grep -o '"failed_jobs": [0-9]*' "$ZPM_PROGRESS_FILE" | cut -d: -f2 | tr -d ' ')
            local total_jobs=$((active_jobs + completed_jobs + failed_jobs))
            
            if [[ $total_jobs -gt 0 ]]; then
                zpm::progress_bar "$((completed_jobs + failed_jobs))" "$total_jobs" 40 "Jobs"
                echo ""
            fi
        fi
        
        # Show job breakdown
        printf "${ZPM_COLORS[cyan]}Active Jobs:${ZPM_COLORS[reset]} %s  " "${active_jobs:-0}"
        printf "${ZPM_COLORS[green]}Completed:${ZPM_COLORS[reset]} %s  " "${completed_jobs:-0}"
        printf "${ZPM_COLORS[red]}Failed:${ZPM_COLORS[reset]} %s\n" "${failed_jobs:-0}"
        echo ""
        
        # Show recent log entries
        echo "${ZPM_COLORS[yellow]}Recent Activity:${ZPM_COLORS[reset]}"
        if [[ -f "$ZPM_LOG_FILE" ]]; then
            tail -n 10 "$ZPM_LOG_FILE" | while IFS= read -r line; do
                case "$line" in
                    *ERROR*)   echo "  ${ZPM_COLORS[red]}$line${ZPM_COLORS[reset]}" ;;
                    *SUCCESS*) echo "  ${ZPM_COLORS[green]}$line${ZPM_COLORS[reset]}" ;;
                    *WARN*)    echo "  ${ZPM_COLORS[yellow]}$line${ZPM_COLORS[reset]}" ;;
                    *)         echo "  $line" ;;
                esac
            done
        fi
        
        sleep "$refresh_rate"
    done
}

zpm::background_log() {
    local level="$1"
    local operation="$2"
    shift 2
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Standard log entry
    echo "[$timestamp] [$level] [$operation] $message" >> "$ZPM_LOG_FILE"
    
    # Background operation specific logging
    local bg_log="$ZPM_CACHE_DIR/background.log"
    echo "[$timestamp] $operation: $message" >> "$bg_log"
    
    # Real-time status update if monitor is running
    if [[ -n "$ZPM_STATUS_PID" ]] && kill -0 "$ZPM_STATUS_PID" 2>/dev/null; then
        echo "REALTIME_UPDATE:$level:$operation:$message" >> "$ZPM_CACHE_DIR/realtime.log"
    fi
}

zpm::job_summary() {
    local operation="$1"
    local start_time="$2"
    local end_time="${3:-$(date '+%Y-%m-%d %H:%M:%S')}"
    
    local summary_file="$ZPM_CACHE_DIR/job_summary.log"
    local total_jobs=${#ZPM_ASYNC_JOBS[@]}
    local successful_jobs=0
    local failed_jobs=0
    
    # Count job results
    for job_id status_info in ${(kv)ZPM_JOB_STATUS}; do
        case "${status_info%%:*}" in
            SUCCESS) ((successful_jobs++)) ;;
            FAILED)  ((failed_jobs++)) ;;
        esac
    done
    
    local duration=""
    if [[ -n "$start_time" ]]; then
        local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
        local end_epoch=$(date -d "$end_time" +%s 2>/dev/null)
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            duration=$((end_epoch - start_epoch))
        fi
    fi
    
    local summary=$(cat << EOF
[$end_time] OPERATION_SUMMARY
  Operation: $operation
  Total Jobs: $total_jobs
  Successful: $successful_jobs
  Failed: $failed_jobs
  Success Rate: $(( total_jobs > 0 ? successful_jobs * 100 / total_jobs : 0 ))%
  Duration: ${duration}s
  Start Time: $start_time
  End Time: $end_time
EOF
)
    
    echo "$summary" >> "$summary_file"
    echo "$summary" >> "$ZPM_LOG_FILE"
    
    if [[ "$ZPM_VERBOSE" == "1" ]] || [[ $failed_jobs -gt 0 ]]; then
        echo "$summary"
    fi
}

# Lock management for concurrent operations
zpm::acquire_lock() {
    local timeout="${1:-10}"
    local count=0
    
    while [[ -f "$ZPM_LOCK_FILE" ]] && [[ $count -lt $timeout ]]; do
        sleep 0.1
        ((count++))
    done
    
    if [[ -f "$ZPM_LOCK_FILE" ]]; then
        zpm::error "Could not acquire lock after ${timeout}s"
        return 1
    fi
    
    echo $$ > "$ZPM_LOCK_FILE"
    zmp::log "info" "Lock acquired by process $$"
}

zpm::release_lock() {
    [[ -f "$ZPM_LOCK_FILE" ]] && rm -f "$ZPM_LOCK_FILE"
    zpm::log "info" "Lock released"
}

# Configuration management
zpm::load_config() {
    [[ -f "$ZPM_CONFIG_FILE" ]] || return 0
    
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        case "$key" in
            max_jobs) ZPM_MAX_JOBS="$value" ;;
            timeout)  ZPM_TIMEOUT="$value" ;;
            verbose)  ZPM_VERBOSE="$value" ;;
        esac
    done < "$ZPM_CONFIG_FILE"
}

zpm::save_config() {
    cat > "$ZPM_CONFIG_FILE" << EOF
# ZPM Configuration
max_jobs=$ZPM_MAX_JOBS
timeout=$ZPM_TIMEOUT
verbose=$ZPM_VERBOSE
EOF
}

# Cache management
zpm::cache_key() {
    local url="$1"
    echo -n "$url" | sha256sum | cut -d' ' -f1
}

zpm::cache_get() {
    local key="$1"
    local cache_file="$ZPM_CACHE_DIR/$key"
    
    [[ -f "$cache_file" ]] && cat "$cache_file"
}

zpm::cache_set() {
    local key="$1"
    local value="$2"
    local cache_file="$ZPM_CACHE_DIR/$key"
    
    echo "$value" > "$cache_file"
}

zpm::cache_expire() {
    local max_age="${1:-86400}"  # Default 24 hours
    
    find "$ZPM_CACHE_DIR" -type f -mtime +$(($max_age / 86400)) -delete 2>/dev/null
    zpm::log "info" "Expired cache entries older than $max_age seconds"
}

# Plugin parsing and validation
zpm::parse_plugin() {
    local spec="$1"
    local name url branch tag depth
    
    # Parse different plugin specification formats
    case "$spec" in
        # GitHub shorthand: user/repo
        */*) 
            if [[ "$spec" =~ ^([^/]+)/([^@#]+)(@([^#]+))?(#(.+))?$ ]]; then
                name="${match[1]}-${match[2]}"
                url="https://github.com/${match[1]}/${match[2]}.git"
                branch="${match[4]}"
                tag="${match[6]}"
            fi
            ;;
        # Full URL
        http*|git@*)
            url="$spec"
            name=$(basename "$url" .git)
            ;;
        *)
            zpm::error "Invalid plugin specification: $spec"
            return 1
            ;;
    esac
    
    # Output parsed information
    cat << EOF
name=$name
url=$url
branch=${branch:-main}
tag=$tag
EOF
}

# Async job management with enhanced logging
zpm::async_job() {
    local job_id="$1"
    local operation="$2"
    local plugin="$3"
    local command="$4"
    shift 4
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    zpm::background_log "info" "$operation" "Starting job $job_id for plugin $plugin"
    
    {
        local result
        local job_start=$(date +%s)
        
        if eval "$command" "$@"; then
            local job_end=$(date +%s)
            local duration=$((job_end - job_start))
            
            echo "SUCCESS:$job_id:$plugin:$duration" > "$ZPM_CACHE_DIR/job_$job_id"
            zpm::detailed_job_log "$job_id" "$operation" "$plugin" "SUCCESS" "$start_time"
            zpm::background_log "success" "$operation" "Job $job_id completed successfully (${duration}s)"
        else
            local job_end=$(date +%s)
            local duration=$((job_end - job_start))
            
            echo "FAILED:$job_id:$plugin:$duration" > "$ZPM_CACHE_DIR/job_$job_id"
            zpm::detailed_job_log "$job_id" "$operation" "$plugin" "FAILED" "$start_time"
            zpm::background_log "error" "$operation" "Job $job_id failed after ${duration}s"
        fi
    } &
    
    local pid=$!
    ZPM_ASYNC_JOBS+=($pid)
    zpm::background_log "info" "$operation" "Started async job $job_id (PID: $pid) for $plugin"
}

zpm::wait_jobs() {
    local timeout="${1:-$ZPM_TIMEOUT}"
    local operation="${2:-update}"
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local completed=0
    local total=${#ZPM_ASYNC_JOBS[@]}
    
    [[ $total -eq 0 ]] && return 0
    
    zpm::background_log "info" "$operation" "Waiting for $total async jobs to complete..."
    
    # Start status monitor for this operation
    zmp::start_status_monitor 1
    
    for pid in $ZPM_ASYNC_JOBS; do
        if kill -0 $pid 2>/dev/null; then
            # Job is still running, wait with timeout
            local count=0
            local wait_start=$(date +%s)
            
            while kill -0 $pid 2>/dev/null && [[ $count -lt $timeout ]]; do
                sleep 0.1
                ((count++))
                
                # Update progress every second during wait
                if [[ $((count % 10)) -eq 0 ]]; then
                    local elapsed=$(($(date +%s) - wait_start))
                    zpm::background_log "debug" "$operation" "Job $pid still running (${elapsed}s elapsed)"
                fi
            done
            
            if kill -0 $pid 2>/dev/null; then
                zpm::background_log "warn" "$operation" "Job $pid timed out after ${timeout}s, terminating..."
                kill $pid 2>/dev/null
                # Mark as failed
                echo "FAILED:timeout:unknown:$timeout" > "$ZPM_CACHE_DIR/job_$pid"
            fi
        fi
        
        ((completed++))
        
        # Show progress bar if verbose or if we have many jobs
        if [[ "$ZPM_VERBOSE" == "1" ]] || [[ $total -gt 5 ]]; then
            zpm::progress_bar $completed $total 50 "Jobs"
        fi
        
        # Log every 25% completion for large operations
        local progress_percent=$((completed * 100 / total))
        if [[ $((progress_percent % 25)) -eq 0 ]] && [[ $progress_percent -gt 0 ]]; then
            zpm::background_log "info" "$operation" "Progress: $completed/$total jobs completed ($progress_percent%)"
        fi
    done
    
    [[ "$ZPM_VERBOSE" == "1" ]] || [[ $total -gt 5 ]] && echo ""
    
    # Stop status monitor
    zpm::stop_status_monitor
    
    # Generate final summary
    zpm::job_summary "$operation" "$start_time"
    
    ZPM_ASYNC_JOBS=()
    zpm::background_log "info" "$operation" "All async jobs completed"
}

# Git operations with caching
zpm::git_clone() {
    local url="$1"
    local dest="$2"
    local branch="$3"
    local tag="$4"
    local depth="${5:-1}"
    
    local cache_key=$(zmp::cache_key "$url:$branch:$tag")
    local cached_commit=$(zpm::cache_get "$cache_key")
    
    if [[ -d "$dest/.git" ]]; then
        # Repository exists, check if update needed
        local current_commit=$(git -C "$dest" rev-parse HEAD 2>/dev/null)
        
        if [[ "$current_commit" == "$cached_commit" ]]; then
            zpm::log "info" "Plugin up to date: $(basename "$dest")"
            return 0
        fi
    fi
    
    # Clone or update repository
    local git_args=("--depth=$depth" "--single-branch")
    
    if [[ -n "$branch" ]]; then
        git_args+=("--branch=$branch")
    elif [[ -n "$tag" ]]; then
        git_args+=("--branch=$tag")
    fi
    
    if [[ -d "$dest" ]]; then
        rm -rf "$dest"
    fi
    
    if git clone "${git_args[@]}" "$url" "$dest" 2>>"$ZPM_LOG_FILE"; then
        local new_commit=$(git -C "$dest" rev-parse HEAD 2>/dev/null)
        zpm::cache_set "$cache_key" "$new_commit"
        zpm::log "success" "Successfully cloned: $url"
        return 0
    else
        zpm::error "Failed to clone: $url"
        return 1
    fi
}

# Plugin dependency resolution
zpm::resolve_dependencies() {
    local plugin="$1"
    local -a deps
    local plugin_dir="$ZPM_PLUGINS_DIR/$plugin"
    
    # Check for dependency files
    if [[ -f "$plugin_dir/.zpm-deps" ]]; then
        deps=(${(f)"$(<$plugin_dir/.zpm-deps)"})
    elif [[ -f "$plugin_dir/dependencies" ]]; then
        deps=(${(f)"$(<$plugin_dir/dependencies)"})
    fi
    
    ZPM_PLUGIN_DEPS[$plugin]="${deps[@]}"
    
    # Recursively resolve dependencies
    for dep in $deps; do
        if [[ -z "${ZPM_PLUGIN_DEPS[$dep]}" ]]; then
            zpm::resolve_dependencies "$dep"
        fi
    done
}

zpm::build_load_order() {
    local -A visited
    local -a order
    
    zpm::_topological_sort() {
        local plugin="$1"
        local dep
        
        [[ -n "${visited[$plugin]}" ]] && return
        visited[$plugin]=1
        
        for dep in ${=ZPM_PLUGIN_DEPS[$plugin]}; do
            zpm::_topological_sort "$dep"
        done
        
        order+=("$plugin")
    }
    
    for plugin in ${(k)ZPM_PLUGINS}; do
        zpm::_topological_sort "$plugin"
    done
    
    ZPM_LOAD_ORDER=($order)
}

# Plugin loading with optimizations
zpm::load_plugin() {
    local plugin="$1"
    local plugin_dir="$ZPM_PLUGINS_DIR/$plugin"
    
    [[ -n "${ZPM_LOADED_PLUGINS[$plugin]}" ]] && return 0
    
    if [[ ! -d "$plugin_dir" ]]; then
        zpm::error "Plugin directory not found: $plugin_dir"
        return 1
    fi
    
# Find the main plugin file
    local plugin_file
    for file in "$plugin_dir"/{$plugin.plugin.zsh,$plugin.zsh,init.zsh,$plugin.sh}; do
        if [[ -f "$file" ]]; then
            plugin_file="$file"
            break
        fi
    done
    
    if [[ -z "$plugin_file" ]]; then
        zpm::error "No loadable file found for plugin: $plugin"
        return 1
    fi
    
    # Add plugin directory to fpath if it has completions
    if [[ -d "$plugin_dir/functions" ]] || [[ -d "$plugin_dir/completions" ]] || 
       [[ -n "$plugin_dir"/_* || -n "$plugin_dir"/comps/_* ]]; then
        fpath=("$plugin_dir" $fpath)
    fi
    
    # Source the plugin
    zpm::log "info" "Loading plugin: $plugin"
    if source "$plugin_file"; then
        ZPM_LOADED_PLUGINS[$plugin]=1
        zpm::log "success" "Plugin loaded: $plugin"
        return 0
    else
        zpm::error "Failed to load plugin: $plugin"
        return 1
    fi
}

# Main plugin management commands
zpm::install() {
    local spec="$1"
    local -A plugin_info
    
    if [[ -z "$spec" ]]; then
        zpm::error "Plugin specification required"
        return 1
    fi
    
    # Parse plugin specification
    local parsed_info=$(zpm::parse_plugin "$spec")
    [[ $? -ne 0 ]] && return 1
    
    # Load parsed information
    while IFS='=' read -r key value; do
        plugin_info[$key]="$value"
    done <<< "$parsed_info"
    
    local name="${plugin_info[name]}"
    local url="${plugin_info[url]}"
    local branch="${plugin_info[branch]}"
    local tag="${plugin_info[tag]}"
    
    zpm::acquire_lock || return 1
    
    local plugin_dir="$ZPM_PLUGINS_DIR/$name"
    
    zpm::log "info" "Installing plugin: $name"
    
    if zpm::git_clone "$url" "$plugin_dir" "$branch" "$tag"; then
        ZPM_PLUGINS[$name]="$spec"
        zpm::resolve_dependencies "$name"
        zpm::log "success" "Plugin installed: $name"
    else
        zpm::error "Failed to install plugin: $name"
        zpm::release_lock
        return 1
    fi
    
    zpm::release_lock
}

zmp::update() {
    local plugin="$1"
    local operation_start=$(date '+%Y-%m-%d %H:%M:%S')
    
    zpm::acquire_lock || return 1
    
    if [[ -n "$plugin" ]]; then
        # Update specific plugin
        if [[ -z "${ZPM_PLUGINS[$plugin]}" ]]; then
            zpm::error "Plugin not installed: $plugin"
            zpm::release_lock
            return 1
        fi
        
        zpm::background_log "info" "update" "Updating plugin: $plugin"
        zpm::async_job "update_$plugin" "update" "$plugin" "zpm::install" "${ZPM_PLUGINS[$plugin]}"
    else
        # Update all plugins
        zpm::background_log "info" "update" "Updating all ${#ZPM_PLUGINS[@]} plugins..."
        local count=0
        
        for name spec in ${(kv)ZPM_PLUGINS}; do
            if [[ $count -ge $ZPM_MAX_JOBS ]]; then
                zpm::wait_jobs "$ZPM_TIMEOUT" "update"
                count=0
            fi
            
            zpm::async_job "update_$name" "update" "$name" "zpm::install" "$spec"
            ((count++))
        done
    fi
    
    zpm::wait_jobs "$ZPM_TIMEOUT" "update"
    zpm::release_lock
    
    # Expire old cache entries
    zpm::cache_expire
    
    zpm::background_log "success" "update" "Update operation completed"
}

zpm::remove() {
    local plugin="$1"
    
    if [[ -z "$plugin" ]]; then
        zpm::error "Plugin name required"
        return 1
    fi
    
    if [[ -z "${ZPM_PLUGINS[$plugin]}" ]]; then
        zpm::error "Plugin not installed: $plugin"
        return 1
    fi
    
    zpm::acquire_lock || return 1
    
    local plugin_dir="$ZPM_PLUGINS_DIR/$plugin"
    
    zpm::log "info" "Removing plugin: $plugin"
    
    if [[ -d "$plugin_dir" ]]; then
        rm -rf "$plugin_dir"
    fi
    
    unset "ZPM_PLUGINS[$plugin]"
    unset "ZPM_LOADED_PLUGINS[$plugin]"
    unset "ZPM_PLUGIN_DEPS[$plugin]"
    
    zpm::log "success" "Plugin removed: $plugin"
    zpm::release_lock
}

zpm::load() {
    # Build dependency-aware load order
    zpm::build_load_order
    
    zpm::log "info" "Loading plugins in dependency order..."
    
    local failed_plugins=()
    for plugin in $ZPM_LOAD_ORDER; do
        if ! zpm::load_plugin "$plugin"; then
            failed_plugins+=("$plugin")
        fi
    done
    
    if [[ ${#failed_plugins[@]} -gt 0 ]]; then
        zpm::error "Failed to load plugins: ${failed_plugins[*]}"
        return 1
    fi
    
    # Rebuild completion system if needed
    if [[ ${#ZPM_LOADED_PLUGINS[@]} -gt 0 ]]; then
        autoload -Uz compinit
        compinit -i
    fi
    
    zpm::log "success" "All plugins loaded successfully"
}

zpm::list() {
    if [[ ${#ZPM_PLUGINS[@]} -eq 0 ]]; then
        echo "No plugins installed."
        return
    fi
    
    echo "${ZPM_COLORS[bold]}Installed plugins:${ZPM_COLORS[reset]}"
    
    for name spec in ${(kv)ZPM_PLUGINS}; do
        local status_color="${ZPM_COLORS[red]}"
        local status="not loaded"
        
        if [[ -n "${ZPM_LOADED_PLUGINS[$name]}" ]]; then
            status_color="${ZPM_COLORS[green]}"
            status="loaded"
        fi
        
        printf "  %s%-20s%s %s[%s]%s %s\n" \
            "${ZPM_COLORS[cyan]}" "$name" "${ZPM_COLORS[reset]}" \
            "$status_color" "$status" "${ZPM_COLORS[reset]}" \
            "$spec"
        
        # Show dependencies if any
        if [[ -n "${ZPM_PLUGIN_DEPS[$name]}" ]]; then
            printf "    %sdeps:%s %s\n" \
                "${ZPM_COLORS[yellow]}" "${ZPM_COLORS[reset]}" \
                "${ZPM_PLUGIN_DEPS[$name]}"
        fi
    done
}

zpm::status() {
    echo "${ZPM_COLORS[bold]}ZPM Status:${ZPM_COLORS[reset]}"
    echo "  Directory: $ZPM_DIR"
    echo "  Plugins: ${#ZPM_PLUGINS[@]} installed, ${#ZPM_LOADED_PLUGINS[@]} loaded"
    echo "  Cache entries: $(find "$ZPM_CACHE_DIR" -type f 2>/dev/null | wc -l)"
    echo "  Max concurrent jobs: $ZPM_MAX_JOBS"
    echo "  Timeout: ${ZPM_TIMEOUT}s"
    
    if [[ -f "$ZPM_LOCK_FILE" ]]; then
        echo "  ${ZPM_COLORS[yellow]}Lock file present${ZPM_COLORS[reset]}"
    fi
}

zpm::clean() {
    zpm::log "info" "Cleaning up..."
    
    # Clean cache
    rm -rf "$ZPM_CACHE_DIR"/*
    mkdir -p "$ZPM_CACHE_DIR"
    
    # Remove unused plugin directories
    if [[ -d "$ZPM_PLUGINS_DIR" ]]; then
        for dir in "$ZPM_PLUGINS_DIR"/*/; do
            local plugin_name=$(basename "$dir")
            if [[ -z "${ZPM_PLUGINS[$plugin_name]}" ]]; then
                zpm::log "info" "Removing unused plugin directory: $plugin_name"
                rm -rf "$dir"
            fi
        done
    fi
    
    zpm::log "success" "Cleanup completed"
}

# Cleanup function
zpm::cleanup() {
    local cleanup_start=$(date '+%Y-%m-%d %H:%M:%S')
    zpm::background_log "info" "cleanup" "Starting ZPM cleanup process"
    
    # Stop status monitor
    zpm::stop_status_monitor
    
    # Kill any remaining async jobs
    local killed_jobs=0
    for pid in $ZPM_ASYNC_JOBS; do
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            ((killed_jobs++))
            zpm::background_log "warn" "cleanup" "Terminated hanging job (PID: $pid)"
        fi
    done
    
    [[ $killed_jobs -gt 0 ]] && zpm::background_log "info" "cleanup" "Terminated $killed_jobs hanging jobs"
    
    # Release lock
    zpm::release_lock
    
    # Final cleanup summary
    zpm::job_summary "cleanup" "$cleanup_start"
    zpm::background_log "info" "cleanup" "ZPM cleanup completed"
}

# Enhanced status command with background logs
zpm::status() {
    echo "${ZPM_COLORS[bold]}ZPM Status:${ZPM_COLORS[reset]}"
    echo "  Directory: $ZPM_DIR"
    echo "  Plugins: ${#ZPM_PLUGINS[@]} installed, ${#ZPM_LOADED_PLUGINS[@]} loaded"
    echo "  Cache entries: $(find "$ZPM_CACHE_DIR" -type f 2>/dev/null | wc -l)"
    echo "  Max concurrent jobs: $ZPM_MAX_JOBS"
    echo "  Timeout: ${ZPM_TIMEOUT}s"
    
    # Background process status
    if [[ -n "$ZPM_STATUS_PID" ]] && kill -0 "$ZPM_STATUS_PID" 2>/dev/null; then
        echo "  ${ZPM_COLORS[green]}Status monitor: Running (PID: $ZPM_STATUS_PID)${ZPM_COLORS[reset]}"
    else
        echo "  Status monitor: Stopped"
    fi
    
    # Active jobs
    local active_jobs=$(ps -eo pid,cmd | grep -c "zpm::" 2>/dev/null || echo 0)
    echo "  Active background jobs: $active_jobs"
    
    if [[ -f "$ZPM_LOCK_FILE" ]]; then
        echo "  ${ZPM_COLORS[yellow]}Lock file present${ZPM_COLORS[reset]}"
    fi
    
    # Recent activity summary
    if [[ -f "$ZPM_CACHE_DIR/job_summary.log" ]]; then
        echo ""
        echo "${ZPM_COLORS[bold]}Recent Operations:${ZPM_COLORS[reset]}"
        tail -n 3 "$ZPM_CACHE_DIR/job_summary.log" | grep "OPERATION_SUMMARY" -A 7 | tail -n +2
    fi
}

# Main command dispatcher
zpm() {
    local command="$1"
    shift
    
    # Initialize on first run
    [[ ! -d "$ZPM_DIR" ]] && zpm::init
    
    case "$command" in
        install|add)     zpm::install "$@" ;;
        update|upgrade)  zmp::update "$@" ;;
        remove|delete)   zpm::remove "$@" ;;
        load)           zpm::load "$@" ;;
        list|ls)        zpm::list "$@" ;;
        status)         zpm::status "$@" ;;
        clean)          zpm::clean "$@" ;;
        config)         zpm::save_config ;;
        monitor)        zpm::live_status "$@" ;;
        logs)           
            if [[ "$1" == "tail" ]]; then
                tail -f "$ZPM_LOG_FILE"
            elif [[ "$1" == "summary" ]]; then
                [[ -f "$ZPM_CACHE_DIR/job_summary.log" ]] && cat "$ZPM_CACHE_DIR/job_summary.log"
            elif [[ "$1" == "background" ]]; then
                [[ -f "$ZPM_CACHE_DIR/background.log" ]] && tail -n 50 "$ZPM_CACHE_DIR/background.log"
            else
                tail -n 50 "$ZPM_LOG_FILE"
            fi
            ;;
        progress)       
            [[ -f "$ZPM_PROGRESS_FILE" ]] && cat "$ZPM_PROGRESS_FILE" || echo "No active operations"
            ;;
        help|--help|-h)
            cat << 'EOF'
ZPM - Modern Zsh Plugin Manager

Usage: zpm <command> [options]

Commands:
  install <spec>    Install a plugin from GitHub (user/repo) or URL
  update [plugin]   Update plugin(s) - all if no plugin specified
  remove <plugin>   Remove a plugin
  load             Load all installed plugins
  list             List installed plugins
  status           Show ZPM status and recent activity
  clean            Clean cache and unused files
  config           Save current configuration
  monitor          Start live status monitor
  logs [tail|summary|background]  View logs
  progress         Show current operation progress

Examples:
  zpm install zsh-users/zsh-autosuggestions
  zpm install robbyrussell/oh-my-zsh@master
  zpm update
  zpm remove zsh-autosuggestions
  zpm load
  zpm monitor          # Live status updates
  zpm logs tail        # Follow logs in real-time
  zpm progress         # Current operation status

Environment Variables:
  ZPM_DIR          ZPM directory (default: ~/.zpm)
  ZPM_MAX_JOBS     Max concurrent jobs (default: 8)
  ZPM_TIMEOUT      Job timeout in seconds (default: 30)
  ZPM_VERBOSE      Verbose output (default: 0)
EOF
            ;;
        *)
            zpm::error "Unknown command: $command"
            echo "Run 'zpm help' for usage information."
            return 1
            ;;
    esac
}

# Auto-initialize on source
zpm::init

# Completion for zpm command
if [[ -n "$ZSH_VERSION" ]]; then
    _zpm() {
        local context state line
        local -a commands
        
        commands=(
            'install:Install a plugin'
            'update:Update plugins'
            'remove:Remove a plugin'
            'load:Load plugins'
            'list:List installed plugins'
            'status:Show status and activity'
            'clean:Clean cache'
            'config:Save configuration'
            'monitor:Live status monitor'
            'logs:View logs (tail|summary|background)'
            'progress:Show operation progress'
            'help:Show help'
        )
        
        _arguments -C \
            '1: :->commands' \
            '*: :->args' && return
        
        case $state in
            commands)
                _describe -t commands 'zpm commands' commands && return
                ;;
            args)
                case $line[1] in
                    remove|update)
                        _describe -t plugins 'plugins' "(${(k)ZPM_PLUGINS[@]})" && return
                        ;;
                esac
                ;;
        esac
    }
    
    compdef _zmp zpm
fi
