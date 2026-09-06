// Unified DDR backend for the KV260 z486 system.
//
// The portable PC system has three logical clients because they have different
// native widths and handshakes: CPU/main memory, ISA DMA, and the MiSTer-style
// 64-bit auxiliary window used by ROM loading and packed VGA.  KV260 maps all
// three into one CMA allocation and one 128-bit AXI HP master.
module z486_ddr_axi_bridge #(
    parameter integer L2_SIZE_KIB = 512,
    parameter L2_ENABLE = 1,
    parameter integer WRITE_OUTSTANDING = 8
) (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [39:0]  memory_base,
    input  wire         cache_invalidate,
    output wire         cache_ready,
    output reg [31:0]   cache_hits, cache_misses, cache_fill_beats,

    input  wire         mem0_valid,
    input  wire         mem0_write,
    input  wire [31:0]  mem0_addr,
    input  wire [31:0]  mem0_din,
    input  wire  [3:0]  mem0_be,
    input  wire         mem0_line_read,
    output wire         mem0_ready,
    output reg  [31:0]  mem0_dout,
    output reg          mem0_resp_valid,
    output reg  [127:0] mem0_line_dout,
    output reg          mem0_line_resp_valid,

    input  wire         mem1_valid,
    input  wire         mem1_write,
    input  wire [31:0]  mem1_addr,
    input  wire [31:0]  mem1_din,
    input  wire  [3:0]  mem1_be,
    output wire         mem1_ready,
    output reg  [31:0]  mem1_dout,
    output reg          mem1_resp_valid,

    // MiSTer DDRAM addresses count 64-bit words in the 0x3000_0000 window.
    // The bridge strips that compatibility prefix, making the same data visible
    // to the CPU at its ordinary guest-relative byte address.
    input  wire         aux_rd,
    input  wire         aux_we,
    input  wire [28:0]  aux_addr,
    input  wire [63:0]  aux_din,
    input  wire  [7:0]  aux_be,
    output wire         aux_busy,
    output reg  [63:0]  aux_dout,
    output reg          aux_dout_ready,

    output reg  [31:0]  request_count,
    output reg  [31:0]  read_beat_count,
    output reg  [31:0]  stall_cycle_count,
    output reg  [31:0]  response_error_count,

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
    output wire         m_axi_rready,
    output wire         idle
);

localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_RADDR = 3'd1;
localparam [2:0] ST_RDATA = 3'd2;
localparam [2:0] ST_WRITE = 3'd3;
localparam [2:0] ST_WRESP = 3'd4;
localparam [2:0] ST_L2_CHECK = 3'd5;

localparam [1:0] CLIENT_MEM0 = 2'd0;
localparam [1:0] CLIENT_MEM1 = 2'd1;
localparam [1:0] CLIENT_AUX  = 2'd2;

reg [2:0] state;
localparam integer WRITE_COUNT_BITS = $clog2(WRITE_OUTSTANDING+1);
reg [WRITE_COUNT_BITS-1:0] pending_writes;
reg request_posted;
assign idle = state == ST_IDLE && pending_writes == 0;
reg [1:0] client;
reg [1:0] round_robin;
reg [39:0] request_addr;
reg [127:0] request_wdata;
reg [15:0] request_wstrb;
reg [2:0] request_size;
reg [3:0] read_lane_addr;
reg coalesced_line_read;
reg aw_done;
reg w_done;
reg grant_mem0;
reg grant_mem1;
reg grant_aux;
reg l2_burst, l2_discard;
reg [8:0] l2_beat;
reg [1:0] l2_wanted;
reg [127:0] l2_selected;
reg [31:0] guest_addr;
reg [39:0] previous_base;
wire l2_hit;
wire [127:0] l2_data;
wire write_sent = state == ST_WRITE &&
                  (aw_done || (m_axi_awvalid && m_axi_awready)) &&
                  (w_done || (m_axi_wvalid && m_axi_wready));
wire write_returned = m_axi_bvalid && m_axi_bready;
wire l2_clear = cache_invalidate || memory_base != previous_base ||
               (write_returned && m_axi_bresp != 0);
// Only L1-generated line fills in ordinary RAM allocate. Scalar/device reads
// bypass. The VGA/ROM hole and storage beyond the guest RAM window never fill.
wire l2_eligible = L2_ENABLE && cache_ready && mem0_line_read && !mem0_write &&
                   mem0_addr[3:0] == 0 && mem0_addr < 32'h08000000 &&
                   (mem0_addr < 32'h000a0000 || mem0_addr >= 32'h00100000);
wire [31:0] aux_guest_addr = {aux_addr,3'b000} - 32'h30000000;
wire [31:0] l2_probe_addr = grant_mem0 ? mem0_addr :
                             grant_mem1 ? mem1_addr : aux_guest_addr;
wire l2_probe_write = grant_mem0 ? mem0_write : grant_mem1 ? mem1_write : aux_we;
wire [127:0] l2_probe_data = grant_mem0 ? {4{mem0_din}} :
                                  grant_mem1 ? {4{mem1_din}} : {2{aux_din}};
wire [15:0] l2_probe_mask = grant_mem0 ? ({12'd0,mem0_be} << {mem0_addr[3:2],2'b00}) :
                           grant_mem1 ? ({12'd0,mem1_be} << {mem1_addr[3:2],2'b00}) :
                           (aux_addr[0] ? {aux_be,8'd0} : {8'd0,aux_be});
wire l2_fill_fire = state == ST_RDATA && l2_burst && m_axi_rvalid;
wire [31:0] l2_fill_address = {guest_addr[31:6],l2_beat[1:0],4'b0000};
generate if (L2_ENABLE) begin : with_l2
    z486_l2_cache #(.SIZE_KIB(L2_SIZE_KIB)) cache (
        .clk(aclk), .reset_n(aresetn), .invalidate(l2_clear), .ready(cache_ready),
        .probe(grant_mem0 || grant_mem1 || grant_aux),
        .address(l2_probe_addr), .write(l2_probe_write),
        .write_data(l2_probe_data), .write_mask(l2_probe_mask),
        .hit(l2_hit), .read_data(l2_data),
        .fill_begin(state == ST_L2_CHECK && !l2_hit),
        .fill_valid(l2_fill_fire && l2_beat < 4),
        .fill_address(l2_fill_address), .fill_data(m_axi_rdata),
        .fill_commit(l2_fill_fire && m_axi_rlast && l2_beat == 3 &&
                     m_axi_rresp == 0 && !l2_discard)
    );
end else begin : without_l2
    assign cache_ready = 0;
    assign l2_hit = 0;
    assign l2_data = 0;
end endgenerate

wire aux_request = aux_rd | aux_we;
// Only ordinary RAM writes may overlap B responses. AXI ID zero preserves
// their ordering. Reads (including L2 hits), apertures and ROM accesses fence
// older writes, so no pending-store forwarding path is required here.
function automatic ram_address(input [31:0] address);
    ram_address = address < 32'h08000000 &&
                  (address < 32'h000a0000 || address >= 32'h00100000);
endfunction
wire mem0_postable = mem0_write && ram_address(mem0_addr);
wire mem1_postable = mem1_write && ram_address(mem1_addr);
wire aux_postable = aux_we && ram_address(aux_guest_addr);

always @* begin
    grant_mem0 = 1'b0;
    grant_mem1 = 1'b0;
    grant_aux = 1'b0;
    if (state == ST_IDLE) begin
        case (round_robin)
            CLIENT_MEM0: begin
                if (mem0_valid) grant_mem0 = 1'b1;
                else if (mem1_valid) grant_mem1 = 1'b1;
                else if (aux_request) grant_aux = 1'b1;
            end
            CLIENT_MEM1: begin
                if (mem1_valid) grant_mem1 = 1'b1;
                else if (aux_request) grant_aux = 1'b1;
                else if (mem0_valid) grant_mem0 = 1'b1;
            end
            default: begin
                if (aux_request) grant_aux = 1'b1;
                else if (mem0_valid) grant_mem0 = 1'b1;
                else if (mem1_valid) grant_mem1 = 1'b1;
            end
        endcase
        // Do not skip a selected read/fence in favor of younger writes.
        if (pending_writes != 0) begin
            if (!mem0_postable) grant_mem0 = 0;
            if (!mem1_postable) grant_mem1 = 0;
            if (!aux_postable) grant_aux = 0;
        end
        if (pending_writes >= WRITE_OUTSTANDING) begin
            grant_mem0 = 0;
            grant_mem1 = 0;
            grant_aux = 0;
        end
    end
end

assign mem0_ready = grant_mem0;
assign mem1_ready = grant_mem1;
// DDRAM_BUSY is a waitrequest signal. It must also block an auxiliary request
// in an idle cycle in which another client wins arbitration.
// The ROM loader samples busy BEFORE pulsing rd on the next cycle; unlike
// the CPU ports it does not hold a rejected request. Advertise pending write
// fences even without aux_request, or a read pulse can be lost during drain.
assign aux_busy = (state != ST_IDLE) || (pending_writes != 0) ||
                  (aux_request && !grant_aux);

assign m_axi_awid = 1'b0;
assign m_axi_awaddr = request_addr;
assign m_axi_awlen = 8'd0;
assign m_axi_awsize = request_size;
assign m_axi_awburst = 2'b01;
assign m_axi_awlock = 1'b0;
assign m_axi_awcache = 4'b0011;
assign m_axi_awprot = 3'b000;
assign m_axi_awqos = 4'b0000;
assign m_axi_awvalid = state == ST_WRITE && !aw_done;
assign m_axi_wdata = request_wdata;
assign m_axi_wstrb = request_wstrb;
assign m_axi_wlast = 1'b1;
assign m_axi_wvalid = state == ST_WRITE && !w_done;
assign m_axi_bready = pending_writes != 0;

assign m_axi_arid = 1'b0;
assign m_axi_araddr = l2_burst ? {request_addr[39:6],6'b0} : request_addr;
// Every logical request maps to one native AXI beat. Cache-line reads use a
// 128-bit beat; scalar CPU/DMA and auxiliary accesses select a narrower beat.
assign m_axi_arlen = l2_burst ? 8'd3 : 8'd0;
assign m_axi_arsize = request_size;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock = 1'b0;
assign m_axi_arcache = 4'b0011;
assign m_axi_arprot = 3'b000;
assign m_axi_arqos = 4'b0000;
assign m_axi_arvalid = state == ST_RADDR;
assign m_axi_rready = state == ST_RDATA;

function automatic [31:0] select_dword(input [127:0] data,
                                       input [1:0] lane);
    case (lane)
        2'd0: select_dword = data[31:0];
        2'd1: select_dword = data[63:32];
        2'd2: select_dword = data[95:64];
        default: select_dword = data[127:96];
    endcase
endfunction

always @(posedge aclk) begin
    if (!aresetn) begin
        state <= ST_IDLE;
        client <= CLIENT_MEM0;
        round_robin <= CLIENT_MEM0;
        request_addr <= 40'd0;
        request_wdata <= 128'd0;
        request_wstrb <= 16'd0;
        request_size <= 3'd2;
        read_lane_addr <= 4'd0;
        coalesced_line_read <= 1'b0;
        aw_done <= 1'b0;
        w_done <= 1'b0;
        mem0_dout <= 32'd0;
        mem1_dout <= 32'd0;
        aux_dout <= 64'd0;
        mem0_resp_valid <= 1'b0;
        mem0_line_dout <= 128'd0;
        mem0_line_resp_valid <= 1'b0;
        mem1_resp_valid <= 1'b0;
        aux_dout_ready <= 1'b0;
        request_count <= 32'd0;
        read_beat_count <= 32'd0;
        stall_cycle_count <= 32'd0;
        response_error_count <= 32'd0;
        cache_hits <= 0; cache_misses <= 0; cache_fill_beats <= 0;
        l2_burst <= 0; l2_discard <= 0; l2_beat <= 0;
        l2_wanted <= 0; l2_selected <= 0; guest_addr <= 0;
        previous_base <= 0;
        pending_writes <= 0;
        request_posted <= 0;
    end else begin
        case ({write_sent, write_returned})
            2'b10: pending_writes <= pending_writes + 1'b1;
            2'b01: pending_writes <= pending_writes - 1'b1;
            default: ;
        endcase
        if (write_returned && m_axi_bresp != 0)
            response_error_count <= response_error_count + 1'b1;
        previous_base <= memory_base;
        if (l2_clear) l2_discard <= 1;
        mem0_resp_valid <= 1'b0;
        mem0_line_resp_valid <= 1'b0;
        mem1_resp_valid <= 1'b0;
        aux_dout_ready <= 1'b0;

        if (state != ST_IDLE &&
            !((state == ST_RADDR && m_axi_arready) ||
              (state == ST_RDATA && m_axi_rvalid) ||
              (state == ST_WRITE && ((m_axi_awvalid && m_axi_awready) ||
                                     (m_axi_wvalid && m_axi_wready))) ||
              (state == ST_WRESP && m_axi_bvalid)))
            stall_cycle_count <= stall_cycle_count + 1'b1;

        case (state)
            ST_IDLE: begin
                if (grant_mem0) begin
                    request_posted <= mem0_postable && WRITE_OUTSTANDING > 1;
                    guest_addr <= mem0_addr;
                    l2_wanted <= mem0_addr[5:4];
                    l2_burst <= l2_eligible;
                    l2_discard <= 0;
                    l2_beat <= 0;
                    l2_selected <= 0;
                    client <= CLIENT_MEM0;
                    round_robin <= CLIENT_MEM1;
                    request_addr <= memory_base + {8'd0, mem0_addr[31:2], 2'b00};
                    // A z486 cache fill is one aligned 16-byte line. Fetch it
                    // as one native 128-bit HP beat and return it intact.
                    coalesced_line_read <= !mem0_write && mem0_line_read &&
                                           mem0_addr[3:0] == 4'd0;
                    request_size <= (!mem0_write && mem0_line_read &&
                                     mem0_addr[3:0] == 4'd0) ? 3'd4 : 3'd2;
                    read_lane_addr <= {mem0_addr[3:2], 2'b00};
                    request_wdata <= {4{mem0_din}};
                    request_wstrb <= {12'd0, mem0_be} << {mem0_addr[3:2], 2'b00};
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    state <= mem0_write ? ST_WRITE : l2_eligible ? ST_L2_CHECK : ST_RADDR;
                    request_count <= request_count + 1'b1;
                end else if (grant_mem1) begin
                    request_posted <= mem1_postable && WRITE_OUTSTANDING > 1;
                    l2_burst <= 0;
                    client <= CLIENT_MEM1;
                    round_robin <= CLIENT_AUX;
                    request_addr <= memory_base + {8'd0, mem1_addr[31:2], 2'b00};
                    coalesced_line_read <= 1'b0;
                    request_size <= 3'd2;
                    read_lane_addr <= {mem1_addr[3:2], 2'b00};
                    request_wdata <= {4{mem1_din}};
                    request_wstrb <= {12'd0, mem1_be} << {mem1_addr[3:2], 2'b00};
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    state <= mem1_write ? ST_WRITE : ST_RADDR;
                    request_count <= request_count + 1'b1;
                end else if (grant_aux) begin
                    request_posted <= aux_postable && WRITE_OUTSTANDING > 1;
                    l2_burst <= 0;
                    client <= CLIENT_AUX;
                    round_robin <= CLIENT_MEM0;
                    // {aux_addr,3'b0} is 0x3000_0000-based. Strip the
                    // compatibility prefix so CPU and auxiliary accesses share
                    // one physical allocation, exactly as in ao486_MiSTer.
                    request_addr <= memory_base +
                                    ({8'd0, aux_addr, 3'b000} - 40'h0030_000000);
                    coalesced_line_read <= 1'b0;
                    request_size <= 3'd3;
                    read_lane_addr <= {aux_addr[0], 3'b000};
                    request_wdata <= {2{aux_din}};
                    request_wstrb <= aux_addr[0] ? {aux_be, 8'd0} : {8'd0, aux_be};
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    state <= aux_we ? ST_WRITE : ST_RADDR;
                    request_count <= request_count + 1'b1;
                end
            end

            ST_L2_CHECK: begin
                if (l2_hit) begin
                    cache_hits <= cache_hits + 1'b1;
                    mem0_line_dout <= l2_data;
                    mem0_line_resp_valid <= 1;
                    state <= ST_IDLE;
                    l2_burst <= 0;
                end else begin
                    cache_misses <= cache_misses + 1'b1;
                    state <= ST_RADDR;
                end
            end
            ST_RADDR:
                if (m_axi_arready)
                    state <= ST_RDATA;

            ST_RDATA:
                if (m_axi_rvalid) begin
                    // Every accepted R transfer is exactly one AXI beat,
                    // including a complete 128-bit cache-line response.
                    read_beat_count <= read_beat_count + 1'b1;
                    if (m_axi_rresp != 2'b00)
                        response_error_count <= response_error_count + 1'b1;
                    if (l2_burst) begin
                        cache_fill_beats <= cache_fill_beats + 1'b1;
                        l2_beat <= l2_beat + 1'b1;
                        if (l2_beat[1:0] == l2_wanted) l2_selected <= m_axi_rdata;
                        if (m_axi_rresp != 0 || m_axi_rlast != (l2_beat == 3))
                            l2_discard <= 1;
                        if (m_axi_rlast) begin
                            mem0_line_dout <= l2_beat[1:0] == l2_wanted ?
                                              m_axi_rdata : l2_selected;
                            mem0_line_resp_valid <= 1;
                            state <= ST_IDLE;
                            if (l2_beat != 3)
                                response_error_count <= response_error_count + 1'b1;
                        end
                    end else case (client)
                        CLIENT_MEM0: begin
                            if (coalesced_line_read) begin
                                mem0_line_dout <= m_axi_rdata;
                                mem0_line_resp_valid <= 1'b1;
                                state <= ST_IDLE;
                                if (!m_axi_rlast)
                                    response_error_count <=
                                        response_error_count + 1'b1;
                            end else begin
                                mem0_dout <= select_dword(m_axi_rdata,
                                                          read_lane_addr[3:2]);
                                mem0_resp_valid <= 1'b1;
                                read_lane_addr <= read_lane_addr + 4'd4;
                            end
                        end
                        CLIENT_MEM1: begin
                            mem1_dout <= select_dword(m_axi_rdata,
                                                      read_lane_addr[3:2]);
                            mem1_resp_valid <= 1'b1;
                            read_lane_addr <= read_lane_addr + 4'd4;
                        end
                        default: begin
                            aux_dout <= read_lane_addr[3] ? m_axi_rdata[127:64]
                                                         : m_axi_rdata[63:0];
                            aux_dout_ready <= 1'b1;
                            read_lane_addr <= read_lane_addr + 4'd8;
                        end
                    endcase
                    if (m_axi_rlast && !coalesced_line_read && !l2_burst)
                        state <= ST_IDLE;
                end

            ST_WRITE: begin
                if (m_axi_awvalid && m_axi_awready)
                    aw_done <= 1'b1;
                if (m_axi_wvalid && m_axi_wready)
                    w_done <= 1'b1;
                if (write_sent)
                    state <= request_posted ? ST_IDLE : ST_WRESP;
            end

            ST_WRESP:
                if (write_returned) begin
                    state <= ST_IDLE;
                end

            default:
                state <= ST_IDLE;
        endcase
    end
end

endmodule
