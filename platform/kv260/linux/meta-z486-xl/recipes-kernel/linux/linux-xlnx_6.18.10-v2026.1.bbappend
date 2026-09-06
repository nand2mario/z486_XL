# Preserve the board-tested kernel while bringing up the new root filesystem.
LINUX_VERSION = "6.18.0"
SRCREV = "3128e0f044012bb39c8e24551d72e4a72e0808f0"
KBRANCH = ""
LINUX_VERSION_EXTENSION = "-xilinx-2026.1-kria"
KBUILD_DEFCONFIG = ""
COMPATIBLE_MACHINE:amd-cortexa53-mali-common = "amd-cortexa53-mali-common"
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://defconfig file://0001-kv260-usb-reset.patch \
            file://0002-zynqmp-dpsub-live-audio.patch"
