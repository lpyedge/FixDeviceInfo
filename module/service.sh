#!/system/bin/sh
# Device Info Fix Module - Service Script
# This script runs at late_start service time to enable the overlay

MODDIR=${0%/*}
LOG_FILE="$MODDIR/service.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Service script started"

# Wait for system to be ready
sleep 5

# Function to enable overlay
enable_overlay() {
    local overlay_package="com.fixdeviceinfo.battery.overlay"
    
    # Try different methods to check and enable overlay
    
    # Method 1: Check via cmd overlay
    if cmd overlay list 2>/dev/null | grep -q "$overlay_package"; then
        log "Found overlay via cmd overlay list"
        cmd overlay enable --user 0 "$overlay_package" 2>/dev/null && log "Enabled via cmd overlay enable --user 0"
        cmd overlay enable "$overlay_package" 2>/dev/null && log "Enabled via cmd overlay enable"
        return 0
    fi
    
    # Method 2: Check if overlay is installed but not registered
    # Look for the APK in vendor/product overlay directories
    local overlay_apk=""
    for path in /system/vendor/overlay/battery-overlay.apk /system/product/overlay/battery-overlay.apk; do
        if [ -f "$path" ]; then
            overlay_apk="$path"
            log "Found overlay APK at: $path"
            break
        fi
    done
    
    if [ -n "$overlay_apk" ]; then
        # Try to trigger overlay refresh
        settings put global overlay_display_devices none 2>/dev/null
        log "Triggered overlay refresh"
    fi
    
    return 1
}

# Try to enable overlay (with retries)
for i in 1 2 3 4 5; do
    log "Attempt $i to enable overlay"
    if enable_overlay; then
        log "Overlay enabled successfully"
        break
    fi
    sleep 3
done

# Check final overlay status
log "Final overlay status:"
cmd overlay list 2>/dev/null | grep -i "battery\|fixdevice" >> "$LOG_FILE" 2>&1

log "Service script completed"
exit 0
