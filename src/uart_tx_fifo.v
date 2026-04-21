`timescale 1ns / 1ps

module uart_tx_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 1024
)(
    input  wire                  clk,
    input  wire                  reset,
    
    // Write side (from CPU)
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  write_en,
    output wire                  full,
    
    // Read side (to UART TX FSM)
    output wire [DATA_WIDTH-1:0] read_data,
    input  wire                  read_en,
    output wire                  empty
);

    // Calculate the number of bits needed to represent the depth
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // FIFO Memory array - inferred as Block RAM (BRAM) by synthesis tools
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    
    // Read and Write pointers
    reg [ADDR_WIDTH:0] write_ptr;
    reg [ADDR_WIDTH:0] read_ptr;
    
    // The extra bit in pointers helps cleanly differentiate between Full and Empty states.
    // Empty: read_ptr == write_ptr
    // Full: read_ptr and write_ptr differ only in the MSB, and are identical in the other bits.
    
    assign empty = (write_ptr == read_ptr);
    assign full  = (write_ptr[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]) && 
                   (write_ptr[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]);

    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $display("ERROR: uart_tx_fifo DEPTH must be a power of 2.");
            $finish;
        end
    end
                   
    // Write Logic
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

    // Read Logic
    // We want a first-word fall-through (FWFT) kind of logic or simple output.
    // Since read_data needs to be available immediately when !empty, we can do 
    // continuous assignment for the read data based on read_ptr.
    assign read_data = memory[read_ptr[ADDR_WIDTH-1:0]];

endmodule
