SUMMARY = "z486 KV260 guest memory, IDE/input bridge and DRM scanout"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://z486-main.c;beginline=1;endline=1;md5=6ec41034e04432ee375d0e14fba596f4"

# The build container exposes only the platform source directory read-only.
# file:// inputs are hashed by BitBake, including edits before a git commit.
FILESEXTRAPATHS:prepend := "/platform-source/userspace:/platform-source/include:/platform-source/board:"
SRC_URI = "file://z486-main.c file://z486-ide.c file://z486-ide.h \
           file://z486-input.c file://z486-input.h file://z486-drm.c \
           file://z486_kv260_memory_map.h file://zsst-perf.py"
S = "${WORKDIR}"
DEPENDS = "linux-libc-headers"
RDEPENDS:${PN} += "python3-core python3-ctypes python3-json python3-mmap"

do_compile() {
    ${CC} ${CPPFLAGS} ${CFLAGS} -I${S} ${LDFLAGS} \
        -o z486-main z486-main.c z486-ide.c z486-input.c
    ${CC} ${CPPFLAGS} ${CFLAGS} ${LDFLAGS} -o z486-drm z486-drm.c
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 z486-main z486-drm ${D}${bindir}/
    install -m 0755 ${S}/zsst-perf.py ${D}${bindir}/zsst-perf
}
