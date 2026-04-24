`timescale 1ns / 1ps

module uart_tx_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 1024
)(
    input  wire                  clk,
    input  wire                  reset,
    
    // CPU interface for enqueuing transmit data
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  write_en,
    output wire                  full,
    
    // Interface driving the UART transmission state machine
    output wire [DATA_WIDTH-1:0] read_data,
    input  wire                  read_en,
    output wire                  empty
);

    // Determine address width based on the configured FIFO depth
    // Utilizes the $clog2 system function to compute the ceiling of log2
    localparam ADDR_WIDTH = $clog2(DEPTH); 

    
    // Primary storage array (typically synthesizes to BRAM on FPGA targets)
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    
    // Internal pointers for tracking current read and write offsets
    reg [ADDR_WIDTH:0] write_ptr;
    reg [ADDR_WIDTH:0] read_ptr;
    
    // Utilizing an N+1 bit pointer scheme to resolve empty/full ambiguity:
    // FIFO is considered empty when both pointers are exactly identical.
    // FIFO is considered full when pointers wrap and only their MSBs differ.
    
    assign empty = (write_ptr == read_ptr);
    assign full  = (write_ptr[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]) && 
                   (write_ptr[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]);

    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $display("ERROR: uart_tx_fifo DEPTH must be a strictly power-of-2 value.");
            $finish;
        end
    end
                   
    // Synchronous pointer updates and memory write operations
    always @(posedge clk) begin
        if (!reset) begin
            write_ptr <= 0;
            read_ptr <= 0;
        end else begin
            if (write_en && !full) begin
                memory[write_ptr[ADDR_WIDTH-1:0]] <= write_data;
                write_ptr <= write_ptr + 1;
            end
            if (read_en && !empty) begin
                read_ptr <= read_ptr + 1;
            end
        end
    end

    // Asynchronous read data assignment
    // Implements First-Word Fall-Through (FWFT) behavior.
    // Data is exposed immediately without a read clock cycle latency, 
    // achieved via combinational fetch of the current read address.
    assign read_data = memory[read_ptr[ADDR_WIDTH-1:0]];

endmodule