`timescale 1ns/1ps

module ex_stage (
    input  wire        clk,
    input  wire        reset,

    input  wire [31:0] pc_i,
    input  wire [31:0] immediate_i,
    input  wire [31:0] reg_rdata1_i,
    input  wire [31:0] reg_rdata2_i,
    input  wire [2:0]  alu_op_i,

    input  wire        immediate_sel_i,
    input  wire        alu_i,
    input  wire        lui_i,
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        branch_i,
    input  wire        arithsubtype_i,

    // RV32M logic
    input  wire        mult_div_en_i,
    
    // CSR logic
    input  wire        is_csr_i,
    input  wire [11:0] csr_addr_i,
    input  wire [31:0] csr_rdata_i, // From global CSR file

    // Forwarding logic
    input  wire [1:0]  forward_a,
    input  wire [1:0]  forward_b,
    input  wire [31:0] forward_ex_mem_val,
    input  wire [31:0] forward_mem_wb_val,

    // Outputs
    output reg  [31:0] ex_result,
    output wire [31:0] write_data_out, // the value to be stored in mem
    output reg         branch_taken,
    output reg  [31:0] branch_target,
    output wire        stall_ex_request, // Stalls earlier stages because Math takes longer
    
    // CSR Outputs
    output reg         csr_we,
    output reg  [31:0] csr_wdata
);

    `include "opcode.vh"

    // ----------------------------------------------------
    // Forwarding Muxes
    // ----------------------------------------------------
    reg [31:0] fw_operand1;
    reg [31:0] fw_operand2;

    always @(*) begin
        case (forward_a)
            2'b00: fw_operand1 = reg_rdata1_i;
            2'b01: fw_operand1 = forward_mem_wb_val;
            2'b10: fw_operand1 = forward_ex_mem_val;
            default: fw_operand1 = reg_rdata1_i;
        endcase

        case (forward_b)
            2'b00: fw_operand2 = reg_rdata2_i;
            2'b01: fw_operand2 = forward_mem_wb_val;
            2'b10: fw_operand2 = forward_ex_mem_val;
            default: fw_operand2 = reg_rdata2_i;
        endcase
    end

    assign write_data_out = fw_operand2;

    wire [31:0] alu_operand1 = fw_operand1;
    wire [31:0] alu_operand2 = immediate_sel_i ? immediate_i : fw_operand2;

    // ----------------------------------------------------
    // Mult/Div Setup
    // ----------------------------------------------------
    wire [31:0] mult_div_result_val;
    wire        mult_div_ready;
    wire        mult_div_busy;
    
    // Fire the module immediately when entering EX with mult_div op, unless it's already busy
    wire        mult_div_start = mult_div_en_i && !mult_div_busy && !mult_div_ready;

    mult_div u_mult_div (
        .clk      (clk),
        .reset    (reset),
        .start    (mult_div_start),
        .rs1_data (alu_operand1),
        .rs2_data (fw_operand2), 
        .op       (alu_op_i),
        .result   (mult_div_result_val),
        .ready    (mult_div_ready),
        .busy     (mult_div_busy)
    );

    // Hazard Unit freezes pipeline if we need to wait
    assign stall_ex_request = mult_div_en_i && !mult_div_ready;

    // ----------------------------------------------------
    // Calculate next PC / branch
    // ----------------------------------------------------
    always @(*) begin
        branch_taken  = 1'b0;
        branch_target = 32'h0;

        if (jal_i) begin
            branch_taken  = 1'b1;
            branch_target = pc_i + immediate_i;
        end
        else if (jalr_i) begin
            branch_taken  = 1'b1;
            branch_target = (alu_operand1 + immediate_i) & ~32'd1;
        end
        else if (branch_i) begin
            branch_target = pc_i + immediate_i;
            case (alu_op_i)
                BEQ:  branch_taken = (alu_operand1 == alu_operand2);
                BNE:  branch_taken = (alu_operand1 != alu_operand2);
                BLT:  branch_taken = ($signed(alu_operand1) < $signed(alu_operand2));
                BGE:  branch_taken = ($signed(alu_operand1) >= $signed(alu_operand2));
                BLTU: branch_taken = (alu_operand1 < alu_operand2);
                BGEU: branch_taken = (alu_operand1 >= alu_operand2);
                default: branch_taken = 1'b0;
            endcase
        end
    end
    
    // ----------------------------------------------------
    // CSR logic
    // ----------------------------------------------------
    always @(*) begin
        csr_we    = 1'b0;
        csr_wdata = 32'h0;
        
        if (is_csr_i) begin
            csr_we = 1'b1;
            case (alu_op_i)
                CSRRW:  csr_wdata = alu_operand1; // write rs1
                CSRRS:  begin
                    csr_wdata = csr_rdata_i | alu_operand1;
                    if (alu_operand1 == 0) csr_we = 1'b0; // Only read
                end
                CSRRC:  begin
                    csr_wdata = csr_rdata_i & ~alu_operand1;
                    if (alu_operand1 == 0) csr_we = 1'b0; // Only read
                end
                CSRRWI: csr_wdata = immediate_i; // zimm
                CSRRSI: begin
                    csr_wdata = csr_rdata_i | immediate_i;
                    if (immediate_i == 0) csr_we = 1'b0; // Only read
                end
                CSRRCI: begin
                    csr_wdata = csr_rdata_i & ~immediate_i;
                    if (immediate_i == 0) csr_we = 1'b0; // Only read
                end
                default: csr_we = 1'b0;
            endcase
        end
    end

    // ----------------------------------------------------
    // ALU functionality & Output Result
    // ----------------------------------------------------
    always @(*) begin
        ex_result = 32'hx;

        if (jal_i || jalr_i) begin
            ex_result = pc_i + 4; // return address
        end
        else if (lui_i) begin
            ex_result = immediate_i;
        end
        else if (is_csr_i) begin
            ex_result = csr_rdata_i; // Output old CSR value to rd
        end
        else if (mult_div_en_i) begin
            ex_result = mult_div_result_val; // RV32M result
        end
        else if (alu_i) begin
            case (alu_op_i)
                ADD: ex_result = arithsubtype_i ? alu_operand1 - alu_operand2 : alu_operand1 + alu_operand2;
                SLL: ex_result = alu_operand1 << alu_operand2[4:0];
                SLT: ex_result = {31'b0, $signed(alu_operand1) < $signed(alu_operand2)};
                SLTU: ex_result = {31'b0, alu_operand1 < alu_operand2};
                XOR: ex_result = alu_operand1 ^ alu_operand2;
                SR:  ex_result = arithsubtype_i ? $signed(alu_operand1) >>> alu_operand2[4:0] : alu_operand1 >> alu_operand2[4:0];
                OR:  ex_result = alu_operand1 | alu_operand2;
                AND: ex_result = alu_operand1 & alu_operand2;
                default: ex_result = 32'hx;
            endcase
        end
        else begin
            // LOAD or STORE addresses
            ex_result = alu_operand1 + immediate_i;
        end
    end

endmodule
