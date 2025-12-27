#!/bin/zsh

# Zap - Zsh Async Plugin Manager
# Save this as ~/.zap/zap.zsh and source it in your .zshrc

# Configuration directory
ZAP_DIR="${HOME}/.config/zap"
ZAP_CACHE="${ZAP_DIR}/cache"
ZAP_PLUGINS_DIR="${ZAP_DIR}/plugins"


# Initialize Zap
zap:init() {
    [[ ! -d "$ZAP_PLUGINS_DIR" ]] && mkdir -p "$ZAP_PLUGINS_DIR"
    [[ ! -d "$ZAP_CACHE" ]] && mkdir -p "$ZAP_CACHE"
}

# Async plugin loading function
zap:load_async() {
    local plugin_name="$1"
    local plugin_path="${ZAP_PLUGINS_DIR}/${plugin_name}"
    local cache_file="${ZAP_CACHE}/${plugin_name}.zsh"

    # Background process for plugin loading
    {
        # Source plugin files
        for script in "${plugin_path}"/*.zsh; do
            [[ -f "$script" ]] && source "$script"
        done
        # Mark as loaded in cache
        touch "$cache_file"
    } &!
}

# Plugin installation function
zap:install() {
    local repo_url="$1"
    local plugin_name="${2:-${repo_url##*/}}"
    local plugin_path="${ZAP_PLUGINS_DIR}/${plugin_name}"

    if [[ ! -d "$plugin_path" ]]; then
        print "Installing ${plugin_name}..."
        git clone --depth 1 "$repo_url" "$plugin_path" 2>/dev/null
    fi
}

# Main plugin management function
zap:plug() {
    local repo_url="$1"
    local plugin_name="${2:-${repo_url##*/}}"
    local plugin_path="${ZAP_PLUGINS_DIR}/${plugin_name}"
    local cache_file="${ZAP_CACHE}/${plugin_name}.zsh"

    # Install if not present
    [[ ! -d "$plugin_path" ]] && zap:install "$repo_url" "$plugin_name"

    # Load asynchronously if not cached
    [[ ! -f "$cache_file" ]] && zap:load_async "$plugin_name"
}

# Update all plugins
zap:update() {
    print "Updating all plugins..."
    for plugin_dir in "${ZAP_PLUGINS_DIR}"/*; do
        if [[ -d "$plugin_dir" && -d "${plugin_dir}/.git" ]]; then
            (
                cd "$plugin_dir"
                git pull --quiet
                # Clear cache for updated plugin
                local plugin_name="${plugin_dir##*/}"
                rm -f "${ZAP_CACHE}/${plugin_name}.zsh"
                zap:load_async "$plugin_name"
            ) &!
        fi
    done
    wait
    print "Update complete!"
}

# List installed plugins
zap:list() {
    print "Installed plugins:"
    for plugin_dir in "${ZAP_PLUGINS_DIR}"/*; do
        [[ -d "$plugin_dir" ]] && print "  - ${plugin_dir##*/}"
    done
}

# Initialize Zap
zap:init

