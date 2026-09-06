#!/usr/bin/env bash
# Sourced by project commands; machine-local paths never enter release recipes.
XL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -z ${Z486_XL_WORK:-} && -f "$XL_ROOT/.local.env" ]]; then
    source "$XL_ROOT/.local.env"
fi
Z486_XL_WORK=${Z486_XL_WORK:-"$XL_ROOT/build"}
Z486_ROM_DIR=${Z486_ROM_DIR:-"$XL_ROOT/roms"}
Z486_XL_BOARD=${Z486_XL_BOARD:-kv260}
if [[ ! $Z486_XL_BOARD =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Invalid Z486_XL_BOARD: $Z486_XL_BOARD" >&2
    return 2 2>/dev/null || exit 2
fi
XL_PLATFORM_ROOT=$XL_ROOT/platform/$Z486_XL_BOARD
XL_PLATFORM_LINUX_ROOT=$XL_PLATFORM_ROOT/linux
XL_REPO_COMMIT=97dc5c1bd9527c2abe2183b16a4b7ef037dc34a7
XL_MANIFEST_COMMIT=cf2b79dbf45608f8289c3ccf526745dbd8400f8f
