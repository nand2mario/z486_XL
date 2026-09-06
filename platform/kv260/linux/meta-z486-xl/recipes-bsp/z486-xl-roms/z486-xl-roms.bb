SUMMARY = "Existing release BIOS ROMs for local XL bring-up"
# Prebuilt development inputs; source/license notice audit precedes publication.
LICENSE = "CLOSED"
FILESEXTRAPATHS:prepend := "/rom-source:"
SRC_URI = "file://boot0.rom file://boot1.rom"
S = "${WORKDIR}"
inherit allarch
do_install() {
    install -d ${D}/root/games
    install -m 0644 ${S}/boot0.rom ${S}/boot1.rom ${D}/root/games/
}
FILES:${PN} = "/root/games"
