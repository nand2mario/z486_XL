# Standalone inference/area gate; not a replacement for platform routed timing.
set sim_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $sim_dir .. rtl]]
foreach source {z486_l2_cache.sv z486_l2_wb_store.sv z486_l2_wb_controller.sv z486_l2_line_axi.sv z486_ddr_axi_bridge.sv z486_ddr_wb_bridge.sv} {
    read_verilog -sv [file join $rtl_dir $source]
}
synth_design -top z486_ddr_wb_bridge -part xck26-sfvc784-2LV-c
create_clock -name aclk -period 10 [get_ports aclk]
report_utilization -hierarchical -file wb_utilization.rpt
report_timing_summary -file wb_synth_timing.rpt
