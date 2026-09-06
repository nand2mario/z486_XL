`timescale 1ns/1ps

// The AVPG DRM driver programs clk_in at twice the requested pixel rate.
// Both DRM-controlled enables share one BUFGCE_DIV so scaler and VTC see the
// same pixel-clock edge.
module z486_clock_gate_div2 (
    input wire clk_in,
    input wire enable_video,
    input wire enable_vtc,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 video_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME video_clk, FREQ_HZ 150000000" *)
    output wire video_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 vtc_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME vtc_clk, FREQ_HZ 150000000" *)
    output wire vtc_clk
);
wire pixel_clk;
wire enable = enable_video | enable_vtc;
BUFGCE_DIV #(.BUFGCE_DIVIDE(2)) pixel_clock_buffer (
    .I(clk_in), .CE(enable), .CLR(1'b0), .O(pixel_clk)
);
assign video_clk = pixel_clk;
assign vtc_clk = pixel_clk;
endmodule
