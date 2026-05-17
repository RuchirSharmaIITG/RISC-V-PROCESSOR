`timescale 1ns/1ps
// Stage files and hazard unit are compiled natively via Vivado workspace.
// change is getting reflected

module pipe #(
	parameter [31:0] RESET = 32'h0000_0000
) (
	input                   clk,
	input                   reset,
	input                   stall,
	output                  exception,
	output [31:0]           pc_out,

	// interface of instruction Memory
	output      [31: 0] inst_mem_address,
	input                   inst_mem_is_valid,
	input       [31: 0] inst_mem_read_data,
	output                  inst_mem_is_ready,

	// interface of Data Memory
	output      [31: 0] dmem_read_address,
	output                  dmem_read_ready,
	input       [31: 0] dmem_read_data_temp,
	input                   dmem_read_valid,
	output      [31: 0] dmem_write_address,
	output                  dmem_write_ready,
	output      [31: 0] dmem_write_data,
	output      [ 3: 0] dmem_write_byte,
	input                   dmem_write_valid
);
    
    // Register File
    reg [31:0] regs [31:1];
    
    // ----------------------------------------------------
    // Wires
    // ----------------------------------------------------
    
    // Hazard Unit Outputs
    wire stall_if_haz;
    wire stall_id_haz;
    wire stall_ex_haz;
    wire flush_if_haz;
    wire flush_id_haz;
    wire flush_ex_haz;
    wire [1:0] forward_a_sel;
    wire [1:0] forward_b_sel;

    // CSR Wires
    wire [11:0] id_csr_addr, ex_csr_addr, mem_csr_addr, wb_csr_addr;
    wire        id_is_csr, ex_is_csr;
    wire        ex_csr_we, mem_csr_we, wb_csr_we;
    wire [31:0] ex_csr_wdata, mem_csr_wdata, wb_csr_wdata;
    wire [31:0] csr_rdata;
    wire        id_mult_div_en, ex_mult_div_en;
    wire        stall_ex_request;

    // Merged stales
    wire stage_stall_if = stall | stall_if_haz;
    wire stage_stall_id = stall | stall_id_haz;
    wire stage_stall_ex = stall | stall_ex_haz;
    wire stage_flush_ex = flush_ex_haz;
    
    // IF Wires
    wire [31:0] if_pc_out;
    wire        branch_taken;
    wire [31:0] branch_target;

    assign pc_out = if_pc_out;

    // ID Wires
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    
    wire [31:0] id_immediate;
    wire        id_immediate_sel;
    wire        id_alu;
    wire        id_lui;
    wire        id_auipc;
    wire        id_jal;
    wire        id_jalr;
    wire        id_branch;
    wire        id_mem_write;
    wire        id_mem_read;
    wire        id_mem_to_reg;
    wire        id_arithsubtype;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rd;
    wire [2:0]  id_alu_op;
    wire        id_illegal_inst;
    
    wire [31:0] id_reg_rdata1;
    wire [31:0] id_reg_rdata2;

    // RV32F ID signals
    wire        id_fp_en;
    wire        id_fp_load;
    wire        id_fp_store;
    wire [4:0]  id_fp_funct5;
    wire [31:0] id_fp_rdata1;
    wire [31:0] id_fp_rdata2;

    // EX Wires
    wire [31:0] ex_pc;
    wire [31:0] ex_immediate;
    wire [31:0] ex_reg_rdata1;
    wire [31:0] ex_reg_rdata2;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [4:0]  ex_rd;
    wire [2:0]  ex_alu_op;
    wire        ex_immediate_sel;
    wire        ex_alu;
    wire        ex_lui;
    wire        ex_auipc;
    wire        ex_jal;
    wire        ex_jalr;
    wire        ex_branch;
    wire        ex_mem_write;
    wire        ex_mem_read;
    wire        ex_mem_to_reg;
    wire        ex_arithsubtype;
    wire        ex_illegal_inst;
    
    // RV32F EX signals
    wire        ex_fp_en;
    wire        ex_fp_load;
    wire        ex_fp_store;
    wire [4:0]  ex_fp_funct5;
    wire [31:0] ex_fp_rdata1;
    wire [31:0] ex_fp_rdata2;

    
    // Internal EX -> EX/MEM Reg
    wire [31:0] ex_result_calc;
    wire [31:0] ex_write_data_calc;

    // MEM Wires
    wire [31:0] mem_ex_result;
    wire [31:0] mem_write_data;
    wire [4:0]  mem_rd;
    wire [2:0]  mem_alu_op;
    wire        mem_mem_write;
    wire        mem_mem_read;
    wire        mem_mem_to_reg;
    wire        mem_alu_to_reg;
    
    wire        mem_fp_reg_write;

    // WB Wires
    wire [31:0] wb_ex_result;
    wire [4:0]  wb_rd;
    wire        wb_mem_to_reg;
    wire        wb_alu_to_reg;
    wire [2:0]  wb_alu_op;
    wire [1:0]  wb_mem_read_offset;
    wire [31:0] wb_result;

    wire        wb_fp_reg_write;

    // Trap & Exception Logic
    wire        ex_exception;
    wire [31:0] exception_vector;
    
    // Unused optional signal
    assign exception = wb_result === 32'hx && ex_illegal_inst;

    // ----------------------------------------------------
    // Internal RegFile Forwarding (Read in ID)
    // ----------------------------------------------------
    // ----------------------------------------------------
    // Internal RegFile Forwarding (Read in ID)
    // ----------------------------------------------------
    assign id_reg_rdata1 = (id_rs1 == 5'd0) ? 32'b0 :
                           (wb_alu_to_reg && !wb_fp_reg_write && (wb_rd == id_rs1)) ? wb_result :
                           regs[id_rs1];

    assign id_reg_rdata2 = (id_rs2 == 5'd0) ? 32'b0 :
                           (wb_alu_to_reg && !wb_fp_reg_write && (wb_rd == id_rs2)) ? wb_result :
                           regs[id_rs2];

    wire [31:0] fp_regs_rdata1;
    wire [31:0] fp_regs_rdata2;

    wire        id_fp_writes_int;
    wire        ex_fp_writes_int;

    assign id_fp_rdata1  = (wb_fp_reg_write && wb_rd == id_rs1 && wb_rd != 5'd0 && !stall) ? wb_result : fp_regs_rdata1;
    assign id_fp_rdata2  = (wb_fp_reg_write && wb_rd == id_rs2 && wb_rd != 5'd0 && !stall) ? wb_result : fp_regs_rdata2;

    fp_regfile u_fp_regfile (
        .clk    (clk),
        .reset  (reset),
        .raddr1 (id_rs1),
        .rdata1 (fp_regs_rdata1),
        .raddr2 (id_rs2),
        .rdata2 (fp_regs_rdata2),
        .we     (wb_fp_reg_write && !stall),
        .waddr  (wb_rd),
        .wdata  (wb_result)
    );

    // ----------------------------------------------------
    // RegFile Write
    // ----------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!reset) begin
            for (i=1; i<32; i=i+1) regs[i] <= 32'b0;
        end else if (wb_alu_to_reg && !wb_fp_reg_write && wb_rd != 5'd0 && !stall) begin
            regs[wb_rd] <= wb_result;
        end
    end


    // In pipeline.v, modify the EX writeback logic:
    // An instruction writes to FP reg if it's an FP op AND it doesn't target an INT reg.
    wire ex_fp_reg_write = (ex_fp_en && !ex_fp_writes_int) | ex_fp_load;
    
    // An instruction writes to INT reg if it's standard ALU, OR if it's an FP op targeting INT.
    wire ex_alu_to_reg = (ex_alu | ex_lui | ex_auipc | ex_jal | ex_jalr | ex_mem_to_reg | ex_is_csr | ex_mult_div_en | ex_fp_writes_int);

    // ----------------------------------------------------
    // Modules
    // ----------------------------------------------------

    hazard_unit u_hazard_unit (
        .id_ex_rs1        (ex_rs1),
        .id_ex_rs2        (ex_rs2),
        .id_ex_mem_read   (ex_mem_read),
        .id_ex_rd         (ex_rd),
        .if_id_rs1        (id_rs1),
        .if_id_rs2        (id_rs2),

        .ex_mem_is_fp     (mem_fp_reg_write), // <--- ADD THIS
        .mem_wb_is_fp     (wb_fp_reg_write),  // <--- ADD THIS
        
        .ex_mem_reg_write (mem_alu_to_reg | mem_fp_reg_write),
        .ex_mem_rd        (mem_rd),
        .mem_wb_reg_write (wb_alu_to_reg | wb_fp_reg_write),
        .mem_wb_rd        (wb_rd),
        
        .branch_taken     (branch_taken),
        .stall_ex_request (stall_ex_request),
        .exception_trigger(ex_exception),
        
        .stall_if         (stall_if_haz),
        .stall_id         (stall_id_haz),
        .stall_ex         (stall_ex_haz),
        .flush_if         (flush_if_haz),
        .flush_id         (flush_id_haz),
        .flush_ex         (flush_ex_haz),
        
        .forward_a        (forward_a_sel),
        .forward_b        (forward_b_sel)
    );

    // ----------------------------------------------------
    // CSR File
    // ----------------------------------------------------

    csr_file u_csr_file (
        .clk              (clk),
        .reset            (reset),
        
        .csr_raddr        (ex_csr_addr),
        .csr_rdata        (csr_rdata),
        
        .csr_we           (wb_csr_we),
        .csr_waddr        (wb_csr_addr),
        .csr_wdata        (wb_csr_wdata),
        
        // Use standardised RISC-V cause (2 = Illegal Instruction) for remaining FPU faults
        .exception_trigger(ex_exception),
        .exception_cause  (ex_exception ? 32'd2 : 32'b0), 
        .exception_pc     (ex_pc),
        .exception_vector (exception_vector)
    );

    if_stage #( .RESET_PC(RESET) ) u_if_stage (
        .clk              (clk),
        .reset            (reset),
        .stall            (stage_stall_if),
        .branch_taken     (branch_taken),
        .branch_target    (branch_target),
        .exception_trigger(ex_exception),
        .exception_vector (exception_vector),
        .inst_mem_address (inst_mem_address),
        .inst_mem_is_ready(inst_mem_is_ready),
        .pc_o             (if_pc_out)
    );

    if_id_reg u_if_id_reg (
        .clk               (clk),
        .reset             (reset),
        .stall             (stage_stall_id),
        .flush             (flush_if_haz & ~stall),
        .if_pc             (if_pc_out),
        .inst_mem_read_data(inst_mem_read_data),
        .inst_mem_is_valid (inst_mem_is_valid),
        .id_pc             (id_pc),
        .id_instruction    (id_inst),
        .id_valid          ()  // unused; reg is internal, NOP-gating already handled
    );

    id_stage u_id_stage (
        .instruction_i (id_inst),
        .immediate     (id_immediate),
        .immediate_sel (id_immediate_sel),
        .alu           (id_alu),
        .lui           (id_lui),
        .auipc         (id_auipc),
        .jal           (id_jal),
        .jalr          (id_jalr),
        .branch        (id_branch),
        .mem_write     (id_mem_write),
        .mem_read      (id_mem_read),
        .mem_to_reg    (id_mem_to_reg),
        .arithsubtype  (id_arithsubtype),
        .src1_sel      (id_rs1),
        .src2_sel      (id_rs2),
        .dest_reg_sel  (id_rd),
        .alu_op        (id_alu_op),
        .illegal_inst  (id_illegal_inst),
        .mult_div_en   (id_mult_div_en),
        .is_csr        (id_is_csr),
        .csr_addr      (id_csr_addr),
        .fp_en         (id_fp_en),
        .fp_load       (id_fp_load),
        .fp_store      (id_fp_store),
        .fp_funct5     (id_fp_funct5),
        .fp_writes_int (id_fp_writes_int) // <--- Connect the new output from ID
       );

    id_ex_reg u_id_ex_reg (
        .clk             (clk),
        .reset           (reset),
        .stall           (stage_stall_id),
        .flush           (flush_id_haz & ~stall),
        
        .pc_i            (id_pc),
        .immediate_i     (id_immediate),
        .reg_rdata1_i    (id_reg_rdata1),
        .reg_rdata2_i    (id_reg_rdata2),
        .src1_sel_i      (id_rs1),
        .src2_sel_i      (id_rs2),
        .dest_reg_sel_i  (id_rd),
        .alu_op_i        (id_alu_op),

        .immediate_sel_i (id_immediate_sel),
        .alu_i           (id_alu),
        .lui_i           (id_lui),
        .auipc_i         (id_auipc),
        .jal_i           (id_jal),
        .jalr_i          (id_jalr),
        .branch_i        (id_branch),
        .mem_write_i     (id_mem_write),
        .mem_read_i      (id_mem_read),
        .mem_to_reg_i    (id_mem_to_reg),
        .arithsubtype_i  (id_arithsubtype),
        .illegal_inst_i  (id_illegal_inst),
        
        .mult_div_en_i   (id_mult_div_en),
        .is_csr_i        (id_is_csr),
        .csr_addr_i      (id_csr_addr),
        
        .fp_en_i         (id_fp_en),
        .fp_load_i       (id_fp_load),
        .fp_store_i      (id_fp_store),
        .fp_funct5_i     (id_fp_funct5),
        .fp_rdata1_i     (id_fp_rdata1),
        .fp_rdata2_i     (id_fp_rdata2),

        .pc_o            (ex_pc),
        .immediate_o     (ex_immediate),
        .reg_rdata1_o    (ex_reg_rdata1),
        .reg_rdata2_o    (ex_reg_rdata2),
        .src1_sel_o      (ex_rs1),
        .src2_sel_o      (ex_rs2),
        .dest_reg_sel_o  (ex_rd),
        .alu_op_o        (ex_alu_op),

        .immediate_sel_o (ex_immediate_sel),
        .alu_o           (ex_alu),
        .lui_o           (ex_lui),
        .auipc_o         (ex_auipc),
        .jal_o           (ex_jal),
        .jalr_o          (ex_jalr),
        .branch_o        (ex_branch),
        .mem_write_o     (ex_mem_write),
        .mem_read_o      (ex_mem_read),
        .mem_to_reg_o    (ex_mem_to_reg),
        .arithsubtype_o  (ex_arithsubtype),
        .illegal_inst_o  (ex_illegal_inst),
        
        .mult_div_en_o   (ex_mult_div_en),
        .is_csr_o        (ex_is_csr),
        .csr_addr_o      (ex_csr_addr),
        
        .fp_en_o         (ex_fp_en),
        .fp_load_o       (ex_fp_load),
        .fp_store_o      (ex_fp_store),
        .fp_funct5_o     (ex_fp_funct5),
        .fp_rdata1_o     (ex_fp_rdata1),
        .fp_rdata2_o     (ex_fp_rdata2),

        .fp_writes_int_i (id_fp_writes_int), // <--- Input to reg
        .fp_writes_int_o (ex_fp_writes_int) // <--- Output from reg
    );

    ex_stage u_ex_stage (
        .clk                (clk), // Added for CSR & Mult/Div
        .reset              (reset),
        
        .pc_i               (ex_pc),
        .immediate_i        (ex_immediate),
        .reg_rdata1_i       (ex_reg_rdata1),
        .reg_rdata2_i       (ex_reg_rdata2),
        .alu_op_i           (ex_alu_op),
        .immediate_sel_i    (ex_immediate_sel),
        .alu_i              (ex_alu),
        .lui_i              (ex_lui),
        .auipc_i            (ex_auipc),
        .jal_i              (ex_jal),
        .jalr_i             (ex_jalr),
        .branch_i           (ex_branch),
        .arithsubtype_i     (ex_arithsubtype),
        
        .rs2_sel_i          (ex_rs2),
        
        .mult_div_en_i      (ex_mult_div_en),
        .is_csr_i           (ex_is_csr),
        .csr_addr_i         (ex_csr_addr),
        .csr_rdata_i        (csr_rdata),
        
        .fp_en_i            (ex_fp_en),
        .fp_load_i          (ex_fp_load),
        .fp_store_i         (ex_fp_store),
        .fp_funct5_i        (ex_fp_funct5),
        .fp_rdata1_i        (ex_fp_rdata1),
        .fp_rdata2_i        (ex_fp_rdata2),
        
        // Forwarding
        .forward_a          (forward_a_sel),
        .forward_b          (forward_b_sel),
        .forward_ex_mem_val (mem_ex_result),
        .forward_mem_wb_val (wb_result),

        .ex_result          (ex_result_calc),
        .write_data_out     (ex_write_data_calc),
        .branch_taken       (branch_taken),
        .branch_target      (branch_target),
        
        .stall_ex_request   (stall_ex_request),
        .ex_exception       (ex_exception),
        .csr_we             (ex_csr_we),
        .csr_wdata          (ex_csr_wdata)
    );

   

    ex_mem_reg u_ex_mem_reg (
        .clk            (clk),
        .reset          (reset),
        
        .ex_result_i    (ex_result_calc),
        .write_data_i   (ex_write_data_calc),
        .dest_reg_sel_i (ex_rd),
        .alu_op_i       (ex_alu_op),
        .mem_write_i    (ex_mem_write && !stall), // prevent storing to memory on stalls
        .mem_read_i     (ex_mem_read && !stall),
        .mem_to_reg_i   (ex_mem_to_reg),
        .alu_to_reg_i   (ex_alu_to_reg),
        .stall          (stage_stall_ex),
        .flush          (stage_flush_ex & ~stall),
        
        .csr_we_i       (ex_csr_we),
        .csr_wdata_i    (ex_csr_wdata),
        .csr_addr_i     (ex_csr_addr),
        
        .fp_reg_write_i (ex_fp_reg_write),

        .ex_result_o    (mem_ex_result),
        .write_data_o   (mem_write_data),
        .dest_reg_sel_o (mem_rd),
        .alu_op_o       (mem_alu_op),
        .mem_write_o    (mem_mem_write),
        .mem_read_o     (mem_mem_read),
        .mem_to_reg_o   (mem_mem_to_reg),
        .alu_to_reg_o   (mem_alu_to_reg),
        
        .csr_we_o       (mem_csr_we),
        .csr_wdata_o    (mem_csr_wdata),
        .csr_addr_o     (mem_csr_addr),
        
        .fp_reg_write_o (mem_fp_reg_write)
    );

    mem_stage u_mem_stage (
        .ex_result_i        (mem_ex_result),
        .write_data_i       (mem_write_data),
        .alu_op_i           (mem_alu_op),
        .mem_write_i        (mem_mem_write),
        .mem_read_i         (mem_mem_read),
        
        .dmem_read_address  (dmem_read_address),
        .dmem_read_ready    (dmem_read_ready),
        
        .dmem_write_address (dmem_write_address),
        .dmem_write_ready   (dmem_write_ready),
        .dmem_write_data    (dmem_write_data),
        .dmem_write_byte    (dmem_write_byte)
    );

    mem_wb_reg u_mem_wb_reg (
        .clk                       (clk),
        .reset                     (reset),
        
        .ex_result_i               (mem_ex_result),
        .dest_reg_sel_i            (mem_rd),
        .mem_to_reg_i              (mem_mem_to_reg),
        .alu_to_reg_i              (mem_alu_to_reg),
        .alu_op_i                  (mem_alu_op),
        .mem_read_address_offset_i (mem_ex_result[1:0]),
        .stall                     (stall),
        
        .csr_we_i                  (mem_csr_we),
        .csr_wdata_i               (mem_csr_wdata),
        .csr_addr_i                (mem_csr_addr),
        
        .fp_reg_write_i            (mem_fp_reg_write),

        .ex_result_o               (wb_ex_result),
        .dest_reg_sel_o            (wb_rd),
        .mem_to_reg_o              (wb_mem_to_reg),
        .alu_to_reg_o              (wb_alu_to_reg),
        .alu_op_o                  (wb_alu_op),
        .mem_read_address_offset_o (wb_mem_read_offset),
        
        .csr_we_o                  (wb_csr_we),
        .csr_wdata_o               (wb_csr_wdata),
        .csr_addr_o                (wb_csr_addr),
        
        .fp_reg_write_o            (wb_fp_reg_write)
    );

    wb_stage u_wb_stage (
        .ex_result_i               (wb_ex_result),
        .dmem_read_data_i          (dmem_read_data_temp),
        .alu_op_i                  (wb_alu_op),
        .mem_read_address_offset_i (wb_mem_read_offset),
        .mem_to_reg_i              (wb_mem_to_reg),
        
        .wb_result_o               (wb_result)
    );

    // Removed duplicate assignments and redundant fpu_cvt/cmp instantiations.

endmodule
