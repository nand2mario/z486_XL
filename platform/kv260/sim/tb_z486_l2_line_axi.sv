`timescale 1ns/1ps
module tb_z486_l2_line_axi;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0;
    reg [39:0] memory_base=40'h40000000;
    reg read_valid=0,writeback_valid=0;
    wire read_ready,writeback_ready,read_done,read_error,writeback_done,writeback_error,idle;
    reg [31:0] read_address=128,writeback_address=64;
    wire [511:0] read_line;
    reg [511:0] writeback_line;
    wire [39:0] araddr,awaddr;
    wire [7:0] arlen,awlen;
    wire [2:0] arsize,awsize;
    wire [1:0] arburst,awburst;
    wire arvalid,awvalid,rready,bready,wvalid,wlast;
    reg arready=0,awready=0,rvalid=0,rlast=0,bvalid=0,wready=0;
    reg [127:0] rdata=0;
    reg [1:0] rresp=0,bresp=0;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    z486_l2_line_axi dut(.*);
    task automatic tick; @(negedge clk); endtask
    initial begin
        for(integer w=0;w<4;w++) writeback_line[w*128+:128]=128'(100+w);
        repeat(3) tick(); reset_n=1;
        tick(); read_valid=1; writeback_valid=1;
        tick(); read_valid=0; writeback_valid=0; memory_base=40'h50000000;
        repeat(4) begin
            if(!arvalid || !awvalid || !wvalid || araddr!=40'h40000080 || awaddr!=40'h40000040)
                $fatal(1,"stalled address changed or request missing");
            tick();
        end
        if(arlen!=3 || awlen!=3 || arsize!=4 || awsize!=4) $fatal(1,"burst format");
        arready=1; tick(); arready=0;
        // W-before-AW with independent read data interleaved and stalled W.
        for(integer w=0;w<4;w++) begin
            repeat(w+1) begin
                if(!wvalid || wdata!=128'(100+w) || wlast!=(w==3)) $fatal(1,"W unstable");
                tick();
            end
            wready=1; rvalid=1; rdata=128'(200+w); rlast=w==3;
            tick(); wready=0; rvalid=0;
        end
        if(!read_done || read_error || idle || bready) $fatal(1,"read/write independence");
        for(integer w=0;w<4;w++)
            if(read_line[w*128+:128]!=128'(200+w)) $fatal(1,"read assembly");
        awready=1; tick(); awready=0;
        repeat(6) begin
            if(idle || writeback_ready || !bready) $fatal(1,"write completed before B");
            tick();
        end
        bvalid=1; bresp=2; tick(); bvalid=0;
        if(!writeback_done || !writeback_error || !idle) $fatal(1,"B error not propagated");
        // Early RLAST is rejected, never presented as a successful full line.
        read_valid=1; tick(); read_valid=0;
        arready=1; tick(); arready=0;
        rvalid=1; rlast=1; rresp=0; tick(); rvalid=0;
        if(!read_done || !read_error) $fatal(1,"short burst accepted");
        $display("PASS line AXI: backpressure, W-before-AW, concurrent read/write, B and R errors");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
