`timescale 1ns/1ps

module tb_z486_ide_tunnel;
    logic clk = 0;
    logic resetn = 0;
    always #5 clk = ~clk;

    logic [7:0] awaddr = 0, araddr = 0;
    logic awvalid = 0, wvalid = 0, bready = 0;
    logic arvalid = 0, rready = 0;
    logic [31:0] wdata = 0;
    logic [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire run;
    wire [39:0] memory_base;
    wire [15:0] mgmt_address, mgmt_writedata, mgmt_readdata;
    wire mgmt_read, mgmt_write;

    logic [3:0] io_address = 0;
    logic io_read = 0, io_write = 0, io_32 = 0;
    logic [31:0] io_writedata = 0;
    wire [31:0] io_readdata;
    wire [2:0] ide_request;

    z486_control control (
        .aclk(clk), .aresetn(resetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
        .s_axi_wready(wready), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
        .s_axi_arready(arready), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready), .run(run), .memory_base(memory_base),
        .memory_size_out(), .guest_ram_size(), .video_run(),
        .video_freeze(), .video_mode(),
        .debug_led(8'd0), .boot_stage(3'd0), .bios_loaded(1'b0),
        .first_instruction(1'b0), .post_code(8'd0), .post_write(1'b0),
        .cpu_cs(16'd0), .cpu_eip(32'd0), .request_count(32'd0),
        .read_beat_count(32'd0), .stall_cycle_count(32'd0),
        .response_error_count(32'd0), .video_width(12'd0),
        .video_height(12'd0), .video_frames(32'd0),
        .video_read_bursts(32'd0), .video_write_bursts(32'd0),
        .video_read_beats(32'd0), .video_write_beats(32'd0),
        .video_stall_cycles(32'd0), .video_error_count(32'd0),
        .video_source(2'd0), .video_line_requests(32'd0),
        .video_line_completions(32'd0), .video_native_frames(32'd0),
        .video_outstanding_high_water(8'd0),
        .fdd_request(2'd0),
        .ide0_request(ide_request), .ide1_request(3'd0),
        .mgmt_address(mgmt_address), .mgmt_read(mgmt_read),
        .mgmt_readdata(mgmt_readdata), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .kbd_tx_empty(1'b1),
        .mouse_tx_empty(1'b1), .kbd_host_cmd(9'd0),
        .mouse_host_cmd(9'd0), .kbd_data(), .kbd_data_valid(),
        .mouse_data(), .mouse_data_valid(), .kbd_host_cmd_clear(),
        .mouse_host_cmd_clear()
    );

    ide ide0 (
        .clk(clk), .rst_n(resetn), .irq(), .drq(), .use_fast(1'b0),
        .no_data(), .drive_en(), .io_address(io_address),
        .io_read(io_read), .io_readdata(io_readdata),
        .io_write(io_write), .io_writedata(io_writedata),
        .io_32(io_32), .io_wait(), .request(ide_request),
        .mgmt_address(mgmt_address[3:0]), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .mgmt_read(mgmt_read),
        .mgmt_readdata(mgmt_readdata)
    );

    task automatic axi_write(input [7:0] address, input [31:0] data);
        begin
            @(negedge clk);
            awaddr = address;
            wdata = data;
            wstrb = 4'hf;
            awvalid = 1;
            wvalid = 1;
            do @(posedge clk); while (!awready || !wready);
            @(negedge clk);
            awvalid = 0;
            wvalid = 0;
            do @(posedge clk); while (!bvalid);
            if (bresp != 0) $fatal(1, "AXI write response error");
            @(negedge clk);
            bready = 1;
            @(negedge clk);
            bready = 0;
        end
    endtask

    task automatic mgmt_write_word(input [15:0] address,
                                   input [15:0] data);
        begin
            axi_write(8'h38, address);
            axi_write(8'h3c, data);
            axi_write(8'h44, 2);
            do @(posedge clk); while (control.mgmt_state != 0);
        end
    endtask

    task automatic guest_write(input [3:0] address,
                               input [31:0] data);
        begin
            @(negedge clk);
            io_address = address;
            io_writedata = data;
            io_write = 1;
            @(posedge clk);
            @(negedge clk);
            io_write = 0;
            @(posedge clk);
        end
    endtask

    task automatic guest_read_word(output [15:0] data);
        begin
            @(negedge clk);
            io_address = 0;
            io_read = 1;
            @(posedge clk);
            @(negedge clk);
            data = io_readdata[15:0];
            io_read = 0;
            @(posedge clk);
		    @(posedge clk);
        end
    endtask

    initial begin
        reg [15:0] value;
        integer i;

        repeat (5) @(posedge clk);
        resetn = 1;
        mgmt_write_word(16'hf006, 16'h0009);
        guest_write(4'h6, 32'h000000e0);
        guest_write(4'h7, 32'h000000ec);
        if (ide_request != 3'b100)
            $fatal(1, "IDENTIFY request missing: %b", ide_request);

        for (i = 0; i < 256; i++)
            mgmt_write_word(16'hf0ff, 16'h4000 + i);
        mgmt_write_word(16'hf000, 16'h0001);
        mgmt_write_word(16'hf001, 16'h0000);
        mgmt_write_word(16'hf002, 16'h0000);
        mgmt_write_word(16'hf003, 16'h0000);
        mgmt_write_word(16'hf004, 16'h0000);
        mgmt_write_word(16'hf005, 16'h4ea0);

        for (i = 0; i < 256; i++) begin
            guest_read_word(value);
            if (value != 16'h4000 + i)
                $fatal(1, "guest data[%0d]: expected=%04x actual=%04x",
                       i, 16'h4000 + i, value);
        end
        $display("PASS: AXI management tunnel feeds ordered IDE guest data");
        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule
