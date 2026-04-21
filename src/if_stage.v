`timescale 1ns/1ps

module if_stage #(
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,
    
    // Branch/Jump from EX
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    
    // Exception Hooks from CSR
    input  wire        exception_trigger,
    input  wire [31:0] exception_vector,
    
    // Outputs to instruction memory
    output wire [31:0] inst_mem_address,
    output wire        inst_mem_is_ready,
    
    // Outputs to IF/ID
    output wire [31:0] pc_o
);

    reg [31:0] pc_reg;

    assign inst_mem_address = pc_reg;
    assign pc_o             = pc_reg;
    assign inst_mem_is_ready = ~stall;

    always @(posedge clk) begin
        if (!reset) begin
            pc_reg <= RESET_PC;
        end
        else if (!stall) begin
            if (exception_trigger) begin
                pc_reg <= exception_vector;
            end
            else if (branch_taken) begin
                pc_reg <= branch_target;
            end
            else begin
                pc_reg <= pc_reg + 4;
            end
        end
    end

endmodule
