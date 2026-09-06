`timescale 1ns/1ps
module tb_z486_ddr_wb_bridge;
reg  aclk='0;
reg  aresetn='0;
reg [39:0] memory_base='0;
reg  cache_invalidate='0;
wire  cache_ready;
wire [31:0] cache_hits;
wire [31:0] cache_misses;
wire [31:0] cache_fill_beats;
reg  mem0_valid='0;
reg  mem0_write='0;
reg [31:0] mem0_addr='0;
reg [31:0] mem0_din='0;
reg [3:0] mem0_be='0;
reg  mem0_line_read='0;
wire  mem0_ready;
wire [31:0] mem0_dout;
wire  mem0_resp_valid;
wire [127:0] mem0_line_dout;
wire  mem0_line_resp_valid;
reg  mem1_valid='0;
reg  mem1_write='0;
reg [31:0] mem1_addr='0;
reg [31:0] mem1_din='0;
reg [3:0] mem1_be='0;
wire  mem1_ready;
wire [31:0] mem1_dout;
wire  mem1_resp_valid;
reg  aux_rd='0;
reg  aux_we='0;
reg [28:0] aux_addr='0;
reg [63:0] aux_din='0;
reg [7:0] aux_be='0;
wire  aux_busy;
wire [63:0] aux_dout;
wire  aux_dout_ready;
wire [31:0] request_count;
wire [31:0] read_beat_count;
wire [31:0] stall_cycle_count;
wire [31:0] response_error_count;
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
reg [0:0] m_axi_bid='0;
reg [1:0] m_axi_bresp='0;
reg  m_axi_bvalid='0;
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
reg [0:0] m_axi_rid='0;
reg [127:0] m_axi_rdata='0;
reg [1:0] m_axi_rresp='0;
reg  m_axi_rlast='0;
reg  m_axi_rvalid='0;
wire  m_axi_rready;
wire  idle;

always #5 aclk=~aclk;
z486_ddr_wb_bridge #(.L2_SIZE_KIB(1)) dut(.*);
reg [127:0] memory[0:255];
reg [31:0] shadow[0:1023];
integer random_word;
reg [31:0] random_data;
integer rd_count=0,wr_count=0,rd_index=0,wr_index=0,b_delay=0;
reg [39:0] rd_addr,wr_addr;
reg [39:0] last_write_address;
assign m_axi_arready=rd_count==0 && !m_axi_rvalid;
assign m_axi_awready=wr_count==0 && !m_axi_bvalid && b_delay==0;
assign m_axi_wready=wr_count!=0;
always @(posedge aclk) begin
    if(m_axi_arvalid && m_axi_arready) begin
        rd_count<=int'(m_axi_arlen)+1; rd_addr<=m_axi_araddr; rd_index<=0;
    end
    if(m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid<=0; rd_count<=rd_count-1; rd_index<=rd_index+1;
    end else if(rd_count!=0 && !m_axi_rvalid) begin
        m_axi_rvalid<=1; m_axi_rdata<=memory[((rd_addr>>4)+rd_index)%256];
        m_axi_rlast<=rd_count==1;
    end
    if(m_axi_awvalid && m_axi_awready) begin
        wr_count<=int'(m_axi_awlen)+1; wr_addr<=m_axi_awaddr; wr_index<=0;
        last_write_address<=m_axi_awaddr;
    end
    if(m_axi_wvalid && m_axi_wready) begin
        for(integer b=0;b<16;b++) if(m_axi_wstrb[b])
            memory[((wr_addr>>4)+wr_index)%256][b*8+:8]<=m_axi_wdata[b*8+:8];
        if(m_axi_wlast!=(wr_count==1)) $fatal(1,"bad write burst");
        wr_count<=wr_count-1; wr_index<=wr_index+1;
        if(wr_count==1) b_delay<=12;
    end
    if(b_delay!=0) begin
        b_delay<=b_delay-1;
        if(b_delay==1) m_axi_bvalid<=1;
    end
    if(m_axi_bvalid && m_axi_bready) m_axi_bvalid<=0;
end
task automatic tick; @(negedge aclk); endtask
task automatic store_word(input integer a,input logic[31:0] d);
    tick(); mem0_valid=1; mem0_write=1; mem0_addr=a; mem0_din=d; mem0_be=15;
    while(!mem0_ready) tick();
    tick(); mem0_valid=0;
endtask
task automatic read_word(input integer a,input logic[31:0] expected);
    tick(); mem1_valid=1; mem1_write=0; mem1_addr=a; mem1_be=15;
    while(!mem1_ready) tick();
    tick(); mem1_valid=0;
    while(!mem1_resp_valid) tick();
    if(mem1_dout!==expected) $fatal(1,"DMA read %h got %h expected %h",a,mem1_dout,expected);
endtask
initial begin
    for(integer i=0;i<256;i++) memory[i]=128'(i);
    repeat(3) tick(); aresetn=1;
    wait(idle);
    store_word(0,32'hdeadbeef);
    read_word(0,32'hdeadbeef);
    if(memory[0]!=0) $fatal(1,"store reached DDR before eviction");
    // A pulsed auxiliary read must see the same dirty line.
    tick(); while(aux_busy) tick();
    aux_addr=29'h06000000; aux_rd=1;
    tick(); aux_rd=0;
    while(!aux_dout_ready) tick();
    if(aux_dout!=64'hdeadbeef) $fatal(1,"aux coherence");
    read_word(1024,64);
    if(memory[0]!=128'hdeadbeef) $fatal(1,"dirty eviction lost store");
    store_word(1024,32'h12345678);
    tick(); cache_invalidate=1;
    tick();
    while(!idle) tick();
    if(memory[64]!=128'h12345678) $fatal(1,"stop flush lost dirty data");
    repeat(5) begin tick(); if(!idle) $fatal(1,"held reset restarted flush"); end
    cache_invalidate=0;
    read_word(1024,32'h12345678);
    store_word(1024,32'h98765432);
    tick(); memory_base=40'h100000;
    tick();
    while(!idle) tick();
    if(last_write_address!=1024 || memory[64]!=128'h98765432)
        $fatal(1,"base remap did not flush to OLD base");
    // VGA/ROM hole uses uncached path; no cache allocation or dirty ownership.
    store_word('hc0000,32'h11223344);
    wait(idle);
    read_word('hc0000,32'h11223344);
    // Conflict-heavy CPU writes must remain visible to the independent DMA
    // reader, then survive a complete stop/flush into physical DDR.
    for(integer w=0;w<1024;w++) shadow[w]=memory[w/4][(w%4)*32+:32];
    for(integer n=0;n<500;n++) begin
        random_word=int'($urandom_range(0,1023)); random_data=$urandom;
        store_word(random_word*4,random_data);
        shadow[random_word]=random_data;
        read_word(random_word*4,random_data);
    end
    tick(); cache_invalidate=1;
    tick();
    while(!idle) tick();
    for(integer w=0;w<1024;w++)
        if(memory[w/4][(w%4)*32+:32]!==shadow[w])
            $fatal(1,"randomized flush mismatch %0d got %h expected %h",w,memory[w/4][(w%4)*32+:32],shadow[w]);
    $display("PASS 500 randomized CPU/DMA updates and complete DDR flush comparison");
    $display("PASS assembled WB bridge: CPU/DMA/aux coherence, eviction, stop flush, old-base flush, uncached ROM");
    $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
