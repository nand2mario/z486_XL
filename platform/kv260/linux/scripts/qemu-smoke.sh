#!/usr/bin/env bash
set -euo pipefail
# Run via container.sh; pass container-visible kernel and ext4 image paths.
if [[ $# != 2 ]]; then
    echo "Usage: $0 Image rootfs.ext4" >&2
    exit 2
fi
test -f "$1"
test -f "$2"
xl_qemu=/work/build/tmp/sysroots-components/x86_64/qemu-system-native/usr/bin/qemu-system-aarch64
shopt -s nullglob
xl_qemu_libs=(/work/build/tmp/work/x86_64-linux/qemu-system-native/*/recipe-sysroot-native/usr/lib)
if [[ ${#xl_qemu_libs[@]} != 1 ]]; then
    echo "Expected exactly one built QEMU native sysroot" >&2
    exit 1
fi
export LD_LIBRARY_PATH=${xl_qemu_libs[0]}
# An init shell is deliberate: validates kernel/rootfs binaries, not normal init
# services or KV260 peripherals. QEMU snapshot writes never modify the image.
xl_init='init=/bin/sh'
if [[ ${XL_QEMU_NORMAL_BOOT:-0} == 1 ]]; then xl_init=''; fi
xl_network=(-nic none)
if [[ -n ${XL_QEMU_SSH_PORT:-} ]]; then
    [[ $XL_QEMU_SSH_PORT =~ ^[0-9]{4,5}$ ]] &&
        (( XL_QEMU_SSH_PORT >= 1024 && XL_QEMU_SSH_PORT <= 65535 )) || exit 2
    # container.sh publishes this port only on the host's loopback address.
    xl_network=(-nic "user,model=virtio-net-pci,hostfwd=tcp:0.0.0.0:$XL_QEMU_SSH_PORT-:22")
fi
exec "$xl_qemu" -machine virt -cpu cortex-a53 -m 1024 -nographic "${xl_network[@]}" \
    -kernel "$1" -drive "file=$2,format=raw,if=virtio,snapshot=on" \
    -append "root=${XL_QEMU_ROOT:-/dev/vda} rw console=ttyAMA0 audit=0 $xl_init"
