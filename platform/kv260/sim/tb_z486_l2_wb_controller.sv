`timescale 1ns/1ps
module tb_z486_l2_wb_controller;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0, request_valid=0, request_write=0;
    reg [31:0] request_address=0;
    reg [127:0] request_data=0;
    reg [15:0] request_mask=0;
    wire request_ready,response_valid;
    wire [127:0] response_data;
    reg flush=0,retry=0;
    wire flush_done,idle,error,read_valid,writeback_valid;
    wire [31:0] read_address,writeback_address;
    wire [511:0] writeback_line;
    reg read_done=0,read_error=0,writeback_done=0,writeback_error=0;
    reg [511:0] read_line=0;
    wire read_ready = rd_timer==0;
    wire writeback_ready = wb_timer==0;
    integer rd_timer=0,wb_timer=0,reads=0,writes=0,overlaps=0;
    reg fail_write=0,fail_read=0;
    reg [31:0] rd_addr,wb_addr;
    reg [511:0] wb_data;
    reg [127:0] memory[0:255];
    z486_l2_wb_controller #(.SIZE_KIB(1)) dut(.*);
    always @(posedge clk) begin
        read_done<=0; writeback_done<=0;
        if (read_valid && read_ready) begin
            rd_addr<=read_address; rd_timer<=3; reads<=reads+1;
            if (wb_timer!=0) overlaps<=overlaps+1;
        end else if (rd_timer!=0) begin
            rd_timer<=rd_timer-1;
            if (rd_timer==1) begin
                for(integer w=0;w<4;w++) read_line[w*128+:128]<=memory[(rd_addr>>4)+w];
                read_done<=1; read_error<=fail_read;
            end
        end
        if(writeback_valid && writeback_ready) begin
            wb_addr<=writeback_address; wb_data<=writeback_line;
            wb_timer<=16; writes<=writes+1;
        end else if(wb_timer!=0) begin
            wb_timer<=wb_timer-1;
            if(wb_timer==1) begin
                if(!fail_write)
                    for(integer w=0;w<4;w++) memory[(wb_addr>>4)+w]<=wb_data[w*128+:128];
                writeback_done<=1; writeback_error<=fail_write;
            end
        end
    end
    task automatic start_request(input bit wr,input integer addr,input logic [127:0] data,input logic [15:0] mask);
        @(negedge clk);
        while(!request_ready) @(negedge clk);
        request_valid=1; request_write=wr; request_address=addr;
        request_data=data; request_mask=mask;
        @(negedge clk); request_valid=0;
    endtask
    task automatic access(input bit wr,input integer addr,input logic [127:0] data,input logic [15:0] mask,input logic [127:0] expected);
        start_request(wr,addr,data,mask);
        while(!response_valid) begin
            @(negedge clk);
            if(error) $fatal(1,"unexpected cache error");
        end
        if(!wr && response_data!==expected) $fatal(1,"read %h got %h expected %h",addr,response_data,expected);
    endtask
    task automatic do_flush;
        @(negedge clk); flush=1;
        @(negedge clk); flush=0;
        while(!flush_done) @(negedge clk);
        if(!idle) $fatal(1,"flush completion not idle");
    endtask
    initial begin
        for(integer i=0;i<256;i++) memory[i]=128'(i);
        repeat(3) @(negedge clk); reset_n=1;
        access(0,0,0,0,0);
        access(1,0,128'h1234,16'hffff,0);
        if(memory[0]!=0) $fatal(1,"store was not write-back");
        access(0,0,0,0,128'h1234);
        access(1,16,128'hff00,16'h0002,0);
        access(0,1024,0,0,64);
        if(memory[0]!=128'h1234 || memory[1]!=128'hff01 || overlaps!=1)
            $fatal(1,"dirty eviction/overlap failed");
        access(1,1024,128'h5678,16'hffff,0);
        fail_write=1;
        start_request(0,0,0,0);
        while(!error) @(negedge clk);
        if(idle || !dut.storage.dirty || response_valid) $fatal(1,"failed eviction lost dirty ownership");
        fail_write=0; retry=1;
        @(negedge clk); retry=0;
        while(!response_valid) @(negedge clk);
        if(response_data!=128'h1234 || memory[64]!=128'h5678) $fatal(1,"writeback retry failed");
        access(1,32,128'hbeef,16'hffff,0);
        fail_read=1;
        start_request(0,1024,0,0);
        while(!error) @(negedge clk);
        if(!dut.storage.dirty) $fatal(1,"read error discarded victim");
        fail_read=0; retry=1;
        @(negedge clk); retry=0;
        while(!response_valid) @(negedge clk);
        if(response_data!=128'h5678 || memory[2]!=128'hbeef) $fatal(1,"fill retry failed");
        access(1,1040,128'hface,16'hffff,0);
        do_flush();
        if(memory[65]!=128'hface) $fatal(1,"flush lost dirty data");
        access(0,1040,0,0,128'hface);
        $display("PASS WB controller: writes=%0d reads=%0d overlapping fills=%0d",writes,reads,overlaps);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
