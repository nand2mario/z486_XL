// Independent 64-byte read-fill and dirty-writeback transports. Physical base
// is captured at acceptance; the owner must flush before changing allocations.
// Only a successful B response permits the cache to release dirty ownership.
module z486_l2_line_axi (
    input wire clk,reset_n,
    input wire [39:0] memory_base,
    input wire read_valid,
    output wire read_ready,
    input wire [31:0] read_address,
    output reg read_done,read_error,
    output reg [511:0] read_line,
    input wire writeback_valid,
    output wire writeback_ready,
    input wire [31:0] writeback_address,
    input wire [511:0] writeback_line,
    output reg writeback_done,writeback_error,
    output wire idle,
    output reg [39:0] araddr,awaddr,
    output wire [7:0] arlen,awlen,
    output wire [2:0] arsize,awsize,
    output wire [1:0] arburst,awburst,
    output wire arvalid,awvalid,
    input wire arready,awready,
    input wire [127:0] rdata,
    input wire [1:0] rresp,bresp,
    input wire rvalid,rlast,bvalid,
    output wire rready,bready,
    output wire [127:0] wdata,
    output wire [15:0] wstrb,
    output wire wvalid,wlast,
    input wire wready
);
    reg rd_active,rd_address_sent,rd_bad;
    reg wr_active,wr_address_sent,wr_data_sent;
    reg [1:0] rd_beat,wr_beat;
    reg [511:0] write_buffer;
    assign read_ready=reset_n && !rd_active;
    assign writeback_ready=reset_n && !wr_active;
    assign idle=!rd_active && !wr_active;
    assign arlen=3; assign awlen=3;
    assign arsize=4; assign awsize=4;
    assign arburst=1; assign awburst=1;
    assign arvalid=rd_active && !rd_address_sent;
    assign awvalid=wr_active && !wr_address_sent;
    assign rready=rd_active && rd_address_sent;
    assign bready=wr_active && wr_address_sent && wr_data_sent;
    assign wvalid=wr_active && !wr_data_sent;
    assign wdata=write_buffer[wr_beat*128+:128];
    assign wstrb=16'hffff;
    assign wlast=wr_beat==3;
    always @(posedge clk) begin
        if(!reset_n) begin
            rd_active<=0; rd_address_sent<=0; rd_bad<=0; rd_beat<=0;
            wr_active<=0; wr_address_sent<=0; wr_data_sent<=0; wr_beat<=0;
            read_done<=0; read_error<=0; read_line<=0;
            writeback_done<=0; writeback_error<=0; write_buffer<=0;
            araddr<=0; awaddr<=0;
        end else begin
            read_done<=0; writeback_done<=0;
            if(read_valid && read_ready) begin
                rd_active<=1; rd_address_sent<=0; rd_bad<=0; rd_beat<=0;
                araddr<=memory_base+{8'b0,read_address[31:6],6'b0};
            end
            if(arvalid && arready) rd_address_sent<=1;
            if(rvalid && rready) begin
                read_line[rd_beat*128+:128]<=rdata;
                rd_bad<=rd_bad || rresp!=0 || (rlast!=(rd_beat==3));
                if(rlast) begin
                    read_error<=rd_bad || rresp!=0 || rd_beat!=3;
                    read_done<=1; rd_active<=0;
                end else rd_beat<=rd_beat+1'b1;
            end
            if(writeback_valid && writeback_ready) begin
                wr_active<=1; wr_address_sent<=0; wr_data_sent<=0; wr_beat<=0;
                awaddr<=memory_base+{8'b0,writeback_address[31:6],6'b0};
                write_buffer<=writeback_line;
            end
            if(awvalid && awready) wr_address_sent<=1;
            if(wvalid && wready) begin
                if(wlast) wr_data_sent<=1;
                else wr_beat<=wr_beat+1'b1;
            end
            if(bvalid && bready) begin
                writeback_done<=1; writeback_error<=bresp!=0; wr_active<=0;
            end
        end
    end
endmodule
