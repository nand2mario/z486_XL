`timescale 1ns/1ps

// One 1024-pixel RGB565 row. The 128-bit organization matches a PS HP AXI
// beat while keeping the video-side read mux small.
module z486_scanout_line_buffer (
    input logic write_clk, input logic write_enable,
    input logic [6:0] write_address, input logic [127:0] write_data,
    input logic read_clk, input logic [6:0] read_address,
    output logic [127:0] read_data
);
`ifdef VERILATOR
    logic [127:0] storage [0:127];
    always_ff @(posedge write_clk)
        if (write_enable) storage[write_address] <= write_data;
    always_ff @(posedge read_clk) read_data <= storage[read_address];
`else
    wire unused_dbiterr, unused_sbiterr;
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(7), .ADDR_WIDTH_B(7), .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(128), .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("independent_clock"), .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"), .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"), .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(16384), .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(128), .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"), .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0), .USE_EMBEDDED_CONSTRAINT(0), .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"), .WRITE_DATA_WIDTH_A(128),
        .WRITE_MODE_B("read_first")
    ) memory (
        .dbiterrb(unused_dbiterr), .doutb(read_data),
        .sbiterrb(unused_sbiterr), .addra(write_address),
        .addrb(read_address), .clka(write_clk), .clkb(read_clk),
        .dina(write_data), .ena(write_enable), .enb(1'b1),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(1'b0), .sleep(1'b0), .wea(write_enable)
    );
`endif
endmodule

// Fixed 1080p60 nearest-neighbor output shared by legacy VGA, the packed
// ET4000 framebuffer, and the zSST front buffer. HDMI owns the row cadence.
module z486_shared_scanout #(
    parameter integer H_ACTIVE=1920, H_IMAGE=1440, H_START=240,
    parameter integer H_TOTAL=2200, H_SYNC_START=2008, H_SYNC_END=2052,
    parameter integer V_ACTIVE=1080, V_TOTAL=1125,
    parameter integer V_SYNC_START=1084, V_SYNC_END=1089
) (
    input logic aclk, input logic aresetn, input logic video_clk,
    input logic enable, input logic select_zsst,
    input logic [39:0] memory_base, input logic [31:0] memory_size,

    input logic vga_ce, input logic vga_de,
    input logic [7:0] vga_r, vga_g, vga_b,
    input logic [10:0] vga_width, vga_height,
    output logic vga_scanline_req, input logic vga_scanline_ready,
    output logic vga_scanline_frame_start,
    output logic [10:0] vga_scanline_y,
    input logic vga_scanline_done,

    input logic packed_enable, input logic [39:0] packed_base,
    input logic [15:0] packed_stride,
    input logic [10:0] packed_width, packed_height,
    input logic [1:0] packed_format, // 0=RGB565, 1=indexed8, 2=BGR888
    input logic [7:0] packed_palette_address,
    input logic [17:0] packed_palette_data,
    input logic packed_palette_write,

    input logic [39:0] zsst_fbi_base,
    input logic [23:0] zsst_buffer_size,
    input logic [15:0] zsst_stride,
    input logic [9:0] zsst_width, zsst_height,
    input logic [1:0] zsst_displayed_buffer,

    output logic v_retrace, output logic [11:0] v_retrace_count,
    output logic [11:0] detected_width, detected_height,
    output logic [31:0] frame_count, read_requests, read_beats,
    output logic [1:0] current_source,
    output logic [31:0] line_request_count, line_completion_count,
    output logic [7:0] outstanding_high_water,
    output logic [31:0] underflow_count,
    output logic sticky_underflow, sticky_axi_error,
    output logic memory_idle,
    output logic [7:0] video_r, video_g, video_b,
    output logic video_hs, video_vs, video_de,

    output logic [0:0] m_axi_arid, output logic [39:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen, output logic [2:0] m_axi_arsize,
    output logic [1:0] m_axi_arburst, output logic m_axi_arlock,
    output logic [3:0] m_axi_arcache, output logic [2:0] m_axi_arprot,
    output logic [3:0] m_axi_arqos, output logic m_axi_arvalid,
    input logic m_axi_arready, input logic [0:0] m_axi_rid,
    input logic [127:0] m_axi_rdata, input logic [1:0] m_axi_rresp,
    input logic m_axi_rlast, input logic m_axi_rvalid,
    output logic m_axi_rready
);
    localparam logic [1:0] SOURCE_VGA=2'd0, SOURCE_PACKED=2'd1,
                           SOURCE_ZSST=2'd2;

    logic select_meta, select_video, packed_enable_meta, packed_enable_video;
    logic enable_meta, enable_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] vga_width_meta, vga_width_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] vga_height_meta, vga_height_video;
    (* ASYNC_REG="TRUE" *) logic [39:0] packed_base_meta, packed_base_video;
    (* ASYNC_REG="TRUE" *) logic [15:0] packed_stride_meta, packed_stride_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] packed_width_meta, packed_width_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] packed_height_meta, packed_height_video;
    (* ASYNC_REG="TRUE" *) logic [1:0] packed_format_meta, packed_format_video;
    (* ASYNC_REG="TRUE" *) logic [39:0] zsst_base_meta, zsst_base_video;
    (* ASYNC_REG="TRUE" *) logic [15:0] zsst_stride_meta, zsst_stride_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] zsst_width_meta, zsst_width_video;
    (* ASYNC_REG="TRUE" *) logic [10:0] zsst_height_meta, zsst_height_video;
    wire [39:0] zsst_front_base = zsst_fbi_base +
        (zsst_displayed_buffer[0] ? {16'd0,zsst_buffer_size} : 40'd0);

    logic [12:0] hcount;
    logic [10:0] vcount, source_y;
    logic [9:0] source_x;
    logic [11:0] h_phase, v_phase;
    logic [10:0] active_width, active_height;
    logic [1:0] active_source, active_format;
    logic [39:0] active_base;
    logic [15:0] active_stride;
    logic current_bank, current_line_valid, bank0_valid, bank1_valid;
    logic [10:0] bank0_row, bank1_row;
    logic [6:0] line_read_address;
    logic [2:0] line_lane_request, line_lane;
    logic [127:0] line0_word, line1_word;
    wire [127:0] line_word = current_bank ? line1_word : line0_word;
    logic [15:0] rgb565;
    logic pixel_inside;

    logic request_toggle, request_active, request_bank, request_epoch;
    logic [1:0] request_source, request_format;
    logic [10:0] request_row, request_width;
    logic [39:0] request_base;
    logic [15:0] request_stride;
    logic frame_epoch, frame_prepare, frame_ready, frame_started;
    (* ASYNC_REG="TRUE" *) logic ack_meta, ack_video;
    (* ASYNC_REG="TRUE" *) logic ack_ok_meta, ack_ok_video;
    logic ack_seen, underflow_toggle;
    logic ack_toggle, ack_ok;
    wire source_row_in_bank0 = bank0_valid && bank0_row==source_y;
    wire source_row_in_bank1 = bank1_valid && bank1_row==source_y;

    // Preserve the established control ABI: dimensions are maximum pixel
    // coordinates (size minus one), as they were on MiSTer's ascal path.
    assign detected_width=active_width!=0 ?
        {1'b0,active_width-1'b1} : 12'd0;
    assign detected_height=active_height!=0 ?
        {1'b0,active_height-1'b1} : 12'd0;
    always_comb begin
        case (line_lane)
            0: rgb565=line_word[15:0]; 1: rgb565=line_word[31:16];
            2: rgb565=line_word[47:32]; 3: rgb565=line_word[63:48];
            4: rgb565=line_word[79:64]; 5: rgb565=line_word[95:80];
            6: rgb565=line_word[111:96]; default: rgb565=line_word[127:112];
        endcase
    end
    assign video_r=pixel_inside ? {rgb565[15:11],rgb565[15:13]} : 8'd0;
    assign video_g=pixel_inside ? {rgb565[10:5],rgb565[10:9]} : 8'd0;
    assign video_b=pixel_inside ? {rgb565[4:0],rgb565[4:2]} : 8'd0;

    always_ff @(posedge video_clk) begin
        if (!aresetn) begin
            hcount<=0; vcount<=0; source_x<=0; source_y<=0;
            h_phase<=0; v_phase<=0;
            active_width<=640; active_height<=480; active_source<=SOURCE_VGA;
            active_base<=0; active_stride<=0; active_format<=0;
            current_bank<=0; current_line_valid<=0;
            bank0_valid<=0; bank1_valid<=0; bank0_row<=0; bank1_row<=0;
            line_read_address<=0; line_lane_request<=0; line_lane<=0;
            pixel_inside<=0; video_hs<=0; video_vs<=0; video_de<=0;
            request_toggle<=0; request_active<=0; request_bank<=0;
            request_epoch<=0; request_source<=SOURCE_VGA; request_row<=0;
            request_width<=0; request_base<=0; request_stride<=0;
            request_format<=0; frame_epoch<=0; frame_prepare<=0;
            frame_ready<=0; frame_started<=0; ack_meta<=0; ack_video<=0;
            ack_ok_meta<=0; ack_ok_video<=0; ack_seen<=0;
            underflow_toggle<=0; select_meta<=0; select_video<=0;
            packed_enable_meta<=0; packed_enable_video<=0;
            enable_meta<=0; enable_video<=0;
            vga_width_meta<=640; vga_width_video<=640;
            vga_height_meta<=480; vga_height_video<=480;
            packed_base_meta<=0; packed_base_video<=0;
            packed_stride_meta<=0; packed_stride_video<=0;
            packed_width_meta<=640; packed_width_video<=640;
            packed_height_meta<=480; packed_height_video<=480;
            packed_format_meta<=0; packed_format_video<=0;
            zsst_base_meta<=0; zsst_base_video<=0;
            zsst_stride_meta<=0; zsst_stride_video<=0;
            zsst_width_meta<=640; zsst_width_video<=640;
            zsst_height_meta<=480; zsst_height_video<=480;
        end else begin
            select_meta<=select_zsst; select_video<=select_meta;
            packed_enable_meta<=packed_enable;
            packed_enable_video<=packed_enable_meta;
            enable_meta<=enable; enable_video<=enable_meta;
            vga_width_meta<=vga_width; vga_width_video<=vga_width_meta;
            vga_height_meta<=vga_height; vga_height_video<=vga_height_meta;
            packed_base_meta<=packed_base; packed_base_video<=packed_base_meta;
            packed_stride_meta<=packed_stride;
            packed_stride_video<=packed_stride_meta;
            packed_width_meta<=packed_width;
            packed_width_video<=packed_width_meta;
            packed_height_meta<=packed_height;
            packed_height_video<=packed_height_meta;
            packed_format_meta<=packed_format;
            packed_format_video<=packed_format_meta;
            zsst_base_meta<=zsst_front_base; zsst_base_video<=zsst_base_meta;
            zsst_stride_meta<=zsst_stride; zsst_stride_video<=zsst_stride_meta;
            zsst_width_meta<={1'b0,zsst_width};
            zsst_width_video<=zsst_width_meta;
            zsst_height_meta<={1'b0,zsst_height};
            zsst_height_video<=zsst_height_meta;
            ack_meta<=ack_toggle; ack_video<=ack_meta;
            ack_ok_meta<=ack_ok; ack_ok_video<=ack_ok_meta;

            video_hs<=hcount>=H_SYNC_START && hcount<H_SYNC_END;
            video_vs<=vcount>=V_SYNC_START && vcount<V_SYNC_END;
            video_de<=enable_video && hcount<H_ACTIVE && vcount<V_ACTIVE;
            pixel_inside<=enable_video && current_line_valid &&
                hcount>=H_START && hcount<H_START+H_IMAGE && vcount<V_ACTIVE;
            line_lane<=line_lane_request;

            if (hcount==H_START-1) begin
                source_x<=0; h_phase<=0; line_read_address<=0;
                line_lane_request<=0;
            end else if (hcount>=H_START && hcount<H_START+H_IMAGE-1) begin
                if (h_phase+active_width>=H_IMAGE) begin
                    h_phase<=h_phase+active_width-H_IMAGE;
                    source_x<=source_x+1'b1;
                    line_read_address<=(source_x+1'b1)>>3;
                    line_lane_request<=(source_x+1'b1)&3'b111;
                end else begin
                    h_phase<=h_phase+active_width;
                    line_read_address<=source_x>>3;
                    line_lane_request<=source_x[2:0];
                end
            end

            if (ack_video!=ack_seen) begin
                ack_seen<=ack_video; request_active<=0;
                if (request_epoch==frame_epoch && ack_ok_video) begin
                    if (request_bank) begin bank1_valid<=1; bank1_row<=request_row; end
                    else begin bank0_valid<=1; bank0_row<=request_row; end
                    if (request_row==0) frame_ready<=1;
                end
            end

            if (hcount==0 && vcount==V_ACTIVE+2) begin
                if (select_video) begin
                    active_source<=SOURCE_ZSST; active_width<=zsst_width_video;
                    active_height<=zsst_height_video; active_base<=zsst_base_video;
                    active_stride<=zsst_stride_video; active_format<=0;
                end else if (packed_enable_video) begin
                    active_source<=SOURCE_PACKED; active_width<=packed_width_video;
                    active_height<=packed_height_video; active_base<=packed_base_video;
                    active_stride<=packed_stride_video;
                    active_format<=packed_format_video;
                end else begin
                    active_source<=SOURCE_VGA; active_width<=vga_width_video;
                    active_height<=vga_height_video; active_base<=0;
                    active_stride<=0; active_format<=0;
                end
                current_line_valid<=0; frame_epoch<=~frame_epoch;
                frame_prepare<=1; frame_ready<=0; frame_started<=0;
                bank0_valid<=0; bank1_valid<=0;
            end

            if (enable_video && frame_prepare && !request_active && active_width!=0 &&
                active_height!=0 && (active_source==SOURCE_VGA || active_base!=0)) begin
                request_source<=active_source; request_row<=0; request_bank<=0;
                request_epoch<=frame_epoch; request_base<=active_base;
                request_stride<=active_stride; request_width<=active_width;
                request_format<=active_format; request_toggle<=~request_toggle;
                request_active<=1; frame_prepare<=0;
            end

            if (hcount==0 && vcount<V_ACTIVE) begin
                current_line_valid<=0;
                if (vcount==0 && frame_ready) frame_started<=1;
                if (source_row_in_bank0) begin
                    current_bank<=0; current_line_valid<=1;
                end else if (source_row_in_bank1) begin
                    current_bank<=1; current_line_valid<=1;
                end else if (frame_started && enable_video) underflow_toggle<=~underflow_toggle;

                // Producers are strictly sequential.  This is essential for
                // the VGA renderer's row-scan/address state and also lets a
                // late producer catch up on a vertically repeated HDMI row
                // without silently skipping source memory.
                if (enable_video && frame_started && !request_active &&
                    request_row+1'b1<active_height &&
                    request_row+1'b1<=source_y+1'b1 &&
                    !(bank0_valid && bank0_row==request_row+1'b1) &&
                    !(bank1_valid && bank1_row==request_row+1'b1)) begin
                    request_source<=active_source;
                    request_row<=request_row+1'b1;
                    request_bank<=~request_bank;
                    request_epoch<=frame_epoch;
                    request_base<=active_base; request_stride<=active_stride;
                    request_width<=active_width; request_format<=active_format;
                    request_toggle<=~request_toggle; request_active<=1;
                end
            end

            if (hcount==H_TOTAL-1) begin
                hcount<=0;
                if (vcount==V_TOTAL-1) begin
                    vcount<=0; source_y<=0; v_phase<=0;
                end else begin
                    vcount<=vcount+1'b1;
                    if (vcount<V_ACTIVE-1) begin
                        if (v_phase+active_height>=V_ACTIVE) begin
                            v_phase<=v_phase+active_height-V_ACTIVE;
                            source_y<=source_y+1'b1;
                        end else v_phase<=v_phase+active_height;
                    end
                end
            end else hcount<=hcount+1'b1;
        end
    end

    logic line_write_enable, line_write_bank;
    logic [6:0] line_write_address;
    logic [127:0] line_write_data;
    logic vga_request_inflight, vga_finish_pending, vga_previous_de;
    logic [10:0] vga_x;
    logic [127:0] vga_pack, vga_pack_with_pixel;
    wire [15:0] vga_pixel_rgb565={vga_r[7:3],vga_g[7:2],vga_b[7:3]};
    logic vga_write_enable; logic [6:0] vga_write_address;
    logic [127:0] vga_write_data;
    always_comb begin
        vga_pack_with_pixel=vga_pack;
        vga_pack_with_pixel[vga_x[2:0]*16+:16]=vga_pixel_rgb565;
    end

    (* ram_style="distributed" *) logic [15:0] palette [0:255];
    logic loading, load_bank, load_failed, load_finish_pending;
    logic [1:0] load_format; logic [10:0] load_width, load_pixel;
    logic [39:0] load_aligned_address;
    logic [8:0] load_total_beats, load_issued_beats;
    logic [4:0] active_burst_beats; logic read_active;
    logic [255:0] byte_fifo; logic [5:0] byte_count;
    logic [3:0] skip_bytes; logic [127:0] load_pack, load_pack_with_pixel;
    logic [15:0] load_pixel_rgb565; logic [2:0] load_bytes_per_pixel;
    logic load_pixel_available, load_write_enable;
    logic [6:0] load_write_address; logic [127:0] load_write_data;
    always_comb begin
        case (load_format)
            1: begin load_bytes_per_pixel=1;
                     load_pixel_rgb565=palette[byte_fifo[7:0]]; end
            2: begin load_bytes_per_pixel=3;
                     load_pixel_rgb565={byte_fifo[23:19],byte_fifo[15:10],
                                        byte_fifo[7:3]}; end
            default: begin load_bytes_per_pixel=2;
                           load_pixel_rgb565=byte_fifo[15:0]; end
        endcase
        load_pixel_available=skip_bytes==0 && load_pixel<load_width &&
                             byte_count>=load_bytes_per_pixel;
        load_pack_with_pixel=load_pack;
        load_pack_with_pixel[load_pixel[2:0]*16+:16]=load_pixel_rgb565;
    end

    assign line_write_enable=vga_write_enable||load_write_enable;
    assign line_write_bank=load_bank;
    assign line_write_address=vga_write_enable?vga_write_address:load_write_address;
    assign line_write_data=vga_write_enable?vga_write_data:load_write_data;
    z486_scanout_line_buffer line_buffer0(
        .write_clk(aclk),.write_enable(line_write_enable&&!line_write_bank),
        .write_address(line_write_address),.write_data(line_write_data),
        .read_clk(video_clk),.read_address(line_read_address),.read_data(line0_word));
    z486_scanout_line_buffer line_buffer1(
        .write_clk(aclk),.write_enable(line_write_enable&&line_write_bank),
        .write_address(line_write_address),.write_data(line_write_data),
        .read_clk(video_clk),.read_address(line_read_address),.read_data(line1_word));

    (* ASYNC_REG="TRUE" *) logic request_meta, request_sync;
    logic request_seen, retrace_video;
    (* ASYNC_REG="TRUE" *) logic [1:0] source_meta;
    (* ASYNC_REG="TRUE" *) logic retrace_meta;
    (* ASYNC_REG="TRUE" *) logic [10:0] vcount_meta;
    logic previous_retrace;
    (* ASYNC_REG="TRUE" *) logic underflow_meta, underflow_sync;
    logic underflow_seen;
    wire unused_rid=&{1'b0,m_axi_rid};
    assign retrace_video=vcount>=V_ACTIVE;
    assign m_axi_arid=0; assign m_axi_arsize=3'd4;
    assign m_axi_arburst=2'b01; assign m_axi_arlock=0;
    assign m_axi_arcache=4'b0011; assign m_axi_arprot=0;
    assign m_axi_arqos=0;
    // A 32-byte elasticity FIFO permits legal AXI beat backpressure while the
    // decoder consumes one output pixel per 100 MHz cycle.
    assign memory_idle = !loading && !read_active && !m_axi_arvalid;
    assign m_axi_rready=read_active && byte_count<=16 &&
                        (skip_bytes==0 || byte_count==0);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            request_meta<=0; request_sync<=0; request_seen<=0;
            ack_toggle<=0; ack_ok<=0; vga_scanline_req<=0;
            vga_scanline_frame_start<=0; vga_scanline_y<=0;
            vga_request_inflight<=0; vga_finish_pending<=0;
            vga_previous_de<=0; vga_x<=0; vga_pack<=0;
            vga_write_enable<=0; vga_write_address<=0; vga_write_data<=0;
            loading<=0; load_bank<=0; load_failed<=0;
            load_finish_pending<=0; load_format<=0; load_width<=0;
            load_pixel<=0; load_aligned_address<=0;
            load_total_beats<=0; load_issued_beats<=0;
            active_burst_beats<=0; read_active<=0; byte_fifo<=0;
            byte_count<=0; skip_bytes<=0; load_pack<=0;
            load_write_enable<=0; load_write_address<=0; load_write_data<=0;
            m_axi_araddr<=0; m_axi_arlen<=0; m_axi_arvalid<=0;
            read_requests<=0; read_beats<=0; retrace_meta<=0;
            v_retrace<=0; vcount_meta<=0; v_retrace_count<=0;
            previous_retrace<=0; frame_count<=0; underflow_meta<=0;
            underflow_sync<=0; underflow_seen<=0; underflow_count<=0;
            source_meta<=SOURCE_VGA; current_source<=SOURCE_VGA;
            line_request_count<=0; line_completion_count<=0;
            outstanding_high_water<=0;
            sticky_underflow<=0; sticky_axi_error<=0;
        end else begin
            if (packed_palette_write)
                palette[packed_palette_address]<={packed_palette_data[17:13],
                    packed_palette_data[11:6],packed_palette_data[5:1]};
            request_meta<=request_toggle; request_sync<=request_meta;
            retrace_meta<=retrace_video; v_retrace<=retrace_meta;
            vcount_meta<=vcount; v_retrace_count<={1'b0,vcount_meta};
            previous_retrace<=v_retrace;
            source_meta<=active_source; current_source<=source_meta;
            if (v_retrace&&!previous_retrace) frame_count<=frame_count+1'b1;
            underflow_meta<=underflow_toggle; underflow_sync<=underflow_meta;
            if (underflow_sync!=underflow_seen) begin
                underflow_seen<=underflow_sync;
                underflow_count<=underflow_count+1'b1; sticky_underflow<=1;
            end
            vga_write_enable<=0; load_write_enable<=0;

            if (request_sync!=request_seen && !loading &&
                !vga_request_inflight && !vga_scanline_req) begin : accept_request
                logic [39:0] line_address, line_end;
                logic [2:0] bytes_per_pixel;
                request_seen<=request_sync; load_bank<=request_bank;
                line_request_count<=line_request_count+1'b1;
                if (request_source!=SOURCE_VGA && outstanding_high_water==0)
                    outstanding_high_water<=1;
                if (!enable) begin
                    // Drain the request toggle even if it crossed clock
                    // domains just as the guest stopped. No new bus work.
                    ack_ok<=0; ack_toggle<=request_sync;
                end else if (request_source==SOURCE_VGA) begin
                    vga_scanline_req<=1; vga_scanline_frame_start<=request_row==0;
                    vga_scanline_y<=request_row; vga_previous_de<=0;
                    vga_x<=0; vga_pack<=0;
                end else begin
                    bytes_per_pixel=request_format==1?1:request_format==2?3:2;
                    line_address=request_base+request_row*request_stride;
                    line_end=line_address+request_width*bytes_per_pixel;
                    load_aligned_address<=line_address&~40'hf;
                    skip_bytes<=line_address[3:0];
                    load_total_beats<=(line_address[3:0]+
                        request_width*bytes_per_pixel+15)>>4;
                    load_format<=request_format; load_width<=request_width;
                    load_pixel<=0; load_issued_beats<=0; byte_fifo<=0;
                    byte_count<=0; load_pack<=0;
                    load_failed<=line_address<memory_base ||
                        line_end>memory_base+memory_size;
                    loading<=1;
                    if (line_address<memory_base ||
                        line_end>memory_base+memory_size) sticky_axi_error<=1;
                end
            end

            if (vga_scanline_req&&vga_scanline_ready) begin
                vga_scanline_req<=0; vga_request_inflight<=1;
            end
            if (vga_ce&&vga_request_inflight) begin
                vga_previous_de<=vga_de;
                // The VGA timing pipeline deliberately exposes a small
                // prefetch/flush margin around some modes.  A line request,
                // however, has an exact logical width; never publish margin
                // pixels into the shared line buffer.
                if (vga_de && vga_x < request_width) begin
                    vga_pack<=vga_pack_with_pixel; vga_x<=vga_x+1'b1;
                    if (vga_x[2:0]==7) begin
                        vga_write_enable<=1; vga_write_address<=vga_x[9:3];
                        vga_write_data<=vga_pack_with_pixel;
                    end
                end
                if (vga_previous_de&&!vga_de) begin
                    if (vga_x[2:0]!=0) begin
                        vga_write_enable<=1; vga_write_address<=vga_x[9:3];
                        vga_write_data<=vga_pack;
                    end
                    vga_x<=0; vga_pack<=0;
                end
            end
            if (vga_request_inflight&&vga_scanline_done) begin
                vga_request_inflight<=0; vga_finish_pending<=1;
            end
            if (vga_finish_pending) begin
                vga_finish_pending<=0; ack_ok<=1; ack_toggle<=request_seen;
                line_completion_count<=line_completion_count+1'b1;
            end

            if (loading&&!load_failed&&!m_axi_arvalid&&!read_active&&
                load_issued_beats<load_total_beats) begin
                m_axi_araddr<=load_aligned_address+load_issued_beats*16;
                if (load_total_beats-load_issued_beats>16) begin
                    m_axi_arlen<=15; active_burst_beats<=16;
                end else begin
                    m_axi_arlen<=load_total_beats-load_issued_beats-1'b1;
                    active_burst_beats<=load_total_beats-load_issued_beats;
                end
                m_axi_arvalid<=1;
            end
            if (m_axi_arvalid&&m_axi_arready) begin
                m_axi_arvalid<=0; read_active<=1;
                load_issued_beats<=load_issued_beats+active_burst_beats;
                read_requests<=read_requests+1'b1;
            end
            if (m_axi_rvalid&&m_axi_rready) begin
                if (load_pixel_available) begin
                    byte_fifo <= (byte_fifo >> (load_bytes_per_pixel*8)) |
                        ({128'd0,m_axi_rdata} <<
                         ((byte_count-load_bytes_per_pixel)*8));
                    byte_count <= byte_count-load_bytes_per_pixel+16;
                end else begin
                    byte_fifo<=byte_fifo|
                        ({128'd0,m_axi_rdata}<<(byte_count*8));
                    byte_count<=byte_count+16;
                end
                read_beats<=read_beats+1'b1;
                if (m_axi_rresp!=0) begin sticky_axi_error<=1; load_failed<=1; end
                if (m_axi_rlast) read_active<=0;
            end else if (skip_bytes!=0&&byte_count!=0) begin
                byte_fifo<=byte_fifo>>8; byte_count<=byte_count-1'b1;
                skip_bytes<=skip_bytes-1'b1;
            end else if (load_pixel_available) begin
                byte_fifo<=byte_fifo>>(load_bytes_per_pixel*8);
                byte_count<=byte_count-load_bytes_per_pixel;
            end

            // Pixel packing is independent of accepting the next AXI beat;
            // the elasticity FIFO therefore sustains one decoded pixel/clock.
            if (load_pixel_available) begin
                load_pack<=load_pack_with_pixel; load_pixel<=load_pixel+1'b1;
                if (load_pixel[2:0]==7 || load_pixel+1'b1==load_width) begin
                    load_write_enable<=1;
                    load_write_address<=load_pixel[9:3];
                    load_write_data<=load_pack_with_pixel; load_pack<=0;
                end
                if (load_pixel+1'b1==load_width) load_finish_pending<=1;
            end
            if (load_finish_pending) begin
                load_finish_pending<=0; loading<=0; m_axi_arvalid<=0;
                ack_ok<=!load_failed; ack_toggle<=request_seen;
                if (!load_failed)
                    line_completion_count<=line_completion_count+1'b1;
            end else if (loading&&load_failed&&!read_active) begin
                loading<=0; m_axi_arvalid<=0; ack_ok<=0;
                ack_toggle<=request_seen;
            end
            // Unlike AXI, the VGA producer is reset with the guest and may
            // never complete its last accepted row. Cancel only VGA work;
            // all accepted DDR requests continue through the normal drain.
            if (!enable && (vga_scanline_req || vga_request_inflight || vga_finish_pending)) begin
                vga_scanline_req<=0; vga_request_inflight<=0; vga_finish_pending<=0;
                vga_write_enable<=0; vga_previous_de<=0; vga_x<=0; vga_pack<=0;
                ack_ok<=0; ack_toggle<=request_seen;
            end
        end
    end
endmodule
