# KV260 PMOD J2 debug LEDs.
set_property PACKAGE_PIN H12 [get_ports {led[0]}]
set_property PACKAGE_PIN B10 [get_ports {led[1]}]
set_property PACKAGE_PIN E10 [get_ports {led[2]}]
set_property PACKAGE_PIN E12 [get_ports {led[3]}]
set_property PACKAGE_PIN D10 [get_ports {led[4]}]
set_property PACKAGE_PIN D11 [get_ports {led[5]}]
set_property PACKAGE_PIN C11 [get_ports {led[6]}]
set_property PACKAGE_PIN B11 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property PULLDOWN true [get_ports {led[*]}]

# KV260 carrier fan PWM from TTC0 channel 2 through EMIO.
set_property PACKAGE_PIN A12 [get_ports {fan_en_b}]
set_property IOSTANDARD LVCMOS33 [get_ports {fan_en_b}]
set_property SLEW SLOW [get_ports {fan_en_b}]
set_property DRIVE 4 [get_ports {fan_en_b}]
