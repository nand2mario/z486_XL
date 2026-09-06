`timescale 1ns/1ps

// Minimal 1-PPC VTC 6.1 register subset used by the Xilinx DRM VTC bridge.
// Vivado 2024.2 offers only 4/8-PPC VTC 6.2 for K26, while DPSUB live input
// consumes one pixel per clock.
module z486_vtc_lite_1ppc (
    input wire s_axi_aclk, input wire s_axi_aresetn,
    input wire [8:0] s_axi_awaddr, input wire s_axi_awvalid,
    output reg s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid, output reg s_axi_wready,
    output wire [1:0] s_axi_bresp, output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [8:0] s_axi_araddr, input wire s_axi_arvalid,
    output reg s_axi_arready, output reg [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp, output reg s_axi_rvalid,
    input wire s_axi_rready,
    input wire pixel_clk, input wire pixel_resetn, input wire pixel_ce,
    output wire active_video, output wire hblank, output wire hsync,
    output wire vblank, output wire vsync
);

localparam [8:0] REG_CTL=9'h000, REG_VER=9'h010, REG_GASIZE=9'h060,
                 REG_GENC=9'h068, REG_GPOL=9'h06c, REG_GHSIZE=9'h070,
                 REG_GVSIZE=9'h074, REG_GHSYNC=9'h078,
                 REG_GVSYNC0=9'h080;
reg [31:0] reg_ctl, reg_gasize, reg_genc, reg_gpol, reg_ghsize,
           reg_gvsize, reg_ghsync, reg_gvsync0;
reg [8:0] awaddr_hold;
reg [31:0] wdata_hold;
reg [3:0] wstrb_hold;
reg aw_pending, w_pending;
assign s_axi_bresp = 0;
assign s_axi_rresp = 0;

function [31:0] merge_wstrb;
    input [31:0] old_value, new_value;
    input [3:0] write_strobe;
    integer i;
    begin
        merge_wstrb = old_value;
        for (i=0; i<4; i=i+1)
            if (write_strobe[i])
                merge_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
    end
endfunction

always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
        s_axi_awready<=0; s_axi_wready<=0; s_axi_bvalid<=0;
        s_axi_arready<=0; s_axi_rvalid<=0; s_axi_rdata<=0;
        aw_pending<=0; w_pending<=0; reg_ctl<=32'h2;
        reg_gasize<=0; reg_genc<=0; reg_gpol<=0; reg_ghsize<=0;
        reg_gvsize<=0; reg_ghsync<=0; reg_gvsync0<=0;
    end else begin
        s_axi_awready<=0; s_axi_wready<=0; s_axi_arready<=0;
        if (s_axi_awvalid && !aw_pending && !s_axi_bvalid) begin
            awaddr_hold<=s_axi_awaddr; aw_pending<=1; s_axi_awready<=1;
        end
        if (s_axi_wvalid && !w_pending && !s_axi_bvalid) begin
            wdata_hold<=s_axi_wdata; wstrb_hold<=s_axi_wstrb;
            w_pending<=1; s_axi_wready<=1;
        end
        if (aw_pending && w_pending && !s_axi_bvalid) begin
            case (awaddr_hold)
                REG_CTL: reg_ctl <= wdata_hold[31] ? 32'h2 :
                         merge_wstrb(reg_ctl,wdata_hold,wstrb_hold);
                REG_GASIZE: reg_gasize<=merge_wstrb(reg_gasize,wdata_hold,wstrb_hold);
                REG_GENC: reg_genc<=merge_wstrb(reg_genc,wdata_hold,wstrb_hold);
                REG_GPOL: reg_gpol<=merge_wstrb(reg_gpol,wdata_hold,wstrb_hold);
                REG_GHSIZE: reg_ghsize<=merge_wstrb(reg_ghsize,wdata_hold,wstrb_hold);
                REG_GVSIZE: reg_gvsize<=merge_wstrb(reg_gvsize,wdata_hold,wstrb_hold);
                REG_GHSYNC: reg_ghsync<=merge_wstrb(reg_ghsync,wdata_hold,wstrb_hold);
                REG_GVSYNC0: reg_gvsync0<=merge_wstrb(reg_gvsync0,wdata_hold,wstrb_hold);
                default: ;
            endcase
            aw_pending<=0; w_pending<=0; s_axi_bvalid<=1;
        end else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;

        if (s_axi_arvalid && !s_axi_rvalid) begin
            s_axi_arready<=1; s_axi_rvalid<=1;
            case (s_axi_araddr)
                REG_CTL: s_axi_rdata<=reg_ctl;
                REG_VER: s_axi_rdata<=32'h0001_0000;
                REG_GASIZE: s_axi_rdata<=reg_gasize;
                REG_GENC: s_axi_rdata<=reg_genc;
                REG_GPOL: s_axi_rdata<=reg_gpol;
                REG_GHSIZE: s_axi_rdata<=reg_ghsize;
                REG_GVSIZE: s_axi_rdata<=reg_gvsize;
                REG_GHSYNC: s_axi_rdata<=reg_ghsync;
                REG_GVSYNC0: s_axi_rdata<=reg_gvsync0;
                default: s_axi_rdata<=0;
            endcase
        end else if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
    end
end

(* ASYNC_REG="TRUE" *) reg [31:0] cfg_ctl_meta,cfg_ctl;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_gasize_meta,cfg_gasize;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_gpol_meta,cfg_gpol;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_ghsize_meta,cfg_ghsize;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_gvsize_meta,cfg_gvsize;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_ghsync_meta,cfg_ghsync;
(* ASYNC_REG="TRUE" *) reg [31:0] cfg_gvsync0_meta,cfg_gvsync0;
always @(posedge pixel_clk) begin
    if (!pixel_resetn) begin
        cfg_ctl_meta<=0; cfg_ctl<=0; cfg_gasize_meta<=0; cfg_gasize<=0;
        cfg_gpol_meta<=0; cfg_gpol<=0; cfg_ghsize_meta<=0; cfg_ghsize<=0;
        cfg_gvsize_meta<=0; cfg_gvsize<=0; cfg_ghsync_meta<=0; cfg_ghsync<=0;
        cfg_gvsync0_meta<=0; cfg_gvsync0<=0;
    end else begin
        cfg_ctl_meta<=reg_ctl; cfg_ctl<=cfg_ctl_meta;
        cfg_gasize_meta<=reg_gasize; cfg_gasize<=cfg_gasize_meta;
        cfg_gpol_meta<=reg_gpol; cfg_gpol<=cfg_gpol_meta;
        cfg_ghsize_meta<=reg_ghsize; cfg_ghsize<=cfg_ghsize_meta;
        cfg_gvsize_meta<=reg_gvsize; cfg_gvsize<=cfg_gvsize_meta;
        cfg_ghsync_meta<=reg_ghsync; cfg_ghsync<=cfg_ghsync_meta;
        cfg_gvsync0_meta<=reg_gvsync0; cfg_gvsync0<=cfg_gvsync0_meta;
    end
end

wire generator_enable=cfg_ctl[2];
wire [12:0] htotal=cfg_ghsize[12:0], vtotal=cfg_gvsize[12:0];
wire [12:0] hactive=cfg_gasize[12:0], vactive=cfg_gasize[28:16];
wire [12:0] hsync_start=cfg_ghsync[12:0], hsync_end=cfg_ghsync[28:16];
wire [12:0] vsync_start=cfg_gvsync0[12:0], vsync_end=cfg_gvsync0[28:16];
reg [12:0] hcount,vcount;
always @(posedge pixel_clk) begin
    if (!pixel_resetn || !generator_enable) begin hcount<=0; vcount<=0; end
    else if (pixel_ce) begin
        if (htotal<2 || hcount==htotal-1'b1) begin
            hcount<=0;
            if (vtotal<2 || vcount==vtotal-1'b1) vcount<=0;
            else vcount<=vcount+1'b1;
        end else hcount<=hcount+1'b1;
    end
end
wire hsync_raw=hcount>=hsync_start && hcount<hsync_end;
wire vsync_raw=vcount>=vsync_start && vcount<vsync_end;
assign active_video=generator_enable && hcount<hactive && vcount<vactive;
assign hblank=generator_enable && hcount>=hactive;
assign vblank=generator_enable && vcount>=vactive;
assign hsync=cfg_gpol[3] ? hsync_raw : ~hsync_raw;
assign vsync=cfg_gpol[2] ? vsync_raw : ~vsync_raw;
endmodule
