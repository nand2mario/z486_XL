#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
mkdir -p "$Z486_XL_WORK" "$XL_ROOT/.tools"
if [[ ! -d "$XL_ROOT/.tools/git-repo/.git" ]]; then
    git clone --depth 1 --branch v2.54 https://gerrit.googlesource.com/git-repo "$XL_ROOT/.tools/git-repo"
fi
test "$(git -C "$XL_ROOT/.tools/git-repo" rev-parse HEAD)" = "$XL_REPO_COMMIT"
cd "$Z486_XL_WORK"
"$XL_ROOT/.tools/git-repo/repo" init \
    -u https://github.com/Xilinx/yocto-manifests.git -b "$XL_MANIFEST_COMMIT" \
    -m default-edf.xml --depth=1 --no-clone-bundle --repo-rev=v2.54 \
    --repo-url=https://gerrit.googlesource.com/git-repo
"$XL_ROOT/.tools/git-repo/repo" sync -c --no-clone-bundle -j "${XL_SYNC_JOBS:-4}"
"$XL_ROOT/.tools/git-repo/repo" manifest -r -o manifest.lock.xml
