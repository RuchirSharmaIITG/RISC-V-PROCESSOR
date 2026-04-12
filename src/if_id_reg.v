`timescale 1ns/1ps

module if_id_reg (
    input  wire        clk,
    input  wire        reset,
    
    input  wire        stall,
    input  wire        flush,
    
    input  wire [31:0] if_pc,
    input  wire [31:0] inst_mem_read_data,
    input  wire        inst_mem_is_valid,
    
    output reg  [31:0] id_pc,
    output wire [31:0] id_instruction,
    output reg         id_valid
);

    localparam NOP_INSTR = 32'h0000_0013;

    // Use combinatorial instruction read to respect BRAM being the implicit IF/ID pipeline reg
    assign id_instruction = (id_valid && inst_mem_is_valid) ? inst_mem_read_data : NOP_INSTR;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            id_pc    <= 32'h0;
            id_valid <= 1'b0;
        end
        else if (flush) begin
            id_pc    <= 32'h0;
            id_valid <= 1'b0; // Flushed path
        end
        else if (!stall) begin
            id_pc    <= if_pc;
            id_valid <= 1'b1; // Valid propagation
        end
    end

endmodule