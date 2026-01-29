#!/system/bin/sh
# Device Info Fix Module - Device Name Override
# Sets device_name in global settings (affects Bluetooth/Hotspot name)
#
# IMPORTANT: This is a persistent setting change. The script handles:
# - Apply: when module is enabled and model_name.conf exists
# - Rollback: when module is disabled (detected via 'disable' flag file)

# Source common functions (MODDIR and LOG_FILE must be set by caller)
. "$MODDIR/scripts/common.sh"

# =============================================================================
# Configuration
# =============================================================================
MODEL_NAME_FILE="$MODDIR/model_name.conf"
DEVICE_NAME_APPLIED_FLAG="$MODDIR/.device_name_applied"
MODULE_DISABLE_FLAG="$MODDIR/disable"

# =============================================================================
# Helper: Wait for settings service
# =============================================================================
wait_for_settings_service() {
    if ! command -v settings >/dev/null 2>&1; then
        log "Warning: settings command not found"
        return 1
    fi
    
    local retries=0
    while [ $retries -lt 30 ]; do
        if settings get global device_name >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        retries=$((retries + 1))
    done
    
    log "Warning: settings service not ready after 30s"
    return 1
}

# =============================================================================
# Rollback: Restore device_name to system default
# =============================================================================
rollback_device_name() {
    log "Rolling back device_name to system default..."
    
    if ! wait_for_settings_service; then
        return 1
    fi
    
    # Delete custom settings to restore system defaults
    settings delete global device_name >/dev/null 2>&1 && \
        log "Deleted global device_name" || true
    settings delete secure bluetooth_name >/dev/null 2>&1 && \
        log "Deleted secure bluetooth_name" || true
    
    # Remove applied flag so it can be re-applied if module is re-enabled
    rm -f "$DEVICE_NAME_APPLIED_FLAG" 2>/dev/null || true
    
    log "device_name rollback completed"
}

# =============================================================================
# Watcher: if user disables the module at runtime (Magisk creates $MODDIR/disable),
# rollback persistent settings before reboot so disable doesn't leave residue.
# Note: Magisk will not execute module scripts on the next boot when disabled,
# so we must catch the disable event while the module is still running.
# =============================================================================
watch_disable_and_rollback() {
    # Only watch if we previously applied a persistent value.
    [ -f "$DEVICE_NAME_APPLIED_FLAG" ] || return 0

    log "Starting disable watcher for device_name..."

    # Poll very lightly; this process exits after rollback.
    while true; do
        # If module directory is gone (uninstalled), stop.
        [ -d "$MODDIR" ] || return 0

        if [ -f "$MODULE_DISABLE_FLAG" ]; then
            log "Detected module disable flag, rolling back device_name now"
            rollback_device_name || true
            return 0
        fi

        sleep 2
    done
}

# =============================================================================
# Apply: Set device_name from config
# =============================================================================
apply_device_name() {
    # Check if module is disabled - rollback instead of apply
    if [ -f "$MODULE_DISABLE_FLAG" ]; then
        log "Module is disabled, rolling back device_name"
        rollback_device_name
        return 0
    fi
    
    local model_name=""
    
    # Read model name from config file
    if [ -f "$MODEL_NAME_FILE" ]; then
        model_name=$(cat "$MODEL_NAME_FILE" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    if [ -z "$model_name" ]; then
        # If we previously applied a device_name and the config is now gone (e.g. updated module
        # without MODEL_NAME), rollback to avoid leaving a stale persistent setting behind.
        if [ -f "$DEVICE_NAME_APPLIED_FLAG" ]; then
            log "model_name.conf missing but device_name was previously applied; rolling back"
            rollback_device_name || true
        else
            log "No model_name.conf found, skip device_name override"
        fi
        return 0
    fi
    
    # Check if already applied (flag file exists and is newer than model_name.conf)
    if [ -f "$DEVICE_NAME_APPLIED_FLAG" ]; then
        if [ "$DEVICE_NAME_APPLIED_FLAG" -nt "$MODEL_NAME_FILE" ]; then
            log "device_name already applied, skip (user can modify manually)"
            return 0
        fi
    fi
    
    log "Applying device_name override: $model_name"
    
    if ! wait_for_settings_service; then
        return 1
    fi
    
    # Set device_name in global settings
    if settings put global device_name "$model_name" 2>/dev/null; then
        log "Set global device_name to: $model_name"
    else
        log "Warning: failed to set global device_name"
    fi
    
    # Also try to set bluetooth_name if available (some ROMs use this)
    settings put secure bluetooth_name "$model_name" 2>/dev/null && \
        log "Set secure bluetooth_name to: $model_name" || true
    
    # Create flag file to indicate device_name has been applied
    touch "$DEVICE_NAME_APPLIED_FLAG"
    log "device_name override completed"
}

# Run if executed directly (for testing)
if [ "${0##*/}" = "device_name.sh" ]; then
    apply_device_name
fi
