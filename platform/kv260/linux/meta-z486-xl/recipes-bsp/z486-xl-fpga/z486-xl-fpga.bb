SUMMARY = "Current z486 XL FPGA application artifacts"
# Prebuilt development artifact: redistribution/source-notice audit is pending.
# CLOSED here is a packaging restriction, not a claim about upstream licenses.
LICENSE = "CLOSED"
FILESEXTRAPATHS:prepend := "/work/firmware/current:"
SRC_URI = "file://z486_kv260.bit.bin file://z486_kv260.dtbo file://shell.json \
           file://z486_console.bit.bin file://z486_console.dtbo \
           file://console-shell.json file://SHA256SUMS"
S = "${WORKDIR}"
inherit allarch

python do_verify_artifacts() {
    import hashlib
    import pathlib
    required = {
        "z486_kv260.bit.bin", "z486_kv260.dtbo", "shell.json",
        "z486_console.bit.bin", "z486_console.dtbo", "console-shell.json",
    }
    expected = {}
    for line in (pathlib.Path(d.getVar("S")) / "SHA256SUMS").read_text().splitlines():
        fields = line.split()
        if len(fields) != 2 or fields[1] not in required or fields[1] in expected:
            bb.fatal("Invalid FPGA artifact manifest entry: " + line)
        expected[fields[1]] = fields[0]
    if set(expected) != required:
        bb.fatal("FPGA artifact manifest does not list exactly the required files")
    for name, digest in expected.items():
        actual = hashlib.sha256((pathlib.Path(d.getVar("S")) / name).read_bytes()).hexdigest()
        if actual != digest:
            bb.fatal("FPGA artifact does not match its generated manifest: " + name)
}
addtask verify_artifacts after do_unpack before do_install

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware/xilinx/z486-kv260
    install -d ${D}${nonarch_base_libdir}/firmware/xilinx/z486-console
    install -m 0644 ${S}/z486_kv260.bit.bin ${S}/z486_kv260.dtbo ${S}/shell.json \
        ${D}${nonarch_base_libdir}/firmware/xilinx/z486-kv260/
    install -m 0644 ${S}/z486_console.bit.bin ${S}/z486_console.dtbo \
        ${D}${nonarch_base_libdir}/firmware/xilinx/z486-console/
    install -m 0644 ${S}/console-shell.json \
        ${D}${nonarch_base_libdir}/firmware/xilinx/z486-console/shell.json
}
FILES:${PN} = "${nonarch_base_libdir}/firmware/xilinx/z486-kv260 \
               ${nonarch_base_libdir}/firmware/xilinx/z486-console"
