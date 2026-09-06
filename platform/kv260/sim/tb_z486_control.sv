`timescale 1ns/1ps

module tb_z486_control;
    logic clk = 0;
    logic resetn = 0;
    always #5 clk = ~clk;

    logic [7:0] awaddr, araddr;
    logic awvalid, wvalid, bready, arvalid, rready;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire run;
    wire [39:0] memory_base;
    wire [31:0] memory_size;
    wire [1:0] guest_ram_size;
    wire video_run, video_freeze;
    wire [4:0] video_mode;
    wire [1:0] audio_boost;
    logic [1:0] fdd_request = 2'b10;
    logic [2:0] ide0_request = 3'b100;
    logic [2:0] ide1_request = 3'b011;
    wire [15:0] mgmt_address, mgmt_writedata;
    wire mgmt_read, mgmt_write;
    logic [15:0] mgmt_readdata = 16'hbeef;
    logic kbd_tx_empty = 1'b1, mouse_tx_empty = 1'b1;
    logic [8:0] kbd_host_cmd = 9'h1ed;
    logic [8:0] mouse_host_cmd = 9'h0f4;
    wire [7:0] kbd_data, mouse_data;
    wire kbd_data_valid, mouse_data_valid;
    wire kbd_host_cmd_clear, mouse_host_cmd_clear;

    z486_control dut (
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
        .memory_size_out(memory_size), .guest_ram_size(guest_ram_size),
        .video_run(video_run),
        .video_freeze(video_freeze), .video_mode(video_mode),
        .audio_boost(audio_boost),
        .debug_led(8'd0), .boot_stage(3'd0), .bios_loaded(1'b0),
        .first_instruction(1'b0), .post_code(8'd0), .post_write(1'b0),
        .cpu_cs(16'd0), .cpu_eip(32'd0), .request_count(32'd0),
        .read_beat_count(32'd0), .stall_cycle_count(32'd0),
        .response_error_count(32'd0),
        .l2_hits(32'd123), .l2_misses(32'd17), .l2_fill_beats(32'd68),
        .l2_status(32'h02000003),
        .video_width(12'd639), .video_height(12'd479),
        .video_frames(32'd60), .video_read_bursts(32'd2),
        .video_write_bursts(32'd3), .video_read_beats(32'd32),
        .video_write_beats(32'd48), .video_stall_cycles(32'd7),
        .video_error_count(32'd0), .video_source(2'd0),
        .video_line_requests(32'd12), .video_line_completions(32'd11),
        .video_native_frames(32'd70), .video_outstanding_high_water(8'd1),
        .fdd_request(fdd_request),
        .ide0_request(ide0_request), .ide1_request(ide1_request),
        .mgmt_address(mgmt_address), .mgmt_read(mgmt_read),
        .mgmt_readdata(mgmt_readdata), .mgmt_write(mgmt_write),
        .mgmt_writedata(mgmt_writedata), .kbd_tx_empty(kbd_tx_empty),
        .mouse_tx_empty(mouse_tx_empty), .kbd_host_cmd(kbd_host_cmd),
        .mouse_host_cmd(mouse_host_cmd), .kbd_data(kbd_data),
        .kbd_data_valid(kbd_data_valid), .mouse_data(mouse_data),
        .mouse_data_valid(mouse_data_valid),
        .kbd_host_cmd_clear(kbd_host_cmd_clear),
        .mouse_host_cmd_clear(mouse_host_cmd_clear)
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

    task automatic axi_read(input [7:0] address, output [31:0] data);
        begin
            @(negedge clk);
            araddr = address;
            arvalid = 1;
            do @(posedge clk); while (!arready);
            @(negedge clk);
            arvalid = 0;
            do @(posedge clk); while (!rvalid);
            data = rdata;
            if (rresp != 0) $fatal(1, "AXI read response error");
            @(negedge clk);
            rready = 1;
            @(negedge clk);
            rready = 0;
        end
    endtask

    initial begin
        reg [31:0] value;
        awaddr = 0;
        awvalid = 0;
        wdata = 0;
        wstrb = 0;
        wvalid = 0;
        bready = 0;
        araddr = 0;
        arvalid = 0;
        rready = 0;
        repeat (5) @(posedge clk);
        resetn = 1;

        axi_read(8'h04, value);
        if (value != 32'h0001_0009)
            $fatal(1, "unexpected ABI %08x", value);
        axi_read(8'hc4, value);
        if (value != 0 || audio_boost != 0)
            $fatal(1, "audio boost reset mismatch");
        axi_write(8'hc4, 2);
        axi_read(8'hc4, value);
        if (value != 2 || audio_boost != 2)
            $fatal(1, "audio boost write mismatch");
        axi_read(8'hb4,value); if(value!=123) $fatal(1,"L2 hits register");
        axi_read(8'hb8,value); if(value!=17) $fatal(1,"L2 misses register");
        axi_read(8'hbc,value); if(value!=68) $fatal(1,"L2 fill register");
        axi_read(8'hc0,value); if(value!=32'h02000003) $fatal(1,"L2 config register");
        axi_read(8'h7c, value);
        if (value != 0 || guest_ram_size != 0)
            $fatal(1, "guest RAM reset default mismatch %08x", value);
        axi_write(8'h7c, 2);
        axi_read(8'h7c, value);
        if (value != 2 || guest_ram_size != 2)
            $fatal(1, "guest RAM configuration mismatch %08x", value);
        axi_write(8'h08, 1);
        axi_write(8'h7c, 3);
        if (guest_ram_size != 2)
            $fatal(1, "guest RAM changed while core was running");
        axi_write(8'h08, 0);
        axi_write(8'h58, 32'h000b_0001);
        if (!video_run || video_freeze || video_mode != 5'h0b)
            $fatal(1, "video control write mismatch");
        axi_read(8'h5c, value);
        if (value != 32'h01df_027f)
            $fatal(1, "video dimensions mismatch %08x", value);
        axi_read(8'h70, value);
        if (value != 32'd32)
            $fatal(1, "video counter mismatch %08x", value);
        axi_read(8'h84, value);
        if (value != 32'd12)
            $fatal(1, "scanout request counter mismatch %08x", value);
        axi_read(8'h8c, value);
        if (value != 32'd70)
            $fatal(1, "native retrace counter mismatch %08x", value);
        axi_read(8'h34, value);
        if (value[7:0] != 8'h9c || value[8])
            $fatal(1, "request status mismatch %08x", value);

        axi_write(8'h38, 16'hf055);
        axi_write(8'h44, 1);
        do @(posedge clk); while (!mgmt_read);
        if (mgmt_address != 16'hf055 || mgmt_write)
            $fatal(1, "management read pulse mismatch");
        do @(posedge clk); while (dut.mgmt_state != 0);
        axi_read(8'h40, value);
        if (value[15:0] != 16'hbeef)
            $fatal(1, "management read data mismatch %08x", value);

        axi_write(8'h38, 16'hf0ff);
        axi_write(8'h3c, 16'hcafe);
        axi_write(8'h44, 2);
        do @(posedge clk); while (!mgmt_write);
        if (mgmt_address != 16'hf0ff || mgmt_writedata != 16'hcafe ||
            mgmt_read)
            $fatal(1, "management write pulse mismatch");
        do @(posedge clk); while (dut.mgmt_state != 0);

        axi_read(8'h48, value);
        if (value != 32'hf4ed_0103)
            $fatal(1, "PS/2 status mismatch %08x", value);
        fork
            begin
                do @(posedge clk); while (!kbd_host_cmd_clear);
            end
            axi_write(8'h54, 1);
        join
        kbd_host_cmd[8] = 1'b0;
        fork
            begin
                do @(posedge clk); while (!kbd_data_valid);
                if (kbd_data != 8'h1c)
                    $fatal(1, "keyboard byte mismatch");
            end
            axi_write(8'h4c, 8'h1c);
        join
        fork
            begin
                do @(posedge clk); while (!mouse_data_valid);
                if (mouse_data != 8'h08)
                    $fatal(1, "mouse byte mismatch");
            end
            axi_write(8'h50, 8'h08);
        join
        mouse_host_cmd[8] = 1'b1;
        fork
            begin
                do @(posedge clk); while (!mouse_host_cmd_clear);
            end
            axi_write(8'h54, 2);
        join

        $display("PASS: z486 AXI-Lite video, management, and PS/2 tunnel");
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule
