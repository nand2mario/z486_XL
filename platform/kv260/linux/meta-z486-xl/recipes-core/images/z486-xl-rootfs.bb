SUMMARY = "Minimal z486 XL bring-up root filesystem (not a complete SD image)"
LICENSE = "MIT"

inherit core-image
inherit extrausers

# User-requested MiSTer-style login: root / 1, no forced password change.
# Public default credentials are suitable only for a trusted local network.
XL_ROOT_PASSWORD_HASH = "\$6\$z486xl\$cE6Smc7K5mXstu2KTP1o58PTTDWA5LxXrUGrWSwh4mYEKUtI.GHyNpPPWepCpqcJqjEZvWb9nZnezMDFzc8tC1"
EXTRA_USERS_PARAMS = "usermod -p '${XL_ROOT_PASSWORD_HASH}' root;"

# No desktop, SDK, vendor demo collection, or passwordless SSH.
# The board-specific boot partition is assembled by z486-xl-sd.
IMAGE_FEATURES = ""
# Depend on the out-of-tree recipe's module metapackage explicitly. The
# kernel's dynamic kernel-module-* provider can otherwise hide this recipe.
IMAGE_INSTALL = "packagegroup-core-boot python3-core libdrm libgpiod-tools z486-userspace z486-uio kbd kbd-consolefonts lmsensors-config-kria-fancontrol"
# Keep the broad tested kernel configuration, but do not ship every optional
# module (~7 GiB). SD, Ethernet, DPSUB, FPGA manager and filesystems are built in.
# These cover carrier peripherals and USB input; package dependencies pull in
# their supporting modules. Revalidate the selection on the physical board.
IMAGE_INSTALL:append = " \
    kernel-module-uio-pdrv-genirq kernel-module-usbhid \
    kernel-module-hid-logitech kernel-module-hid-logitech-dj \
    kernel-module-hid-logitech-hidpp kernel-module-joydev \
    kernel-module-input-leds kernel-module-display-connector \
    kernel-module-da9121-regulator kernel-module-i2c-cadence \
    kernel-module-rtc-zynqmp kernel-module-thermal-generic-adc \
    kernel-module-zynqmp-edac \
"
IMAGE_FSTYPES = "tar.xz ext4"
IMAGE_ROOTFS_EXTRA_SPACE = "65536"

# Boot artifacts are assembled separately for the existing SD FIT boot flow.
ROOTFS_BOOTSTRAP_INSTALL = ""
MACHINE_ESSENTIAL_EXTRA_RDEPENDS:pn-packagegroup-core-boot = ""

ROOTFS_POSTPROCESS_COMMAND:append = " xl_console_identity;"
python xl_console_identity() {
    from pathlib import Path
    etc = Path(d.getVar("IMAGE_ROOTFS")) / "etc"
    build = d.getVar("IMAGE_VERSION_SUFFIX").lstrip("-")
    welcome = "Welcome to z486 XL, build " + build + "\n"
    for filename in ("issue", "issue.net"):
        (etc / filename).write_text(welcome)
    motd = f"""Welcome to z486 XL, test build {build}

This is experimental software. Keep backups of VHDs and removable media.

Quick start:
  Put VHD files in /root/games, using SFTP/SCP or a USB drive.
  Start one with: z486-run /root/games/<disk>.vhd
  Quit the guest with Ctrl+Alt+Esc; the Linux console will return.
  USB drives mount at /media/<label>; unmount them before unplugging.
  Run z486-run --help for launcher options.
"""
    (etc / "motd").write_text(motd)
    # 16x32 glyphs: twice the common 8x16 size, approximately 120x33 at 1080p.
    # systemd applies this to Linux virtual consoles, not the serial terminal.
    (etc / "vconsole.conf").write_text("KEYMAP=us\nFONT=latarcyrheb-sun32\n")
}
