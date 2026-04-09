`timescale 1ns/1ps

module wb_stage (
    input  wire [31:0] ex_result_i,
    input  wire [31:0] dmem_read_data_i,
    
    input  wire [2:0]  alu_op_i, // LB, LH, LW, LBU, LHU
    input  wire [1:0]  mem_read_address_offset_i,
    input  wire        mem_to_reg_i,
    
    output reg  [31:0] wb_result_o
);

    `include "opcode.vh"
    
    reg [31:0] formatted_mem_read;

    always @(*) begin
        case (alu_op_i)
            LB: begin
                case (mem_read_address_offset_i)
                    2'b00: formatted_mem_read = {{24{dmem_read_data_i[7]}},  dmem_read_data_i[7:0]};
                    2'b01: formatted_mem_read = {{24{dmem_read_data_i[15]}}, dmem_read_data_i[15:8]};
                    2'b10: formatted_mem_read = {{24{dmem_read_data_i[23]}}, dmem_read_data_i[23:16]};
                    2'b11: formatted_mem_read = {{24{dmem_read_data_i[31]}}, dmem_read_data_i[31:24]};
                endcase
            end
            LH: begin
                formatted_mem_read = mem_read_address_offset_i[1] 
                    ? {{16{dmem_read_data_i[31]}}, dmem_read_data_i[31:16]}
                    : {{16{dmem_read_data_i[15]}}, dmem_read_data_i[15:0]};
            end
            LW: formatted_mem_read = dmem_read_data_i;
            LBU: begin
                case (mem_read_address_offset_i)
                    2'b00: formatted_mem_read = {24'h0, dmem_read_data_i[7:0]};
                    2'b01: formatted_mem_read = {24'h0, dmem_read_data_i[15:8]};
                    2'b10: formatted_mem_read = {24'h0, dmem_read_data_i[23:16]};
                    2'b11: formatted_mem_read = {24'h0, dmem_read_data_i[31:24]};
                endcase
            end
            LHU: begin
                formatted_mem_read = mem_read_address_offset_i[1]
                    ? {16'h0, dmem_read_data_i[31:16]}
                    : {16'h0, dmem_read_data_i[15:0]};
            end
            default: formatted_mem_read = dmem_read_data_i;
        endcase

        // Either ALU calculation or memory read data
        wb_result_o = mem_to_reg_i ? formatted_mem_read : ex_result_i;
    end

endmodule
