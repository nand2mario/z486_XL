`timescale 1ns/1ps
// Independently stall AXI address/data channels and verify transaction pairing.
module tb_zsst_write_pairing;
    import sst1_pkg::*;
    bit clk = 0;
    always #5 clk = ~clk;
    bit reset_n = 0;
    logic valid, ready, qvalid, qready;
    sst1_mem_req_t req, qreq;
    logic [39:0] awaddr;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic awvalid, awready, wvalid, wready, bvalid, bready;
    int sent = 0, addresses = 0, data_beats = 0, responses = 0;
    int cycles = 0;
    zsst_mem_request_fifo fifo (
        .clk(clk), .reset_n(reset_n), .in_valid(valid), .in_ready(ready),
        .in_req(req), .out_valid(qvalid), .out_ready(qready), .out_req(qreq), .empty());
    sst1_axi_bridge dut (
        .aclk(clk), .aresetn(reset_n), .req_valid(qvalid), .req_ready(qready),
`ifdef BRIDGE_NETLIST
        .\req[addr] (qreq.addr), .\req[wdata] (qreq.wdata),
        .\req[wstrb] (qreq.wstrb), .\req[beats] (qreq.beats),
        .\req[tag] (qreq.tag), .\req[source] (qreq.source),
        .\req[order_class] (qreq.order_class), .\req[write] (qreq.write),
`else
        .req(qreq),
`endif
        .rsp_ready(1'b1), .m_axi_awaddr(awaddr), .m_axi_awvalid(awvalid),
        .m_axi_awready(awready), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready), .m_axi_bvalid(bvalid),
        .m_axi_bready(bready), .m_axi_bid(4'd0), .m_axi_bresp(2'd0),
        .m_axi_arready(1'b1), .m_axi_rid(4'd0), .m_axi_rdata(128'd0),
        .m_axi_rresp(2'd0), .m_axi_rlast(1'b0), .m_axi_rvalid(1'b0));
    always_comb begin
        req = '0;
        req.write = 1;
        req.beats = 1;
        req.addr = 40'h100000 + 40'(sent * 16);
        req.wdata = 128'(sent + 1) << ((sent % 8) * 16);
        req.wstrb = 16'h3 << ((sent % 8) * 2);
        valid = reset_n && sent < 2000;
        bvalid = responses < addresses && responses < data_beats;
    end
    always @(negedge clk) begin
        awready = $urandom_range(0, 7) < 3;
        wready = $urandom_range(0, 7) < 5;
    end
    always @(posedge clk) if (reset_n) begin
        if (valid && ready) sent <= sent + 1;
        if (awvalid && awready) begin
            assert (awaddr == 40'h100000 + 40'(addresses * 16))
                else $fatal(1, "address pairing at %0d", addresses);
            addresses <= addresses + 1;
        end
        if (wvalid && wready) begin
            assert (wdata == (128'(data_beats + 1) << ((data_beats % 8)*16)) &&
                    wstrb == (16'h3 << ((data_beats % 8)*2)))
                else $fatal(1, "data pairing at %0d", data_beats);
            data_beats <= data_beats + 1;
        end
        if (bvalid && bready) responses <= responses + 1;
        cycles <= cycles + 1;
        if (responses == 2000) begin
            $display("PASS: 2000 independently stalled AXI writes");
            $finish;
        end
        if (cycles == 30000) $fatal(1, "timeout");
    end
    initial begin
        // Also outlast the 100 ns global reset in Xilinx functional netlists.
        repeat (20) @(negedge clk);
        reset_n = 1;
    end
endmodule
