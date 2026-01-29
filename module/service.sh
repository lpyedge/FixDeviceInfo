#!/system/bin/sh
# Device Info Fix Module - Service Script
# Main entry point that orchestrates all feature modules
#
# Features:
# - Battery capacity override (bind-mount)
# - Volume curve optimization (bind-mount)
# - Brightness floor guard (sysfs)
# - Device name override (settings)

MODDIR=${0%/*}
LOG_FILE="$MODDIR/service.log"

# Export for sub-scripts
export MODDIR LOG_FILE

# =============================================================================
# Load common functions
# =============================================================================
if [ -f "$MODDIR/scripts/common.sh" ]; then
    . "$MODDIR/scripts/common.sh"
else
    # Fallback minimal log function if common.sh is missing
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }
    log "Warning: scripts/common.sh not found, using minimal logging"
fi

log "=============================================="
log "Service script started"
log "Module path: $MODDIR"

# =============================================================================
# Feature: Battery Overlay Enabling (Late Start)
# =============================================================================
# Enable overlay if RRO was generated (fallback/supplemental)
if [ -f "$MODDIR/scripts/battery.sh" ]; then
    . "$MODDIR/scripts/battery.sh"
    enable_battery_overlay
else
    log "Warning: scripts/battery.sh not found, skip battery overlay"
fi

# =============================================================================
# Feature: CPU Name Overlay (Late Start)
# =============================================================================
# Just ensure it's enabled (simple cmd call)
enable_cpu_overlay() {
    local bg_pkg="com.fixdeviceinfo.cpu.overlay"
    if cmd overlay list 2>/dev/null | grep -q "$bg_pkg"; then
        cmd overlay enable "$bg_pkg" 2>/dev/null && log "Enabled CPU name overlay"
    fi
}
enable_cpu_overlay

# =============================================================================
# Feature: Brightness Floor Guard (Runtime)
# =============================================================================
if [ -f "$MODDIR/scripts/brightness.sh" ]; then
    . "$MODDIR/scripts/brightness.sh"
    apply_brightness_floor
else
    log "Warning: scripts/brightness.sh not found, skip brightness floor"
fi

log "Service script completed"

# =============================================================================
# Feature: Device Name Override (runs in background)
# This needs to wait for settings service, so run async
# =============================================================================
if [ -f "$MODDIR/scripts/device_name.sh" ]; then
    (
        # Keep this self-contained: if common.sh is missing, device_name.sh will log minimally.
        [ -f "$MODDIR/scripts/common.sh" ] && . "$MODDIR/scripts/common.sh"
        . "$MODDIR/scripts/device_name.sh"

        apply_device_name
        # Watch for module disable at runtime and rollback persistent settings.
        watch_disable_and_rollback
    ) &
else
    log "Warning: scripts/device_name.sh not found, skip device_name override"
fi

exit 0
