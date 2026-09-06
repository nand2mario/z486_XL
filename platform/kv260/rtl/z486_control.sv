module z486_control (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001" *)
    input  wire        aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    output reg         run,
    output reg  [39:0] memory_base,
    output wire [31:0] memory_size_out,
    output reg   [1:0] guest_ram_size,
    output reg         video_run,
    output reg         video_freeze,
    output reg   [4:0] video_mode,
    output reg   [1:0] audio_boost,
    input  wire [7:0]  debug_led,
    input  wire [2:0]  boot_stage,
    input  wire        bios_loaded,
    input  wire        first_instruction,
    input  wire [7:0]  post_code,
    input  wire        post_write,
    input  wire [15:0] cpu_cs,
    input  wire [31:0] cpu_eip,
    input  wire [31:0] request_count,
    input  wire [31:0] read_beat_count,
    input  wire [31:0] stall_cycle_count,
    input  wire [31:0] response_error_count,
    input  wire [11:0] video_width,
    input  wire [11:0] video_height,
    input  wire [31:0] video_frames,
    input  wire [31:0] video_read_bursts,
    input  wire [31:0] video_write_bursts,
    input  wire [31:0] video_read_beats,
    input  wire [31:0] video_write_beats,
    input  wire [31:0] video_stall_cycles,
    input  wire [31:0] video_error_count,
    input  wire  [1:0] video_source,
    output reg [31:0] zsst_debug_control,
    output reg [15:0] zsst_debug_index,
    input wire [31:0] zsst_debug_data,
    input wire [31:0] zsst_debug_status,
    input wire [31:0] bus_status,
    input wire [31:0] l2_hits, l2_misses, l2_fill_beats, l2_status,
    input  wire [31:0] video_line_requests,
    input  wire [31:0] video_line_completions,
    input  wire [31:0] video_native_frames,
    input  wire  [7:0] video_outstanding_high_water,
    input  wire  [1:0] fdd_request,
    input  wire  [2:0] ide0_request,
    input  wire  [2:0] ide1_request,
    output reg  [15:0] mgmt_address,
    output reg         mgmt_read,
    input  wire [15:0] mgmt_readdata,
    output reg         mgmt_write,
    output reg  [15:0] mgmt_writedata,
    input  wire        kbd_tx_empty,
    input  wire        mouse_tx_empty,
    input  wire  [8:0] kbd_host_cmd,
    input  wire  [8:0] mouse_host_cmd,
    output reg   [7:0] kbd_data,
    output reg         kbd_data_valid,
    output reg   [7:0] mouse_data,
    output reg         mouse_data_valid,
    output reg         kbd_host_cmd_clear,
    output reg         mouse_host_cmd_clear
);

reg aw_pending;
reg w_pending;
reg [7:0] write_addr;
reg [31:0] write_data;
reg [3:0] write_strobe;
reg [31:0] memory_size;
reg [1:0] mgmt_state;
reg       mgmt_is_write;
reg [15:0] mgmt_read_data;

localparam [1:0] MGMT_IDLE    = 2'd0;
localparam [1:0] MGMT_SETUP   = 2'd1;
localparam [1:0] MGMT_PULSE   = 2'd2;
localparam [1:0] MGMT_CAPTURE = 2'd3;

assign memory_size_out = memory_size;

assign s_axi_awready = !aw_pending && !s_axi_bvalid;
assign s_axi_wready = !w_pending && !s_axi_bvalid;
assign s_axi_arready = !s_axi_rvalid;

always @(posedge aclk) begin
    if (!aresetn) begin
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
        write_addr <= 8'd0;
        write_data <= 32'd0;
        write_strobe <= 4'd0;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
        run <= 1'b0;
        video_run <= 1'b0;
        video_freeze <= 1'b0;
        // Retained ABI field; direct scanout implements nearest-neighbor only.
        video_mode <= 5'b00000;
        audio_boost <= 2'd0;
        zsst_debug_control <= 0;
        zsst_debug_index <= 0;
        memory_base <= 40'd0;
        memory_size <= 32'd0;
        guest_ram_size <= 2'd0;
        mgmt_state <= MGMT_IDLE;
        mgmt_is_write <= 1'b0;
        mgmt_address <= 16'd0;
        mgmt_read <= 1'b0;
        mgmt_write <= 1'b0;
        mgmt_writedata <= 16'd0;
        mgmt_read_data <= 16'd0;
        kbd_data <= 8'd0;
        kbd_data_valid <= 1'b0;
        mouse_data <= 8'd0;
        mouse_data_valid <= 1'b0;
        kbd_host_cmd_clear <= 1'b0;
        mouse_host_cmd_clear <= 1'b0;
    end else begin
        mgmt_read <= 1'b0;
        mgmt_write <= 1'b0;
        kbd_data_valid <= 1'b0;
        mouse_data_valid <= 1'b0;
        kbd_host_cmd_clear <= 1'b0;
        mouse_host_cmd_clear <= 1'b0;
        case (mgmt_state)
            MGMT_SETUP:
                mgmt_state <= MGMT_PULSE;
            MGMT_PULSE: begin
                mgmt_read <= !mgmt_is_write;
                mgmt_write <= mgmt_is_write;
                mgmt_state <= MGMT_CAPTURE;
            end
            MGMT_CAPTURE: begin
                mgmt_read_data <= mgmt_readdata;
                mgmt_state <= MGMT_IDLE;
            end
            default: ;
        endcase

        if (s_axi_awready && s_axi_awvalid) begin
            aw_pending <= 1'b1;
            write_addr <= s_axi_awaddr;
        end
        if (s_axi_wready && s_axi_wvalid) begin
            w_pending <= 1'b1;
            write_data <= s_axi_wdata;
            write_strobe <= s_axi_wstrb;
        end
        if (aw_pending && w_pending && !s_axi_bvalid) begin
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b1;
            case (write_addr[7:2])
                6'h28: if (&write_strobe) zsst_debug_control <= write_data;
                6'h29: if (&write_strobe) zsst_debug_index <= write_data[15:0];
                6'h02:
                    if (write_strobe[0]) run <= write_data[0];
                6'h03: begin
                    if (write_strobe[0]) memory_base[7:0] <= write_data[7:0];
                    if (write_strobe[1]) memory_base[15:8] <= write_data[15:8];
                    if (write_strobe[2]) memory_base[23:16] <= write_data[23:16];
                    if (write_strobe[3]) memory_base[31:24] <= write_data[31:24];
                end
                6'h04:
                    if (write_strobe[0]) memory_base[39:32] <= write_data[7:0];
                6'h09: begin
                    if (write_strobe[0]) memory_size[7:0] <= write_data[7:0];
                    if (write_strobe[1]) memory_size[15:8] <= write_data[15:8];
                    if (write_strobe[2]) memory_size[23:16] <= write_data[23:16];
                    if (write_strobe[3]) memory_size[31:24] <= write_data[31:24];
                end
                6'h0e:
                    mgmt_address <= write_data[15:0];
                6'h0f:
                    mgmt_writedata <= write_data[15:0];
                6'h11:
                    if (write_strobe[0] && mgmt_state == MGMT_IDLE &&
                        (write_data[1:0] == 2'b01 ||
                         write_data[1:0] == 2'b10)) begin
                        mgmt_is_write <= write_data[1];
                        mgmt_state <= MGMT_SETUP;
                    end
                6'h13:
                    if (write_strobe[0] && kbd_tx_empty &&
                        !kbd_host_cmd[8]) begin
                        kbd_data <= write_data[7:0];
                        kbd_data_valid <= 1'b1;
                    end
                6'h14:
                    if (write_strobe[0] && mouse_tx_empty &&
                        !mouse_host_cmd[8]) begin
                        mouse_data <= write_data[7:0];
                        mouse_data_valid <= 1'b1;
                    end
                6'h15: begin
                    if (write_strobe[0] && write_data[0])
                        kbd_host_cmd_clear <= 1'b1;
                    if (write_strobe[0] && write_data[1])
                        mouse_host_cmd_clear <= 1'b1;
                end
                6'h16: begin
                    if (write_strobe[0]) begin
                        video_run <= write_data[0];
                        video_freeze <= write_data[1];
                    end
                    if (write_strobe[2])
                        video_mode <= write_data[20:16];
                end
                6'h1f:
                    if (write_strobe[0] && !run)
                        guest_ram_size <= write_data[1:0];
                6'h31:
                    if (write_strobe[0]) audio_boost <= write_data[1:0];
                default: ;
            endcase
        end
        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end
end

always @(posedge aclk) begin
    if (!aresetn) begin
        s_axi_rdata <= 32'd0;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_arready && s_axi_arvalid) begin
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b1;
            case (s_axi_araddr[7:2])
                6'h00: s_axi_rdata <= 32'h5a34_3836; // "Z486"
                6'h01: s_axi_rdata <= 32'h0001_0009; // ABI 1.9: DP audio control
                6'h02: s_axi_rdata <= {24'd0, debug_led[6:0], run};
                6'h03: s_axi_rdata <= memory_base[31:0];
                6'h04: s_axi_rdata <= {24'd0, memory_base[39:32]};
                6'h05: s_axi_rdata <= request_count;
                6'h06: s_axi_rdata <= read_beat_count;
                6'h07: s_axi_rdata <= stall_cycle_count;
                6'h08: s_axi_rdata <= response_error_count;
                6'h09: s_axi_rdata <= memory_size;
                6'h0a: s_axi_rdata <= {18'd0, post_write, post_code,
                                        first_instruction, bios_loaded,
                                        boot_stage};
                6'h0b: s_axi_rdata <= {16'd0, cpu_cs};
                6'h0c: s_axi_rdata <= cpu_eip;
                6'h0d: s_axi_rdata <= {23'd0, mgmt_state != MGMT_IDLE,
                                        fdd_request, ide1_request,
                                        ide0_request};
                6'h0e: s_axi_rdata <= {16'd0, mgmt_address};
                6'h0f: s_axi_rdata <= {16'd0, mgmt_writedata};
                6'h10: s_axi_rdata <= {16'd0, mgmt_read_data};
                6'h11: s_axi_rdata <= {30'd0, mgmt_is_write,
                                        mgmt_state != MGMT_IDLE};
                6'h12: s_axi_rdata <= {mouse_host_cmd[7:0],
                                        kbd_host_cmd[7:0], 6'd0,
                                        mouse_host_cmd[8], kbd_host_cmd[8],
                                        6'd0, mouse_tx_empty, kbd_tx_empty};
                6'h16: s_axi_rdata <= {11'd0, video_mode, 14'd0,
                                        video_freeze, video_run};
                6'h17: s_axi_rdata <= {4'd0, video_height,
                                        4'd0, video_width};
                6'h18: s_axi_rdata <= video_frames;
                6'h19: s_axi_rdata <= video_write_bursts;
                6'h1a: s_axi_rdata <= video_read_bursts;
                6'h1b: s_axi_rdata <= video_write_beats;
                6'h1c: s_axi_rdata <= video_read_beats;
                6'h1d: s_axi_rdata <= video_stall_cycles;
                6'h1e: s_axi_rdata <= video_error_count;
                6'h1f: s_axi_rdata <= {30'd0, guest_ram_size};
                6'h20: s_axi_rdata <= {30'd0, video_source};
                6'h21: s_axi_rdata <= video_line_requests;
                6'h22: s_axi_rdata <= video_line_completions;
                6'h23: s_axi_rdata <= video_native_frames;
                6'h24: s_axi_rdata <= {24'd0, video_outstanding_high_water};
                6'h28: s_axi_rdata <= zsst_debug_control;
                6'h29: s_axi_rdata <= {16'd0, zsst_debug_index};
                6'h2a: s_axi_rdata <= zsst_debug_data;
                6'h2b: s_axi_rdata <= zsst_debug_status;
                6'h2c: s_axi_rdata <= bus_status;
                6'h2d: s_axi_rdata <= l2_hits;
                6'h2e: s_axi_rdata <= l2_misses;
                6'h2f: s_axi_rdata <= l2_fill_beats;
                6'h30: s_axi_rdata <= l2_status;
                6'h31: s_axi_rdata <= {30'd0, audio_boost};
                default: s_axi_rdata <= 32'd0;
            endcase
        end
        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;
    end
end

endmodule
