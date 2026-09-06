// KV260 physical read cache. 64-byte lines, 128-bit data port. Writes are
// write-through in the bridge; a matching cached word is patched in parallel.
// Only explicit L1 fills allocate. All physical writers probe for coherence.
module z486_l2_cache #(
    parameter integer SIZE_KIB = 512,
    parameter integer SET_BITS = $clog2(SIZE_KIB * 1024 / 64)
) (
    input wire clk, reset_n, invalidate,
    output wire ready,
    input wire probe,
    input wire [31:0] address,
    input wire write,
    input wire [127:0] write_data,
    input wire [15:0] write_mask,
    output wire hit,
    output wire [127:0] read_data,
    input wire fill_valid,
    input wire fill_begin,
    input wire [31:0] fill_address,
    input wire [127:0] fill_data,
    input wire fill_commit
);
    localparam integer TAG_BITS = 26 - SET_BITS;
    localparam integer SETS = 1 << SET_BITS;
    wire [127:0] data_q;
    wire [TAG_BITS:0] tag_q;
    reg [31:0] address_q;
    reg [127:0] write_data_q;
    reg [15:0] write_mask_q;
    reg probe_q, write_q;
    reg scrubbing;
    reg [SET_BITS-1:0] scrub_index;
    wire [SET_BITS-1:0] probe_set = address[SET_BITS+5:6];
    wire [SET_BITS-1:0] fill_set = fill_address[SET_BITS+5:6];
    wire [SET_BITS+1:0] probe_word = address[SET_BITS+5:4];
    wire [SET_BITS+1:0] fill_word = fill_address[SET_BITS+5:4];
    assign ready = reset_n && !invalidate && !scrubbing;
    assign hit = ready && probe_q && tag_q[TAG_BITS] &&
                 tag_q[TAG_BITS-1:0] == address_q[31:SET_BITS+6];
    assign read_data = data_q;
    reg [127:0] patched;
    always @* begin
        patched = data_q;
        for (integer b = 0; b < 16; b = b + 1)
            if (write_mask_q[b]) patched[b*8+:8] = write_data_q[b*8+:8];
    end
    // Explicit single write ports: fill/patch and scrub/commit are muxed
    // before the RAM, not represented as separate inferred memory ports.
    // Never reset RAM contents. Tags are scrubbed; data is overwritten on fill.
    wire data_we = fill_valid || (hit && write_q);
    wire [SET_BITS+1:0] data_wa = fill_valid ? fill_word : address_q[SET_BITS+5:4];
    wire [127:0] data_wd = fill_valid ? fill_data : patched;
    wire tag_we = scrubbing || (ready && (fill_begin || fill_commit));
    wire [SET_BITS-1:0] tag_wa = scrubbing ? scrub_index : fill_set;
    wire [TAG_BITS:0] tag_wd = (scrubbing || fill_begin) ? 0 :
                              {1'b1, fill_address[31:SET_BITS+6]};
    z486_l2_ram #(.WIDTH(128), .ADDR_BITS(SET_BITS+2), .PRIMITIVE("ultra"))
        data_ram (clk, data_we, data_wa, data_wd, probe, probe_word, data_q);
    z486_l2_ram #(.WIDTH(TAG_BITS+1), .ADDR_BITS(SET_BITS), .PRIMITIVE("block"))
        tag_ram (clk, tag_we, tag_wa, tag_wd, probe, probe_set, tag_q);
    always @(posedge clk) begin
        if (!reset_n || invalidate) begin
            scrubbing <= 1;
            scrub_index <= 0;
            probe_q <= 0;
            write_q <= 0;
        end else begin
            if (scrubbing) begin
                scrub_index <= scrub_index + 1'b1;
                if (&scrub_index) scrubbing <= 0;
            end
            probe_q <= probe && ready;
            write_q <= write;
            address_q <= address;
            write_data_q <= write_data;
            write_mask_q <= write_mask;
        end
    end
endmodule

// One-cycle synchronous lookup, no reset or initialization of the array.
// The bridge serializes probes and updates; same-address read/write is unused.
module z486_l2_ram #(
    parameter integer WIDTH = 128,
    parameter integer ADDR_BITS = 15,
    parameter PRIMITIVE = "ultra"
) (
    input wire clk, write_enable,
    input wire [ADDR_BITS-1:0] write_address,
    input wire [WIDTH-1:0] write_data,
    input wire read_enable,
    input wire [ADDR_BITS-1:0] read_address,
    output wire [WIDTH-1:0] read_data
);
`ifdef VERILATOR
    reg [WIDTH-1:0] storage [0:(1<<ADDR_BITS)-1];
    reg [WIDTH-1:0] read_q;
    assign read_data = read_q;
    always @(posedge clk) begin
        if (write_enable) storage[write_address] <= write_data;
        if (read_enable)
            read_q <= storage[read_address];
    end
`else
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_BITS), .ADDR_WIDTH_B(ADDR_BITS),
        .AUTO_SLEEP_TIME(0), .BYTE_WRITE_WIDTH_A(WIDTH), .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"), .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"), .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"), .MEMORY_PRIMITIVE(PRIMITIVE),
        .MEMORY_SIZE(WIDTH * (1<<ADDR_BITS)), .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(WIDTH), .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"), .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(1), .USE_EMBEDDED_CONSTRAINT(0), .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"), .WRITE_DATA_WIDTH_A(WIDTH),
        .WRITE_MODE_B("read_first")
    ) memory (
        .dbiterrb(), .sbiterrb(), .doutb(read_data),
        .addra(write_address), .addrb(read_address), .clka(clk), .clkb(clk),
        .dina(write_data), .ena(write_enable), .enb(read_enable),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(1'b0), .sleep(1'b0), .wea(write_enable)
    );
`endif
endmodule
