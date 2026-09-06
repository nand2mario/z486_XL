`timescale 1ns/1ps

module tb_z486_shared_scanout;
    logic aclk = 1'b0;
    logic video_clk = 1'b0;
    always #5 aclk = ~aclk;
    always #3 video_clk = ~video_clk;

    logic aresetn = 1'b0;
    logic enable = 1'b1;
    logic drop_vga = 0, dropped_vga = 0;
    logic select_zsst = 1'b0;
    logic vga_ce = 1'b1;
    logic vga_de = 1'b0;
    logic vga_hs = 1'b0;
    logic vga_vs = 1'b0;
    logic [7:0] vga_r = 8'hff;
    logic [7:0] vga_g = 8'h00;
    logic [7:0] vga_b = 8'h00;
    logic [10:0] vga_width = 11'd8;
    logic [10:0] vga_height = 11'd4;
    wire vga_scanline_req;
    logic vga_scanline_ready = 1'b1;
    wire vga_scanline_frame_start;
    wire [10:0] vga_scanline_y;
    logic vga_scanline_done = 1'b0;
    logic packed_enable = 1'b0;
    logic [39:0] packed_base = 40'h0010_0000;
    logic [15:0] packed_stride = 16'd24;
    logic [10:0] packed_width = 11'd8;
    logic [10:0] packed_height = 11'd4;
    logic [1:0] packed_format = 2'd2;
    logic [7:0] packed_palette_address = 8'd0;
    logic [17:0] packed_palette_data = 18'd0;
    logic packed_palette_write = 1'b0;

    wire v_retrace;
    wire [11:0] v_retrace_count;
    wire [11:0] detected_width, detected_height;
    wire [31:0] frame_count, read_requests, read_beats, underflow_count;
    wire [1:0] current_source;
    wire [31:0] line_request_count, line_completion_count;
    wire [7:0] outstanding_high_water;
    wire sticky_underflow, sticky_axi_error;
    wire [7:0] video_r, video_g, video_b;
    wire video_hs, video_vs, video_de;
    wire [0:0] m_axi_arid;
    wire [39:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arlock;
    wire [3:0] m_axi_arcache;
    wire [2:0] m_axi_arprot;
    wire [3:0] m_axi_arqos;
    wire m_axi_arvalid;
    logic m_axi_arready = 1'b0;
    logic [0:0] m_axi_rid = 1'b0;
    logic [127:0] m_axi_rdata = 128'd0;
    logic [1:0] m_axi_rresp = 2'b00;
    logic m_axi_rlast = 1'b0;
    logic m_axi_rvalid = 1'b0;
    wire m_axi_rready;

    integer response_beats;
    logic [39:0] response_address;
    logic [15:0] response_lfsr = 16'hace1;
    integer memory_pattern;
    integer red_pixels;
    integer green_pixels;
    integer blue_pixels;
    logic previous_active_zsst;

    z486_shared_scanout #(
        .H_ACTIVE(16), .H_IMAGE(8), .H_START(4), .H_TOTAL(20),
        .H_SYNC_START(18), .H_SYNC_END(19),
        .V_ACTIVE(8), .V_TOTAL(12), .V_SYNC_START(10), .V_SYNC_END(11)
    ) dut (
        .aclk, .aresetn, .video_clk, .enable, .select_zsst,
        .memory_base(40'h0010_0000), .memory_size(32'h0010_0000),
        .vga_ce, .vga_de, .vga_r, .vga_g, .vga_b,
        .vga_width, .vga_height, .vga_scanline_req,
        .vga_scanline_ready, .vga_scanline_frame_start,
        .vga_scanline_y, .vga_scanline_done,
        .packed_enable, .packed_base, .packed_stride, .packed_width,
        .packed_height, .packed_format, .packed_palette_address,
        .packed_palette_data, .packed_palette_write,
        .zsst_fbi_base(40'h0010_0000),
        .zsst_buffer_size(24'h001000), .zsst_stride(16'd16),
        .zsst_width(10'd8), .zsst_height(10'd4),
        .zsst_displayed_buffer(2'd0),
        .v_retrace, .v_retrace_count, .detected_width, .detected_height,
        .frame_count, .read_requests, .read_beats, .underflow_count,
        .current_source, .line_request_count, .line_completion_count,
        .outstanding_high_water,
        .sticky_underflow, .sticky_axi_error,
        .video_r, .video_g, .video_b, .video_hs, .video_vs, .video_de,
        .m_axi_arid, .m_axi_araddr, .m_axi_arlen, .m_axi_arsize,
        .m_axi_arburst, .m_axi_arlock, .m_axi_arcache, .m_axi_arprot,
        .m_axi_arqos, .m_axi_arvalid, .m_axi_arready, .m_axi_rid,
        .m_axi_rdata, .m_axi_rresp, .m_axi_rlast, .m_axi_rvalid,
        .m_axi_rready
    );

    function automatic [127:0] memory_beat(input logic [39:0] address,
                                           input integer pattern);
        logic [127:0] value;
        integer offset;
        begin
            value = 128'd0;
            for (integer i = 0; i < 16; i = i + 1) begin
                offset = address + i - 40'h0010_0000;
                case (pattern)
                    0: value[i*8 +: 8] = offset[0] ? 8'hf8 : 8'h00;
                    1: value[i*8 +: 8] = 8'h01;
                    2: value[i*8 +: 8] = offset % 3 == 0 ? 8'hff : 8'h00;
                    default:
                        value[i*8 +: 8] = offset[0] ? 8'h00 : 8'h1f;
                endcase
            end
            memory_beat = value;
        end
    endfunction

    // Minimal AXI read responder with deterministic RGB565, indexed, and
    // BGR888 rows.  Its row starts are deliberately not assumed beat-aligned.
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            response_beats <= 0;
            response_lfsr <= 16'hace1;
            m_axi_arready <= 1'b0;
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
        end else begin
            response_lfsr <= {response_lfsr[14:0],
                response_lfsr[15] ^ response_lfsr[13] ^
                response_lfsr[12] ^ response_lfsr[10]};
            m_axi_arready <= response_beats == 0 &&
                (response_lfsr[0] || response_lfsr[3]);
            if (m_axi_arvalid && m_axi_arready) begin
                response_beats <= m_axi_arlen + 1;
                response_address <= m_axi_araddr;
                m_axi_rdata <= memory_beat(m_axi_araddr, memory_pattern);
                m_axi_rvalid <= 1'b1;
                m_axi_rlast <= m_axi_arlen == 0;
            end else if (m_axi_rvalid && m_axi_rready) begin
                if (response_beats == 1) begin
                    response_beats <= 0;
                    m_axi_rvalid <= 1'b0;
                    m_axi_rlast <= 1'b0;
                end else begin
                    response_beats <= response_beats - 1;
                    response_address <= response_address + 16;
                    m_axi_rdata <= memory_beat(response_address + 16,
                                               memory_pattern);
                    m_axi_rlast <= response_beats == 2;
                    // Insert legal gaps between beats. Once RVALID is raised,
                    // data remains stable until the scanout accepts it.
                    m_axi_rvalid <= response_lfsr[1] || response_lfsr[4];
                end
            end else if (!m_axi_rvalid && response_beats != 0) begin
                m_axi_rvalid <= response_lfsr[1] || response_lfsr[4];
            end
        end
    end

    // The HDMI scheduler, rather than a free-running VGA raster, asks the
    // legacy renderer for exactly one source row.
    initial begin : vga_source
        integer expected_row;
        wait (aresetn);
        expected_row = 0;
        forever begin
            wait (vga_scanline_req);
            if (vga_scanline_frame_start)
                expected_row = 0;
            if (vga_scanline_y != expected_row)
                $fatal(1, "non-sequential VGA row: got %0d, expected %0d",
                       vga_scanline_y, expected_row);
            expected_row = expected_row + 1;
            if (drop_vga) begin
                // Model a CPU/VGA reset abandoning an accepted row.
                dropped_vga = 1;
                wait (!drop_vga);
                dropped_vga = 0;
            end else begin
            @(posedge aclk);
            repeat (2) @(posedge aclk);
            vga_de = 1'b1;
            repeat (8) @(posedge aclk);
            vga_de = 1'b0;
            repeat (2) @(posedge aclk);
            vga_scanline_done = 1'b1;
            @(posedge aclk);
            vga_scanline_done = 1'b0;
            end
        end
    end

    always_ff @(posedge video_clk) begin
        if (!aresetn) begin
            red_pixels <= 0;
            green_pixels <= 0;
            blue_pixels <= 0;
            previous_active_zsst <= 1'b0;
        end else begin
            if (video_de && video_r > video_b)
                red_pixels <= red_pixels + 1;
            if (video_de && video_g > video_r && video_g > video_b)
                green_pixels <= green_pixels + 1;
            if (video_de && video_b > video_r)
                blue_pixels <= blue_pixels + 1;
            if ((dut.active_source == 2) != previous_active_zsst && video_de)
                $fatal(1, "source changed during active video");
            previous_active_zsst <= dut.active_source == 2;
        end
    end

    task automatic wait_frames(input integer count);
        integer target;
        begin
            target = frame_count + count;
            while (frame_count < target)
                @(posedge aclk);
        end
    endtask

    initial begin
        repeat (8) @(posedge aclk);
        memory_pattern = 3;
        aresetn = 1'b1;

        wait_frames(4);
        if (detected_width != 7 || detected_height != 3)
            $fatal(1, "VGA dimensions %0dx%0d", detected_width,
                   detected_height);
        if (red_pixels == 0)
            $fatal(1, "VGA producer did not reach shared output");
        if (read_requests != 0)
            $fatal(1, "VGA scanout unexpectedly accessed DDR");

        @(negedge aclk); drop_vga=1;
        wait(dropped_vga);
        repeat(3) @(negedge aclk);
        enable=0;
        repeat(20) @(negedge aclk);
        red_pixels=0; enable=1; drop_vga=0;
        wait_frames(4);
        if (red_pixels == 0) $fatal(1,"scanout stuck after abandoned VGA row");

        red_pixels = 0; green_pixels = 0; blue_pixels = 0;
        memory_pattern = 0;
        packed_format = 0;
        packed_enable = 1'b1;
        wait_frames(4);
        if (detected_width != 7 || detected_height != 3 || red_pixels == 0)
            $fatal(1, "packed RGB565 producer failed");

        red_pixels = 0; green_pixels = 0; blue_pixels = 0;
        packed_palette_address = 1;
        packed_palette_data = {6'h00, 6'h3f, 6'h00};
        packed_palette_write = 1'b1;
        @(posedge aclk);
        packed_palette_write = 1'b0;
        memory_pattern = 1;
        packed_format = 1;
        wait_frames(4);
        if (green_pixels == 0)
            $fatal(1, "packed indexed8 producer failed");

        red_pixels = 0; green_pixels = 0; blue_pixels = 0;
        memory_pattern = 2;
        packed_base = 40'h0010_0005;
        packed_format = 2;
        wait_frames(4);
        if (green_pixels == 0)
            $fatal(1, "unaligned packed BGR888 producer failed");

        red_pixels = 0; green_pixels = 0; blue_pixels = 0;
        packed_enable = 1'b0;
        memory_pattern = 3;
        select_zsst = 1'b1;
        wait_frames(4);
        if (read_requests == 0 || read_beats == 0)
            $fatal(1, "zSST producer did not access DDR");
        if (blue_pixels == 0)
            $fatal(1, "zSST producer did not reach shared output");
        if (sticky_axi_error)
            $fatal(1, "unexpected AXI error");
        if (outstanding_high_water != 1)
            $fatal(1, "AXI outstanding high-water mark was not recorded");

        red_pixels = 0; green_pixels = 0; blue_pixels = 0;
        select_zsst = 1'b0;
        wait_frames(4);
        if (red_pixels == 0)
            $fatal(1, "VGA did not resume after zSST");
        if (line_completion_count == 0 ||
            line_completion_count > line_request_count)
            $fatal(1, "invalid row request/completion counters");

        $display("PASS: shared VGA/zSST nearest-neighbor scanout");
        $finish;
    end
endmodule
