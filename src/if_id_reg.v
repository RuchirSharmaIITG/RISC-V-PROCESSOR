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

    // Hold register: captures the instruction when a stall begins, so that
    // subsequent BRAM output changes (due to IF PC advancing before freeze)
    // don't corrupt the instruction visible to the ID stage.
    reg [31:0] inst_hold;
    reg        stall_prev;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            stall_prev <= 1'b0;
            inst_hold  <= NOP_INSTR;
        end else begin
            stall_prev <= stall;
            if (!stall_prev)
                inst_hold <= (inst_mem_is_valid) ? inst_mem_read_data : NOP_INSTR;
        end
    end

    // During the first stall cycle, BRAM still has the correct data.
    // After that, it may have changed. Use the hold register during stalls.
    wire use_hold = stall_prev; // If we were stalled last cycle, BRAM output is stale
    
    assign id_instruction = (!id_valid) ? NOP_INSTR :
                            (use_hold)  ? inst_hold :
                            (inst_mem_is_valid) ? inst_mem_read_data : NOP_INSTR;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            id_pc    <= 32'h0;
            id_valid <= 1'b0;
        end
        else if (flush) begin
            id_pc    <= 32'h0;
            id_valid <= 1'b0;
        end
        else if (!stall) begin
            id_pc    <= if_pc;
            id_valid <= 1'b1;
        end
    end

endmodule
