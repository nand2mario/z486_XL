#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf 'Run this installer as root on the KV260.\n' >&2
    exit 1
fi

source_dir="${1:-build/app/z486-kv260}"
module_file="${2:-build/module/z486_uio.ko}"
main_file="${3:-userspace/z486-main}"
drm_file="${4:-userspace/z486-drm}"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_dir="/lib/firmware/xilinx/z486-kv260"

for file in z486_kv260.bit.bin z486_kv260.dtbo shell.json; do
    [[ -f "$source_dir/$file" ]] || {
        printf 'Missing %s/%s\n' "$source_dir" "$file" >&2
        exit 1
    }
done
[[ -f "$module_file" ]] || { printf 'Missing %s\n' "$module_file" >&2; exit 1; }
[[ -f "$main_file" ]] || { printf 'Missing %s\n' "$main_file" >&2; exit 1; }
[[ -f "$drm_file" ]] || { printf 'Missing %s\n' "$drm_file" >&2; exit 1; }

module_release=$(modinfo -F vermagic "$module_file" | awk '{print $1}')
if [[ "$module_release" != "$(uname -r)" ]]; then
    printf 'Module is for %s, but this board runs %s\n' \
        "$module_release" "$(uname -r)" >&2
    exit 1
fi

install -d -m 0755 "$target_dir"
install -m 0644 "$source_dir/z486_kv260.bit.bin" "$target_dir/"
install -m 0644 "$source_dir/z486_kv260.dtbo" "$target_dir/"
install -m 0644 "$source_dir/shell.json" "$target_dir/"
install -d -m 0755 "/lib/modules/$(uname -r)/extra"
install -m 0644 "$module_file" "/lib/modules/$(uname -r)/extra/z486_uio.ko"
install -m 0755 "$main_file" /usr/local/bin/z486-main
install -m 0755 "$drm_file" /usr/local/bin/z486-drm
install -m 0755 "$script_dir/appctl.sh" /usr/local/sbin/z486-kv260ctl
install -m 0755 "$script_dir/run.sh" /usr/local/bin/z486-run
install -m 0755 "$script_dir/zsst-perf.py" /usr/local/bin/zsst-perf
depmod -a
modprobe z486_uio

printf 'Installed z486-kv260, z486_uio, z486-main, z486-drm, z486-run, and z486-kv260ctl.\n'
