`timescale 1ns/1ps
// ABI 1.7: rising control[0] snapshots all banks without stopping the guest.
// Index 0..79 selects renderer counters; 128..143 selects board events.
// Counters wrap at 32 bits. Snapshot sequence changes after capture completes.
module zsst_board_perf (
    input logic clk, reset_n,
    input logic [31:0] control,
    input logic [15:0] read_index,
    input logic [15:0] events,
    input logic [63:0] renderer_data,
    output wire snapshot,
    output wire [31:0] read_data,
    output logic [31:0] sequence_number
);
    logic previous_request;
    logic [31:0] live [0:15];
    logic [31:0] shadow [0:15];
    assign snapshot = reset_n && control[0] && !previous_request;
    assign read_data = read_index < 80 ? renderer_data[31:0] :
                       (read_index >= 128 && read_index < 144) ?
                       shadow[read_index[3:0]] : 32'd0;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            previous_request <= 0;
            sequence_number <= 0;
            for (int i = 0; i < 16; i++) begin
                live[i] <= 0;
                shadow[i] <= 0;
            end
        end else begin
            previous_request <= control[0];
            for (int i = 0; i < 16; i++) begin
                if (events[i]) live[i] <= live[i] + 1'b1;
                if (snapshot) shadow[i] <= live[i];
            end
            if (snapshot) sequence_number <= sequence_number + 1'b1;
        end
    end
endmodule
