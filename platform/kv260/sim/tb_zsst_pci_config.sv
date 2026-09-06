`timescale 1ns/1ns

module tb_zsst_pci_config;
    logic clk = 0;
    logic reset_n = 0;
    logic [15:0] io_address = 0;
    logic io_read = 0;
    logic io_write = 0;
    logic [7:0] io_writedata = 0;
    wire [7:0] io_readdata;
    wire io_chip_select;
    wire memory_enable;
    wire [31:0] bar0_base;
    wire [31:0] init_enable;

    always #5 clk = ~clk;

    zsst_pci_config dut (.*);

    task automatic write_byte(input logic [15:0] address,
                              input logic [7:0] value);
        begin
            @(negedge clk);
            io_address = address;
            io_writedata = value;
            io_write = 1;
            @(negedge clk);
            io_write = 0;
        end
    endtask

    task automatic read_byte(input logic [15:0] address,
                             output logic [7:0] value);
        begin
            @(negedge clk);
            io_address = address;
            io_read = 1;
            @(negedge clk);
            io_read = 0;
            @(negedge clk);
            value = io_readdata;
        end
    endtask

    task automatic set_config_address(input logic [31:0] value);
        integer lane;
        begin
            for (lane = 0; lane < 4; lane = lane + 1)
                write_byte(16'h0cf8 + lane, value[8 * lane +: 8]);
        end
    endtask

    task automatic write_config_dword(input logic [7:0] offset,
                                      input logic [31:0] value);
        integer lane;
        begin
            set_config_address(32'h8000_2800 | offset);
            for (lane = 0; lane < 4; lane = lane + 1)
                write_byte(16'h0cfc + lane, value[8 * lane +: 8]);
        end
    endtask

    task automatic read_config_dword(input logic [7:0] offset,
                                     output logic [31:0] value);
        integer lane;
        logic [7:0] byte_value;
        begin
            set_config_address(32'h8000_2800 | offset);
            for (lane = 0; lane < 4; lane = lane + 1) begin
                read_byte(16'h0cfc + lane, byte_value);
                value[8 * lane +: 8] = byte_value;
            end
        end
    endtask

    initial begin
        logic [31:0] value;
        repeat (4) @(posedge clk);
        reset_n = 1;

        if (bar0_base != 32'he000_0000 || !memory_enable)
            $fatal(1, "firmware resource defaults mismatch: BAR=%08x enable=%0d",
                   bar0_base, memory_enable);

        if (!((16'h0cf8 >= 16'h0cf8) && (16'h0cf8 <= 16'h0cff)))
            $fatal(1, "test error");
        io_address = 16'h0cf8;
        #1;
        if (!io_chip_select)
            $fatal(1, "configuration ports not selected");

        read_config_dword(8'h00, value);
        if (value != 32'h0001_121a)
            $fatal(1, "vendor/device mismatch: %08x", value);

        read_config_dword(8'h08, value);
        if (value != 32'h0400_0002)
            $fatal(1, "class/revision mismatch: %08x", value);

        write_config_dword(8'h10, 32'hffff_ffff);
        read_config_dword(8'h10, value);
        if (value != 32'hff00_0000)
            $fatal(1, "BAR size probe mismatch: %08x", value);

        write_config_dword(8'h10, 32'he000_0000);
        if (bar0_base != 32'he000_0000)
            $fatal(1, "BAR assignment mismatch: %08x", bar0_base);
        write_config_dword(8'h04, 32'h0000_0002);
        if (!memory_enable)
            $fatal(1, "memory enable did not set");

        write_config_dword(8'h40, 32'h1234_5678);
        read_config_dword(8'h40, value);
        if (value != 32'h1234_5678 || init_enable != value)
            $fatal(1, "initEnable mismatch: %08x", value);

        // A different BDF must return the PCI no-device value.
        set_config_address(32'h8000_3000);
        read_byte(16'h0cfc, value[7:0]);
        if (value[7:0] != 8'hff)
            $fatal(1, "nonexistent function responded: %02x", value[7:0]);

        $display("PASS: SST-1 PCI config mechanism, BAR probe, and enable");
        $finish;
    end
endmodule
