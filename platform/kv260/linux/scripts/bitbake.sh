#!/usr/bin/env bash
set -eo pipefail
# Run inside the build container; upstream environment setup is not nounset-safe.
cd /work
unset TEMPLATECONF
source ./edf-init-build-env /work/build
xl_layer=/platform-source/linux/meta-z486-xl
xl_site_conf=/platform-source/linux/config/site.conf
# Remove the pre-platform-layout path from an existing development build.
if grep -Fq '/project/meta-z486-xl' conf/bblayers.conf; then
    sed -i '\|/project/meta-z486-xl|d' conf/bblayers.conf
fi
if ! grep -Fq "$xl_layer" conf/bblayers.conf; then
    bitbake-layers add-layer "$xl_layer"
fi
exec bitbake -R "$xl_site_conf" "$@"
