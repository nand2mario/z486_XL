#!/usr/bin/env bash
set -euo pipefail

z486_app="z486-kv260"
stock_app="z486-console"
dfx_manager="/usr/bin/dfx-mgr-client"
dp_device="fd4a0000.display"

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run this command as root on the KV260.\n' >&2
    exit 1
fi

active_app() {
    "$dfx_manager" -listPackage | awk '$2 == "XRT_FLAT" && $4 != "-1" { print $5; exit }'
}

unbind_dp() {
    local device_path="/sys/bus/platform/devices/$dp_device" driver_path
    [[ -L "$device_path/driver" ]] || return 0
    driver_path="$(readlink -f "$device_path/driver")"
    printf '%s' "$dp_device" > "$driver_path/unbind"
}

bind_dp() {
    local driver_path
    [[ ! -L "/sys/bus/platform/devices/$dp_device/driver" ]] || return 0
    for driver_path in /sys/bus/platform/drivers/zynqmp-dpsub \
                       /sys/bus/platform/drivers/zynqmp-display; do
        if [[ -d "$driver_path" ]]; then
            printf '%s' "$dp_device" > "$driver_path/bind"
            return 0
        fi
    done
    printf 'Cannot find the ZynqMP DisplayPort driver.\n' >&2
    return 1
}

recover_display() {
    local status=$?
    trap - EXIT
    if (( status != 0 )); then
        bind_dp || true
        restore_console || true
    fi
    exit "$status"
}
trap recover_display EXIT

restore_console() {
    local blank="/sys/class/graphics/fb0/blank"
    for _ in {1..50}; do [[ -e "$blank" ]] && break; sleep 0.1; done
    [[ -e "$blank" ]] || return 1
    printf '0' > "$blank"
}

stop_drm_clients() {
    local client
    for client in z486-drm live-pattern; do
        pgrep -x "$client" >/dev/null || continue
        pkill -TERM -x "$client"
        for _ in 1 2 3 4 5; do
            pgrep -x "$client" >/dev/null || break
            sleep 1
        done
        if pgrep -x "$client" >/dev/null; then
            printf '%s did not release the DRM device.\n' "$client" >&2
            return 1
        fi
    done
}

show_status() {
    local current uio
    current="$(active_app)"
    printf 'FPGA application: %s\n' "${current:-none}"
    uio="$(grep -l '^z486$' /sys/class/uio/uio*/name 2>/dev/null | head -1 || true)"
    if [[ -n "$uio" ]]; then
        printf 'z486 controller: /dev/%s\n' "$(basename "$(dirname "$uio")")"
        printf 'CMA free: %s KiB\n' "$(awk '/CmaFree/ {print $2}' /proc/meminfo)"
    else
        printf 'z486 controller: unavailable\n'
    fi
    if [[ -L "/sys/bus/platform/devices/$dp_device/driver" ]]; then
        printf 'DPSUB driver: %s\n' \
            "$(basename "$(readlink -f "/sys/bus/platform/devices/$dp_device/driver")")"
    else
        printf 'DPSUB driver: unbound\n'
    fi
}

load_app() {
    local previous
    previous="$(active_app)"
    if [[ "$previous" == "$z486_app" ]]; then
        bind_dp
        show_status
        return 0
    fi
    if pgrep -x z486-main >/dev/null; then
        printf 'Refusing to switch while z486-main is running.\n' >&2
        exit 1
    fi
    stop_drm_clients
    modprobe z486_uio
    unbind_dp
    if [[ -n "$previous" ]]; then "$dfx_manager" -unloadByName "$previous"; fi
    "$dfx_manager" -loadByName "$z486_app"
    bind_dp
    udevadm settle
    for _ in $(seq 1 20); do
        grep -q '^z486$' /sys/class/uio/uio*/name 2>/dev/null && break
        sleep 0.25
    done
    grep -q '^z486$' /sys/class/uio/uio*/name
    show_status
}

unload_app() {
    local previous
    if pgrep -x z486-main >/dev/null; then
        printf 'Stop z486-main before unloading the FPGA application.\n' >&2
        exit 1
    fi
    previous="$(active_app)"
    if [[ "$previous" == "$stock_app" ]]; then
        bind_dp
        restore_console
        show_status
        return 0
    fi
    # Guest reset does not reset the PS AXI queues. Never reconfigure away
    # the masters until all accepted addresses, data and responses drained.
    if [[ "$previous" == "$z486_app" ]]; then
        z486-main --stop
    fi
    stop_drm_clients
    unbind_dp
    [[ -z "$previous" ]] || "$dfx_manager" -unloadByName "$previous"
    "$dfx_manager" -loadByName "$stock_app"
    bind_dp
    restore_console
    show_status
}

case "${1:-status}" in
    load) load_app ;;
    unload) unload_app ;;
    stock) unload_app ;;
    status) show_status ;;
    *) printf 'Usage: %s {load|unload|stock|status}\n' "$0" >&2; exit 2 ;;
esac
