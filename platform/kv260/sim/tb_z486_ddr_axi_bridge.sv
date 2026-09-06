`timescale 1ns/1ps

module tb_z486_ddr_axi_bridge #(
    parameter TEST_L2 = 0,
    parameter integer WRITE_RESPONSE_DELAY = 0,
    parameter integer TEST_WRITE_OUTSTANDING = 8
);
    logic clk = 0;
    logic resetn = 0;
    always #5 clk = ~clk;

    logic mem0_valid, mem0_write;
    logic [31:0] mem0_addr, mem0_din, mem0_dout;
    logic [3:0] mem0_be;
    logic mem0_line_read;
    logic mem0_ready, mem0_resp_valid;
    logic [127:0] mem0_line_dout;
    logic mem0_line_resp_valid;
    logic cache_invalidate = 0;
    wire cache_ready;
    wire [31:0] cache_hits, cache_misses, cache_fill_beats;
    logic inject_read_error = 0;
    logic inject_write_error = 0;
    integer ar_count = 0;
    logic mem1_valid, mem1_write;
    logic [31:0] mem1_addr, mem1_din, mem1_dout;
    logic [3:0] mem1_be;
    logic mem1_ready, mem1_resp_valid;
    logic aux_rd, aux_we, aux_busy, aux_dout_ready;
    logic [28:0] aux_addr;
    logic [63:0] aux_din, aux_dout;
    logic [7:0] aux_be;

    wire [39:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire awvalid, wvalid, bready, arvalid, rready;
    logic awready, wready, bvalid, arready, rvalid, rlast;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    logic [127:0] rdata;
    logic [1:0] bresp, rresp;

    z486_ddr_axi_bridge #(.L2_ENABLE(TEST_L2), .WRITE_OUTSTANDING(TEST_WRITE_OUTSTANDING)) dut (
        .aclk(clk), .aresetn(resetn), .memory_base(40'h0000_001000),
        .cache_invalidate, .cache_ready,
        .cache_hits, .cache_misses, .cache_fill_beats,
        .mem0_valid, .mem0_write, .mem0_addr, .mem0_din, .mem0_be,
        .mem0_ready, .mem0_dout, .mem0_resp_valid,
        .mem0_line_read,
        .mem0_line_dout, .mem0_line_resp_valid,
        .mem1_valid, .mem1_write, .mem1_addr, .mem1_din, .mem1_be,
        .mem1_ready, .mem1_dout, .mem1_resp_valid,
        .aux_rd, .aux_we, .aux_addr, .aux_din, .aux_be,
        .aux_busy, .aux_dout, .aux_dout_ready,
        .request_count(), .read_beat_count(), .stall_cycle_count(),
        .response_error_count(),
        .m_axi_awid(), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(), .m_axi_awlock(),
        .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(1'b0), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
        .m_axi_bready(bready), .m_axi_arid(), .m_axi_araddr(araddr),
        .m_axi_arlen(arlen), .m_axi_arsize(arsize), .m_axi_arburst(),
        .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arqos(),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_rid(1'b0),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    byte memory [0:2097151];
    logic aw_seen, w_seen;
    logic [39:0] saved_awaddr;
    logic [127:0] saved_wdata;
    logic [15:0] saved_wstrb;
    logic read_active;
    logic [39:0] read_addr;
    logic [2:0] read_size;
    logic [7:0] read_left;
    integer cycle;
    integer b_due [0:31];
    logic b_error [0:31];
    integer b_head = 0, b_tail = 0, b_count = 0;
    integer pending_high_water = 0;
    integer lane;
    logic saw_native_line_read;

    // A deliberately uneven AXI RAM model exercises independent AW/W
    // acceptance and gaps between read beats.
    always_comb begin
        awready = !aw_seen && b_count < 31 && cycle[1:0] != 2'd1;
        wready = !w_seen && b_count < 31 && cycle[2:0] != 3'd2;
        arready = !read_active && cycle[1:0] != 2'd2;
        bvalid = b_count != 0 && cycle >= b_due[b_head];
        bresp = (b_count != 0 && b_error[b_head]) ? 2'b10 : 2'b00;
    end

    always_ff @(posedge clk) begin
        cycle <= cycle + 1;
        rvalid <= 0;
        if (dut.pending_writes > pending_high_water)
            pending_high_water <= int'(dut.pending_writes);
        if (resetn) begin
            if (dut.pending_writes != 0 && !aux_busy)
                $fatal(1,"auxiliary pulse producer can launch during write fence");
            if (arvalid && dut.pending_writes != 0)
                $fatal(1,"read overtook a pending write");
            if (dut.pending_writes > TEST_WRITE_OUTSTANDING)
                $fatal(1,"outstanding write limit exceeded");
            if (dut.idle && (b_count != 0 || aw_seen || w_seen))
                $fatal(1,"bridge reported idle before AXI drain");
        end
        if (bvalid && bready) b_head <= (b_head+1)%32;
        case ({(aw_seen && w_seen), (bvalid && bready)})
            2'b10: b_count <= b_count+1;
            2'b01: b_count <= b_count-1;
            default: ;
        endcase

        if (awvalid && awready) begin
            aw_seen <= 1;
            saved_awaddr <= awaddr;
        end
        if (wvalid && wready) begin
            w_seen <= 1;
            saved_wdata <= wdata;
            saved_wstrb <= wstrb;
        end
        if (aw_seen && w_seen) begin
            for (lane = 0; lane < 16; lane = lane + 1)
                if (saved_wstrb[lane])
                    memory[saved_awaddr - 40'h1000 + lane - saved_awaddr[3:0]] <=
                        saved_wdata[lane*8 +: 8];
            aw_seen <= 0;
            w_seen <= 0;
            b_due[b_tail] <= cycle + WRITE_RESPONSE_DELAY + 1;
            b_error[b_tail] <= inject_write_error;
            b_tail <= (b_tail+1)%32;
        end

        if (arvalid && arready) begin
            if (arlen != 0 && (!TEST_L2 || arlen != 3))
                $fatal(1, "KV260 DDR bridge issued an AXI burst");
            ar_count <= ar_count + 1;
            read_active <= 1;
            read_addr <= araddr;
            read_size <= arsize;
            read_left <= arlen + 1'b1;
            if (araddr == 40'h1040 && arsize == 3'd4 && arlen == (TEST_L2 ? 3 : 0))
                saw_native_line_read <= 1'b1;
        end
        if (read_active && !rvalid && cycle[1:0] != 2'd3) begin
            rresp <= inject_read_error ? 2'b10 : 0;
            rdata <= 0;
            for (lane = 0; lane < (1 << read_size); lane = lane + 1)
                rdata[((read_addr[3:0] + lane) * 8) +: 8] <=
                    memory[read_addr - 40'h1000 + lane];
            rlast <= read_left == 1;
            rvalid <= 1;
        end
        if (rvalid && rready) begin
            if (read_left == 1)
                read_active <= 0;
            else begin
                read_left <= read_left - 1'b1;
                read_addr <= read_addr + (1 << read_size);
            end
        end

        if (!resetn) begin
            cycle <= 0;
            b_head <= 0; b_tail <= 0; b_count <= 0;
            pending_high_water <= 0;
            aw_seen <= 0;
            w_seen <= 0;
            read_active <= 0;
            rvalid <= 0;
            rlast <= 0;
            rresp <= 0;
            saw_native_line_read <= 0;
        end
    end

    task automatic mem0_write_word(input [31:0] address,
                                   input [31:0] data,
                                   input [3:0] be);
        begin
            @(negedge clk);
            mem0_addr = address;
            mem0_din = data;
            mem0_be = be;
            mem0_write = 1;
            mem0_valid = 1;
            do @(posedge clk); while (!mem0_ready);
            @(negedge clk);
            mem0_valid = 0;
            mem0_write = 0;
        end
    endtask

    task automatic mem0_read_line(input [31:0] address);
        integer beat;
        reg [31:0] expected;
        begin
            @(negedge clk);
            mem0_addr = address;
            // The explicit line marker selects one native 128-bit DDR beat.
            mem0_line_read = 1;
            mem0_write = 0;
            mem0_valid = 1;
            do @(posedge clk); while (!mem0_ready);
            @(negedge clk);
            mem0_valid = 0;
            mem0_line_read = 0;
            do @(negedge clk); while (!mem0_line_resp_valid);
            if (mem0_resp_valid)
                $fatal(1, "native line read also asserted legacy DWORD response");
            for (beat = 0; beat < 4; beat = beat + 1) begin
                for (int b=0; b<4; b++) expected[b*8+:8] = memory[address+beat*4+b];
                if (mem0_line_dout[beat*32 +: 32] !== expected)
                    $fatal(1, "mem0 beat %0d: got %08x expected %08x",
                           beat, mem0_line_dout[beat*32 +: 32], expected);
            end
        end
    endtask

    initial begin
        integer word_index;
        integer saved_ar;
        integer write_start;
        reg [31:0] random_address;
        for (int b=0; b<2097152; b++) memory[b] = 8'(b ^ (b>>13));
        mem0_valid = 0;
        mem0_write = 0;
        mem0_addr = 0;
        mem0_din = 0;
        mem0_be = 0;
        mem0_line_read = 0;
        mem1_valid = 0;
        mem1_write = 0;
        mem1_addr = 0;
        mem1_din = 0;
        mem1_be = 0;
        aux_rd = 0;
        aux_we = 0;
        aux_addr = 0;
        aux_din = 0;
        aux_be = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1;
        if (TEST_L2) wait(cache_ready);

        for (word_index = 0; word_index < 4; word_index = word_index + 1)
            mem0_write_word(32'h40 + word_index*4,
                            32'h1111_0000 + word_index, 4'hf);
        repeat (8) @(posedge clk);
        mem0_read_line(32'h40);
        if (!saw_native_line_read)
            $fatal(1, "cache fill was not coalesced into one 128-bit read");

        // DMA byte write shares the guest address space.
        @(negedge clk);
        mem1_addr = 32'h45;
        mem1_din = 32'h0000_aa00;
        mem1_be = 4'b0010;
        mem1_write = 1;
        mem1_valid = 1;
        do @(posedge clk); while (!mem1_ready);
        @(negedge clk);
        mem1_valid = 0;
        mem1_write = 0;
        wait(dut.idle);
        if (memory['h45] !== 8'haa)
            $fatal(1, "DMA byte-enable translation failed");

        // 0x3000_0100 in the MiSTer compatibility window aliases guest offset
        // 0x100, rather than consuming a separate physical memory.
        @(negedge clk);
        aux_addr = 29'h0600_0020;
        aux_din = 64'h8877_6655_4433_2211;
        aux_be = 8'hff;
        aux_we = 1;
        do @(posedge clk); while (aux_busy);
        @(negedge clk);
        aux_we = 0;
        repeat (8) @(posedge clk);
        aux_rd = 1;
        do @(posedge clk); while (aux_busy);
        @(negedge clk);
        aux_rd = 0;
        do @(negedge clk); while (!aux_dout_ready);
        if (aux_dout !== 64'h8877_6655_4433_2211)
            $fatal(1, "auxiliary DDR alias failed: %016x", aux_dout);

        if (TEST_L2) begin
            // The DMA write above must patch the cached 64-byte line.
            saved_ar=ar_count;
            mem0_read_line('h40);
            mem0_read_line('h50);
            mem0_read_line('h60);
            mem0_read_line('h70);
            if (ar_count != saved_ar) $fatal(1,"spatial/DMA cache hits missed");
            mem0_write_word('h48,32'hfedcba98,4'b0101);
            mem0_read_line('h40);
            if (ar_count != saved_ar) $fatal(1,"CPU partial store evicted line");

            // Auxiliary writer also updates a previously cached word.
            mem0_read_line('h100);
            saved_ar=ar_count;
            @(negedge clk); aux_we=1; aux_din=64'h123456789abcdef0; aux_be=8'h55;
            do @(posedge clk); while(aux_busy);
            @(negedge clk); aux_we=0;
            mem0_read_line('h100);
            if (ar_count != saved_ar) $fatal(1,"auxiliary patch missed");

            // Same set, different physical tag (512 KiB stride).
            mem0_read_line('h80040);
            saved_ar=ar_count;
            mem0_read_line('h40);
            if (ar_count != saved_ar+1) $fatal(1,"conflict did not replace tag");
            // ROM/VGA hole bypasses even if the upstream line marker is set.
            saved_ar=ar_count;
            mem0_read_line('ha0040); mem0_read_line('ha0040);
            if (ar_count != saved_ar+2) $fatal(1,"aperture was cached");

            // Failed fill must invalidate the previous colliding line too.
            inject_read_error=1; mem0_read_line('h80040); inject_read_error=0;
            saved_ar=ar_count; mem0_read_line('h40);
            if (ar_count != saved_ar+1) $fatal(1,"failed fill retained corrupted victim");

            // Clear while a burst is in flight: preserve response, discard fill.
            fork
                mem0_read_line('h80080);
                begin
                    wait(arvalid && arready); @(negedge clk);
                    cache_invalidate=1; repeat(3) @(negedge clk);
                    cache_invalidate=0;
                end
            join
            wait(cache_ready);
            saved_ar=ar_count; mem0_read_line('h80080);
            if (ar_count != saved_ar+1) $fatal(1,"invalidated burst was retained");
            for (int trial=0; trial<300; trial++) begin
                random_address = ($urandom & 32'h3fc0) | (($urandom & 1)<<19);
                mem0_read_line(random_address);
                mem0_write_word(random_address + (($urandom & 15)<<2),
                                $urandom,4'($urandom));
                for (int word=0; word<4; word++) mem0_read_line(random_address+word*16);
            end
            $display("PASS: 512 KiB L2 spatial/conflict/partial-write/DMA/aux/error/reset tests hits=%0d misses=%0d beats=%0d",
                     cache_hits,cache_misses,cache_fill_beats);
            // Sustained adjacent stores, with realistic delayed write responses.
            // Include drain time, so merely accepting into a queue cannot fake
            // throughput. Verify expected bytes independently of the read model.
            wait(dut.idle);
            write_start = cycle;
            for (int word=0; word<256; word++)
                mem0_write_word('h10000+word*4, 32'h12340000+32'(word), 4'hf);
            wait(dut.idle);
            $display("WRITE_PERF: 256 stores incl drain: %0d cycles, response delay=%0d",
                     cycle-write_start, WRITE_RESPONSE_DELAY);
            $display("WRITE_PERF: max outstanding=%0d limit=%0d",pending_high_water,TEST_WRITE_OUTSTANDING);
            if (TEST_WRITE_OUTSTANDING > 1 && WRITE_RESPONSE_DELAY >= 20 && pending_high_water < 4)
                $fatal(1,"write stream failed to overlap DDR responses");
            for (int word=0; word<256; word++)
                for (int b=0; b<4; b++)
                    if (memory['h10000+word*4+b] !== 8'((32'h12340000+32'(word))>>(b*8)))
                        $fatal(1,"stream write lost/corrupt at word %0d byte %0d",word,b);
            // A delayed write error must be counted even outside ST_WRESP,
            // and must discard the write-through cache's optimistic patch.
            mem0_read_line('h10000);
            inject_write_error = 1;
            mem0_write_word('h10000,32'hdeadbeef,4'hf);
            wait(dut.idle);
            inject_write_error = 0;
            wait(cache_ready);
            saved_ar=ar_count;
            mem0_read_line('h10000);
            if (ar_count != saved_ar+1 || dut.response_error_count == 0)
                $fatal(1,"delayed B error did not invalidate/count");
            $display("PASS: posted write ordering, drain and delayed B error");
        end

        $display("PASS: unified z486 DDR AXI bridge");
        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $fatal(1, "timeout: bridge state=%0d", dut.state);
    end
endmodule
