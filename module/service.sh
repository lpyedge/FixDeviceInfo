#!/system/bin/sh
# Device Info Fix Module - Service Script
# Hybrid method:
# 1) Preferred: dynamically locate the active power_profile.xml (often under /odm/...) and bind-mount a patched copy.
#    - Only replaces battery.capacity, keeps vendor's full profile intact.
#    - No partition is written; changes disappear after reboot/disable/uninstall.
# 2) Fallback: try to enable the RRO overlay (may be blocked on some ROMs).

MODDIR=${0%/*}
LOG_FILE="$MODDIR/service.log"
CONF_FILE="$MODDIR/battery_capacity.conf"
TARGET_FILE="$MODDIR/power_profile_target"

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

trim_log

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
    trim_log
}

log "Service script started"

CAP=""
if [ -f "$CONF_FILE" ]; then
    CAP=$(cat "$CONF_FILE" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

is_int() {
    case "$1" in
        *[!0-9]*|'') return 1 ;;
        *) return 0 ;;
    esac
}

find_power_profile() {
    # Search likely partitions first; stop at first hit.
    for root in \
        /odm/etc/power_profile \
        /odm/etc \
        /odm \
        /vendor/etc \
        /vendor \
        /product/etc \
        /product \
        /system/etc \
        /system \
        /system_ext/etc \
        /system_ext; do
        [ -d "$root" ] || continue
        p=$(find "$root" -name power_profile.xml 2>/dev/null | head -n 1)
        if [ -n "$p" ] && [ -f "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

enable_overlay_fallback() {
    local overlay_package="com.fixdeviceinfo.battery.overlay"
    if cmd overlay list 2>/dev/null | grep -q "$overlay_package"; then
        cmd overlay enable --user 0 "$overlay_package" 2>/dev/null && log "Enabled overlay for user 0"
        cmd overlay enable "$overlay_package" 2>/dev/null && log "Enabled overlay (all users)"
        return 0
    fi
    return 1
}

if ! is_int "$CAP"; then
    # Safety principle: if user did not configure battery capacity, do not touch/enable any battery override.
    log "No valid battery_capacity.conf, skip all battery overrides"
    log "Service script completed"
    exit 0
fi

# Wait a bit for early boot mounts to settle
sleep 5

SRC=$(find_power_profile || true)
if [ -z "$SRC" ]; then
    log "power_profile.xml not found in known locations"
    enable_overlay_fallback || true
    log "Service script completed"
    exit 0
fi

log "Found power_profile: $SRC"
echo "$SRC" > "$TARGET_FILE" 2>/dev/null || true

WORKDIR="$MODDIR/power_profile"
mkdir -p "$WORKDIR" 2>/dev/null || true
OUT="$WORKDIR/power_profile.xml"

# Create patched copy (preserve full OEM file, only replace battery.capacity)
if grep -q 'name="battery\.capacity"' "$SRC"; then
    sed -E "s#(<item[[:space:]]+name=\"battery\.capacity\">)[0-9]+(</item>)#\1${CAP}\2#" "$SRC" > "$OUT" 2>/dev/null
else
    cp "$SRC" "$OUT" 2>/dev/null
    if grep -q '</device>' "$OUT" 2>/dev/null; then
        sed -i "s#</device>#  <item name=\"battery.capacity\">${CAP}</item>\n</device>#" "$OUT" 2>/dev/null || true
    else
        echo "<!-- patched by Device Info Fix -->" >> "$OUT"
        echo "<item name=\"battery.capacity\">${CAP}</item>" >> "$OUT"
    fi
fi

chmod 0644 "$OUT" 2>/dev/null || true

# Preserve SELinux context to reduce ROM/system_server access denials.
# Some ROMs block reading a bind-mounted file if it keeps a magisk_file label.
SRC_CTX=""
SRC_CTX_LINE=$(ls -Z "$SRC" 2>/dev/null || true)
if [ -n "$SRC_CTX_LINE" ]; then
    SRC_CTX=${SRC_CTX_LINE%% *}
fi

if command -v chcon >/dev/null 2>&1; then
    if chcon --reference="$SRC" "$OUT" 2>/dev/null; then
        log "Applied SELinux context via chcon --reference"
    elif [ -n "$SRC_CTX" ] && chcon "$SRC_CTX" "$OUT" 2>/dev/null; then
        log "Applied SELinux context via chcon $SRC_CTX"
    else
        log "Warning: failed to apply SELinux context to patched file"
    fi
else
    log "Warning: chcon not found, cannot preserve SELinux context"
fi

# Bind-mount patched file over the discovered path
umount "$SRC" 2>/dev/null || true
if mount --bind "$OUT" "$SRC" 2>/dev/null; then
    log "Bind-mounted patched power_profile to $SRC (capacity=$CAP)"
else
    log "Bind-mount failed for $SRC"
    enable_overlay_fallback || true
fi

log "Service script completed"
exit 0
