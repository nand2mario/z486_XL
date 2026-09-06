SUMMARY = "One-shot z486 XL SD root filesystem expansion"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://z486-xl-grow-root file://z486-xl-grow-root.service"
S = "${WORKDIR}"

RDEPENDS:${PN} = "e2fsprogs-resize2fs parted systemd util-linux-blockdev util-linux-findmnt util-linux-partx udev"
SYSTEMD_SERVICE:${PN} = "z486-xl-grow-root.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${S}/z486-xl-grow-root ${D}${sbindir}/z486-xl-grow-root
    install -m 0644 ${S}/z486-xl-grow-root.service ${D}${systemd_system_unitdir}/
}
