set script_dir [file normalize [file dirname [info script]]]
set board_dir [file normalize [file join $script_dir ..]]
set xl_dir [file normalize [file join $board_dir .. ..]]
set pc_dir [file join $xl_dir deps z486-pc]
set src_dir [file join $pc_dir src]
set zsst_rtl_dir [file join $xl_dir deps zsst]
set zsst_platform_dir [file join $board_dir rtl zsst]
set build_dir [file join $board_dir build vivado]

set stop_after_synth 0
set stop_after_validate 0
if {$argc > 0 && [lindex $argv 0] eq "synth"} {
    set stop_after_synth 1
} elseif {$argc > 0 && [lindex $argv 0] eq "validate"} {
    set stop_after_validate 1
}

file mkdir $build_dir
create_project z486_kv260 $build_dir -force -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property include_dirs [list $src_dir [file join $src_dir z486] \
    [file join $src_dir z486 x87]] [get_filesets sources_1]
set_property verilog_define {Z486_XILINX=1 Z486_VOODOO=1 ZSST_XILINX=1} \
    [get_filesets sources_1]

proc add_rtl_tree {dir} {
    foreach path [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $path]} {
            if {[lsearch -exact {.Xil boards scripts tests zsst} [file tail $path]] < 0} {
                add_rtl_tree $path
            }
        } elseif {[file tail $path] eq "x87_logexp_rom.sv"} {
            add_files -norecurse $path
            set_property file_type {Verilog Header} [get_files $path]
        } elseif {[lsearch -exact {sdram_sim.v saa1099.sv} \
                    [file tail $path]] >= 0} {
            continue
        } elseif {[file extension $path] eq ".sv"} {
            read_verilog -sv $path
        } elseif {[file extension $path] eq ".svh"} {
            add_files -norecurse $path
            set_property file_type {Verilog Header} [get_files $path]
        } elseif {[file extension $path] eq ".v"} {
            read_verilog -sv $path
        }
    }
}

read_verilog -sv [file join $board_dir rtl z486_kv260_memory_map_pkg.sv]
add_rtl_tree $src_dir

# Keep the shared zSST order explicit: packages must precede the modules
# importing them. Private development uses a symlink at deps/zsst; the public
# repository uses a submodule at the same path.
set zsst_sources [list \
    sst1_pkg.sv generated/sst1_regs_pkg.sv generated/sst1_tmu_tables_pkg.sv \
    frontend/sst1_addr_decode.sv frontend/sst1_float_to_fixed.sv \
    frontend/sst1_pci_fifo.sv frontend/sst1_regfile.sv \
    frontend/sst1_frontend.sv tmu/sst1_texture_layout.sv \
    tmu/sst1_tmu_front_staged.sv tmu/sst1_texture_cache_ram.sv \
    tmu/sst1_texture_cache.sv tmu/sst1_texture_address.sv \
    tmu/sst1_texel_decode.sv tmu/sst1_texture_combine.sv tmu/sst1_tmu.sv \
    fbi/sst1_pixel_pipeline.sv fbi/sst1_fb_write_combine.sv \
    fbi/sst1_fb_read_cache.sv fbi/sst1_fbi.sv \
    video/sst1_video_control.sv sst1_perf_counters.sv \
    sst1_core.sv sst1_device.sv]
foreach source $zsst_sources {
    read_verilog -sv [file join $zsst_rtl_dir $source]
}
foreach source {sst1_axi_bridge.sv zsst_mem_request_fifo.sv zsst_board_perf.sv zsst_reset_guard.sv} {
    read_verilog -sv [file join $zsst_platform_dir $source]
}
read_verilog -sv [file join $board_dir rtl z486_l2_cache.sv]
read_verilog -sv [file join $board_dir rtl z486_ddr_axi_bridge.sv]
set l2_writeback 1
if {[info exists ::env(Z486_L2_WRITEBACK)]} {
    if {$::env(Z486_L2_WRITEBACK) eq "0"} {
        set l2_writeback 0
    } elseif {$::env(Z486_L2_WRITEBACK) ne "1"} {
        error "Z486_L2_WRITEBACK must be 0 or 1"
    }
}
if {$l2_writeback} {
    set_property verilog_define [concat [get_property verilog_define [current_fileset]] \
        {Z486_L2_WRITEBACK=1}] [current_fileset]
    foreach source {z486_l2_wb_store.sv z486_l2_wb_controller.sv z486_l2_line_axi.sv z486_ddr_wb_bridge.sv} {
        read_verilog -sv [file join $board_dir rtl $source]
    }
}
read_verilog -sv [file join $board_dir rtl z486_shared_scanout.sv]
read_verilog -sv [file join $board_dir rtl z486_zsst.sv]
read_verilog -sv [file join $board_dir rtl z486_control.sv]
read_verilog -sv [file join $board_dir rtl z486_audio_mixer.sv]
read_verilog -sv [file join $board_dir rtl z486_dp_audio.sv]
read_verilog -sv [file join $board_dir rtl z486_kv260_core.sv]
read_verilog [file join $board_dir rtl z486_rgb_to_dp36.v]
read_verilog [file join $board_dir rtl z486_clock_gate_div2.v]
read_verilog [file join $board_dir rtl z486_vtc_lite_1ppc.v]
set_property file_type Verilog [get_files [file join $board_dir rtl z486_control.sv]]
set_property file_type Verilog [get_files [file join $board_dir rtl z486_kv260_core.sv]]
read_xdc [file join $board_dir constraints kv260.xdc]
read_xdc [file join $board_dir constraints video.xdc]
set_property USED_IN_SYNTHESIS false \
    [get_files [file join $board_dir constraints video.xdc]]

foreach image [list \
        [file join $src_dir z486 ucode.hex] \
        [file join $src_dir z486 pla_entry_rom.hex] \
        [file join $src_dir z486 pla_group_entry.hex] \
        [file join $src_dir z486 x87 x87_ucode.mem]] {
    add_files -norecurse $image
    set_property file_type {Memory Initialization Files} [get_files $image]
}

update_compile_order -fileset sources_1
create_bd_design z486_platform

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP3 {0} \
    CONFIG.PSU__USE__S_AXI_GP4 {1} \
    CONFIG.PSU__SAXIGP4__DATA_WIDTH {128} \
    CONFIG.PSU__USE__S_AXI_GP5 {1} \
    CONFIG.PSU__SAXIGP5__DATA_WIDTH {128} \
    CONFIG.PSU__USE__VIDEO {1} \
    CONFIG.PSU__USE__AUDIO {1} \
    CONFIG.PSU__TTC0__WAVEOUT__ENABLE {1} \
    CONFIG.PSU__TTC0__WAVEOUT__IO {EMIO} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}] $ps

set core [create_bd_cell -type module -reference z486_kv260_core core]
set control [create_bd_cell -type module -reference z486_control control]
set control_bus [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 control_bus]
set_property -dict [list CONFIG.NUM_MI {5} CONFIG.NUM_SI {1}] $control_bus
set memory_bus [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 memory_bus]
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1}] $memory_bus
set avpg [create_bd_cell -type ip -vlnv xilinx.com:ip:av_pat_gen:2.0 avpg]
set_property -dict [list CONFIG.BPC {8} CONFIG.PPC {1}] $avpg
set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
set_property -dict [list \
    CONFIG.CLKIN1_JITTER_PS {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.PRIM_IN_FREQ {99.999001} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.USE_DYN_RECONFIG {true} \
    CONFIG.USE_LOCKED {true}] $clk_wiz
set audio_clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 audio_clk_wiz]
set_property -dict [list \
    CONFIG.CLKIN1_JITTER_PS {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {24.576} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.PRIM_IN_FREQ {99.999001} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.USE_LOCKED {true}] $audio_clk_wiz
set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 clk_enable_gpio]
set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} CONFIG.C_GPIO_WIDTH {2} \
    CONFIG.C_IS_DUAL {0}] $gpio
set ce0 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 ce_video]
set_property -dict [list CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DIN_WIDTH {2}] $ce0
set ce1 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 ce_vtc]
set_property -dict [list CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1} CONFIG.DIN_WIDTH {2}] $ce1
set fan_pwm [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 fan_pwm]
set_property -dict [list CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2} \
    CONFIG.DIN_WIDTH {3} CONFIG.DOUT_WIDTH {1}] $fan_pwm
set gate [create_bd_cell -type module -reference z486_clock_gate_div2 clock_gate]
set pack [create_bd_cell -type module -reference z486_rgb_to_dp36 rgb_to_dp]
set vtc [create_bd_cell -type module -reference z486_vtc_lite_1ppc vtc]
set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset]
set video_reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 video_reset]
set vtc_reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 vtc_reset]
set audio_reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 audio_reset]
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one]
set_property CONFIG.CONST_VAL {1} $one

connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins control_bus/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins control_bus/M00_AXI] [get_bd_intf_pins avpg/av_axi]
connect_bd_intf_net [get_bd_intf_pins control_bus/M01_AXI] [get_bd_intf_pins vtc/S_AXI]
connect_bd_intf_net [get_bd_intf_pins control_bus/M02_AXI] [get_bd_intf_pins clk_enable_gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins control_bus/M03_AXI] [get_bd_intf_pins clk_wiz/s_axi_lite]
connect_bd_intf_net [get_bd_intf_pins control_bus/M04_AXI] [get_bd_intf_pins control/s_axi]
connect_bd_intf_net [get_bd_intf_pins core/m_axi] \
    [get_bd_intf_pins memory_bus/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins memory_bus/M00_AXI] \
    [get_bd_intf_pins ps/S_AXI_HP0_FPD]
connect_bd_intf_net [get_bd_intf_pins core/render_axi] \
    [get_bd_intf_pins ps/S_AXI_HP2_FPD]
connect_bd_intf_net [get_bd_intf_pins core/scanout_axi] \
    [get_bd_intf_pins ps/S_AXI_HP3_FPD]
connect_bd_intf_net [get_bd_intf_pins core/audio_axis] \
    [get_bd_intf_pins avpg/aud_in_axi4s]
connect_bd_intf_net [get_bd_intf_pins avpg/aud_out_axi4s] \
    [get_bd_intf_pins ps/S_AXIS_AUDIO]

connect_bd_net [get_bd_pins core/video_r] [get_bd_pins rgb_to_dp/r]
connect_bd_net [get_bd_pins core/video_g] [get_bd_pins rgb_to_dp/g]
connect_bd_net [get_bd_pins core/video_b] [get_bd_pins rgb_to_dp/b]
connect_bd_net [get_bd_pins rgb_to_dp/dp36] [get_bd_pins ps/dp_live_video_in_pixel1]
connect_bd_net [get_bd_pins core/video_hs] [get_bd_pins ps/dp_live_video_in_hsync]
connect_bd_net [get_bd_pins core/video_vs] [get_bd_pins ps/dp_live_video_in_vsync]
connect_bd_net [get_bd_pins core/video_de] [get_bd_pins ps/dp_live_video_in_de]

connect_bd_net [get_bd_pins ps/pl_clk0] \
    [get_bd_pins ps/maxihpm0_fpd_aclk] \
    [get_bd_pins ps/saxihp0_fpd_aclk] \
    [get_bd_pins ps/saxihp2_fpd_aclk] \
    [get_bd_pins ps/saxihp3_fpd_aclk] \
    [get_bd_pins control_bus/aclk] \
    [get_bd_pins memory_bus/aclk] \
    [get_bd_pins control/aclk] \
    [get_bd_pins core/aclk] \
    [get_bd_pins avpg/av_axi_aclk] \
    [get_bd_pins vtc/s_axi_aclk] [get_bd_pins clk_enable_gpio/s_axi_aclk] \
    [get_bd_pins clk_wiz/s_axi_aclk] [get_bd_pins clk_wiz/clk_in1] \
    [get_bd_pins audio_clk_wiz/clk_in1] \
    [get_bd_pins reset/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins reset/ext_reset_in] \
    [get_bd_pins video_reset/ext_reset_in] [get_bd_pins vtc_reset/ext_reset_in] \
    [get_bd_pins audio_reset/ext_reset_in]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset/dcm_locked]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins video_reset/dcm_locked] \
    [get_bd_pins vtc_reset/dcm_locked]
connect_bd_net [get_bd_pins audio_clk_wiz/locked] [get_bd_pins audio_reset/dcm_locked]
connect_bd_net [get_bd_pins reset/interconnect_aresetn] \
    [get_bd_pins control_bus/aresetn] [get_bd_pins memory_bus/aresetn]
connect_bd_net [get_bd_pins reset/peripheral_aresetn] \
    [get_bd_pins control/aresetn] [get_bd_pins core/aresetn] \
    [get_bd_pins avpg/av_axi_aresetn] \
    [get_bd_pins vtc/s_axi_aresetn] [get_bd_pins clk_enable_gpio/s_axi_aresetn] \
    [get_bd_pins clk_wiz/s_axi_aresetn]

connect_bd_net [get_bd_pins clk_enable_gpio/gpio_io_o] \
    [get_bd_pins ce_video/Din] [get_bd_pins ce_vtc/Din]
connect_bd_net [get_bd_pins ce_video/Dout] [get_bd_pins clock_gate/enable_video]
connect_bd_net [get_bd_pins ce_vtc/Dout] [get_bd_pins clock_gate/enable_vtc]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] [get_bd_pins clock_gate/clk_in]
connect_bd_net [get_bd_pins clock_gate/video_clk] [get_bd_pins core/video_clk] \
    [get_bd_pins avpg/vid_out_axi4s_aclk] [get_bd_pins video_reset/slowest_sync_clk] \
    [get_bd_pins ps/dp_video_in_clk]
connect_bd_net [get_bd_pins clock_gate/vtc_clk] [get_bd_pins vtc/pixel_clk] \
    [get_bd_pins vtc_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins video_reset/peripheral_aresetn] \
    [get_bd_pins avpg/vid_out_axi4s_aresetn]
connect_bd_net [get_bd_pins vtc_reset/peripheral_aresetn] [get_bd_pins vtc/pixel_resetn]
connect_bd_net [get_bd_pins audio_clk_wiz/clk_out1] [get_bd_pins core/audio_clk] \
    [get_bd_pins avpg/aud_clk] [get_bd_pins avpg/aud_out_axi4s_aclk] \
    [get_bd_pins ps/dp_s_axis_audio_clk] [get_bd_pins audio_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins audio_reset/peripheral_aresetn] \
    [get_bd_pins core/audio_aresetn] [get_bd_pins avpg/aud_out_axi4s_aresetn]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins vtc/pixel_ce]

connect_bd_net [get_bd_pins control/run] [get_bd_pins core/run]
connect_bd_net [get_bd_pins control/memory_base] [get_bd_pins core/memory_base]
connect_bd_net [get_bd_pins control/memory_size_out] [get_bd_pins core/memory_size]
connect_bd_net [get_bd_pins control/guest_ram_size] [get_bd_pins core/guest_ram_size]
foreach signal {video_run video_freeze video_mode audio_boost zsst_debug_control zsst_debug_index} {
    connect_bd_net [get_bd_pins control/$signal] [get_bd_pins core/$signal]
}
foreach signal {debug_led request_count read_beat_count stall_cycle_count response_error_count zsst_debug_data zsst_debug_status bus_status l2_hits l2_misses l2_fill_beats l2_status} {
    connect_bd_net [get_bd_pins core/$signal] [get_bd_pins control/$signal]
}
foreach signal {boot_stage bios_loaded first_instruction post_code post_write cpu_cs cpu_eip} {
    connect_bd_net [get_bd_pins core/$signal] [get_bd_pins control/$signal]
}
foreach signal {video_width video_height video_frames video_read_bursts \
                video_write_bursts video_read_beats video_write_beats \
                video_stall_cycles video_error_count video_source \
                video_line_requests video_line_completions \
                video_native_frames video_outstanding_high_water} {
    connect_bd_net [get_bd_pins core/$signal] [get_bd_pins control/$signal]
}
foreach signal {fdd_request ide0_request ide1_request mgmt_readdata} {
    connect_bd_net [get_bd_pins core/$signal] [get_bd_pins control/$signal]
}
foreach signal {mgmt_address mgmt_read mgmt_write mgmt_writedata} {
    connect_bd_net [get_bd_pins control/$signal] [get_bd_pins core/$signal]
}
foreach signal {kbd_tx_empty mouse_tx_empty kbd_host_cmd mouse_host_cmd} {
    connect_bd_net [get_bd_pins core/$signal] [get_bd_pins control/$signal]
}
foreach signal {kbd_data kbd_data_valid mouse_data mouse_data_valid \
                kbd_host_cmd_clear mouse_host_cmd_clear} {
    connect_bd_net [get_bd_pins control/$signal] [get_bd_pins core/$signal]
}
set led [create_bd_port -dir O -from 7 -to 0 led]
connect_bd_net [get_bd_pins core/debug_led] $led
set fan_en_b [create_bd_port -dir O fan_en_b]
connect_bd_net [get_bd_pins ps/emio_ttc0_wave_o] [get_bd_pins fan_pwm/Din]
connect_bd_net [get_bd_pins fan_pwm/Dout] $fan_en_b

assign_bd_address -offset 0xA0000000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps/Data] \
    [get_bd_addr_segs avpg/av_axi/Reg] -force
assign_bd_address -offset 0xA0010000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps/Data] \
    [get_bd_addr_segs vtc/s_axi/reg0] -force
assign_bd_address -offset 0xA0020000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps/Data] \
    [get_bd_addr_segs clk_enable_gpio/S_AXI/Reg] -force
assign_bd_address -offset 0xA0030000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps/Data] \
    [get_bd_addr_segs clk_wiz/s_axi_lite/Reg] -force
assign_bd_address -offset 0xA0040000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps/Data] \
    [get_bd_addr_segs control/s_axi/reg0] -force
assign_bd_address
validate_bd_design
save_bd_design

set bd_file [get_files z486_platform.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top z486_platform_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

if {$stop_after_validate} {
    exit
}

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synthesis failed"
}

file mkdir [file join $board_dir build]
open_run synth_1
report_utilization -hierarchical -file [file join $board_dir build utilization_synth.rpt]
report_timing_summary -file [file join $board_dir build timing_synth.rpt]
if {$stop_after_synth} {
    exit
}

set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation failed"
}
open_run impl_1
report_utilization -hierarchical -file [file join $board_dir build utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $board_dir build timing_summary.rpt]
report_drc -file [file join $board_dir build drc.rpt]
write_hw_platform -fixed -include_bit -force \
    [file join $board_dir build z486_kv260.xsa]
