`timescale 1ns/1ps

module tb_z486_dp_audio;
    logic clk = 0;
    logic resetn = 0;
    logic [15:0] sample_l = 16'h1234;
    logic [15:0] sample_r = 16'hf000;
    logic [1:0] boost = 0;
    logic ready = 1;
    wire [31:0] data;
    wire [7:0] id;
    wire valid;

    always #5 clk = ~clk;

    z486_dp_audio dut (
        .clk(clk), .resetn(resetn), .sample_l(sample_l), .sample_r(sample_r),
        .boost(boost), .m_axis_tdata(data), .m_axis_tid(id),
        .m_axis_tvalid(valid), .m_axis_tready(ready)
    );

    task automatic next_word(output logic [31:0] word,
                             output logic [7:0] word_id);
        begin
            while (!valid) @(negedge clk);
            word = data;
            word_id = id;
            @(posedge clk);
            #1;
        end
    endtask

    function automatic parity_ok(input logic [31:0] word);
        parity_ok = word[31] == ((^word[27:4]) ^ word[30]);
    endfunction

    initial begin
        logic [31:0] word;
        logic [31:0] held;
        logic [7:0] word_id;
        integer frame;

        repeat (3) @(posedge clk);
        resetn = 1;

        next_word(word, word_id);
        if (word_id != 0 || word[3:0] != 4'b0001 ||
            word[27:4] != 24'h123400 || word[30] || !parity_ok(word))
            $fatal(1, "bad first left subframe %08x id=%0d", word, word_id);
        next_word(word, word_id);
        if (word_id != 1 || word[3:0] != 4'b0011 ||
            word[27:4] != 24'hf00000 || word[30] || !parity_ok(word))
            $fatal(1, "bad first right subframe %08x id=%0d", word, word_id);

        // TREADY, not a local divider, controls the sample cadence.
        if (!valid || id != 0)
            $fatal(1, "next left subframe was not offered continuously");

        // AXI backpressure must hold the complete subframe stable.
        ready = 0;
        do @(negedge clk); while (!valid);
        held = data;
        repeat (12) begin
            @(negedge clk);
            if (!valid || data != held)
                $fatal(1, "audio word changed under backpressure");
        end
        ready = 1;
        word = data;
        word_id = id;
        @(posedge clk);
        #1;
        if (word != held || word_id != 0 || word[3:0] != 4'b0010)
            $fatal(1, "bad held left subframe word=%08x held=%08x id=%0d",
                   word, held, word_id);
        next_word(word, word_id);
        if (word_id != 1)
            $fatal(1, "right channel did not follow held left channel");

        // Reach IEC60958 frame 25, whose channel-status bit identifies 48 kHz.
        for (frame = 2; frame <= 25; frame = frame + 1) begin
            next_word(word, word_id);
            if (word_id != 0 || word[30] != (frame == 25) ||
                !parity_ok(word))
                $fatal(1, "bad channel status at frame %0d: %08x", frame, word);
            next_word(word, word_id);
            if (word_id != 1 || word[30] != (frame == 25) ||
                !parity_ok(word))
                $fatal(1, "bad right channel status at frame %0d", frame);
        end

        boost = 1;
        sample_l = 16'h3000;
        sample_r = 16'he000;
        // The current stereo pair was sampled at the preceding right-channel
        // handshake.  Consume it so the new mixer values are sampled.
        next_word(word, word_id);
        next_word(word, word_id);
        next_word(word, word_id);
        if (word[27:4] != 24'h600000)
            $fatal(1, "2x positive gain failed: %08x", word);
        next_word(word, word_id);
        if (word[27:4] != 24'hc00000)
            $fatal(1, "2x negative gain failed: %08x", word);

        boost = 2;
        sample_l = 16'h3000;
        sample_r = 16'he000;
        next_word(word, word_id);
        next_word(word, word_id);
        next_word(word, word_id);
        if (word[27:4] != 24'h7fff00)
            $fatal(1, "4x positive saturation failed: %08x", word);
        next_word(word, word_id);
        if (word[27:4] != 24'h800000)
            $fatal(1, "4x negative saturation failed: %08x", word);

        $display("PASS: 48 kHz DisplayPort audio framing, backpressure and boost");
        $finish;
    end
endmodule
