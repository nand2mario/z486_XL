SUMMARY = "XL VHD launcher using the tested KV260 application loader"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
FILESEXTRAPATHS:prepend := "${THISDIR}/files:/platform-source/board:"
SRC_URI = "file://z486-run file://z486-thermal file://appctl.sh file://z486-xl.conf \
           file://z486-console.service"
S = "${WORKDIR}"
inherit systemd
RDEPENDS:${PN} = "bash coreutils util-linux-flock procps udev z486-userspace dfx-mgr z486-uio z486-xl-fpga"
SYSTEMD_SERVICE:${PN} = "z486-console.service"
SYSTEMD_AUTO_ENABLE = "enable"
do_install() {
    install -d ${D}${bindir} ${D}${sbindir} ${D}${nonarch_libdir}/tmpfiles.d \
        ${D}${systemd_system_unitdir}
    install -m 0755 ${S}/z486-run ${D}${bindir}/z486-run
    install -m 0755 ${S}/z486-thermal ${D}${bindir}/z486-thermal
    install -m 0755 ${S}/appctl.sh ${D}${sbindir}/z486-kv260ctl
    install -m 0644 ${S}/z486-xl.conf ${D}${nonarch_libdir}/tmpfiles.d/
    install -m 0644 ${S}/z486-console.service ${D}${systemd_system_unitdir}/
}
FILES:${PN} += "${nonarch_libdir}/tmpfiles.d/z486-xl.conf \
                ${systemd_system_unitdir}/z486-console.service"
