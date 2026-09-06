`timescale 1ns/1ps

// KV260 adapter for the portable zSST device. The guest's PCI BAR is the host
// interface; framebuffer and texture traffic use one HP port.  The shared
// KV260 scanout engine consumes the exported framebuffer metadata.
module z486_zsst (
    input  logic         aclk,
    input  logic         aresetn,
    input  logic         soft_reset,
    output logic         reset_busy,
    output logic         memory_idle,
    input  logic [39:0]  memory_base,
    input logic [31:0] debug_control,
    input logic [15:0] debug_index,
    output logic [31:0] debug_data,
    output logic [31:0] debug_status,
    input logic cpu_mem_accept_wait,
    input logic cpu_mem_read_wait,
    input  logic         memory_enable,
    input  logic [31:0]  init_enable,

    input  logic         host_req_valid,
    output logic         host_req_ready,
    input  logic [23:0]  host_address,
    input  logic [31:0]  host_writedata,
    input  logic [3:0]   host_byteenable,
    input  logic         host_write,
    output logic         host_rsp_valid,
    input  logic         host_rsp_ready,
    output logic [31:0]  host_readdata,
    output logic         host_error,

    output logic         video_active,
    output logic [39:0]  scanout_fbi_base,
    output logic [23:0]  scanout_buffer_size,
    output logic [15:0]  scanout_stride,
    output logic [9:0]   scanout_width,
    output logic [9:0]   scanout_height,
    output logic [1:0]   scanout_displayed_buffer,
    input  logic         scanout_v_retrace,
    input  logic [11:0]  scanout_v_retrace_count,
    output logic         busy,
    output logic         memory_error,

    output logic [3:0]   render_axi_awid,
    output logic [39:0]  render_axi_awaddr,
    output logic [7:0]   render_axi_awlen,
    output logic [2:0]   render_axi_awsize,
    output logic [1:0]   render_axi_awburst,
    output logic         render_axi_awlock,
    output logic [3:0]   render_axi_awcache,
    output logic [2:0]   render_axi_awprot,
    output logic [3:0]   render_axi_awqos,
    output logic         render_axi_awvalid,
    input  logic         render_axi_awready,
    output logic [127:0] render_axi_wdata,
    output logic [15:0]  render_axi_wstrb,
    output logic         render_axi_wlast,
    output logic         render_axi_wvalid,
    input  logic         render_axi_wready,
    input  logic [3:0]   render_axi_bid,
    input  logic [1:0]   render_axi_bresp,
    input  logic         render_axi_bvalid,
    output logic         render_axi_bready,
    output logic [3:0]   render_axi_arid,
    output logic [39:0]  render_axi_araddr,
    output logic [7:0]   render_axi_arlen,
    output logic [2:0]   render_axi_arsize,
    output logic [1:0]   render_axi_arburst,
    output logic         render_axi_arlock,
    output logic [3:0]   render_axi_arcache,
    output logic [2:0]   render_axi_arprot,
    output logic [3:0]   render_axi_arqos,
    output logic         render_axi_arvalid,
    input  logic         render_axi_arready,
    input  logic [3:0]   render_axi_rid,
    input  logic [127:0] render_axi_rdata,
    input  logic [1:0]   render_axi_rresp,
    input  logic         render_axi_rlast,
    input  logic         render_axi_rvalid,
    output logic         render_axi_rready
);
    import sst1_pkg::*;
    import sst1_regs_pkg::*;
    import z486_kv260_memory_map_pkg::*;

    sst1_host_req_t host_req;
    sst1_host_rsp_t host_rsp;
    sst1_mem_req_t device_mem_req, queued_mem_req;
    sst1_mem_rsp_t device_mem_rsp;
    logic device_mem_req_valid, device_mem_req_ready;
    logic device_mem_rsp_valid, device_mem_rsp_ready;
    logic queued_mem_req_valid, queued_mem_req_ready, request_fifo_empty;
    logic bridge_writes_idle, memory_writes_idle;
    logic bridge_idle, bridge_rsp_valid;
    logic device_reset_n;
    // A guest reset may discard work not yet issued to AXI, but it must not
    // discard an accepted AW, W, AR, or an outstanding response in the PS.
    // Keep the bridge alive and discard old read responses until drained.
    zsst_reset_guard reset_guard (
        .clk(aclk), .reset_n(aresetn), .soft_reset,
        .bus_idle(bridge_idle), .client_reset_n(device_reset_n), .reset_busy
    );
    assign memory_idle = bridge_idle && request_fifo_empty;
    assign device_mem_rsp_valid = bridge_rsp_valid && device_reset_n;
    logic [39:0] fbi_base, texture_base;
    logic [31:0] video_dimensions;
    logic [1:0] displayed_buffer;
    logic [2:0] swaps_pending;
    logic [15:0] scanout_rgb565;
    logic [23:0] scanout_rgb888;
    logic [6:0] fifo_free;

    assign fbi_base = memory_base + {8'd0, ZSST_FBI_OFFSET};
    assign texture_base = memory_base + {8'd0, ZSST_TMU_OFFSET};
    assign scanout_fbi_base = fbi_base;
    assign scanout_displayed_buffer = displayed_buffer;
    assign host_req.addr = host_address;
    assign host_req.wdata = host_writedata;
    assign host_req.be = host_byteenable;
    assign host_req.write = host_write;
    assign host_readdata = host_rsp.rdata;
    assign host_error = host_rsp.error;
    assign scanout_width = video_dimensions[21:0] == 0 ? 10'd640 :
                           video_dimensions[9:0] + 1'b1;
    assign scanout_height = video_dimensions[25:16] == 0 ? 10'd480 :
                            video_dimensions[25:16];
    assign memory_writes_idle = request_fifo_empty && bridge_writes_idle;

    // Track the two layout fields consumed by the board scanout. They remain
    // guest-programmed SST-1 registers; this is only a timing-local mirror.
    always_ff @(posedge aclk) begin
        if (!device_reset_n) begin
            scanout_buffer_size <= 24'h10_0000;
            scanout_stride <= 16'd1280;
        end else if (host_req_valid && host_req_ready && host_write &&
                     init_enable[0]) begin
            case (host_address)
                24'h000214: scanout_stride <=
                    {5'd0, host_writedata[7:4], 7'd0};
                24'h000218: scanout_buffer_size <=
                    {15'd0, host_writedata[19:11]} << 12;
                default: ;
            endcase
        end
    end

    logic perf_snapshot, swap_event, fbi_active;
    logic [63:0] perf_data;
    wire [15:0] perf_events = {
        render_axi_bvalid && render_axi_bready, // 15: write responses
        render_axi_rvalid && render_axi_rready, // 14: read beats
        render_axi_wvalid && render_axi_wready, // 13: write beats
        !busy && !cpu_mem_read_wait && !cpu_mem_accept_wait, // 12
        fbi_active && cpu_mem_read_wait,        // 11: overlap
        cpu_mem_read_wait,                      // 10: PC outstanding read
        cpu_mem_accept_wait,                    // 9: PC request blocked
        queued_mem_req_valid && !queued_mem_req_ready, // 8: AXI bridge full
        device_mem_req_valid && !device_mem_req_ready, // 7: request FIFO full
        host_rsp_valid && host_rsp_ready,       // 6: host responses
        host_req_valid && host_req_ready && !host_write, // 5: host reads
        host_req_valid && host_req_ready && host_write,  // 4: host writes
        host_req_valid && !host_req_ready,      // 3: host blocked
        swap_event,                            // 2: displayed swaps
        fbi_active,                            // 1: FBI active cycles
        1'b1                                   // 0: total cycles
    };
    zsst_board_perf counters (
        .clk(aclk), .reset_n(device_reset_n), .control(debug_control),
        .read_index(debug_index), .read_data(debug_data),
        .sequence_number(debug_status), .events(perf_events),
        .renderer_data(perf_data), .snapshot(perf_snapshot)
    );

    sst1_device #(.PERF_COUNTER_BITS(32), .PERF_SNAPSHOT_WHILE_BUSY(1)) device (
        .clk(aclk), .reset_n(device_reset_n),
        .init_write_enable(init_enable[0]),
        .init_remap_enable(init_enable[2]), .memory_enable,
        .memory_writes_idle,
        .fbi_memory_base(fbi_base),
        .fbi_memory_size(ZSST_FBI_SIZE[23:0]),
        .texture_memory_base(texture_base),
        .texture_memory_size(ZSST_TMU_SIZE[23:0]),
        .v_retrace(scanout_v_retrace),
        .v_retrace_count(scanout_v_retrace_count),
        .scanout_rgb565, .scanout_rgb888,
        .displayed_buffer, .swaps_pending, .swap_event, .perf_fbi_active(fbi_active),
        .video_frame_count(), .video_hsync_register(),
        .video_vsync_register(), .video_backporch_register(),
        .video_dimensions_register(video_dimensions), .video_active,
        .host_req_valid, .host_req_ready, .host_req,
        .host_rsp_valid, .host_rsp_ready, .host_rsp,
        .mem_req_valid(device_mem_req_valid),
        .mem_req_ready(device_mem_req_ready), .mem_req(device_mem_req),
        .mem_rsp_valid(device_mem_rsp_valid),
        .mem_rsp_ready(device_mem_rsp_ready), .mem_rsp(device_mem_rsp),
        .debug_host_event_valid(), .debug_host_event(), .fifo_free, .busy,
        .pixels_in(), .chroma_fail(), .zfunc_fail(), .afunc_fail(),
        .pixels_out(), .last_alpha(), .last_w(), .perf_snapshot,
        .perf_clear(1'b0), .perf_read_index(debug_index[6:0]), .perf_read_data(perf_data),
        .perf_pending()
    );

    zsst_mem_request_fifo #(.DEPTH(4)) request_fifo (
        .clk(aclk), .reset_n(device_reset_n),
        .in_valid(device_mem_req_valid), .in_ready(device_mem_req_ready),
        .in_req(device_mem_req), .empty(request_fifo_empty),
        .out_valid(queued_mem_req_valid), .out_ready(queued_mem_req_ready),
        .out_req(queued_mem_req)
    );

    sst1_axi_bridge memory_bridge (
        .aclk, .aresetn, .req_valid(queued_mem_req_valid && device_reset_n),
        .req_ready(queued_mem_req_ready), .req(queued_mem_req),
        .rsp_valid(bridge_rsp_valid),
        .rsp_ready(device_reset_n ? device_mem_rsp_ready : 1'b1),
        .rsp(device_mem_rsp), .read_requests(), .read_beats(),
        .write_requests(), .write_beats(), .outstanding_reads(),
        .writes_idle(bridge_writes_idle), .idle(bridge_idle), .sticky_error(memory_error),
        .m_axi_awid(render_axi_awid), .m_axi_awaddr(render_axi_awaddr),
        .m_axi_awlen(render_axi_awlen), .m_axi_awsize(render_axi_awsize),
        .m_axi_awburst(render_axi_awburst), .m_axi_awlock(render_axi_awlock),
        .m_axi_awcache(render_axi_awcache), .m_axi_awprot(render_axi_awprot),
        .m_axi_awqos(render_axi_awqos), .m_axi_awvalid(render_axi_awvalid),
        .m_axi_awready(render_axi_awready), .m_axi_wdata(render_axi_wdata),
        .m_axi_wstrb(render_axi_wstrb), .m_axi_wlast(render_axi_wlast),
        .m_axi_wvalid(render_axi_wvalid), .m_axi_wready(render_axi_wready),
        .m_axi_bid(render_axi_bid), .m_axi_bresp(render_axi_bresp),
        .m_axi_bvalid(render_axi_bvalid), .m_axi_bready(render_axi_bready),
        .m_axi_arid(render_axi_arid), .m_axi_araddr(render_axi_araddr),
        .m_axi_arlen(render_axi_arlen), .m_axi_arsize(render_axi_arsize),
        .m_axi_arburst(render_axi_arburst), .m_axi_arlock(render_axi_arlock),
        .m_axi_arcache(render_axi_arcache), .m_axi_arprot(render_axi_arprot),
        .m_axi_arqos(render_axi_arqos), .m_axi_arvalid(render_axi_arvalid),
        .m_axi_arready(render_axi_arready), .m_axi_rid(render_axi_rid),
        .m_axi_rdata(render_axi_rdata), .m_axi_rresp(render_axi_rresp),
        .m_axi_rlast(render_axi_rlast), .m_axi_rvalid(render_axi_rvalid),
        .m_axi_rready(render_axi_rready)
    );

endmodule
