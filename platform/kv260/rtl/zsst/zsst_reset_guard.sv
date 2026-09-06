`timescale 1ns/1ps
// A guest reset is not an AXI fabric reset. Keep the bus master alive and
// hold its client in reset until every old response has been consumed.
module zsst_reset_guard (
    input logic clk, reset_n, soft_reset, bus_idle,
    output logic client_reset_n, reset_busy
);
    always_ff @(posedge clk) begin
        if (!reset_n || soft_reset)
            reset_busy <= 1'b1;
        else if (bus_idle)
            reset_busy <= 1'b0;
    end
    assign client_reset_n = reset_n && !soft_reset && !reset_busy;
endmodule
