#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
mkdir -p "$Z486_XL_WORK"
if [[ ${1:-} == build ]]; then
    exec docker build --build-arg BUILD_UID="$(id -u)" --build-arg BUILD_GID="$(id -g)" \
        -t z486-xl-build:2026.1 "$XL_ROOT/container"
fi
for directory in "$XL_PLATFORM_ROOT" "$XL_PLATFORM_LINUX_ROOT" "$Z486_ROM_DIR"; do
    if [[ ! -d $directory ]]; then
        echo "Missing directory: $directory" >&2
        exit 2
    fi
done
tty_args=()
if [[ -t 0 && -t 1 ]]; then tty_args=(-it); fi
network_args=()
if [[ -n ${XL_QEMU_SSH_PORT:-} ]]; then
    [[ $XL_QEMU_SSH_PORT =~ ^[0-9]{4,5}$ ]] &&
        (( XL_QEMU_SSH_PORT >= 1024 && XL_QEMU_SSH_PORT <= 65535 )) || {
        echo 'Invalid QEMU SSH test port' >&2; exit 2;
    }
    network_args=(-p "127.0.0.1:$XL_QEMU_SSH_PORT:$XL_QEMU_SSH_PORT"
                  -e XL_QEMU_SSH_PORT)
fi
exec docker run --rm --init "${tty_args[@]}" \
    "${network_args[@]}" \
    -e "Z486_XL_BOARD=$Z486_XL_BOARD" \
    -v "$XL_ROOT:/project" -v "$Z486_XL_WORK:/work" \
    -v "$XL_PLATFORM_ROOT:/platform-source:ro" \
    -v "$Z486_ROM_DIR:/rom-source:ro" \
    -w /work z486-xl-build:2026.1 "$@"
