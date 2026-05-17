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
    input  wire        auipc_i,   // RV32I AUIPC: result = pc + (imm20 << 12)
    input  wire        jal_i,
    input  wire        jalr_i,
    input  wire        branch_i,
    input  wire        arithsubtype_i,

    // RV32M logic
    input  wire        mult_div_en_i,
    
    // RV32F logic / General Instruction Selectors
    input  wire [4:0]  rs2_sel_i, // Extracted rs2 field from instruction
    input  wire        fp_en_i,
    input  wire        fp_load_i,
    input  wire        fp_store_i,
    input  wire [4:0]  fp_funct5_i,
    input  wire [31:0] fp_rdata1_i,
    input  wire [31:0] fp_rdata2_i,
    
    // CSR logic
    input  wire        is_csr_i,
    input  wire [11:0] csr_addr_i, // Connected to CSR address decoding logic
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
    output wire        ex_exception,     // Triggered on traps like div-by-zero
    
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
    reg [31:0] fp_fw_operand1;
    reg [31:0] fp_fw_operand2;

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
        
        // Similar forwarding approach for FP registers
        case (forward_a)
            2'b00: fp_fw_operand1 = fp_rdata1_i;
            2'b01: fp_fw_operand1 = forward_mem_wb_val;
            2'b10: fp_fw_operand1 = forward_ex_mem_val;
            default: fp_fw_operand1 = fp_rdata1_i;
        endcase

        case (forward_b)
            2'b00: fp_fw_operand2 = fp_rdata2_i;
            2'b01: fp_fw_operand2 = forward_mem_wb_val;
            2'b10: fp_fw_operand2 = forward_ex_mem_val;
            default: fp_fw_operand2 = fp_rdata2_i;
        endcase
    end

    // Use fp_fw_operand2 for write data during an FP Store
    assign write_data_out = fp_store_i ? fp_fw_operand2 : fw_operand2;

    wire [31:0] alu_operand1 = fw_operand1;
    wire [31:0] alu_operand2 = immediate_sel_i ? immediate_i : fw_operand2;

    // ----------------------------------------------------
    // Mult/Div Setup
    // ----------------------------------------------------
    wire [31:0] mult_div_result_val;
    wire        mult_div_ready;
    wire        mult_div_busy;
    wire        mult_div_zero_fault;
    
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
        .busy     (mult_div_busy),
        .div_zero_fault (mult_div_zero_fault)
    );

    // ----------------------------------------------------
    // FPU Setup
    // ----------------------------------------------------
    wire [31:0] fpu_result_val;
    wire        stall_fpu;
    wire        fpu_zero_fault;
    
    // FCVT.S.W (11010) and FMV.W.X (11110) read an INTEGER from rs1
    wire use_int_operand = (fp_funct5_i == 5'b11010 || fp_funct5_i == 5'b11110);
    wire [31:0] fpu_operand_a = use_int_operand ? alu_operand1 : fp_fw_operand1;
    
    fpu u_fpu (
        .clk            (clk),
        .reset          (reset),
        .a              (fpu_operand_a),
        .b              (fp_fw_operand2),
        .funct5         (fp_funct5_i),
        .funct3         (alu_op_i),
        .rs2_sel        (rs2_sel_i),
        .fp_en          (fp_en_i),
        .result         (fpu_result_val),
        .stall_fpu      (stall_fpu),
        .fpu_exception  (fpu_zero_fault)
    );

    // Combine trap sources, mapped tightly to the active math execute enable flag
    // NOTE: RISC-V spec mandates that integer divide-by-zero is NOT an exception.
    // The mult_div module already returns the correct defined values (-1 for DIV, dividend for REM).
    // Only FPU faults should trigger hardware exceptions.
    assign ex_exception = (fp_en_i & fpu_zero_fault);

    // Hazard Unit freezes pipeline if we need to wait
    assign stall_ex_request = (mult_div_en_i && !mult_div_ready) || stall_fpu;

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
            
            // Catch the hijacked MRET instruction!
            // Normal JALR doesn't assert is_csr, so this combination uniquely identifies MRET.
            if (is_csr_i) begin
                branch_target = csr_rdata_i; // Jump to the value held in MEPC!
            end else begin
                branch_target = (alu_operand1 + immediate_i) & ~32'd1; // Normal JALR
            end
            
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
        else if (auipc_i) begin
            // AUIPC is PC-relative. Without this case the default
            // `alu_operand1 + immediate_i` computed `x0 + imm`, which broke
            // every PC-relative address the compiler generated (string
            // pointers, global data, trap-vector setup, etc.).
            ex_result = pc_i + immediate_i;
        end
        else if (is_csr_i) begin
            ex_result = csr_rdata_i; // Output old CSR value to rd
        end
        else if (fp_en_i) begin
            ex_result = fpu_result_val; // RV32F ALu result
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
            // LOAD or STORE addresses (even for FP, the base address is integer register)
            ex_result = alu_operand1 + immediate_i;
        end
    end

endmodule
