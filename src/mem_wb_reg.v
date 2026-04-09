`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        reset,
    
    // Data inputs
    input  wire [31:0] ex_result_i,
    
    // Control inputs
    input  wire [4:0]  dest_reg_sel_i,
    input  wire        mem_to_reg_i,
    input  wire        alu_to_reg_i,
    input  wire [2:0]  alu_op_i, // Load type
    input  wire [1:0]  mem_read_address_offset_i, // 2 LSB bits of addr
    input  wire        stall,
    
    // CSR signals
    input  wire        csr_we_i,
    input  wire [31:0] csr_wdata_i,
    input  wire [11:0] csr_addr_i,

    // Outputs
    output reg  [31:0] ex_result_o,
    output reg  [4:0]  dest_reg_sel_o,
    output reg         mem_to_reg_o,
    output reg         alu_to_reg_o,
    output reg  [2:0]  alu_op_o,
    output reg  [1:0]  mem_read_address_offset_o,
    
    output reg         csr_we_o,
    output reg  [31:0] csr_wdata_o,
    output reg  [11:0] csr_addr_o
);

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            ex_result_o               <= 32'h0;
            dest_reg_sel_o            <= 5'h0;
            mem_to_reg_o              <= 1'b0;
            alu_to_reg_o              <= 1'b0;
            alu_op_o                  <= 3'h0;
            mem_read_address_offset_o <= 2'h0;
            
            csr_we_o                  <= 1'b0;
            csr_wdata_o               <= 32'h0;
            csr_addr_o                <= 12'h0;
        end
        else if (!stall) begin
            ex_result_o               <= ex_result_i;
            dest_reg_sel_o            <= dest_reg_sel_i;
            mem_to_reg_o              <= mem_to_reg_i;
            alu_to_reg_o              <= alu_to_reg_i;
            alu_op_o                  <= alu_op_i;
            mem_read_address_offset_o <= mem_read_address_offset_i;
            
            csr_we_o                  <= csr_we_i;
            csr_wdata_o               <= csr_wdata_i;
            csr_addr_o                <= csr_addr_i;
        end
    end

endmodule
