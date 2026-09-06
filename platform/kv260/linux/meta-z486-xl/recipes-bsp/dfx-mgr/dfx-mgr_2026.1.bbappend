# XL uses AMD's generic arm64 rootfs machine with a KV260-specific kernel/DT.
COMPATIBLE_MACHINE:amd-cortexa53-mali-common = "amd-cortexa53-mali-common"

# The console comes up before any guest is launched. Do not let EEPROM-based
# default firmware selection race the explicit launcher/DRM handoff.
SYSTEMD_SERVICE:${PN} = "dfx-mgr.service"
do_install:append() {
    install -d ${D}${sysconfdir}/systemd/system
    ln -s /dev/null ${D}${sysconfdir}/systemd/system/dfx-mgr-fw-load.service
}
