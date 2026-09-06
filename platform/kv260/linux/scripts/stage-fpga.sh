#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../../scripts/common.sh"
if [[ $# -eq 0 ]]; then
    # Refresh the application directory from the most recent successful Vivado
    # output. This packages an existing build; it does not launch Vivado.
    make -C "$XL_PLATFORM_ROOT" package-files
    xl_fpga_source=$XL_PLATFORM_ROOT/build/app
elif [[ $# -eq 1 ]]; then
    xl_fpga_source=$1
    if [[ -s "$xl_fpga_source/z486_kv260.bit.bin" ]]; then
        # Preserve the original interface, which accepted z486-kv260 itself.
        xl_fpga_source=$(dirname -- "$xl_fpga_source")
    fi
else
    printf 'Usage: %s [fpga-application-directory]\n' "$0" >&2
    exit 2
fi
xl_fpga_target=$Z486_XL_WORK/firmware/current
declare -A sources=(
    [z486_kv260.bit.bin]="$xl_fpga_source/z486-kv260/z486_kv260.bit.bin"
    [z486_kv260.dtbo]="$xl_fpga_source/z486-kv260/z486_kv260.dtbo"
    [shell.json]="$xl_fpga_source/z486-kv260/shell.json"
    [z486_console.bit.bin]="$xl_fpga_source/z486-console/z486_console.bit.bin"
    [z486_console.dtbo]="$xl_fpga_source/z486-console/z486_console.dtbo"
    [console-shell.json]="$xl_fpga_source/z486-console/shell.json"
)
files=(z486_kv260.bit.bin z486_kv260.dtbo shell.json
       z486_console.bit.bin z486_console.dtbo console-shell.json)

# Stage only the deployable files. Reports and generated Vivado metadata may
# contain host paths and must never enter an image or release artifact.
for file in "${files[@]}"; do
    [[ -s "${sources[$file]}" ]] || {
        printf 'Missing FPGA application artifact: %s\n' \
            "${sources[$file]}" >&2
        exit 1
    }
done
mkdir -p "$xl_fpga_target"
for file in "${files[@]}"; do
    install -C -m 0644 "${sources[$file]}" "$xl_fpga_target/$file"
done
manifest_tmp=$(mktemp "$xl_fpga_target/.SHA256SUMS.XXXXXX")
trap 'rm -f -- "$manifest_tmp"' EXIT
(
    cd "$xl_fpga_target"
    sha256sum "${files[@]}"
) >"$manifest_tmp"
chmod 0644 "$manifest_tmp"
mv -f -- "$manifest_tmp" "$xl_fpga_target/SHA256SUMS"
trap - EXIT

printf 'Staged current FPGA application from %s\n' "$xl_fpga_source"
cat "$xl_fpga_target/SHA256SUMS"
