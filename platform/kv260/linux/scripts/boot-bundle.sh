#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../../scripts/common.sh"
if [[ $# != 4 ]]; then
    echo "Usage: $0 Image kv260-revA.dtb kv260-revB.dtb NEW_OUTPUT_DIR" >&2
    exit 2
fi
xl_boot_source=$XL_PLATFORM_LINUX_ROOT/boot
for input in "$1" "$2" "$3"; do test -f "$input"; done
command -v mkimage >/dev/null
# Do not overwrite any existing bundle or target a block device.
test ! -e "$4"
mkdir -p -- "$4"
cp -- "$1" "$4/Image"
cp -- "$2" "$4/kv260-revA.dtb"
cp -- "$3" "$4/kv260-revB.dtb"
cp -- "$xl_boot_source/image.its" "$4/image.its"
cp -- "$xl_boot_source/boot.cmd" "$4/boot.cmd"
cd -- "$4"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}
mkimage -f image.its image.fit
mkimage -A arm64 -T script -C none -n 'z486 XL SD boot' -d boot.cmd boot.scr.uimg
sha256sum image.fit boot.scr.uimg
