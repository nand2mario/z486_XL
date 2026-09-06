`timescale 1ns/1ps
module tb_zsst_reset_drain;
    import sst1_pkg::*;
    bit clk=0;
    always #5 clk=~clk;
    bit reset_n=0, soft_reset=1;
    logic client_reset_n, reset_busy, bus_idle;
    logic valid=0, ready;
    sst1_mem_req_t req='0;
    logic [39:0] awaddr;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic awvalid, awready=0, wvalid, wready=0, bvalid, bready;
    logic allow_b=0, rvalid=0, rready, arvalid, rsp_valid;
    logic [3:0] arid, rid=0;
    integer sent=0, addresses=0, data_beats=0, responses=0;
    zsst_reset_guard guard (
        .clk, .reset_n, .soft_reset, .bus_idle, .client_reset_n, .reset_busy);
    sst1_axi_bridge dut (
        .aclk(clk), .aresetn(reset_n), .idle(bus_idle),
        .req_valid(valid && client_reset_n), .req_ready(ready), .req,
        .rsp_valid(rsp_valid), .rsp_ready(!client_reset_n),
        .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid),
        .m_axi_wready(wready), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_bid(4'd0), .m_axi_bresp(2'd0), .m_axi_arvalid(arvalid),
        .m_axi_arid(arid), .m_axi_arready(1'b1), .m_axi_rid(rid),
        .m_axi_rdata(128'd0), .m_axi_rresp(2'd0), .m_axi_rlast(1'b1),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready));
    assign bvalid = allow_b && responses < addresses && responses < data_beats;
    // Slave queues deliberately survive every guest reset.
    always @(posedge clk) if (reset_n) begin
        if (awvalid && awready) begin
            assert(awaddr == 40'h1000 + 40'(addresses*16)) else $fatal(1,"AW pairing");
            addresses <= addresses+1;
        end
        if (wvalid && wready) begin
            assert(wdata == (128'(data_beats+1) << ((data_beats%8)*16)) &&
                   wstrb == (16'h3 << ((data_beats%8)*2))) else $fatal(1,"W pairing");
            data_beats <= data_beats+1;
        end
        if (bvalid && bready) responses <= responses+1;
    end
    task automatic send_write;
        @(negedge clk);
        req='0; req.write=1; req.beats=1;
        req.addr=40'h1000 + 40'(sent*16);
        req.wdata=128'(sent+1) << ((sent%8)*16);
        req.wstrb=16'h3 << ((sent%8)*2);
        valid=1;
        do @(posedge clk); while (!(ready && client_reset_n));
        @(negedge clk); valid=0; sent++;
    endtask
    task automatic reset_and_restart;
        @(negedge clk); soft_reset=1;
        repeat(3) @(negedge clk);
        soft_reset=0;
        repeat(3) begin
            @(negedge clk);
            assert(!client_reset_n && reset_busy) else $fatal(1,"restart before drain");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);
        reset_n=1; soft_reset=0;
        wait(client_reset_n);
        // AW accepted before reset; W and B must finish with their old data.
        awready=1; send_write(); wait(addresses==1);
        reset_and_restart(); wready=1; allow_b=1;
        wait(client_reset_n); assert(responses==1) else $fatal;
        // W accepted before reset; preserve its still-pending address.
        @(negedge clk); awready=0; allow_b=0;
        send_write(); wait(data_beats==2);
        reset_and_restart(); awready=1; allow_b=1;
        wait(client_reset_n); assert(responses==2) else $fatal;
        // Both channels accepted, delayed B response must also drain.
        @(negedge clk); allow_b=0;
        send_write(); wait(data_beats==3 && addresses==3);
        reset_and_restart(); allow_b=1;
        wait(client_reset_n); assert(responses==3) else $fatal;
        // Old R data is drained while the client remains held in reset.
        @(negedge clk); req='0; req.beats=1; req.addr=40'h2000; valid=1;
        do @(posedge clk); while (!ready);
        @(negedge clk); valid=0;
        wait(arvalid); rid=arid;
        @(posedge clk);
        reset_and_restart();
        rvalid=1;
        do @(posedge clk); while (!rready);
        @(negedge clk); rvalid=0;
        wait(client_reset_n);
        send_write(); wait(responses==4);
        $display("PASS: AW-first, W-first, delayed B/R and immediate restart drain safely");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1,"reset drain timeout");
    end
endmodule
