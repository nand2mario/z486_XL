module z486_ddr_wb_bridge #(
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


wire  lb_cache_ready;
wire [31:0] lb_cache_hits;
wire [31:0] lb_cache_misses;
wire [31:0] lb_cache_fill_beats;
wire  lb_mem0_ready;
wire [31:0] lb_mem0_dout;
wire  lb_mem0_resp_valid;
wire [127:0] lb_mem0_line_dout;
wire  lb_mem0_line_resp_valid;
wire  lb_mem1_ready;
wire [31:0] lb_mem1_dout;
wire  lb_mem1_resp_valid;
wire  lb_aux_busy;
wire [63:0] lb_aux_dout;
wire  lb_aux_dout_ready;
wire [31:0] lb_request_count;
wire [31:0] lb_read_beat_count;
wire [31:0] lb_stall_cycle_count;
wire [31:0] lb_response_error_count;
wire [0:0] lb_m_axi_awid;
wire [39:0] lb_m_axi_awaddr;
wire [7:0] lb_m_axi_awlen;
wire [2:0] lb_m_axi_awsize;
wire [1:0] lb_m_axi_awburst;
wire  lb_m_axi_awlock;
wire [3:0] lb_m_axi_awcache;
wire [2:0] lb_m_axi_awprot;
wire [3:0] lb_m_axi_awqos;
wire  lb_m_axi_awvalid;
wire [127:0] lb_m_axi_wdata;
wire [15:0] lb_m_axi_wstrb;
wire  lb_m_axi_wlast;
wire  lb_m_axi_wvalid;
wire  lb_m_axi_bready;
wire [0:0] lb_m_axi_arid;
wire [39:0] lb_m_axi_araddr;
wire [7:0] lb_m_axi_arlen;
wire [2:0] lb_m_axi_arsize;
wire [1:0] lb_m_axi_arburst;
wire  lb_m_axi_arlock;
wire [3:0] lb_m_axi_arcache;
wire [2:0] lb_m_axi_arprot;
wire [3:0] lb_m_axi_arqos;
wire  lb_m_axi_arvalid;
wire  lb_m_axi_rready;
wire  lb_idle;
wire [0:0] wb_awid;
wire [39:0] wb_awaddr;
wire [7:0] wb_awlen;
wire [2:0] wb_awsize;
wire [1:0] wb_awburst;
wire  wb_awlock;
wire [3:0] wb_awcache;
wire [2:0] wb_awprot;
wire [3:0] wb_awqos;
wire  wb_awvalid;
wire [127:0] wb_wdata;
wire [15:0] wb_wstrb;
wire  wb_wlast;
wire  wb_wvalid;
wire  wb_bready;
wire [0:0] wb_arid;
wire [39:0] wb_araddr;
wire [7:0] wb_arlen;
wire [2:0] wb_arsize;
wire [1:0] wb_arburst;
wire  wb_arlock;
wire [3:0] wb_arcache;
wire [2:0] wb_arprot;
wire [3:0] wb_arqos;
wire  wb_arvalid;
wire  wb_rready;

// Cacheable ordinary RAM shares one coherent cache across CPU, DMA and aux.
// Uncached legacy accesses and cached transfers never own AXI simultaneously.
reg [39:0] active_base;
reg bypass_active, cache_active;
reg [1:0] rr, selected, owner;
reg [3:0] lane;
reg line_q, write_q, missed_q;
wire ctrl_idle, transport_idle;
reg flush_inflight, invalidation_done;
wire ctrl_ready, ctrl_response, ctrl_error, ctrl_flush_done;
wire [127:0] ctrl_data;
wire flush_needed = (cache_invalidate && !invalidation_done) || memory_base != active_base;
wire flush_request = flush_needed && !flush_inflight && !bypass_active;
wire available = !bypass_active && !cache_active && ctrl_idle &&
                 !flush_needed && !flush_inflight && !cache_invalidate && lb_idle;
wire [31:0] aux_guest = {aux_addr,3'b0}-32'h30000000;
wire [31:0] selected_addr = selected==0 ? mem0_addr : selected==1 ? mem1_addr : aux_guest;
wire selected_write = selected==0 ? mem0_write : selected==1 ? mem1_write : aux_we;
wire [127:0] selected_data = selected==0 ? {4{mem0_din}} :
    selected==1 ? {4{mem1_din}} : {2{aux_din}};
wire [15:0] selected_mask = selected==0 ? ({12'b0,mem0_be} << {mem0_addr[3:2],2'b0}) :
    selected==1 ? ({12'b0,mem1_be} << {mem1_addr[3:2],2'b0}) :
    (aux_addr[0] ? {aux_be,8'b0} : {8'b0,aux_be});
wire selected_cached = selected_addr<32'h08000000 &&
    (selected_addr<32'h000a0000 || selected_addr>=32'h00100000);
reg selected_valid;
always @* begin
    selected=0; selected_valid=0;
    for(integer n=2;n>=0;n=n-1) begin
        case((int'(rr)+n)%3)
            0: if(mem0_valid) begin selected=0; selected_valid=1; end
            1: if(mem1_valid) begin selected=1; selected_valid=1; end
            2: if(aux_rd || aux_we) begin selected=2; selected_valid=1; end
        endcase
    end
end
wire cache_request = available && selected_valid && selected_cached;
wire bypass_request = available && selected_valid && !selected_cached;
wire accepted = cache_request ? ctrl_ready :
    bypass_request && (selected==0 ? lb_mem0_ready : selected==1 ? lb_mem1_ready : !lb_aux_busy);
assign mem0_ready=accepted && selected==0;
assign mem1_ready=accepted && selected==1;
// Aux pulse producer needs advance backpressure, even before asserting rd.
assign aux_busy=!available || ((aux_rd || aux_we) && !(accepted && selected==2));
assign mem0_dout=cache_active ? ctrl_data[lane[3:2]*32+:32] : lb_mem0_dout;
assign mem1_dout=cache_active ? ctrl_data[lane[3:2]*32+:32] : lb_mem1_dout;
assign aux_dout=cache_active ? ctrl_data[lane[3]*64+:64] : lb_aux_dout;
assign mem0_line_dout=cache_active ? ctrl_data : lb_mem0_line_dout;
assign mem0_resp_valid=lb_mem0_resp_valid || (cache_active && ctrl_response && owner==0 && !write_q && !line_q);
assign mem0_line_resp_valid=lb_mem0_line_resp_valid || (cache_active && ctrl_response && owner==0 && !write_q && line_q);
assign mem1_resp_valid=lb_mem1_resp_valid || (cache_active && ctrl_response && owner==1 && !write_q);
assign aux_dout_ready=lb_aux_dout_ready || (cache_active && ctrl_response && owner==2 && !write_q);
assign idle=!bypass_active && !cache_active && ctrl_idle && transport_idle &&
            lb_idle && !flush_needed && !flush_inflight;
assign cache_ready=ctrl_ready;
wire read_valid,read_ready,read_done,read_error;
wire [31:0] read_address,writeback_address;
wire [511:0] read_line,writeback_line;
wire writeback_valid,writeback_ready,writeback_done,writeback_error;
z486_l2_wb_controller #(.SIZE_KIB(L2_SIZE_KIB)) cache(
    .clk(aclk),.reset_n(aresetn),
    .request_valid(cache_request),.request_ready(ctrl_ready),
    .request_write(selected_write),.request_address(selected_addr),
    .request_data(selected_data),.request_mask(selected_mask),
    .response_valid(ctrl_response),.response_data(ctrl_data),
    .flush(flush_request),.flush_done(ctrl_flush_done),.idle(ctrl_idle),
    .error(ctrl_error),.retry(1'b0),
    .read_valid,.read_ready,.read_address,.read_done,.read_error,.read_line,
    .writeback_valid,.writeback_ready,.writeback_address,.writeback_line,
    .writeback_done,.writeback_error
);
always @(posedge aclk) begin
    if(!aresetn) begin
        active_base<=0; bypass_active<=0; cache_active<=0;
        flush_inflight<=0; invalidation_done<=0;
        rr<=0; owner<=0; lane<=0; line_q<=0; write_q<=0; missed_q<=0;
        request_count<=0; read_beat_count<=0; stall_cycle_count<=0;
        response_error_count<=0; cache_hits<=0; cache_misses<=0; cache_fill_beats<=0;
    end else begin
        if(!cache_invalidate) invalidation_done<=0;
        if(flush_request) flush_inflight<=1;
        if(ctrl_flush_done) begin
            active_base<=memory_base; flush_inflight<=0;
            invalidation_done<=cache_invalidate;
        end
        if(accepted) begin
            rr<=selected==2 ? 0 : selected+1'b1;
            request_count<=request_count+1'b1;
            if(selected_cached) begin
                cache_active<=1; owner<=selected; lane<=selected_addr[3:0];
                line_q<=selected==0 && mem0_line_read; write_q<=selected_write; missed_q<=0;
            end else bypass_active<=1;
        end
        if(bypass_active && lb_idle) bypass_active<=0;
        if(cache_active && ctrl_response) begin
            cache_active<=0;
            if(!missed_q) cache_hits<=cache_hits+1'b1;
        end
        if(read_valid && read_ready) begin
            missed_q<=1; cache_misses<=cache_misses+1'b1;
        end
        if(m_axi_rvalid && m_axi_rready) begin
            read_beat_count<=read_beat_count+1'b1;
            if(!bypass_active) cache_fill_beats<=cache_fill_beats+1'b1;
        end
        if((m_axi_bvalid && m_axi_bready && m_axi_bresp!=0) ||
           (m_axi_rvalid && m_axi_rready && m_axi_rresp!=0))
            response_error_count<=response_error_count+1'b1;
        if(!idle) stall_cycle_count<=stall_cycle_count+1'b1;
    end
end
assign wb_awid='0;
assign m_axi_awid=bypass_active ? lb_m_axi_awid : wb_awid;
assign m_axi_awaddr=bypass_active ? lb_m_axi_awaddr : wb_awaddr;
assign m_axi_awlen=bypass_active ? lb_m_axi_awlen : wb_awlen;
assign m_axi_awsize=bypass_active ? lb_m_axi_awsize : wb_awsize;
assign m_axi_awburst=bypass_active ? lb_m_axi_awburst : wb_awburst;
assign wb_awlock='0;
assign m_axi_awlock=bypass_active ? lb_m_axi_awlock : wb_awlock;
assign wb_awcache=4'b0011;
assign m_axi_awcache=bypass_active ? lb_m_axi_awcache : wb_awcache;
assign wb_awprot='0;
assign m_axi_awprot=bypass_active ? lb_m_axi_awprot : wb_awprot;
assign wb_awqos='0;
assign m_axi_awqos=bypass_active ? lb_m_axi_awqos : wb_awqos;
assign m_axi_awvalid=bypass_active ? lb_m_axi_awvalid : wb_awvalid;
assign m_axi_wdata=bypass_active ? lb_m_axi_wdata : wb_wdata;
assign m_axi_wstrb=bypass_active ? lb_m_axi_wstrb : wb_wstrb;
assign m_axi_wlast=bypass_active ? lb_m_axi_wlast : wb_wlast;
assign m_axi_wvalid=bypass_active ? lb_m_axi_wvalid : wb_wvalid;
assign m_axi_bready=bypass_active ? lb_m_axi_bready : wb_bready;
assign wb_arid='0;
assign m_axi_arid=bypass_active ? lb_m_axi_arid : wb_arid;
assign m_axi_araddr=bypass_active ? lb_m_axi_araddr : wb_araddr;
assign m_axi_arlen=bypass_active ? lb_m_axi_arlen : wb_arlen;
assign m_axi_arsize=bypass_active ? lb_m_axi_arsize : wb_arsize;
assign m_axi_arburst=bypass_active ? lb_m_axi_arburst : wb_arburst;
assign wb_arlock='0;
assign m_axi_arlock=bypass_active ? lb_m_axi_arlock : wb_arlock;
assign wb_arcache=4'b0011;
assign m_axi_arcache=bypass_active ? lb_m_axi_arcache : wb_arcache;
assign wb_arprot='0;
assign m_axi_arprot=bypass_active ? lb_m_axi_arprot : wb_arprot;
assign wb_arqos='0;
assign m_axi_arqos=bypass_active ? lb_m_axi_arqos : wb_arqos;
assign m_axi_arvalid=bypass_active ? lb_m_axi_arvalid : wb_arvalid;
assign m_axi_rready=bypass_active ? lb_m_axi_rready : wb_rready;

z486_ddr_axi_bridge #(.L2_ENABLE(0),.WRITE_OUTSTANDING(1)) bypass(
.aclk(aclk),
.aresetn(aresetn),
.memory_base(active_base),
.cache_invalidate(1'b0),
.cache_ready(lb_cache_ready),
.cache_hits(lb_cache_hits),
.cache_misses(lb_cache_misses),
.cache_fill_beats(lb_cache_fill_beats),
.mem0_valid((mem0_valid && bypass_request && selected==0)),
.mem0_write(mem0_write),
.mem0_addr(mem0_addr),
.mem0_din(mem0_din),
.mem0_be(mem0_be),
.mem0_line_read(mem0_line_read),
.mem0_ready(lb_mem0_ready),
.mem0_dout(lb_mem0_dout),
.mem0_resp_valid(lb_mem0_resp_valid),
.mem0_line_dout(lb_mem0_line_dout),
.mem0_line_resp_valid(lb_mem0_line_resp_valid),
.mem1_valid((mem1_valid && bypass_request && selected==1)),
.mem1_write(mem1_write),
.mem1_addr(mem1_addr),
.mem1_din(mem1_din),
.mem1_be(mem1_be),
.mem1_ready(lb_mem1_ready),
.mem1_dout(lb_mem1_dout),
.mem1_resp_valid(lb_mem1_resp_valid),
.aux_rd((aux_rd && bypass_request && selected==2)),
.aux_we((aux_we && bypass_request && selected==2)),
.aux_addr(aux_addr),
.aux_din(aux_din),
.aux_be(aux_be),
.aux_busy(lb_aux_busy),
.aux_dout(lb_aux_dout),
.aux_dout_ready(lb_aux_dout_ready),
.request_count(lb_request_count),
.read_beat_count(lb_read_beat_count),
.stall_cycle_count(lb_stall_cycle_count),
.response_error_count(lb_response_error_count),
.m_axi_awid(lb_m_axi_awid),
.m_axi_awaddr(lb_m_axi_awaddr),
.m_axi_awlen(lb_m_axi_awlen),
.m_axi_awsize(lb_m_axi_awsize),
.m_axi_awburst(lb_m_axi_awburst),
.m_axi_awlock(lb_m_axi_awlock),
.m_axi_awcache(lb_m_axi_awcache),
.m_axi_awprot(lb_m_axi_awprot),
.m_axi_awqos(lb_m_axi_awqos),
.m_axi_awvalid(lb_m_axi_awvalid),
.m_axi_awready((m_axi_awready && bypass_active)),
.m_axi_wdata(lb_m_axi_wdata),
.m_axi_wstrb(lb_m_axi_wstrb),
.m_axi_wlast(lb_m_axi_wlast),
.m_axi_wvalid(lb_m_axi_wvalid),
.m_axi_wready((m_axi_wready && bypass_active)),
.m_axi_bid(m_axi_bid),
.m_axi_bresp(m_axi_bresp),
.m_axi_bvalid((m_axi_bvalid && bypass_active)),
.m_axi_bready(lb_m_axi_bready),
.m_axi_arid(lb_m_axi_arid),
.m_axi_araddr(lb_m_axi_araddr),
.m_axi_arlen(lb_m_axi_arlen),
.m_axi_arsize(lb_m_axi_arsize),
.m_axi_arburst(lb_m_axi_arburst),
.m_axi_arlock(lb_m_axi_arlock),
.m_axi_arcache(lb_m_axi_arcache),
.m_axi_arprot(lb_m_axi_arprot),
.m_axi_arqos(lb_m_axi_arqos),
.m_axi_arvalid(lb_m_axi_arvalid),
.m_axi_arready((m_axi_arready && bypass_active)),
.m_axi_rid(m_axi_rid),
.m_axi_rdata(m_axi_rdata),
.m_axi_rresp(m_axi_rresp),
.m_axi_rlast(m_axi_rlast),
.m_axi_rvalid((m_axi_rvalid && bypass_active)),
.m_axi_rready(lb_m_axi_rready),
.idle(lb_idle)
);
z486_l2_line_axi transport(
.clk(aclk),.reset_n(aresetn),.memory_base(active_base),.idle(transport_idle),
.read_valid,.read_ready,.read_address,.read_done,.read_error,.read_line,
.writeback_valid,.writeback_ready,.writeback_address,.writeback_line,
.writeback_done,.writeback_error,
.awaddr(wb_awaddr),
.awlen(wb_awlen),
.awsize(wb_awsize),
.awburst(wb_awburst),
.awvalid(wb_awvalid),
.wdata(wb_wdata),
.wstrb(wb_wstrb),
.wlast(wb_wlast),
.wvalid(wb_wvalid),
.bready(wb_bready),
.araddr(wb_araddr),
.arlen(wb_arlen),
.arsize(wb_arsize),
.arburst(wb_arburst),
.arvalid(wb_arvalid),
.rready(wb_rready),
.arready(m_axi_arready && !bypass_active),
.awready(m_axi_awready && !bypass_active),
.rvalid(m_axi_rvalid && !bypass_active),
.bvalid(m_axi_bvalid && !bypass_active),
.wready(m_axi_wready && !bypass_active),
.rdata(m_axi_rdata),
.rresp(m_axi_rresp),
.bresp(m_axi_bresp),
.rlast(m_axi_rlast)
);
endmodule
