module z486_kv260_core (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF m_axi:render_axi:scanout_axi, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001" *)
    input  wire         aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire         aresetn,
    input  wire         run,
    input  wire [39:0]  memory_base,
    input  wire [31:0]  memory_size,
    input  wire  [1:0]  guest_ram_size,
    input  wire         video_run,
    input  wire         video_freeze,
    input  wire  [4:0]  video_mode,
    input  wire  [1:0]  audio_boost,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 video_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME video_clk, FREQ_HZ 150000000" *)
    input  wire         video_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 audio_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME audio_clk, ASSOCIATED_BUSIF audio_axis, ASSOCIATED_RESET audio_aresetn" *)
    input  wire         audio_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 audio_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME audio_aresetn, POLARITY ACTIVE_LOW" *)
    input  wire         audio_aresetn,
    output wire  [7:0]  debug_led,
    output wire  [2:0]  boot_stage,
    output wire         bios_loaded,
    output wire         first_instruction,
    output wire  [7:0]  post_code,
    output wire         post_write,
    output wire [15:0]  cpu_cs,
    output wire [31:0]  cpu_eip,
    output wire [31:0]  request_count,
    output wire [31:0]  read_beat_count,
    output wire [31:0]  stall_cycle_count,
    output wire [31:0]  response_error_count,
    output wire [11:0]  video_width,
    output wire [11:0]  video_height,
    output wire [31:0]  video_frames,
    output wire [31:0]  video_read_bursts,
    output wire [31:0]  video_write_bursts,
    output wire [31:0]  video_read_beats,
    output wire [31:0]  video_write_beats,
    output wire [31:0]  video_stall_cycles,
    output wire [31:0]  video_error_count,
    output wire  [1:0]  video_source,
    input wire [31:0] zsst_debug_control,
    input wire [15:0] zsst_debug_index,
    output wire [31:0] zsst_debug_data,
    output wire [31:0] zsst_debug_status,
    output wire [31:0] bus_status,
    output wire [31:0] l2_hits, l2_misses, l2_fill_beats, l2_status,
    output wire [31:0]  video_line_requests,
    output wire [31:0]  video_line_completions,
    output wire [31:0]  video_native_frames,
    output wire  [7:0]  video_outstanding_high_water,
    output wire  [1:0]  fdd_request,
    output wire  [2:0]  ide0_request,
    output wire  [2:0]  ide1_request,
    input  wire [15:0]  mgmt_address,
    input  wire         mgmt_read,
    output wire [15:0]  mgmt_readdata,
    input  wire         mgmt_write,
    input  wire [15:0]  mgmt_writedata,
    input  wire  [7:0]  kbd_data,
    input  wire         kbd_data_valid,
    input  wire  [7:0]  mouse_data,
    input  wire         mouse_data_valid,
    output wire         kbd_tx_empty,
    output wire         mouse_tx_empty,
    output wire  [8:0]  kbd_host_cmd,
    output wire  [8:0]  mouse_host_cmd,
    input  wire         kbd_host_cmd_clear,
    input  wire         mouse_host_cmd_clear,

    output wire [7:0]   video_r,
    output wire [7:0]   video_g,
    output wire [7:0]   video_b,
    output wire         video_hs,
    output wire         video_vs,
    output wire         video_de,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 audio_axis TDATA" *)
    output wire [31:0]  audio_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 audio_axis TID" *)
    output wire  [7:0]  audio_axis_tid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 audio_axis TVALID" *)
    output wire         audio_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 audio_axis TREADY" *)
    input  wire         audio_axis_tready,

    output wire [5:0]   render_axi_awid,
    output wire [48:0]  render_axi_awaddr,
    output wire         render_axi_awuser,
    output wire  [7:0]  render_axi_awlen,
    output wire  [2:0]  render_axi_awsize,
    output wire  [1:0]  render_axi_awburst,
    output wire         render_axi_awlock,
    output wire  [3:0]  render_axi_awcache,
    output wire  [2:0]  render_axi_awprot,
    output wire  [3:0]  render_axi_awqos,
    output wire         render_axi_awvalid,
    input  wire         render_axi_awready,
    output wire [127:0] render_axi_wdata,
    output wire [15:0]  render_axi_wstrb,
    output wire         render_axi_wlast,
    output wire         render_axi_wvalid,
    input  wire         render_axi_wready,
    input  wire  [5:0]  render_axi_bid,
    input  wire  [1:0]  render_axi_bresp,
    input  wire         render_axi_bvalid,
    output wire         render_axi_bready,
    output wire  [5:0]  render_axi_arid,
    output wire [48:0]  render_axi_araddr,
    output wire         render_axi_aruser,
    output wire  [7:0]  render_axi_arlen,
    output wire  [2:0]  render_axi_arsize,
    output wire  [1:0]  render_axi_arburst,
    output wire         render_axi_arlock,
    output wire  [3:0]  render_axi_arcache,
    output wire  [2:0]  render_axi_arprot,
    output wire  [3:0]  render_axi_arqos,
    output wire         render_axi_arvalid,
    input  wire         render_axi_arready,
    input  wire  [5:0]  render_axi_rid,
    input  wire [127:0] render_axi_rdata,
    input  wire  [1:0]  render_axi_rresp,
    input  wire         render_axi_rlast,
    input  wire         render_axi_rvalid,
    output wire         render_axi_rready,

    output wire [5:0]   scanout_axi_arid,
    output wire [48:0]  scanout_axi_araddr,
    output wire         scanout_axi_aruser,
    output wire  [7:0]  scanout_axi_arlen,
    output wire  [2:0]  scanout_axi_arsize,
    output wire  [1:0]  scanout_axi_arburst,
    output wire         scanout_axi_arlock,
    output wire  [3:0]  scanout_axi_arcache,
    output wire  [2:0]  scanout_axi_arprot,
    output wire  [3:0]  scanout_axi_arqos,
    output wire         scanout_axi_arvalid,
    input  wire         scanout_axi_arready,
    input  wire [5:0]   scanout_axi_rid,
    input  wire [127:0] scanout_axi_rdata,
    input  wire  [1:0]  scanout_axi_rresp,
    input  wire         scanout_axi_rlast,
    input  wire         scanout_axi_rvalid,
    output wire         scanout_axi_rready,

    output wire [0:0]   m_axi_awid,
    output wire [39:0]  m_axi_awaddr,
    output wire  [7:0]  m_axi_awlen,
    output wire  [2:0]  m_axi_awsize,
    output wire  [1:0]  m_axi_awburst,
    output wire         m_axi_awlock,
    output wire  [3:0]  m_axi_awcache,
    output wire  [2:0]  m_axi_awprot,
    output wire  [3:0]  m_axi_awqos,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [0:0]   m_axi_bid,
    input  wire  [1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,
    output wire [0:0]   m_axi_arid,
    output wire [39:0]  m_axi_araddr,
    output wire  [7:0]  m_axi_arlen,
    output wire  [2:0]  m_axi_arsize,
    output wire  [1:0]  m_axi_arburst,
    output wire         m_axi_arlock,
    output wire  [3:0]  m_axi_arcache,
    output wire  [2:0]  m_axi_arprot,
    output wire  [3:0]  m_axi_arqos,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [0:0]   m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire  [1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready
);

wire core_reset;
wire zsst_reset_busy, zsst_memory_idle, scanout_memory_idle, cpu_memory_idle;
assign core_reset = !aresetn || !run || zsst_reset_busy;
assign bus_status = {29'd0, scanout_memory_idle, zsst_memory_idle, cpu_memory_idle};

wire [31:0] mem0_addr, mem0_din, mem0_dout;
wire  [3:0] mem0_be;
wire        mem0_line_read;
wire mem0_valid, mem0_write, mem0_ready, mem0_resp_valid;
wire [127:0] mem0_line_dout;
wire mem0_line_resp_valid;
wire [31:0] mem1_addr, mem1_din, mem1_dout;
wire  [3:0] mem1_be;
wire mem1_valid, mem1_write, mem1_ready, mem1_resp_valid;
wire [28:0] aux_addr;
wire [63:0] aux_din, aux_dout;
wire  [7:0] aux_be;
wire aux_rd, aux_we, aux_busy, aux_dout_ready;
wire pc_video_ce, pc_video_de, pc_video_hs, pc_video_vs;
wire [7:0] pc_video_r, pc_video_g, pc_video_b;
wire pc_scanline_req, pc_scanline_ready, pc_scanline_frame_start;
wire [10:0] pc_scanline_y;
wire [10:0] pc_scanline_width, pc_scanline_height;
wire [31:0] pc_native_frames;
wire pc_scanline_done;
wire [19:0] pc_fb_start_addr;
wire [8:0] pc_fb_width, pc_fb_stride;
wire [10:0] pc_fb_height;
wire [3:0] pc_fb_flags;
wire pc_fb_off;
wire [7:0] pc_fb_pal_addr;
wire [17:0] pc_fb_pal_data;
wire pc_fb_pal_write;
wire zsst_host_req_valid, zsst_host_req_ready;
wire [23:0] zsst_host_address;
wire [31:0] zsst_host_writedata;
wire [3:0] zsst_host_byteenable;
wire zsst_host_write, zsst_host_rsp_valid, zsst_host_rsp_ready;
wire [31:0] zsst_host_readdata;
wire zsst_host_error, zsst_memory_enable;
wire [31:0] zsst_init_enable;
wire zsst_video_active;
wire [39:0] zsst_scanout_fbi_base;
wire [23:0] zsst_scanout_buffer_size;
wire [15:0] zsst_scanout_stride;
wire [9:0] zsst_scanout_width, zsst_scanout_height;
wire [1:0] zsst_scanout_displayed_buffer;
wire scanout_v_retrace;
wire [11:0] scanout_v_retrace_count;
wire [31:0] scanout_underflow_count;
wire [31:0] scanout_line_requests, scanout_line_completions;
wire [7:0] scanout_outstanding_high_water;
wire [1:0] scanout_source;
wire scanout_underflow, scanout_axi_error;

// The ZynqMP HP ports use 49-bit addresses, six-bit IDs, and one-bit address
// user fields. zSST only accesses the staged low DDR window, so its native
// 40-bit addresses and smaller IDs zero-extend directly. Both zSST clients use
// full-width 128-bit beats; unlike the CPU memory port they need no narrow-beat
// converter between the core and the PS.
assign render_axi_awuser = 1'b0;
assign render_axi_aruser = 1'b0;
assign scanout_axi_aruser = 1'b0;
wire ps2_kbd_clk, ps2_kbd_dat, ps2_kbd_clk_fb, ps2_kbd_dat_fb;
wire ps2_mouse_clk, ps2_mouse_dat, ps2_mouse_clk_fb, ps2_mouse_dat_fb;
wire [8:0] sample_cms_l, sample_cms_r;
wire [15:0] sample_sb_l, sample_sb_r, sample_opl_l, sample_opl_r;
wire speaker_out, sound_sbp;
wire [4:0] vol_master_l, vol_master_r, vol_voice_l, vol_voice_r;
wire [4:0] vol_midi_l, vol_midi_r;
wire [1:0] vol_spk;
wire [15:0] mixed_audio_l, mixed_audio_r;
wire [35:0] audio_controls;
wire audio_run, audio_sbp;
wire [1:0] audio_boost_sync, audio_vol_spk;
wire [4:0] audio_vol_master_l, audio_vol_master_r;
wire [4:0] audio_vol_voice_l, audio_vol_voice_r;
wire [4:0] audio_vol_midi_l, audio_vol_midi_r;
reg [11:0] ps2_divider;
reg ps2_clock;

wire pc_packed_enable = !pc_fb_flags[2] && |pc_fb_flags[1:0] &&
    !pc_fb_off;
// The packed ET4000 aperture owns the final 8 MiB of the CMA allocation.
// Expressing it relative to memory_size keeps this Vivado block-design
// reference module in Verilog syntax while matching memory_map.json.
wire [39:0] pc_packed_base = memory_base + {8'd0, memory_size} -
    40'h0000800000 +
    {18'd0, pc_fb_start_addr, 2'b00};
wire [11:0] pc_packed_width_full = pc_fb_flags[1:0] == 2'd3 ? 12'd640 :
    {pc_fb_width, 3'b000};
wire [10:0] pc_packed_width = pc_packed_width_full > 12'd1024 ?
    11'd1024 : pc_packed_width_full[10:0];
wire [10:0] pc_packed_height_half = pc_fb_height >> 1;
wire [10:0] pc_packed_height_full = pc_fb_flags[3] ?
    pc_packed_height_half : pc_fb_height;
wire [10:0] pc_packed_height = pc_packed_height_full > 11'd1024 ?
    11'd1024 : pc_packed_height_full;
wire [15:0] pc_packed_stride = {4'd0, pc_fb_stride, 3'b000};
wire [1:0] pc_packed_format = pc_fb_flags[1:0] == 2'd3 ? 2'd2 :
    pc_fb_flags[1:0] == 2'd2 ? 2'd0 : 2'd1;

always @(posedge aclk) begin
    if (core_reset) begin
        ps2_divider <= 12'd0;
        ps2_clock <= 1'b0;
    end else if (ps2_divider == 12'd3999) begin
        ps2_divider <= 12'd0;
        ps2_clock <= ~ps2_clock;
    end else begin
        ps2_divider <= ps2_divider + 1'b1;
    end
end

z486_ps2_device ps2_keyboard (
    .clk_sys(aclk), .reset(core_reset), .wdata(kbd_data),
    .we(kbd_data_valid), .ps2_clk(ps2_clock),
    .ps2_clk_out(ps2_kbd_clk), .ps2_dat_out(ps2_kbd_dat),
    .tx_empty(kbd_tx_empty), .ps2_clk_in(ps2_kbd_clk_fb),
    .ps2_dat_in(ps2_kbd_dat_fb), .rdata(kbd_host_cmd),
    .rd(kbd_host_cmd_clear)
);

z486_ps2_device ps2_mouse (
    .clk_sys(aclk), .reset(core_reset), .wdata(mouse_data),
    .we(mouse_data_valid), .ps2_clk(ps2_clock),
    .ps2_clk_out(ps2_mouse_clk), .ps2_dat_out(ps2_mouse_dat),
    .tx_empty(mouse_tx_empty), .ps2_clk_in(ps2_mouse_clk_fb),
    .ps2_dat_in(ps2_mouse_dat_fb), .rdata(mouse_host_cmd),
    .rd(mouse_host_cmd_clear)
);

system #(
    .SYS_FREQ(100_000_000),
    .DCACHE_SET_BITS(7),
    .ICACHE_SET_BITS(7),
    .ENABLE_X87(1'b1),
    .ENABLE_CMS(1'b0),
    .VGA_USE_URAM(1'b1),
    .VGA_ONDEMAND_SCANOUT(1'b1),
    .ENABLE_VOODOO(1'b1)
) pc (
    .clk_sys(aclk),
    .reset(core_reset),
    .hps_apply_reset(1'b0),
    .clock_rate(28'd100_000_000),
    .floppy_wp(2'b00),
    .joystick_dis(2'b11),
    .joystick_dig_1(14'd0),
    .joystick_dig_2(14'd0),
    .joystick_ana_1(16'd0),
    .joystick_ana_2(16'd0),
    .joystick_mode(2'd0),
    .joystick_timed(2'd0),
    .fdd_request(fdd_request),
    .ide0_request(ide0_request),
    .ide1_request(ide1_request),
    .mgmt_address(mgmt_address),
    .mgmt_read(mgmt_read),
    .mgmt_readdata(mgmt_readdata),
    .mgmt_write(mgmt_write),
    .mgmt_writedata(mgmt_writedata),

    .ext_mem_busy(1'b0),
    .ext_mem0_addr(mem0_addr),
    .ext_mem0_din(mem0_din),
    .ext_mem0_dout(mem0_dout),
    .ext_mem0_resp_valid(mem0_resp_valid),
    .ext_mem0_line_dout(mem0_line_dout),
    .ext_mem0_line_resp_valid(mem0_line_resp_valid),
    .ext_mem0_be(mem0_be),
    .ext_mem0_burstcount(),
    .ext_mem0_line_read(mem0_line_read),
    .ext_mem0_ready(mem0_ready),
    .ext_mem0_valid(mem0_valid),
    .ext_mem0_write(mem0_write),
    .ext_mem1_addr(mem1_addr),
    .ext_mem1_din(mem1_din),
    .ext_mem1_dout(mem1_dout),
    .ext_mem1_resp_valid(mem1_resp_valid),
    .ext_mem1_be(mem1_be),
    .ext_mem1_burstcount(),
    .ext_mem1_ready(mem1_ready),
    .ext_mem1_valid(mem1_valid),
    .ext_mem1_write(mem1_write),

    .ddram_busy(aux_busy),
    .ddram_burstcnt(),
    .ddram_addr(aux_addr),
    .ddram_dout(aux_dout),
    .ddram_dout_ready(aux_dout_ready),
    .ddram_rd(aux_rd),
    .ddram_din(aux_din),
    .ddram_be(aux_be),
    .ddram_we(aux_we),

    .ioctl_download(1'b0),
    .ioctl_index(16'd0),
    .ioctl_wr(1'b0),
    .ioctl_addr(27'd0),
    .ioctl_dout(16'd0),
    .img_mounted(1'b0),
    .img_readonly(1'b0),
    .img_size(64'd0),
    .img_ack(1'b0),
    .img_buff_din(16'd0),
    .ps2_mouseclk_in(ps2_mouse_clk),
    .ps2_mousedat_in(ps2_mouse_dat),
    .ps2_mouseclk_out(ps2_mouse_clk_fb),
    .ps2_mousedat_out(ps2_mouse_dat_fb),
    .ps2_kbclk_in(ps2_kbd_clk),
    .ps2_kbdat_in(ps2_kbd_dat),
    .ps2_kbclk_out(ps2_kbd_clk_fb),
    .ps2_kbdat_out(ps2_kbd_dat_fb),
    .mouse_data(8'd0),
    .mouse_data_valid(1'b0),
    .mouse_host_cmd_clear(1'b0),
    .zsst_host_req_valid(zsst_host_req_valid),
    .zsst_host_req_ready(zsst_host_req_ready),
    .zsst_host_address(zsst_host_address),
    .zsst_host_writedata(zsst_host_writedata),
    .zsst_host_byteenable(zsst_host_byteenable),
    .zsst_host_write(zsst_host_write),
    .zsst_host_rsp_valid(zsst_host_rsp_valid),
    .zsst_host_rsp_ready(zsst_host_rsp_ready),
    .zsst_host_readdata(zsst_host_readdata),
    .zsst_host_error(zsst_host_error),
    .zsst_memory_enable(zsst_memory_enable),
    .zsst_init_enable(zsst_init_enable),
    .bootcfg(6'd0),
    .ram_size(guest_ram_size),
    .uma_ram(1'b0),
    .cpu_speed_osd(2'd0),
    // Preserve native VGA timing (notably 70 Hz DOS modes).  The shared
    // HDMI scanout independently emits fixed 1080p60 and permits tearing.
    .video_f60(1'b0),
    .video_border(1'b0),
    .video_scanline_req(pc_scanline_req),
    .video_scanline_ready(pc_scanline_ready),
    .video_scanline_frame_start(pc_scanline_frame_start),
    .video_scanline_y(pc_scanline_y),
    .video_scanline_width(pc_scanline_width),
    .video_scanline_height(pc_scanline_height),
    .video_native_frames(pc_native_frames),
    .video_scanline_done(pc_scanline_done),
    .video_ce(pc_video_ce),
    .video_blank_n(pc_video_de),
    .video_hsync(pc_video_hs),
    .video_vsync(pc_video_vs),
    .video_r(pc_video_r),
    .video_g(pc_video_g),
    .video_b(pc_video_b),
    .video_start_addr(pc_fb_start_addr),
    .video_width(pc_fb_width),
    .video_height(pc_fb_height),
    .video_stride(pc_fb_stride),
    .video_flags(pc_fb_flags),
    .video_off(pc_fb_off),
    .video_pal_a(pc_fb_pal_addr),
    .video_pal_d(pc_fb_pal_data),
    .video_pal_we(pc_fb_pal_write),
    .clk_audio(audio_clk),
    .sound_fm_mode(1'b1),
    .sound_cms_en(1'b0),
    .sample_cms_l(sample_cms_l),
    .sample_cms_r(sample_cms_r),
    .sample_sb_l(sample_sb_l),
    .sample_sb_r(sample_sb_r),
    .sample_opl_l(sample_opl_l),
    .sample_opl_r(sample_opl_r),
    .speaker_out(speaker_out),
    .sbp(sound_sbp),
    .vol_master_l(vol_master_l),
    .vol_master_r(vol_master_r),
    .vol_voice_l(vol_voice_l),
    .vol_voice_r(vol_voice_r),
    .vol_midi_l(vol_midi_l),
    .vol_midi_r(vol_midi_r),
    .vol_spk(vol_spk),

    .debug_boot_stage(boot_stage),
    .debug_bios_loaded(bios_loaded),
    .debug_first_instruction(first_instruction),
    .debug_post_code(post_code),
    .debug_post_write(post_write),
    .cpu_cs(cpu_cs),
    .cpu_eip(cpu_eip)
);

// These controls change only on reset or mixer/control writes.  Synchronize
// them into the audio domain rather than allowing timing paths directly from
// the 100 MHz system domain into the audio datapath.
synchronizer #(.DATA_WIDTH(36)) audio_control_sync (
    .clk(audio_clk),
    .in({run, audio_boost, sound_sbp, vol_spk,
         vol_master_l, vol_master_r, vol_voice_l, vol_voice_r,
         vol_midi_l, vol_midi_r}),
    .out(audio_controls)
);
assign {audio_run, audio_boost_sync, audio_sbp, audio_vol_spk,
        audio_vol_master_l, audio_vol_master_r,
        audio_vol_voice_l, audio_vol_voice_r,
        audio_vol_midi_l, audio_vol_midi_r} = audio_controls;

z486_audio_mixer audio_mixer (
    .clk(audio_clk), .reset(!audio_aresetn || !audio_run),
    .speaker_out(speaker_out), .sbp(audio_sbp), .vol_spk(audio_vol_spk),
    .vol_master_l(audio_vol_master_l), .vol_master_r(audio_vol_master_r),
    .vol_voice_l(audio_vol_voice_l), .vol_voice_r(audio_vol_voice_r),
    .vol_midi_l(audio_vol_midi_l), .vol_midi_r(audio_vol_midi_r),
    .sample_cms_l(sample_cms_l), .sample_cms_r(sample_cms_r),
    .sample_sb_l(sample_sb_l), .sample_sb_r(sample_sb_r),
    .sample_opl_l(sample_opl_l), .sample_opl_r(sample_opl_r),
    .sample_l(mixed_audio_l), .sample_r(mixed_audio_r)
);

z486_dp_audio dp_audio (
    .clk(audio_clk), .resetn(audio_aresetn && audio_run),
    .sample_l(mixed_audio_l), .sample_r(mixed_audio_r), .boost(audio_boost_sync),
    .m_axis_tdata(audio_axis_tdata), .m_axis_tid(audio_axis_tid),
    .m_axis_tvalid(audio_axis_tvalid), .m_axis_tready(audio_axis_tready)
);

// Passive PC-backend wait measurements; writes may be buffered, so these
// describe memory pressure, not architectural CPU stall/retirement counts.
reg perf_cpu_read_pending;
always @(posedge aclk) begin
    if (!aresetn) perf_cpu_read_pending <= 1'b0;
    else begin
        if (mem0_resp_valid || mem0_line_resp_valid) perf_cpu_read_pending <= 1'b0;
        if (mem0_valid && mem0_ready && !mem0_write) perf_cpu_read_pending <= 1'b1;
    end
end
z486_zsst zsst (
    .cpu_mem_accept_wait(mem0_valid && !mem0_ready),
    .cpu_mem_read_wait(perf_cpu_read_pending),
    .debug_control(zsst_debug_control), .debug_index(zsst_debug_index),
    .debug_data(zsst_debug_data), .debug_status(zsst_debug_status),
    .aclk(aclk), .aresetn(aresetn), .soft_reset(!run),
    .reset_busy(zsst_reset_busy), .memory_idle(zsst_memory_idle),
    .memory_base(memory_base), .memory_enable(zsst_memory_enable),
    .init_enable(zsst_init_enable),
    .host_req_valid(zsst_host_req_valid),
    .host_req_ready(zsst_host_req_ready),
    .host_address(zsst_host_address),
    .host_writedata(zsst_host_writedata),
    .host_byteenable(zsst_host_byteenable), .host_write(zsst_host_write),
    .host_rsp_valid(zsst_host_rsp_valid),
    .host_rsp_ready(zsst_host_rsp_ready),
    .host_readdata(zsst_host_readdata), .host_error(zsst_host_error),
    .video_active(zsst_video_active),
    .scanout_fbi_base(zsst_scanout_fbi_base),
    .scanout_buffer_size(zsst_scanout_buffer_size),
    .scanout_stride(zsst_scanout_stride),
    .scanout_width(zsst_scanout_width),
    .scanout_height(zsst_scanout_height),
    .scanout_displayed_buffer(zsst_scanout_displayed_buffer),
    .scanout_v_retrace(scanout_v_retrace),
    .scanout_v_retrace_count(scanout_v_retrace_count),
    .busy(), .memory_error(),
    .render_axi_awid(render_axi_awid),
    .render_axi_awaddr(render_axi_awaddr),
    .render_axi_awlen(render_axi_awlen),
    .render_axi_awsize(render_axi_awsize),
    .render_axi_awburst(render_axi_awburst),
    .render_axi_awlock(render_axi_awlock),
    .render_axi_awcache(render_axi_awcache),
    .render_axi_awprot(render_axi_awprot),
    .render_axi_awqos(render_axi_awqos),
    .render_axi_awvalid(render_axi_awvalid),
    .render_axi_awready(render_axi_awready),
    .render_axi_wdata(render_axi_wdata), .render_axi_wstrb(render_axi_wstrb),
    .render_axi_wlast(render_axi_wlast), .render_axi_wvalid(render_axi_wvalid),
    .render_axi_wready(render_axi_wready), .render_axi_bid(render_axi_bid),
    .render_axi_bresp(render_axi_bresp), .render_axi_bvalid(render_axi_bvalid),
    .render_axi_bready(render_axi_bready), .render_axi_arid(render_axi_arid),
    .render_axi_araddr(render_axi_araddr), .render_axi_arlen(render_axi_arlen),
    .render_axi_arsize(render_axi_arsize),
    .render_axi_arburst(render_axi_arburst),
    .render_axi_arlock(render_axi_arlock),
    .render_axi_arcache(render_axi_arcache),
    .render_axi_arprot(render_axi_arprot),
    .render_axi_arqos(render_axi_arqos),
    .render_axi_arvalid(render_axi_arvalid),
    .render_axi_arready(render_axi_arready), .render_axi_rid(render_axi_rid),
    .render_axi_rdata(render_axi_rdata), .render_axi_rresp(render_axi_rresp),
    .render_axi_rlast(render_axi_rlast), .render_axi_rvalid(render_axi_rvalid),
    .render_axi_rready(render_axi_rready)
);

z486_shared_scanout scanout (
    .aclk(aclk), .aresetn(aresetn), .video_clk(video_clk),
    .memory_idle(scanout_memory_idle),
    .enable(run && video_run && !video_freeze && memory_base != 0),
    .select_zsst(zsst_video_active),
    .memory_base(memory_base), .memory_size(memory_size),
    .vga_ce(pc_video_ce), .vga_de(pc_video_de),
    .vga_r(pc_video_r), .vga_g(pc_video_g), .vga_b(pc_video_b),
    .vga_width(pc_scanline_width), .vga_height(pc_scanline_height),
    .vga_scanline_req(pc_scanline_req),
    .vga_scanline_ready(pc_scanline_ready),
    .vga_scanline_frame_start(pc_scanline_frame_start),
    .vga_scanline_y(pc_scanline_y),
    .vga_scanline_done(pc_scanline_done),
    .packed_enable(pc_packed_enable), .packed_base(pc_packed_base),
    .packed_stride(pc_packed_stride), .packed_width(pc_packed_width),
    .packed_height(pc_packed_height), .packed_format(pc_packed_format),
    .packed_palette_address(pc_fb_pal_addr),
    .packed_palette_data(pc_fb_pal_data),
    .packed_palette_write(pc_fb_pal_write),
    .zsst_fbi_base(zsst_scanout_fbi_base),
    .zsst_buffer_size(zsst_scanout_buffer_size),
    .zsst_stride(zsst_scanout_stride),
    .zsst_width(zsst_scanout_width), .zsst_height(zsst_scanout_height),
    .zsst_displayed_buffer(zsst_scanout_displayed_buffer),
    .v_retrace(scanout_v_retrace),
    .v_retrace_count(scanout_v_retrace_count),
    .detected_width(video_width), .detected_height(video_height),
    .frame_count(video_frames), .read_requests(video_read_bursts),
    .read_beats(video_read_beats),
    .current_source(scanout_source),
    .line_request_count(scanout_line_requests),
    .line_completion_count(scanout_line_completions),
    .outstanding_high_water(scanout_outstanding_high_water),
    .underflow_count(scanout_underflow_count),
    .sticky_underflow(scanout_underflow),
    .sticky_axi_error(scanout_axi_error),
    .video_r(video_r), .video_g(video_g), .video_b(video_b),
    .video_hs(video_hs), .video_vs(video_vs), .video_de(video_de),
    .m_axi_arid(scanout_axi_arid), .m_axi_araddr(scanout_axi_araddr),
    .m_axi_arlen(scanout_axi_arlen), .m_axi_arsize(scanout_axi_arsize),
    .m_axi_arburst(scanout_axi_arburst), .m_axi_arlock(scanout_axi_arlock),
    .m_axi_arcache(scanout_axi_arcache), .m_axi_arprot(scanout_axi_arprot),
    .m_axi_arqos(scanout_axi_arqos), .m_axi_arvalid(scanout_axi_arvalid),
    .m_axi_arready(scanout_axi_arready), .m_axi_rid(scanout_axi_rid),
    .m_axi_rdata(scanout_axi_rdata), .m_axi_rresp(scanout_axi_rresp),
    .m_axi_rlast(scanout_axi_rlast), .m_axi_rvalid(scanout_axi_rvalid),
    .m_axi_rready(scanout_axi_rready)
);

assign video_write_bursts = 32'd0;
assign video_write_beats = 32'd0;
assign video_stall_cycles = scanout_underflow_count;
assign video_error_count = {30'd0, scanout_axi_error, scanout_underflow};
assign video_source = scanout_source;
assign video_line_requests = scanout_line_requests;
assign video_line_completions = scanout_line_completions;
assign video_native_frames = pc_native_frames;
assign video_outstanding_high_water = scanout_outstanding_high_water;

localparam integer L2_SIZE_KIB = 512;
wire l2_ready;
`ifdef Z486_L2_WRITEBACK
assign l2_status = (L2_SIZE_KIB << 16) | {29'd0,1'b1,1'b1,l2_ready};
z486_ddr_wb_bridge #(.L2_SIZE_KIB(L2_SIZE_KIB)) memory (
`else
assign l2_status = (L2_SIZE_KIB << 16) | {30'd0,1'b1,l2_ready};
z486_ddr_axi_bridge #(.L2_SIZE_KIB(L2_SIZE_KIB)) memory (
`endif
    .cache_invalidate(core_reset), .cache_ready(l2_ready),
    .cache_hits(l2_hits), .cache_misses(l2_misses), .cache_fill_beats(l2_fill_beats),
    .idle(cpu_memory_idle),
    .aclk(aclk),
    .aresetn(aresetn),
    .memory_base(memory_base),
    .mem0_valid(mem0_valid), .mem0_write(mem0_write),
    .mem0_addr(mem0_addr), .mem0_din(mem0_din), .mem0_be(mem0_be),
    .mem0_ready(mem0_ready),
    .mem0_line_read(mem0_line_read),
    .mem0_dout(mem0_dout), .mem0_resp_valid(mem0_resp_valid),
    .mem0_line_dout(mem0_line_dout),
    .mem0_line_resp_valid(mem0_line_resp_valid),
    .mem1_valid(mem1_valid), .mem1_write(mem1_write),
    .mem1_addr(mem1_addr), .mem1_din(mem1_din), .mem1_be(mem1_be),
    .mem1_ready(mem1_ready),
    .mem1_dout(mem1_dout), .mem1_resp_valid(mem1_resp_valid),
    .aux_rd(aux_rd), .aux_we(aux_we), .aux_addr(aux_addr),
    .aux_din(aux_din), .aux_be(aux_be),
    .aux_busy(aux_busy), .aux_dout(aux_dout), .aux_dout_ready(aux_dout_ready),
    .request_count(request_count), .read_beat_count(read_beat_count),
    .stall_cycle_count(stall_cycle_count),
    .response_error_count(response_error_count),
    .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst), .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
    .m_axi_awqos(m_axi_awqos), .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst), .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache), .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos), .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready), .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready)
);

assign debug_led = {response_error_count != 0, first_instruction, bios_loaded,
                    boot_stage, post_write, run};

endmodule
