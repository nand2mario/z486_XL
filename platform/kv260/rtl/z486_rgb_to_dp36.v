`timescale 1ns/1ps

// DPSUB live input is three 12-bit components, MSB aligned.
module z486_rgb_to_dp36 (
    input wire [7:0] r,
    input wire [7:0] g,
    input wire [7:0] b,
    output wire [35:0] dp36
);
assign dp36 = {r, 4'b0000, g, 4'b0000, b, 4'b0000};
endmodule
