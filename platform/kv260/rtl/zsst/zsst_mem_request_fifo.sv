`timescale 1ns/1ps

// Registered boundary between the renderer/ring arbiter and the AXI bridge.
// In particular, AXI write-FIFO backpressure must not propagate through the
// complete renderer request path in the same cycle.  A shallow distributed
// RAM queue preserves one request/cycle throughput while breaking that path.
module zsst_mem_request_fifo #(
    parameter int DEPTH = 4
) (
    input  logic                    clk,
    input  logic                    reset_n,
    input  logic                    in_valid,
    output logic                    in_ready,
    input  sst1_pkg::sst1_mem_req_t in_req,
    output logic                    empty,
    output logic                    out_valid,
    input  logic                    out_ready,
    output sst1_pkg::sst1_mem_req_t out_req
);
    import sst1_pkg::*;

    localparam int POINTER_WIDTH = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);

    (* ram_style = "distributed" *)
    sst1_mem_req_t requests [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] read_pointer;
    logic [POINTER_WIDTH-1:0] write_pointer;
    logic [COUNT_WIDTH-1:0] count;
    logic push, pop;

    initial begin
        assert (DEPTH >= 2) else $fatal(1, "request FIFO depth must be >= 2");
        assert ((DEPTH & (DEPTH - 1)) == 0)
            else $fatal(1, "request FIFO depth must be a power of two");
    end

    // Deliberately do not include out_ready in in_ready.  This boundary is
    // what prevents bridge/AXI backpressure from becoming a long combinational
    // path into the TMU and FBI.  Once non-full, simultaneous pop/push still
    // sustains an initiation interval of one cycle.
    assign in_ready = count != DEPTH_COUNT;
    assign empty = count == 0;
    assign out_valid = count != 0;
    assign out_req = requests[read_pointer];
    assign push = in_valid && in_ready;
    assign pop = out_valid && out_ready;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            read_pointer <= '0;
            write_pointer <= '0;
            count <= '0;
        end else begin
            if (push) begin
                requests[write_pointer] <= in_req;
                write_pointer <= write_pointer + 1'b1;
            end
            if (pop)
                read_pointer <= read_pointer + 1'b1;

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
