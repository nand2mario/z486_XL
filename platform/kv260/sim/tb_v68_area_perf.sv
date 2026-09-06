`timescale 1ns/1ps
module tb_v68_area_perf;
    logic clk = 0;
    always #5 clk = !clk;
    logic reset_n = 0, we = 0, re = 0;
    logic [7:0] wa = 0, ra = 0;
    logic [23:0] wd = 0;
    wire [23:0] rd;
    sst1_palette_ram palette (.clk, .reset_n, .write_enable(we),
        .read_enable(re), .write_address(wa), .read_address(ra),
        .write_data(wd), .read_data(rd));
    logic [31:0] control = 0;
    logic [15:0] index = 128, events = 1;
    wire snap;
    wire [31:0] result, seq;
    wire [63:0] renderer32;
    sst1_perf_counters #(.COUNTER_BITS(32), .SNAPSHOT_WHILE_BUSY(1)) bank (
        .clk, .reset_n, .renderer_busy(1'b1), .snapshot(snap), .clear(1'b0),
        .read_index(7'd2), .read_data(renderer32), .pending(),
        .fbi('0), .tmu('0), .mem_req_fire(1'b0), .mem_req('0),
        .mem_rsp_fire(1'b0), .mem_rsp('0), .tmu_arb_wait(1'b0),
        .fbi_arb_wait(1'b0), .response_backpressure(1'b0)
    );
    zsst_board_perf perf (.clk, .reset_n, .control, .read_index(index),
        .events, .renderer_data(64'h12345678), .snapshot(snap),
        .read_data(result), .sequence_number(seq));
    task tick;
        @(posedge clk); #1; @(negedge clk);
    endtask
    logic [23:0] expected [0:255];
    logic [23:0] old_value;
    logic [31:0] saved;
    initial begin
        tick(); reset_n = 1;
        for (int i=0; i<256; i++) expected[i]=0;
        // Randomized old-data read/write collisions and enable holds.
        old_value = 0;
        for (int i=0; i<3000; i++) begin
            wa = 8'($urandom); ra = i[0] ? wa : 8'($urandom);
            we = 1'($urandom); re = 1'($urandom); wd = 24'($urandom);
            if (re) old_value = expected[ra];
            if (we) expected[wa] = wd;
            tick();
            if (rd !== old_value) $fatal(1,"palette mismatch %d", i);
        end
        // Reset invalidates RAM without needing to erase the stored data.
        reset_n=0; tick(); reset_n=1; we=0; re=1;
        for (int i=0; i<256; i++) begin
            ra=8'(i); tick();
            if (rd !== 0) $fatal(1,"palette reset mismatch");
        end
        control=1; tick();
        if (seq != 1) $fatal(1,"snapshot not captured");
        saved=result;
        repeat (5) tick();
        if (renderer32 != {32'd0,saved}) $fatal(1,"busy renderer snapshot misaligned");
        if (seq != 1 || result != saved) $fatal(1,"snapshot not stable");
        control=0; tick(); control=1; tick();
        if (seq != 2 || result <= saved) $fatal(1,"snapshot did not advance");
        index=0; #1;
        if (result != 32'h12345678) $fatal(1,"renderer read mux");
        index=144; #1;
        if (result != 0) $fatal(1,"out of range read");
        $display("PASS: palette collisions/reset and board counter snapshots");
        $finish;
    end
endmodule
