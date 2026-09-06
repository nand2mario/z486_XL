module z486_wb_sim_memory(
input wire  aclk,
input wire  aresetn,
input wire [39:0] memory_base,
input wire  cache_invalidate,
output wire  cache_ready,
output wire [31:0] cache_hits,
output wire [31:0] cache_misses,
output wire [31:0] cache_fill_beats,
input wire  mem0_valid,
input wire  mem0_write,
input wire [31:0] mem0_addr,
input wire [31:0] mem0_din,
input wire [3:0] mem0_be,
input wire  mem0_line_read,
output wire  mem0_ready,
output wire [31:0] mem0_dout,
output wire  mem0_resp_valid,
output wire [127:0] mem0_line_dout,
output wire  mem0_line_resp_valid,
input wire  mem1_valid,
input wire  mem1_write,
input wire [31:0] mem1_addr,
input wire [31:0] mem1_din,
input wire [3:0] mem1_be,
output wire  mem1_ready,
output wire [31:0] mem1_dout,
output wire  mem1_resp_valid,
input wire  aux_rd,
input wire  aux_we,
input wire [28:0] aux_addr,
input wire [63:0] aux_din,
input wire [7:0] aux_be,
output wire  aux_busy,
output wire [63:0] aux_dout,
output wire  aux_dout_ready,
output wire [31:0] request_count,
output wire [31:0] read_beat_count,
output wire [31:0] stall_cycle_count,
output wire [31:0] response_error_count,
output wire  idle
);
wire [0:0] m_axi_awid;
wire [39:0] m_axi_awaddr;
wire [7:0] m_axi_awlen;
wire [2:0] m_axi_awsize;
wire [1:0] m_axi_awburst;
wire  m_axi_awlock;
wire [3:0] m_axi_awcache;
wire [2:0] m_axi_awprot;
wire [3:0] m_axi_awqos;
wire  m_axi_awvalid;
wire m_axi_awready;
wire [127:0] m_axi_wdata;
wire [15:0] m_axi_wstrb;
wire  m_axi_wlast;
wire  m_axi_wvalid;
wire m_axi_wready;
reg [0:0] m_axi_bid=0;
reg [1:0] m_axi_bresp=0;
reg  m_axi_bvalid=0;
wire  m_axi_bready;
wire [0:0] m_axi_arid;
wire [39:0] m_axi_araddr;
wire [7:0] m_axi_arlen;
wire [2:0] m_axi_arsize;
wire [1:0] m_axi_arburst;
wire  m_axi_arlock;
wire [3:0] m_axi_arcache;
wire [2:0] m_axi_arprot;
wire [3:0] m_axi_arqos;
wire  m_axi_arvalid;
wire m_axi_arready;
reg [0:0] m_axi_rid=0;
reg [127:0] m_axi_rdata=0;
reg [1:0] m_axi_rresp=0;
reg  m_axi_rlast=0;
reg  m_axi_rvalid=0;
wire  m_axi_rready;
z486_ddr_wb_bridge bridge(.*);
import "DPI-C" function int unsigned kv260_memory_read(input int unsigned address);
import "DPI-C" function void kv260_memory_write(input int unsigned address,input int unsigned data,input int unsigned mask);
integer cycle=0,rd_count=0,wr_count=0,rd_index=0,wr_index=0,b_delay=0,rd_delay=0;
reg [31:0] rd_addr,wr_addr;
assign m_axi_arready=rd_count==0 && !m_axi_rvalid && cycle%4!=1;
assign m_axi_awready=wr_count==0 && !m_axi_bvalid && b_delay==0 && cycle%4!=2;
assign m_axi_wready=wr_count!=0 && cycle%4!=3;
always @(posedge aclk) begin
    cycle<=cycle+1;
    if(!aresetn) begin
        rd_count<=0; wr_count<=0; rd_index<=0; wr_index<=0;
        b_delay<=0; rd_delay<=0; m_axi_rvalid<=0; m_axi_bvalid<=0;
    end else begin
        if(m_axi_arvalid && m_axi_arready) begin
            rd_count<=int'(m_axi_arlen)+1; rd_addr<={m_axi_araddr[31:4],4'b0};
            rd_index<=0; rd_delay<=20;
        end
        if(rd_delay!=0) rd_delay<=rd_delay-1;
        if(m_axi_rvalid && m_axi_rready) begin
            m_axi_rvalid<=0; rd_count<=rd_count-1; rd_index<=rd_index+1;
        end else if(rd_count!=0 && rd_delay==0 && !m_axi_rvalid) begin
            m_axi_rvalid<=1; m_axi_rlast<=rd_count==1;
            for(integer w=0;w<4;w++)
                m_axi_rdata[w*32+:32]<=kv260_memory_read(rd_addr+rd_index*16+w*4);
        end
        if(m_axi_awvalid && m_axi_awready) begin
            wr_count<=int'(m_axi_awlen)+1; wr_addr<={m_axi_awaddr[31:4],4'b0}; wr_index<=0;
        end
        if(m_axi_wvalid && m_axi_wready) begin
            for(integer w=0;w<4;w++)
                kv260_memory_write(wr_addr+wr_index*16+w*4,m_axi_wdata[w*32+:32],{28'b0,m_axi_wstrb[w*4+:4]});
            assert(m_axi_wlast==(wr_count==1)) else $fatal(1,"DDR model burst mismatch");
            wr_count<=wr_count-1; wr_index<=wr_index+1;
            if(wr_count==1) b_delay<=20;
        end
        if(b_delay!=0) begin
            b_delay<=b_delay-1;
            if(b_delay==1) m_axi_bvalid<=1;
        end
        if(m_axi_bvalid && m_axi_bready) m_axi_bvalid<=0;
    end
end
endmodule
