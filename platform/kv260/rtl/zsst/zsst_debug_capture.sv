`timescale 1ns/1ps
// Passive, finite capture. Disable clears the cursor; enable records until
// full. Mode 0 captures guest writes, mode 1 renderer memory requests.
module zsst_debug_capture (
    input logic clk, reset_n,
    input logic [31:0] control,
    input logic [15:0] read_index,
    output logic [31:0] read_data,
    output logic [31:0] status,
    input logic host_valid,
    input logic [23:0] host_address,
    input logic [31:0] host_data,
    input logic [3:0] host_be,
    input logic memory_valid,
    input sst1_pkg::sst1_mem_req_t memory_req
);
    (* ram_style = "block" *) logic [255:0] records [0:8191];
    logic [13:0] count;
    logic [255:0] read_record;
    logic [2:0] word_index;
    logic [255:0] record_data;
    logic valid;
    always_comb begin
        record_data = '0;
        if (control[1]) begin
            record_data[39:0] = memory_req.addr;
            record_data[167:40] = memory_req.wdata;
            record_data[183:168] = memory_req.wstrb;
            record_data[191:184] = memory_req.beats;
            record_data[199:192] = memory_req.tag;
            record_data[202:200] = memory_req.source;
            record_data[203] = memory_req.write;
        end else begin
            record_data[23:0] = host_address;
            record_data[55:24] = host_data;
            record_data[59:56] = host_be;
        end
        valid = control[1] ? memory_valid : host_valid;
        status = {18'd0, count};
        read_data = read_record[word_index*32 +: 32];
    end
    always_ff @(posedge clk) begin
        read_record <= records[read_index[15:3]];
        word_index <= read_index[2:0];
        if (!reset_n || !control[0])
            count <= '0;
        else if (valid && count < 14'd8192) begin
            records[count[12:0]] <= record_data;
            count <= count + 1'b1;
        end
    end
endmodule
