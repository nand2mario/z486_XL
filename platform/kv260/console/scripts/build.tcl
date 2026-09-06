set script_dir [file normalize [file dirname [info script]]]
set console_dir [file normalize [file join $script_dir ..]]
set board_dir [file normalize [file join $console_dir ..]]
set build_dir [file join $board_dir build console_vivado]

file mkdir $build_dir
create_project z486_console $build_dir -force -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
set_property target_language Verilog [current_project]

read_xdc [file join $console_dir constraints kv260_console.xdc]

create_bd_design z486_console_platform
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1} \
    CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO} \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_ACE {0} \
    CONFIG.PSU__USE__S_AXI_ACP {0} \
    CONFIG.PSU__USE__S_AXI_GP0 {0} \
    CONFIG.PSU__USE__S_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP3 {0} \
    CONFIG.PSU__USE__S_AXI_GP4 {0} \
    CONFIG.PSU__USE__S_AXI_GP5 {0} \
    CONFIG.PSU__USE__S_AXI_GP6 {0}] $ps

set fan_pwm [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 fan_pwm]
set_property -dict [list \
    CONFIG.DIN_FROM {2} \
    CONFIG.DIN_TO {2} \
    CONFIG.DIN_WIDTH {3} \
    CONFIG.DOUT_WIDTH {1}] $fan_pwm
set fan_en_b [create_bd_port -dir O fan_en_b]
connect_bd_net [get_bd_pins ps/emio_ttc0_wave_o] [get_bd_pins fan_pwm/Din]
connect_bd_net [get_bd_pins fan_pwm/Dout] $fan_en_b

validate_bd_design
save_bd_design
set bd_file [get_files z486_console_platform.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top z486_console_platform_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "console-shell synthesis failed"
}

set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "console-shell implementation failed"
}

file mkdir [file join $board_dir build console]
open_run impl_1
report_utilization -file [file join $board_dir build console utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $board_dir build console timing_summary.rpt]
