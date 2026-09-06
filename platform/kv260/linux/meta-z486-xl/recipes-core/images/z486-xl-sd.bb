require z486-xl-rootfs.bb
SUMMARY = "z486 XL KV260 SD bring-up image"
IMAGE_INSTALL:append = " dfx-mgr z486-xl-grow-root z486-xl-launcher z486-xl-roms z486-xl-usb-mount"
# Requested root/1 login also supports SCP/SFTP on a trusted local network.
# Do not add empty-password or automatic-login features.
IMAGE_FEATURES:append = " ssh-server-openssh allow-root-login"
IMAGE_FSTYPES = "wic.xz wic.bmap"
IMAGE_BASENAME = "z486_XL-sd-kv260"
IMAGE_MACHINE_SUFFIX = ""
IMAGE_NAME_SUFFIX = ""
WKS_FILE = "z486-xl.wks"
# Only FAT/ext4 SD tools are needed, not the default ISO/Btrfs/EFI set.
WKS_FILE_DEPENDS = "z486-xl-boot e2fsprogs-native"
IMAGE_BOOT_FILES = "boot.scr.uimg image.fit"
do_image_wic[depends] += "z486-xl-boot:do_deploy"
