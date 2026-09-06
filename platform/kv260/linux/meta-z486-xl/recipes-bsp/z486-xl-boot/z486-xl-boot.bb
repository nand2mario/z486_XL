SUMMARY = "KV260 SD-only FIT and boot script"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
FILESEXTRAPATHS:prepend := "/platform-source/linux/boot:"
SRC_URI = "file://image.its file://boot.cmd"
S = "${WORKDIR}"
inherit deploy
DEPENDS = "u-boot-tools-native dtc-native"
do_compile[depends] += "virtual/kernel:do_deploy"

do_compile() {
    install -m 0644 ${DEPLOY_DIR_IMAGE}/Image ${B}/Image
    install -m 0644 ${DEPLOY_DIR_IMAGE}/zynqmp-smk-k26-revA-sck-kv-g-revA.dtb ${B}/kv260-revA.dtb
    install -m 0644 ${DEPLOY_DIR_IMAGE}/zynqmp-smk-k26-revA-sck-kv-g-revB.dtb ${B}/kv260-revB.dtb
    mkimage -f ${S}/image.its ${B}/image.fit
    mkimage -A arm64 -T script -C none -n 'z486 XL SD boot' -d ${S}/boot.cmd ${B}/boot.scr.uimg
}

do_deploy() {
    install -m 0644 ${B}/image.fit ${B}/boot.scr.uimg ${DEPLOYDIR}/
}
addtask deploy after do_compile before do_build
