`timescale 1ns/1ps
module tb_zsst_debug_capture;
    import sst1_pkg::*;
    logic clk=0, reset_n=0;
    always #5 clk=~clk;
    logic [31:0] control=0, read_data, status;
    logic [15:0] read_index=0;
    logic host_valid=0, memory_valid=0;
    logic [23:0] host_address=24'h123456;
    logic [31:0] host_data=32'h89abcdef;
    logic [3:0] host_be=4'hb;
    sst1_mem_req_t memory_req;
    zsst_debug_capture dut(.*);
    task tick;
        @(posedge clk); @(negedge clk);
    endtask
    task check_word(input integer index, input logic [31:0] value);
        read_index=16'(index); tick();
        if(read_data!==value) $fatal(1,"word %d: %h != %h",index,read_data,value);
    endtask
    initial begin
        memory_req='0;
        tick(); reset_n=1; control=1; host_valid=1; tick(); host_valid=0;
        if(status!=1) $fatal(1,"host count");
        check_word(0,32'hef123456); check_word(1,32'h0b89abcd);
        control=0; tick(); control=3;
        memory_req.addr=40'h1234567890;
        memory_req.wdata=128'hffeeddccbbaa99887766554433221100;
        memory_req.wstrb=16'hc003; memory_req.beats=1;
        memory_req.tag=8'h5a; memory_req.source=SST1_MEM_FB_COLOR;
        memory_req.write=1; memory_valid=1; tick(); memory_valid=0;
        check_word(0,32'h34567890); check_word(1,32'h22110012);
        check_word(2,32'h66554433); check_word(3,32'haa998877);
        check_word(4,32'heeddccbb); check_word(5,32'h01c003ff);
        host_valid=1; tick(); if(status!=1) $fatal(1,"mode filtering");
        host_valid=0; memory_valid=1;
        repeat(8200) tick();
        if(status!=8192) $fatal(1,"capture must stop at capacity");
        memory_valid=0; control=0; tick();
        if(status!=0) $fatal(1,"disable must rearm");
        $display("PASS: passive GPU capture packing, selection, capacity and rearm");
        $finish;
    end
endmodule
