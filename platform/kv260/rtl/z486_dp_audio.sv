`timescale 1ns/1ps

module z486_dp_audio (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] sample_l,
    input  wire [15:0] sample_r,
    input  wire  [1:0] boost,
    output wire [31:0] m_axis_tdata,
    output wire  [7:0] m_axis_tid,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready
);

reg active;
reg channel;
reg [7:0] block_frame;
reg [23:0] left_sample;
reg [23:0] right_sample;

function automatic [23:0] boosted_sample;
    input [15:0] value;
    input [1:0] shift;
    reg signed [17:0] extended;
    begin
        extended = $signed({{2{value[15]}}, value});
        extended = extended <<< shift;
        if (extended > 18'sd32767)
            boosted_sample = {16'h7fff, 8'h00};
        else if (extended < -18'sd32768)
            boosted_sample = {16'h8000, 8'h00};
        else
            boosted_sample = {extended[15:0], 8'h00};
    end
endfunction

// Consumer PCM, 48 kHz. IEC60958 transmits each status byte LSB first, so
// the 48 kHz code (byte 3 = 2) appears in frame 25.
wire channel_status = block_frame == 8'd25;
wire [23:0] active_sample = !channel ? left_sample : right_sample;
wire [3:0] preamble = !channel ?
    (block_frame == 0 ? 4'b0001 : 4'b0010) : 4'b0011;
wire parity = (^active_sample) ^ channel_status;

// The ZynqMP DisplayPort audio input paces IEC60958 subframes with TREADY.
// Keep a subframe offered continuously; adding a second 512-clock divider here
// can miss the sink's ready windows and starve its audio packetizer.
assign m_axis_tvalid = active;
assign m_axis_tid = {7'd0, channel};
assign m_axis_tdata = {parity, channel_status, 2'b00,
                       active_sample, preamble};

always @(posedge clk) begin
    if (!resetn) begin
        active <= 0;
        channel <= 0;
        block_frame <= 0;
        left_sample <= 0;
        right_sample <= 0;
    end else begin
        if (!active) begin
            left_sample <= boosted_sample(sample_l, boost);
            right_sample <= boosted_sample(sample_r, boost);
            active <= 1;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            if (!channel) begin
                channel <= 1;
            end else begin
                channel <= 0;
                block_frame <= block_frame == 191 ? 0 : block_frame + 1'b1;
                left_sample <= boosted_sample(sample_l, boost);
                right_sample <= boosted_sample(sample_r, boost);
            end
        end
    end
end

endmodule
