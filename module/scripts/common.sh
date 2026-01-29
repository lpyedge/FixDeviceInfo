#!/system/bin/sh
# Device Info Fix Module - Common Functions
# Shared utilities used by all feature scripts

# =============================================================================
# Logging
# =============================================================================
LOG_MAX_LINES=2000

trim_log() {
    [ -f "$LOG_FILE" ] || return 0
    local lines
    lines=$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)
    case "$lines" in
        *[!0-9]*|'') lines=0 ;;
    esac
    if [ "$lines" -gt "$LOG_MAX_LINES" ]; then
        local tmp
        tmp="$MODDIR/.service.log.tmp"
        tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$LOG_FILE"
        rm -f "$tmp" 2>/dev/null || true
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
    trim_log
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if value is a positive integer
is_int() {
    case "$1" in
        *[!0-9]*|'') return 1 ;;
        *) return 0 ;;
    esac
}

# Write value to sysfs node if exists and writable
write_if_exists() {
    local path="$1"
    local value="$2"
    if [ -w "$path" ]; then
        echo "$value" > "$path" 2>/dev/null
        return 0
    fi
    return 1
}

# Preserve SELinux context from source to target file
preserve_selinux_context() {
    local src="$1"
    local target="$2"
    
    local src_ctx=""
    local src_ctx_line
    src_ctx_line=$(ls -Z "$src" 2>/dev/null || true)
    if [ -n "$src_ctx_line" ]; then
        src_ctx=${src_ctx_line%% *}
    fi

    if command -v chcon >/dev/null 2>&1; then
        if chcon --reference="$src" "$target" 2>/dev/null; then
            log "Applied SELinux context via chcon --reference"
            return 0
        elif [ -n "$src_ctx" ] && chcon "$src_ctx" "$target" 2>/dev/null; then
            log "Applied SELinux context via chcon $src_ctx"
            return 0
        else
            log "Warning: failed to apply SELinux context to $target"
            return 1
        fi
    else
        log "Warning: chcon not found, cannot preserve SELinux context"
        return 1
    fi
}
