#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Optionally wait for an already-running container build instead of duplicating it.
if [[ -n ${1:-} ]]; then
    [[ $1 =~ ^[0-9]+$ ]] || exit 2
    while kill -0 "$1" 2>/dev/null; do sleep 10; done
fi
docker image inspect z486-xl-build:2026.1 >/dev/null
make parse
make rootfs
