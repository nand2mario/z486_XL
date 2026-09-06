#!/usr/bin/env bash
set -euo pipefail

main_pid=""
drm_pid=""
main_args=("$@")

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [[ -n "$drm_pid" ]] && kill -0 "$drm_pid" 2>/dev/null; then
        kill -TERM "$drm_pid"
        wait "$drm_pid" 2>/dev/null || true
    fi
    if [[ -n "$main_pid" ]] && kill -0 "$main_pid" 2>/dev/null; then
        kill -TERM "$main_pid"
        wait "$main_pid" 2>/dev/null || true
    fi
    z486-kv260ctl stock || true
    exit "$status"
}

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run this command as root on the KV260.\n' >&2
    exit 1
fi
if ! command -v z486-drm >/dev/null; then
    printf 'z486-drm is required to hold the DRM 1080p mode.\n' >&2
    exit 1
fi

exec 9>/run/z486-run.lock
if ! flock -n 9; then
    printf 'Another z486-run launcher is already active.\n' >&2
    exit 1
fi
if pgrep -x z486-main >/dev/null; then
    printf 'z486-main is already running.\n' >&2
    exit 1
fi

have_keyboard=0
have_mouse=0
for arg in "$@"; do
    [[ "$arg" == "--keyboard" ]] && have_keyboard=1
    [[ "$arg" == "--mouse" ]] && have_mouse=1
done

find_input_event() {
    local kind=$1
    awk -v kind="$kind" '
        /^H: Handlers=/ {
            keyboard = 0
            mouse = 0
            event = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "kbd")
                    keyboard = 1
                if ($i ~ /^mouse[0-9]+$/)
                    mouse = 1
                if ($i ~ /^event[0-9]+$/)
                    event = $i
            }
            matched = (kind == "keyboard" && keyboard) ||
                      (kind == "mouse" && mouse) ||
                      (kind == "combined" && keyboard && mouse)
            if (matched && event != "") {
                print "/dev/input/" event
                exit
            }
        }
    ' /proc/bus/input/devices
}

combined=$(find_input_event combined)
if (( ! have_keyboard )); then
    keyboard=${combined:-$(find_input_event keyboard)}
    if [[ -n "$keyboard" ]]; then
        main_args+=(--keyboard "$keyboard")
        printf 'Using keyboard %s\n' "$keyboard"
    fi
fi
if (( ! have_mouse )); then
    mouse=${combined:-$(find_input_event mouse)}
    if [[ -n "$mouse" ]]; then
        main_args+=(--mouse "$mouse")
        printf 'Using mouse %s\n' "$mouse"
    fi
fi
for drm_client in z486-drm live-pattern; do
    if pgrep -x "$drm_client" >/dev/null; then
        printf 'Stopping the existing %s DRM session.\n' "$drm_client"
        pkill -TERM -x "$drm_client"
        for _ in 1 2 3 4 5; do
            pgrep -x "$drm_client" >/dev/null || break
            sleep 1
        done
        if pgrep -x "$drm_client" >/dev/null; then
            printf 'The existing %s process did not stop.\n' "$drm_client" >&2
            exit 1
        fi
    fi
done

z486-kv260ctl load
trap cleanup EXIT INT TERM HUP

z486-main "${main_args[@]}" &
main_pid=$!
z486-drm red 1920x1080 &
drm_pid=$!

set +e
wait -n "$main_pid" "$drm_pid"
result=$?
set -e
exit "$result"
