#!/system/bin/sh

if [ -z "$MODDIR" ]; then
    MODDIR=$(cd "${0%/*}/.." 2>/dev/null && pwd)
fi

if [ -z "$LOG_FILE" ] && [ -n "$MODDIR" ]; then
    LOG_FILE="$MODDIR/service.log"
fi

if [ -f "$MODDIR/scripts/common.sh" ]; then
    . "$MODDIR/scripts/common.sh"
else
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "${LOG_FILE:-/dev/null}" 2>/dev/null || true; }
    is_int() { case "$1" in *[!0-9]*|'') return 1 ;; *) return 0 ;; esac; }
fi

AUTO_BRIGHTNESS_FIX_CONF="$MODDIR/auto_brightness_fix.conf"
MODULE_DISABLE_FLAG="$MODDIR/disable"
PID_FILE="$MODDIR/.auto_brightness_fix.pid"

read_interval_seconds() {
    local interval=""
    interval=$(cat "$AUTO_BRIGHTNESS_FIX_CONF" 2>/dev/null | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if is_int "$interval"; then
        if [ "$interval" -ge 1 ] && [ "$interval" -le 3600 ]; then
            echo "$interval"
            return 0
        fi
    fi

    echo 30
    return 0
}

read_backlight_value() {
    local bl_dir="$1"
    local v=""
    if [ -r "$bl_dir/actual_brightness" ]; then
        v=$(cat "$bl_dir/actual_brightness" 2>/dev/null | tr -d '\r\n')
    else
        v=$(cat "$bl_dir/brightness" 2>/dev/null | tr -d '\r\n')
    fi
    echo "$v"
}

is_screen_likely_on() {
    local bl_dir
    local v
    for bl_dir in /sys/class/backlight/*; do
        [ -d "$bl_dir" ] || continue
        [ -r "$bl_dir/brightness" ] || continue
        v=$(read_backlight_value "$bl_dir")
        is_int "$v" || continue
        [ "$v" -gt 0 ] && return 0
    done
    return 1
}

is_pid_running() {
    local pid="$1"
    is_int "$pid" || return 1
    kill -0 "$pid" 2>/dev/null
}

start_auto_brightness_daemon() {
    [ -f "$AUTO_BRIGHTNESS_FIX_CONF" ] || return 0
    [ -f "$MODULE_DISABLE_FLAG" ] && return 0

    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n')
        if is_pid_running "$old_pid"; then
            log "Auto-brightness fixer daemon already running (pid=$old_pid)"
            return 0
        fi
        rm -f "$PID_FILE" 2>/dev/null || true
    fi

    if [ ! -f "$MODDIR/scripts/auto_brightness_fixer.sh" ]; then
        log "Warning: auto_brightness_fixer.sh not found, skip daemon"
        return 0
    fi

    (
        log "Auto-brightness fixer daemon started"

        interval=""

        while true; do
            [ -d "$MODDIR" ] || exit 0
            [ -f "$MODULE_DISABLE_FLAG" ] && exit 0
            [ -f "$AUTO_BRIGHTNESS_FIX_CONF" ] || exit 0

            interval=$(read_interval_seconds)

            if ! is_screen_likely_on; then
                sleep 300
                continue
            fi

            sh "$MODDIR/scripts/auto_brightness_fixer.sh" >/dev/null 2>&1 || true
            sleep "$interval"
        done
    ) &

    local pid
    pid=$!
    echo "$pid" > "$PID_FILE" 2>/dev/null || true
    log "Auto-brightness fixer daemon forked (pid=$pid)"
    return 0
}

stop_auto_brightness_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null | tr -d '\r\n')

    if is_pid_running "$pid"; then
        kill "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE" 2>/dev/null || true
    return 0
}

if [ "${0##*/}" = "auto_brightness_daemon.sh" ]; then
    start_auto_brightness_daemon
fi
