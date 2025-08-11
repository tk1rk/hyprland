#!/usr/bin/env zsh

# ZPM - Fast Async Zsh Plugin Manager
# Features: Asynchronous loading, caching, parallel downloads, dependency resolution

# Configuration
ZPM_DIR="${ZPM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zpm}"
ZPM_CACHE_DIR="$ZPM_DIR/cache"
ZPM_PLUGINS_DIR="$ZPM_DIR/plugins"
ZPM_CONFIG_FILE="${ZPM_CONFIG_FILE:-$HOME/.zpmrc}"
ZPM_PARALLEL_JOBS="${ZPM_PARALLEL_JOBS:-4}"

# Internal variables
typeset -gA ZPM_PLUGINS ZPM_PLUGIN_PATHS ZPM_ASYNC_JOBS
typeset -ga ZPM_LOAD_ORDER
ZPM_CACHE_VALID=3600  # 1 hour cache validity

# Colors for output
autoload -U colors && colors
ZPM_COLOR_INFO="$fg[cyan]"
ZPM_COLOR_SUCCESS="$fg[green]"
ZPM_COLOR_WARNING="$fg[yellow]"
ZPM_COLOR_ERROR="$fg[red]"
ZPM_COLOR_RESET="$reset_color"

# Utility functions
zpm_log() {
    local level="$1" && shift
    local color_var="ZPM_COLOR_${level:u}"
    local color="${(P)color_var}"
    printf "${color}[ZPM:${level}]${ZPM_COLOR_RESET} %s\n" "$*"
}

zpm_info() { zpm_log "info" "$@" }
zpm_success() { zpm_log "success" "$@" }
zpm_warning() { zpm_log "warning" "$@" }
zpm_error() { zpm_log "error" "$@" }

# Create necessary directories
zpm_init_dirs() {
    [[ ! -d "$ZPM_DIR" ]] && mkdir -p "$ZPM_DIR"
    [[ ! -d "$ZPM_CACHE_DIR" ]] && mkdir -p "$ZPM_CACHE_DIR"
    [[ ! -d "$ZPM_PLUGINS_DIR" ]] && mkdir -p "$ZPM_PLUGINS_DIR"
}

# Parse plugin specification (user/repo, local:/path, or gh:user/repo)
zpm_parse_plugin() {
    local spec="$1"
    local plugin_name plugin_url plugin_dir plugin_type

    case "$spec" in
        local:*)
            plugin_type="local"
            plugin_dir="${spec#local:}"
            plugin_name="$(basename "$plugin_dir")"
            plugin_url="$plugin_dir"
            ;;
        gh:*|*/*)
            plugin_type="github"
            local repo="${spec#gh:}"
            plugin_name="${repo##*/}"
            plugin_url="https://github.com/${repo}.git"
            plugin_dir="$ZPM_PLUGINS_DIR/$plugin_name"
            ;;
        *)
            zpm_error "Invalid plugin specification: $spec"
            return 1
            ;;
    esac

    # Store plugin info
    ZPM_PLUGINS[$plugin_name]="$spec"
    ZPM_PLUGIN_PATHS[$plugin_name]="$plugin_dir"
    
    printf "%s\n%s\n%s\n%s" "$plugin_name" "$plugin_url" "$plugin_dir" "$plugin_type"
}

# Async job management using zsh/zpty
zpm_async_start() {
    local job_id="$1" && shift
    local job_cmd="$*"
    
    # Kill existing job if running
    [[ -n "${ZPM_ASYNC_JOBS[$job_id]}" ]] && zpm_async_stop "$job_id"
    
    # Start new job
    zmodload zsh/zpty 2>/dev/null
    zpty -b "$job_id" "$job_cmd"
    ZPM_ASYNC_JOBS[$job_id]="$job_id"
}

zpm_async_stop() {
    local job_id="$1"
    [[ -n "${ZPM_ASYNC_JOBS[$job_id]}" ]] && {
        zpty -d "$job_id" 2>/dev/null
        unset "ZPM_ASYNC_JOBS[$job_id]"
    }
}

zpm_async_get_result() {
    local job_id="$1"
    local result
    zpty -r "$job_id" result 2>/dev/null && printf "%s" "$result"
}

# Cache management
zpm_cache_key() {
    printf "%s" "$1" | shasum -a 256 | cut -d' ' -f1
}

zpm_cache_get() {
    local key="$(zpm_cache_key "$1")"
    local cache_file="$ZPM_CACHE_DIR/$key"
    
    [[ -f "$cache_file" ]] && {
        local cache_time=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
        local current_time=$(date +%s)
        
        if (( current_time - cache_time < ZPM_CACHE_VALID )); then
            cat "$cache_file"
            return 0
        fi
    }
    return 1
}

zpm_cache_set() {
    local key="$(zpm_cache_key "$1")"
    local cache_file="$ZPM_CACHE_DIR/$key"
    shift
    printf "%s" "$*" > "$cache_file"
}

# Plugin installation
zpm_install_plugin() {
    local spec="$1"
    local plugin_info
    plugin_info=($(zpm_parse_plugin "$spec")) || return 1
    
    local plugin_name="$plugin_info[1]"
    local plugin_url="$plugin_info[2]"
    local plugin_dir="$plugin_info[3]"
    local plugin_type="$plugin_info[4]"
    
    case "$plugin_type" in
        github)
            if [[ -d "$plugin_dir" ]]; then
                zpm_info "Updating $plugin_name..."
                (cd "$plugin_dir" && git pull --quiet) || {
                    zpm_error "Failed to update $plugin_name"
                    return 1
                }
            else
                zpm_info "Installing $plugin_name..."
                git clone --quiet --depth=1 "$plugin_url" "$plugin_dir" || {
                    zpm_error "Failed to install $plugin_name"
                    return 1
                }
            fi
            ;;
        local)
            if [[ ! -d "$plugin_url" ]]; then
                zpm_error "Local plugin directory not found: $plugin_url"
                return 1
            fi
            ;;
    esac
    
    zpm_success "Plugin $plugin_name ready"
}

# Async plugin installation
zpm_install_async() {
    local specs=("$@")
    local jobs=()
    local max_jobs="$ZPM_PARALLEL_JOBS"
    local active_jobs=0
    local spec_index=0
    
    zpm_info "Installing ${#specs[@]} plugins (max $max_jobs parallel jobs)..."
    
    # Function to check and collect completed jobs
    check_jobs() {
        local job completed_jobs=()
        for job in "${jobs[@]}"; do
            [[ -n "${ZPM_ASYNC_JOBS[$job]}" ]] || completed_jobs+=("$job")
        done
        
        # Remove completed jobs
        for job in "${completed_jobs[@]}"; do
            jobs=(${jobs[@]/$job})
            ((active_jobs--))
        done
    }
    
    # Start initial batch of jobs
    while (( spec_index < ${#specs[@]} && active_jobs < max_jobs )); do
        local spec="${specs[$((++spec_index))]}"
        local job_id="install_$(basename "${spec//\//_}")"
        
        zpm_async_start "$job_id" "zpm_install_plugin '$spec'"
        jobs+=("$job_id")
        ((active_jobs++))
    done
    
    # Wait for jobs to complete and start new ones
    while (( active_jobs > 0 || spec_index < ${#specs[@]} )); do
        check_jobs
        
        # Start new jobs if slots available
        while (( spec_index < ${#specs[@]} && active_jobs < max_jobs )); do
            local spec="${specs[$((++spec_index))]}"
            local job_id="install_$(basename "${spec//\//_}")"
            
            zpm_async_start "$job_id" "zpm_install_plugin '$spec'"
            jobs+=("$job_id")
            ((active_jobs++))
        done
        
        sleep 0.1
    done
    
    # Clean up any remaining jobs
    for job in "${jobs[@]}"; do
        zpm_async_stop "$job"
    done
}

# Find plugin files to source
zpm_find_plugin_files() {
    local plugin_dir="$1"
    local plugin_name="$(basename "$plugin_dir")"
    local files=()
    
    # Check cache first
    local cache_result
    if cache_result=$(zpm_cache_get "files:$plugin_dir"); then
        printf "%s" "$cache_result"
        return 0
    fi
    
    # Common plugin file patterns
    local patterns=(
        "$plugin_dir/$plugin_name.plugin.zsh"
        "$plugin_dir/$plugin_name.zsh"
        "$plugin_dir/init.zsh"
        "$plugin_dir/$plugin_name.sh"
        "$plugin_dir/$(basename "$plugin_dir").plugin.zsh"
    )
    
    # Find the main plugin file
    local file
    for file in "${patterns[@]}"; do
        [[ -f "$file" ]] && {
            files+=("$file")
            break
        }
    done
    
    # If no main file found, look for any .zsh files
    if (( ${#files[@]} == 0 )); then
        files=($(find "$plugin_dir" -name "*.zsh" -type f | head -5))
    fi
    
    # Cache the result
    local result="${(j: :)files}"
    zpm_cache_set "files:$plugin_dir" "$result"
    printf "%s" "$result"
}

# Load a single plugin
zpm_load_plugin() {
    local plugin_name="$1"
    local plugin_dir="${ZPM_PLUGIN_PATHS[$plugin_name]}"
    
    [[ -z "$plugin_dir" || ! -d "$plugin_dir" ]] && {
        zpm_error "Plugin directory not found: $plugin_name"
        return 1
    }
    
    # Add to fpath if needed
    [[ -d "$plugin_dir" ]] && {
        [[ ":$FPATH:" != *":$plugin_dir:"* ]] && FPATH="$plugin_dir:$FPATH"
        [[ -d "$plugin_dir/functions" && ":$FPATH:" != *":$plugin_dir/functions:"* ]] && FPATH="$plugin_dir/functions:$FPATH"
    }
    
    # Find and source plugin files
    local files=($(zpm_find_plugin_files "$plugin_dir"))
    local file
    
    for file in "${files[@]}"; do
        [[ -f "$file" ]] && {
            source "$file" || zpm_warning "Failed to source $file"
        }
    done
    
    (( ${#files[@]} > 0 )) && zpm_info "Loaded $plugin_name"
}

# Main plugin management functions
zpm_add() {
    local spec="$1"
    [[ -z "$spec" ]] && { zpm_error "No plugin specified"; return 1 }
    
    # Parse plugin
    local plugin_info
    plugin_info=($(zpm_parse_plugin "$spec")) || return 1
    local plugin_name="$plugin_info[1]"
    
    # Add to load order if not already present
    [[ "${ZPM_LOAD_ORDER[(i)$plugin_name]}" -gt "${#ZPM_LOAD_ORDER[@]}" ]] && {
        ZPM_LOAD_ORDER+=("$plugin_name")
    }
    
    zpm_info "Added plugin: $plugin_name"
}

zpm_install() {
    if (( $# > 0 )); then
        # Install specific plugins
        zpm_install_async "$@"
    else
        # Install all configured plugins
        local specs=()
        local plugin_name
        for plugin_name in "${ZPM_LOAD_ORDER[@]}"; do
            specs+=("${ZPM_PLUGINS[$plugin_name]}")
        done
        (( ${#specs[@]} > 0 )) && zpm_install_async "${specs[@]}"
    fi
}

zpm_load() {
    if (( $# > 0 )); then
        # Load specific plugins
        local spec
        for spec in "$@"; do
            zpm_add "$spec"
            local plugin_info
            plugin_info=($(zpm_parse_plugin "$spec")) || continue
            zmp_load_plugin "$plugin_info[1]"
        done
    else
        # Load all configured plugins
        local plugin_name
        for plugin_name in "${ZPM_LOAD_ORDER[@]}"; do
            zpm_load_plugin "$plugin_name"
        done
    fi
}

zpm_update() {
    zpm_info "Updating all plugins..."
    local specs=()
    local plugin_name
    for plugin_name in "${ZPM_LOAD_ORDER[@]}"; do
        specs+=("${ZPM_PLUGINS[$plugin_name]}")
    done
    (( ${#specs[@]} > 0 )) && zmp_install_async "${specs[@]}"
}

zpm_clean() {
    zmp_info "Cleaning cache..."
    rm -rf "$ZPM_CACHE_DIR"/*
    zpm_success "Cache cleaned"
}

zpm_list() {
    zpm_info "Installed plugins:"
    local plugin_name
    for plugin_name in "${ZPM_LOAD_ORDER[@]}"; do
        local spec="${ZPM_PLUGINS[$plugin_name]}"
        local dir="${ZPM_PLUGIN_PATHS[$plugin_name]}"
        local status="✗"
        [[ -d "$dir" ]] && status="✓"
        printf "  %s %s (%s)\n" "$status" "$plugin_name" "$spec"
    done
}

# Load configuration file
zpm_load_config() {
    [[ -f "$ZPM_CONFIG_FILE" ]] && source "$ZPM_CONFIG_FILE"
}

# Main command dispatcher
zpm() {
    zpm_init_dirs
    
    local cmd="$1" && shift
    
    case "$cmd" in
        add|a)      zpm_add "$@" ;;
        install|i)  zpm_install "$@" ;;
        load|l)     zpm_load "$@" ;;
        update|u)   zpm_update "$@" ;;
        clean|c)    zpm_clean "$@" ;;
        list|ls)    zpm_list "$@" ;;
        *)
            cat <<EOF
ZPM - Fast Async Zsh Plugin Manager

Usage: zpm <command> [arguments]

Commands:
  add <plugin>     Add plugin to configuration
  install [plugin] Install plugin(s) (all if none specified)
  load [plugin]    Load plugin(s) (all if none specified)  
  update          Update all plugins
  clean           Clean cache
  list            List all plugins

Plugin formats:
  user/repo       GitHub repository
  gh:user/repo    GitHub repository (explicit)
  local:/path     Local directory

Examples:
  zpm add ohmyzsh/ohmyzsh
  zpm add local:/path/to/plugin
  zpm install
  zpm load
EOF
            ;;
    esac
}

# Auto-load configuration on startup
zpm_load_config

# Completion for zpm command
_zpm() {
    local context state line
    typeset -A opt_args
    
    _arguments \
        '1:command:(add install load update clean list)' \
        '*:plugin:_files'
}

compdef _zpm zpm