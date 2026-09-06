SUMMARY = "z486 CMA allocation and UIO platform driver"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://z486_uio.c;beginline=1;endline=1;md5=50d2ba0afecd20f74c12a4bdbcfcfe61"

inherit module

FILESEXTRAPATHS:prepend := "${THISDIR}/files:/platform-source/kernel:/platform-source/include:"
SRC_URI = "file://Makefile file://z486_uio.c file://z486_kv260_memory_map.h"
S = "${WORKDIR}"
KERNEL_MODULE_AUTOLOAD += "z486_uio"
