SUMMARY = "Automatic removable USB filesystem mounting for z486 XL"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://99-z486-usb-mount.rules file://z486-usb-mount file://z486-usb-mount@.service"
S = "${WORKDIR}"

RDEPENDS:${PN} = "coreutils e2fsprogs kernel-module-exfat kernel-module-ntfs3 sed systemd udev util-linux-blkid util-linux-findmnt util-linux-mount util-linux-umount"
SYSTEMD_SERVICE:${PN} = "z486-usb-mount@.service"
SYSTEMD_AUTO_ENABLE = "disable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir} ${D}${nonarch_base_libdir}/udev/rules.d
    install -m 0755 ${S}/z486-usb-mount ${D}${sbindir}/z486-usb-mount
    install -m 0644 ${S}/z486-usb-mount@.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${S}/99-z486-usb-mount.rules ${D}${nonarch_base_libdir}/udev/rules.d/
}

FILES:${PN} += "${nonarch_base_libdir}/udev/rules.d/99-z486-usb-mount.rules"
