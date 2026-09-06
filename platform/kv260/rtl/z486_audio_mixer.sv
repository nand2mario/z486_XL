module z486_audio_mixer (
    input  wire        clk,
    input  wire        reset,
    input  wire        speaker_out,
    input  wire        sbp,
    input  wire  [1:0] vol_spk,
    input  wire  [4:0] vol_master_l,
    input  wire  [4:0] vol_master_r,
    input  wire  [4:0] vol_voice_l,
    input  wire  [4:0] vol_voice_r,
    input  wire  [4:0] vol_midi_l,
    input  wire  [4:0] vol_midi_r,
    input  wire  [8:0] sample_cms_l,
    input  wire  [8:0] sample_cms_r,
    input  wire [15:0] sample_sb_l,
    input  wire [15:0] sample_sb_r,
    input  wire [15:0] sample_opl_l,
    input  wire [15:0] sample_opl_r,
    output wire [15:0] sample_l,
    output wire [15:0] sample_r
);

wire speaker_audio;
reg [16:0] speaker_sample;
reg [16:0] mix_sum_l;
reg [16:0] mix_sum_r;
reg [15:0] mix_dry_l;
reg [15:0] mix_dry_r;
reg [15:0] sample_l_r;
reg [15:0] sample_r_r;

synchronizer speaker_sync (
    .clk(clk),
    .in(speaker_out),
    .out(speaker_audio)
);

wire [15:0] master_l;
wire [15:0] master_r;
wire [15:0] sb_l;
wire [15:0] sb_r;
wire [15:0] opl_l;
wire [15:0] opl_r;
wire volume_valid;

sb_volume #(.NUM_CH(6), .SAMPLE_WIDTH(16)) volume (
    .clk(clk),
    .sbp(sbp),
    .volumes_in({vol_master_l, vol_master_r,
                 vol_voice_l,  vol_voice_r,
                 vol_midi_l,   vol_midi_r}),
    .samples_in({mix_dry_l,    mix_dry_r,
                 sample_sb_l,  sample_sb_r,
                 sample_opl_l, sample_opl_r}),
    .samples_out({master_l, master_r,
                  sb_l,     sb_r,
                  opl_l,    opl_r}),
    .valid(volume_valid)
);

always @(posedge clk) begin
    if (reset) begin
        speaker_sample <= 17'd0;
        mix_sum_l <= 17'd0;
        mix_sum_r <= 17'd0;
        mix_dry_l <= 16'd0;
        mix_dry_r <= 16'd0;
        sample_l_r <= 16'd0;
        sample_r_r <= 16'd0;
    end else begin
        speaker_sample <= ({5'd0, speaker_audio, 11'd0} >> ~vol_spk);

        if (volume_valid) begin
            sample_l_r <= master_l;
            sample_r_r <= master_r;
            mix_sum_l <= speaker_sample
                       + {2'b00, sample_cms_l, sample_cms_l[8:4]}
                       + {sb_l[15], sb_l}
                       + {opl_l[15], opl_l};
            mix_sum_r <= speaker_sample
                       + {2'b00, sample_cms_r, sample_cms_r[8:4]}
                       + {sb_r[15], sb_r}
                       + {opl_r[15], opl_r};
        end

        mix_dry_l <= (^mix_sum_l[16:15]) ?
            {mix_sum_l[16], {15{mix_sum_l[15]}}} : mix_sum_l[15:0];
        mix_dry_r <= (^mix_sum_r[16:15]) ?
            {mix_sum_r[16], {15{mix_sum_r[15]}}} : mix_sum_r[15:0];
    end
end

assign sample_l = sample_l_r;
assign sample_r = sample_r_r;

endmodule
