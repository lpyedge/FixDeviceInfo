#!/system/bin/sh
# Device Info Fix Module - post-fs-data script
# This runs early in boot to ensure overlay idmap is refreshed

MODDIR=${0%/*}

# Force overlay re-registration by disabling and enabling
# This ensures the system picks up our overlay APKs after module installation

enable_overlay() {
    local pkg="$1"
    # Try to enable overlay (it may not be registered yet on first boot)
    cmd overlay disable "$pkg" 2>/dev/null || true
    cmd overlay enable "$pkg" 2>/dev/null || true
    cmd overlay enable --user 0 "$pkg" 2>/dev/null || true
}

# Battery overlay (targets android framework)
enable_overlay "com.fixdeviceinfo.battery.overlay"

# CPU overlay (targets com.android.settings)
enable_overlay "com.fixdeviceinfo.cpu.overlay"

exit 0
