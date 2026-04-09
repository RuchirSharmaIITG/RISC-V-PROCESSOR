`timescale 1ns/1ps

module mem_stage (
    // Inputs from EX/MEM
    input  wire [31:0] ex_result_i, // Is the memory address
    input  wire [31:0] write_data_i,
    input  wire [2:0]  alu_op_i, // tells us Load/Store width
    input  wire        mem_write_i,
    input  wire        mem_read_i,
    
    // Connects to Data Memory
    output wire [31:0] dmem_read_address,
    output wire        dmem_read_ready,
    
    output reg  [31:0] dmem_write_address,
    output reg         dmem_write_ready,
    output reg  [31:0] dmem_write_data,
    output reg  [3:0]  dmem_write_byte
);

    `include "opcode.vh"

    // Reads
    assign dmem_read_address = ex_result_i;
    assign dmem_read_ready   = mem_read_i;

    // Writes
    always @(*) begin
        dmem_write_address = ex_result_i;
        dmem_write_ready   = mem_write_i;
        dmem_write_data    = 32'h0;
        dmem_write_byte    = 4'h0;

        if (mem_write_i) begin
            case (alu_op_i)
                SB: begin
                    dmem_write_data = {4{write_data_i[7:0]}};
                    case (ex_result_i[1:0])
                        2'b00: dmem_write_byte = 4'b0001;
                        2'b01: dmem_write_byte = 4'b0010;
                        2'b10: dmem_write_byte = 4'b0100;
                        default: dmem_write_byte = 4'b1000;
                    endcase
                end
                SH: begin
                    dmem_write_data = {2{write_data_i[15:0]}};
                    dmem_write_byte = ex_result_i[1] ? 4'b1100 : 4'b0011;
                end
                SW: begin
                    dmem_write_data = write_data_i;
                    dmem_write_byte = 4'b1111;
                end
            endcase
        end
    end

endmodule
