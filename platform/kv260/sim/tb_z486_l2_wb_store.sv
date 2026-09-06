`timescale 1ns/1ps
module tb_z486_l2_wb_store;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0, probe=0, patch=0, clean=0, invalidate=0, fill=0, commit=0;
    reg [31:0] address=0, fill_address=0;
    reg [127:0] patch_data=0, fill_data=0;
    reg [15:0] patch_mask=0;
    wire ready, hit, valid, dirty;
    wire [31:0] victim_address;
    wire [127:0] read_data;
    reg [127:0] expected [0:3];
    integer selected_word;
    z486_l2_wb_store dut(.*);
    task automatic lookup(input [31:0] addr);
        @(negedge clk); address=addr; probe=1;
        @(negedge clk); probe=0;
    endtask
    task automatic install(input [31:0] addr);
        for (int word=0;word<4;word++) begin
            @(negedge clk); fill=1; fill_address=addr+word*16;
            fill_data={4{32'h10000000+32'(word)}}; commit=word==3;
        end
        @(negedge clk); fill=0; commit=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); reset_n=1;
        wait(ready);
        lookup('h1040);
        if (valid || hit || dirty) $fatal(1,"hard reset left valid line");
        install('h1040);
        for (int word=0;word<4;word++) begin
            lookup('h1040+word*16);
            if (!hit || dirty || read_data !== {4{32'h10000000+32'(word)}})
                $fatal(1,"fill/probe failed word %0d",word);
        end
        lookup('h1050);
        patch=1; patch_mask=16'h8001; patch_data=128'hff0000000000000000000000000000aa;
        @(negedge clk); patch=0;
        lookup('h1050);
        if (!hit || !dirty || read_data !== 128'hff0000011000000110000001100000aa)
            $fatal(1,"dirty partial store failed: %032x",read_data);
        lookup('h81040); // same set, different physical tag
        if (hit || !valid || !dirty || victim_address != 'h1040)
            $fatal(1,"dirty victim identity lost");
        // An eviction walks all four words using the victim physical address.
        for (int word=0;word<4;word++) begin
            lookup('h1040+word*16);
            if (!hit || !dirty) $fatal(1,"eviction read lost dirty state");
        end
        clean=1; @(negedge clk); clean=0;
        lookup('h1040);
        if (!hit || dirty) $fatal(1,"writeback clean failed");
        invalidate=1; @(negedge clk); invalidate=0;
        lookup('h1040);
        if (valid || dirty) $fatal(1,"clean invalidation failed");
        install('h81040);
        lookup('h81040);
        if (!hit || dirty || victim_address != 'h81040)
            $fatal(1,"replacement publication failed");
        for (int word=0;word<4;word++) expected[word]={4{32'h10000000+32'(word)}};
        for (int trial=0;trial<300;trial++) begin
            selected_word=int'($urandom & 3);
            lookup('h81040+selected_word*16);
            patch_data={$urandom,$urandom,$urandom,$urandom};
            patch_mask=16'($urandom); patch=1;
            for (int b=0;b<16;b++)
                if (patch_mask[b]) expected[selected_word][b*8+:8]=patch_data[b*8+:8];
            @(negedge clk); patch=0;
            for (int word=0;word<4;word++) begin
                lookup('h81040+word*16);
                if (!hit || !dirty || read_data !== expected[word])
                    $fatal(1,"random dirty patch corrupted word %0d",word);
            end
        end
        $display("PASS: write-back storage clean/dirty/partial-store/victim/eviction/invalidation");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1,"timeout");
    end
endmodule
