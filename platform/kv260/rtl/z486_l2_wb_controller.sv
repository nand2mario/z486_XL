// Normalized ordinary-RAM cache interface. The platform adapter routes every
// CPU/DMA/auxiliary access to cacheable RAM here, with byte lanes prealigned.
// The line transport has independent read and write channels: a dirty victim
// writeback overlaps the replacement read. Responses follow request acceptance.
// Base-address remapping must first complete flush using the OLD physical base.
module z486_l2_wb_controller #(
    parameter integer SIZE_KIB=512,
    parameter integer SET_BITS=$clog2(SIZE_KIB*1024/64)
) (
    input wire clk, reset_n,
    input wire request_valid, request_write,
    input wire [31:0] request_address,
    input wire [127:0] request_data,
    input wire [15:0] request_mask,
    output wire request_ready,
    output reg response_valid,
    output reg [127:0] response_data,
    input wire flush,
    output reg flush_done,
    output wire idle, error,
    input wire retry,
    output wire read_valid,
    input wire read_ready,
    output wire [31:0] read_address,
    input wire read_done, read_error,
    input wire [511:0] read_line,
    output wire writeback_valid,
    input wire writeback_ready,
    output reg [31:0] writeback_address,
    output reg [511:0] writeback_line,
    input wire writeback_done, writeback_error
);
    typedef enum logic [4:0] {
        IDLE, LOOK, CHECK, EVICT_LOOK, EVICT_CAPTURE, WRITE_SEND,
        WRITE_WAIT, READ_SEND, READ_WAIT, JOIN, CLEAN, CLEAN_LOOK,
        DROP, INSTALL, ADVANCE, FAILED
    } state_t;
    state_t state;
    reg [31:0] address_q;
    reg [127:0] data_q;
    reg [15:0] mask_q;
    reg write_q, flushing, flush_requested, flush_seen;
    reg [SET_BITS-1:0] scan_set;
    reg [1:0] word_index;
    reg need_evict, wb_pending, wb_failed, rd_failed;
    reg [511:0] fill_buffer;
    wire storage_ready, hit, valid, dirty;
    wire [127:0] word_data;
    wire [31:0] victim_address;
    wire probe = state==LOOK || state==EVICT_LOOK || state==CLEAN_LOOK;
    wire [31:0] probe_address = state==CLEAN_LOOK ? writeback_address :
        state==EVICT_LOOK ? writeback_address+{26'd0,word_index,4'b0} :
        flushing ? {{(26-SET_BITS){1'b0}},scan_set,6'b0} : address_q;
    wire invalidate = state==DROP || (state==CHECK &&
        ((flushing && !dirty) || (!flushing && !hit && !dirty)));
    z486_l2_wb_store #(.SIZE_KIB(SIZE_KIB)) storage (
        .clk, .reset_n, .ready(storage_ready), .probe, .address(probe_address),
        .hit, .valid, .dirty, .victim_address, .read_data(word_data),
        .patch(state==CHECK && !flushing && hit && write_q),
        .patch_data(data_q), .patch_mask(mask_q), .clean(state==CLEAN),
        .invalidate, .fill(state==INSTALL),
        .fill_address({address_q[31:6],word_index,4'b0}),
        .fill_data(fill_buffer[word_index*128+:128]),
        .commit(state==INSTALL && word_index==3)
    );
    assign request_ready = state==IDLE && storage_ready && !flush && !flush_requested;
    assign idle = state==IDLE && storage_ready && !flush_requested && (!flush || flush_seen);
    assign error = state==FAILED;
    assign read_valid = state==READ_SEND;
    assign read_address = {address_q[31:6],6'b0};
    assign writeback_valid = state==WRITE_SEND;
    always @(posedge clk) begin
        if (!reset_n) begin
            state<=IDLE; response_valid<=0; response_data<=0;
            flush_done<=0; flush_requested<=0; flush_seen<=0; flushing<=0;
            scan_set<=0; word_index<=0; address_q<=0; data_q<=0; mask_q<=0; write_q<=0;
            need_evict<=0; wb_pending<=0; wb_failed<=0; rd_failed<=0;
            writeback_address<=0; writeback_line<=0; fill_buffer<=0;
        end else begin
            response_valid<=0; flush_done<=0;
            if (!flush) flush_seen<=0;
            if (flush && !flush_seen) begin flush_requested<=1; flush_seen<=1; end
            if (writeback_done && wb_pending) begin
                wb_pending<=0;
                if (writeback_error) wb_failed<=1;
            end
            case(state)
                IDLE: if (storage_ready) begin
                    if (flush_requested) begin
                        flushing<=1; scan_set<=0; state<=LOOK;
                    end else if (request_valid && request_ready) begin
                        flushing<=0; address_q<=request_address;
                        data_q<=request_data; mask_q<=request_mask; write_q<=request_write;
                        state<=LOOK;
                    end
                end
                LOOK: state<=CHECK;
                CHECK: begin
                    wb_failed<=0; rd_failed<=0; word_index<=0;
                    if (!flushing && hit) begin
                        response_data<=word_data; response_valid<=1; state<=IDLE;
                    end else if (dirty) begin
                        need_evict<=1; writeback_address<=victim_address;
                        state<=EVICT_LOOK;
                    end else if (flushing) state<=ADVANCE;
                    else begin need_evict<=0; state<=READ_SEND; end
                end
                EVICT_LOOK: state<=EVICT_CAPTURE;
                EVICT_CAPTURE: begin
                    writeback_line[word_index*128+:128]<=word_data;
                    if (word_index==3) state<=WRITE_SEND;
                    else begin word_index<=word_index+1'b1; state<=EVICT_LOOK; end
                end
                WRITE_SEND: if (writeback_ready) begin
                    wb_pending<=1;
                    state<=flushing ? WRITE_WAIT : READ_SEND;
                end
                WRITE_WAIT: if (!wb_pending) begin
                    state<=wb_failed ? FAILED : CLEAN;
                end
                READ_SEND: if (read_ready) state<=READ_WAIT;
                READ_WAIT: if (read_done) begin
                    fill_buffer<=read_line; rd_failed<=read_error;
                    state<=JOIN;
                end
                JOIN: if (!wb_pending) begin
                    if (wb_failed || rd_failed) state<=FAILED;
                    else if (need_evict) state<=CLEAN;
                    else begin word_index<=0; state<=INSTALL; end
                end
                CLEAN: state<=CLEAN_LOOK;
                CLEAN_LOOK: state<=DROP;
                DROP: begin
                    word_index<=0; state<=flushing ? ADVANCE : INSTALL;
                end
                INSTALL: begin
                    if (word_index==3) state<=LOOK;
                    else word_index<=word_index+1'b1;
                end
                ADVANCE: begin
                    if (&scan_set) begin
                        flush_done<=1; flush_requested<=0; flushing<=0; state<=IDLE;
                    end else begin scan_set<=scan_set+1'b1; state<=LOOK; end
                end
                // Keep victim RAM and its full buffered copy on an error.
                // Retry is explicit; failed writebacks cannot make idle true.
                FAILED: if (retry) begin
                    wb_failed<=0; rd_failed<=0;
                    state<=wb_failed ? WRITE_SEND : READ_SEND;
                end
                default: state<=FAILED;
            endcase
        end
    end
endmodule
