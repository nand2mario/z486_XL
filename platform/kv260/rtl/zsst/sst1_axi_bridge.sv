`timescale 1ns/1ps

// Convert the portable zSST memory stream to a 128-bit AXI4 HP master.
// Sixteen local AXI IDs preserve the core's eight-bit tags across the PS port
// and allow independent cache fills to complete out of issue order.  Writes
// use one ordered AXI ID, but are queued and issued without waiting for earlier
// B responses.  This is important on the ZynqMP HP port, where a response can
// arrive tens of renderer clocks after AW/W have been accepted.
module sst1_axi_bridge (
    input  logic                    aclk,
    input  logic                    aresetn,
    input  logic                    req_valid,
    output logic                    req_ready,
    input  sst1_pkg::sst1_mem_req_t req,
    output logic                    rsp_valid,
    input  logic                    rsp_ready,
    output sst1_pkg::sst1_mem_rsp_t rsp,
    output logic [31:0]             read_requests,
    output logic [31:0]             read_beats,
    output logic [31:0]             write_requests,
    output logic [31:0]             write_beats,
    output logic [4:0]              outstanding_reads,
    output logic                    writes_idle,
    output logic                    idle,
    output logic                    sticky_error,

    output logic [3:0]              m_axi_awid,
    output logic [39:0]             m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awlock,
    output logic [3:0]              m_axi_awcache,
    output logic [2:0]              m_axi_awprot,
    output logic [3:0]              m_axi_awqos,
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,
    output logic [127:0]            m_axi_wdata,
    output logic [15:0]             m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,
    input  logic [3:0]              m_axi_bid,
    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,
    output logic [3:0]              m_axi_arid,
    output logic [39:0]             m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arlock,
    output logic [3:0]              m_axi_arcache,
    output logic [2:0]              m_axi_arprot,
    output logic [3:0]              m_axi_arqos,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,
    input  logic [3:0]              m_axi_rid,
    input  logic [127:0]            m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready
);
    import sst1_pkg::*;

    localparam int WRITE_FIFO_DEPTH = 32;
    localparam int WRITE_PTR_WIDTH = $clog2(WRITE_FIFO_DEPTH);
    localparam logic [WRITE_PTR_WIDTH:0] WRITE_FIFO_DEPTH_COUNT =
        {1'b1, {WRITE_PTR_WIDTH{1'b0}}};

    logic [15:0] read_slot_active;
    logic [7:0] read_slot_tag [0:15];
    logic free_slot_found;
    logic [3:0] free_slot;

    logic [39:0] write_fifo_addr [0:WRITE_FIFO_DEPTH-1];
    logic [127:0] write_fifo_data [0:WRITE_FIFO_DEPTH-1];
    logic [15:0] write_fifo_strb [0:WRITE_FIFO_DEPTH-1];
    logic [WRITE_PTR_WIDTH-1:0] write_fifo_push_ptr;
    logic [WRITE_PTR_WIDTH-1:0] write_fifo_issue_ptr;
    logic [WRITE_PTR_WIDTH:0] write_fifo_count;
    logic [WRITE_PTR_WIDTH:0] write_outstanding;
    logic write_aw_sent;
    logic write_w_sent;
    logic write_fifo_full;
    logic write_can_issue;
    logic write_push;
    logic write_aw_fire;
    logic write_w_fire;
    logic write_issue;
    logic write_response;

    always_comb begin
        free_slot_found = 1'b0;
        free_slot = 4'd0;
        for (int search_slot = 0; search_slot < 16; search_slot = search_slot + 1)
            if (!read_slot_active[search_slot] && !free_slot_found) begin
                free_slot_found = 1'b1;
                free_slot = search_slot[3:0];
            end
        req_ready = req.write ? ((!write_fifo_full || write_issue) &&
                                 req.beats == 1) :
                                (!m_axi_arvalid && free_slot_found && req.beats != 0);
        outstanding_reads = 5'd0;
        for (int count_slot = 0; count_slot < 16; count_slot = count_slot + 1)
            outstanding_reads = outstanding_reads + read_slot_active[count_slot];
    end

    assign rsp_valid = m_axi_rvalid;
    assign rsp.rdata = m_axi_rdata;
    assign rsp.tag = read_slot_tag[m_axi_rid];
    assign rsp.last = m_axi_rlast;
    assign rsp.error = m_axi_rresp != 2'b00 || !read_slot_active[m_axi_rid];
    assign m_axi_rready = rsp_ready;

    assign m_axi_awid = 4'd0;
    assign m_axi_awlen = 8'd0;
    assign m_axi_awsize = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awqos = 4'b0000;
    assign m_axi_wlast = 1'b1;
    assign m_axi_arsize = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arqos = 4'b0000;

    assign write_fifo_full = write_fifo_count == WRITE_FIFO_DEPTH_COUNT;
    assign writes_idle = write_fifo_count == 0 && write_outstanding == 0 &&
                         !write_aw_sent && !write_w_sent;
    assign idle = writes_idle && read_slot_active == 0 && !m_axi_arvalid;
    // If a response retires this cycle, its slot can be replaced immediately.
    assign write_can_issue = write_fifo_count != 0 &&
                             (write_outstanding != WRITE_FIFO_DEPTH_COUNT ||
                              (m_axi_bvalid && m_axi_bready));
    assign m_axi_awaddr = write_fifo_addr[write_fifo_issue_ptr];
    assign m_axi_wdata = write_fifo_data[write_fifo_issue_ptr];
    assign m_axi_wstrb = write_fifo_strb[write_fifo_issue_ptr];
    assign m_axi_awvalid = write_can_issue && !write_aw_sent;
    assign m_axi_wvalid = write_can_issue && !write_w_sent;
    assign m_axi_bready = write_outstanding != 0;

    assign write_push = req_valid && req_ready && req.write;
    assign write_aw_fire = m_axi_awvalid && m_axi_awready;
    assign write_w_fire = m_axi_wvalid && m_axi_wready;
    assign write_issue = write_can_issue &&
                         (write_aw_sent || write_aw_fire) &&
                         (write_w_sent || write_w_fire);
    assign write_response = m_axi_bvalid && m_axi_bready;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            read_slot_active <= 16'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_arid <= 4'd0;
            m_axi_araddr <= 40'd0;
            m_axi_arlen <= 8'd0;
            write_fifo_push_ptr <= '0;
            write_fifo_issue_ptr <= '0;
            write_fifo_count <= '0;
            write_outstanding <= '0;
            write_aw_sent <= 1'b0;
            write_w_sent <= 1'b0;
            read_requests <= 32'd0;
            read_beats <= 32'd0;
            write_requests <= 32'd0;
            write_beats <= 32'd0;
            sticky_error <= 1'b0;
            for (int reset_slot = 0; reset_slot < 16; reset_slot = reset_slot + 1)
                read_slot_tag[reset_slot] <= 8'd0;
        end else begin
            if (m_axi_arvalid && m_axi_arready)
                m_axi_arvalid <= 1'b0;
            if (write_w_fire)
                write_beats <= write_beats + 1'b1;

            if (req_valid && req_ready) begin
                if (req.write) begin
                    write_fifo_addr[write_fifo_push_ptr] <= req.addr;
                    write_fifo_data[write_fifo_push_ptr] <= req.wdata;
                    write_fifo_strb[write_fifo_push_ptr] <= req.wstrb;
                    write_fifo_push_ptr <= write_fifo_push_ptr + 1'b1;
                    write_requests <= write_requests + 1'b1;
                end else begin
                    read_slot_active[free_slot] <= 1'b1;
                    read_slot_tag[free_slot] <= req.tag;
                    m_axi_arid <= free_slot;
                    m_axi_araddr <= req.addr;
                    m_axi_arlen <= req.beats - 1'b1;
                    m_axi_arvalid <= 1'b1;
                    read_requests <= read_requests + 1'b1;
                end
            end

            case ({write_push, write_issue})
                2'b10: write_fifo_count <= write_fifo_count + 1'b1;
                2'b01: write_fifo_count <= write_fifo_count - 1'b1;
                default: ;
            endcase

            if (write_issue) begin
                write_fifo_issue_ptr <= write_fifo_issue_ptr + 1'b1;
                write_aw_sent <= 1'b0;
                write_w_sent <= 1'b0;
            end else begin
                if (write_aw_fire)
                    write_aw_sent <= 1'b1;
                if (write_w_fire)
                    write_w_sent <= 1'b1;
            end

            case ({write_issue, write_response})
                2'b10: write_outstanding <= write_outstanding + 1'b1;
                2'b01: write_outstanding <= write_outstanding - 1'b1;
                default: ;
            endcase

            if (m_axi_rvalid && m_axi_rready) begin
                read_beats <= read_beats + 1'b1;
                if (m_axi_rresp != 2'b00 || !read_slot_active[m_axi_rid])
                    sticky_error <= 1'b1;
                if (m_axi_rlast)
                    read_slot_active[m_axi_rid] <= 1'b0;
            end
            if (write_response) begin
                if (m_axi_bresp != 2'b00)
                    sticky_error <= 1'b1;
            end
        end
    end
endmodule
