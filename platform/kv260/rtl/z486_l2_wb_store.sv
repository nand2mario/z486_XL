// Storage for the write-back L2 controller. One synchronous probe port and
// one explicitly multiplexed update port. Whole-array scrub is HARD reset
// only: soft flush must walk valid/dirty victims and write them back first.
module z486_l2_wb_store #(
    parameter integer SIZE_KIB = 512,
    parameter integer SET_BITS = $clog2(SIZE_KIB*1024/64)
) (
    input wire clk, reset_n,
    output wire ready,
    input wire probe,
    input wire [31:0] address,
    output wire hit, valid, dirty,
    output wire [31:0] victim_address,
    output wire [127:0] read_data,
    // Actions refer to the most recent probe; no simultaneous probe/update
    // to the same location. Controller serializes lookup and modification.
    input wire patch,
    input wire [127:0] patch_data,
    input wire [15:0] patch_mask,
    input wire clean,
    input wire invalidate,
    // A fill installs four words and publishes its tag only on commit.
    // Controller must preserve a dirty victim until successful writeback.
    input wire fill,
    input wire [31:0] fill_address,
    input wire [127:0] fill_data,
    input wire commit
);
    localparam integer TAG_BITS = 26-SET_BITS;
    reg scrubbing;
    reg [SET_BITS-1:0] scrub_set;
    reg [31:0] address_q;
    reg probe_q;
    wire [TAG_BITS+1:0] tag_q;
    wire [127:0] data_q;
    assign ready = reset_n && !scrubbing;
    assign valid = ready && probe_q && tag_q[TAG_BITS];
    assign dirty = valid && tag_q[TAG_BITS+1];
    assign hit = valid && tag_q[TAG_BITS-1:0] == address_q[31:SET_BITS+6];
    assign victim_address = {tag_q[TAG_BITS-1:0],address_q[SET_BITS+5:6],6'b0};
    assign read_data = data_q;
    reg [127:0] merged;
    always @* begin
        merged = data_q;
        for (integer b=0;b<16;b=b+1)
            if (patch_mask[b]) merged[b*8+:8] = patch_data[b*8+:8];
    end
    wire patch_fire = ready && patch && hit;
    wire data_we = ready && (fill || patch_fire);
    wire [SET_BITS+1:0] data_wa = fill ? fill_address[SET_BITS+5:4] : address_q[SET_BITS+5:4];
    wire [127:0] data_wd = fill ? fill_data : merged;
    wire tag_we = scrubbing || (ready && (commit || patch_fire || clean || invalidate));
    wire [SET_BITS-1:0] tag_wa = scrubbing ? scrub_set :
        commit ? fill_address[SET_BITS+5:6] : address_q[SET_BITS+5:6];
    wire [TAG_BITS+1:0] tag_wd = (scrubbing || invalidate) ? 0 :
        commit ? {2'b01,fill_address[31:SET_BITS+6]} :
        {patch_fire,tag_q[TAG_BITS:0]};
    z486_l2_ram #(.WIDTH(128),.ADDR_BITS(SET_BITS+2),.PRIMITIVE("ultra"))
        data_ram(clk,data_we,data_wa,data_wd,probe && ready,address[SET_BITS+5:4],data_q);
    z486_l2_ram #(.WIDTH(TAG_BITS+2),.ADDR_BITS(SET_BITS),.PRIMITIVE("block"))
        tag_ram(clk,tag_we,tag_wa,tag_wd,probe && ready,address[SET_BITS+5:6],tag_q);
    always @(posedge clk) begin
        if (!reset_n) begin
            scrubbing <= 1;
            scrub_set <= 0;
            probe_q <= 0;
            address_q <= 0;
        end else begin
            if (scrubbing) begin
                scrub_set <= scrub_set+1'b1;
                if (&scrub_set) scrubbing <= 0;
            end
            if (probe) begin
                address_q <= address;
                probe_q <= ready;
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if (ready) begin
        assert (!(patch && fill)) else $fatal(1,"WB storage has conflicting data writers");
        assert (!(invalidate && dirty)) else $fatal(1,"WB storage would discard dirty data");
        assert (!patch || hit) else $fatal(1,"WB patch without a matching line");
        assert (!(clean && (commit || patch || invalidate)))
            else $fatal(1,"WB clean overlaps another tag operation");
    end
`endif
endmodule
