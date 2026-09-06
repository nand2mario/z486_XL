# z486 XL uses fancontrol only. The default sensord daemon pulls in rrdtool
# and a graphics/text-rendering stack that the console image does not need.
PACKAGECONFIG:remove = "sensord"

# The generic arm64 machine does not receive meta-xilinx's zynqmp overrides.
# Apply the two fancontrol settings needed by the Kria image explicitly: do
# not pull the dummy /etc/fancontrol, and start the service at boot.
RRECOMMENDS:${PN}-fancontrol = ""
SYSTEMD_AUTO_ENABLE:${PN}-fancontrol = "enable"
