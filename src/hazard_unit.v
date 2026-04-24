`timescale 1ns/1ps

module hazard_unit (
    // Forwarding inputs
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,
    input  wire       ex_mem_is_fp,    
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,
    input  wire       mem_wb_is_fp,     
    
    // Load-use stall inputs
    input  wire [4:0] if_id_rs1,
    input  wire [4:0] if_id_rs2,
    input  wire [4:0] id_ex_rd,
    input  wire       id_ex_mem_read,
    
    // Control hazard stall inputs
    input  wire       branch_taken,  // Driven from EX

    input  wire       stall_ex_request,
    
    // Exception CSR triggers
    input  wire       exception_trigger,
    
    // Forwarding outputs
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b,
    
    // Hazard outputs
    output reg        stall_if,
    output reg        stall_id,
    output reg        stall_ex,
    output reg        flush_id,  // FLUSH ID/EX when load/use or branch
    output reg        flush_if,  // FLUSH IF/ID when branch taken
    output reg        flush_ex
);

    always @(*) begin
        // --- Forwarding Logic ---
        // 00: Read from RegFile
        // 01: Forward from MEM/WB
        // 10: Forward from EX/MEM
        
        forward_a = 2'b00;
        forward_b = 2'b00;
        
        // --- Forward A (RS1) ---
        // Forward if it's an FP write (even to f0), OR if it's an INT write to a non-zero register.
        if (ex_mem_reg_write && (ex_mem_is_fp || (ex_mem_rd != 5'd0)) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end
        else if (mem_wb_reg_write && (mem_wb_is_fp || (mem_wb_rd != 5'd0)) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end
        
        // --- Forward B (RS2) ---
        if (ex_mem_reg_write && (ex_mem_is_fp || (ex_mem_rd != 5'd0)) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end
        else if (mem_wb_reg_write && (mem_wb_is_fp || (mem_wb_rd != 5'd0)) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end

        // --- Load-Use Hazard Logic ---
        stall_if = 1'b0;
        stall_id = 1'b0;
        stall_ex = 1'b0;
        flush_id = 1'b0;
        flush_if = 1'b0;
        flush_ex = 1'b0;

        if (id_ex_mem_read && (id_ex_rd != 5'd0) && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2))) begin
            stall_if = 1'b1;
            stall_id = 1'b1;
            flush_id = 1'b1; // Insert bubble in EX
        end
        
        // --- Stall Logic (Mult/Div Multi cycle stall) ---
        if (stall_ex_request) begin
            stall_if = 1'b1; // Freeze fetch
            stall_id = 1'b1; // Freeze decode
            stall_ex = 1'b1; // Freeze EX so the instruction holds steady
            flush_ex = 1'b1; // Push bubble to EX/MEM so side-effects aren't replayed
        end

        // --- Control Hazard Logic ---
        if (exception_trigger) begin
            flush_if = 1'b0; // Comb fetch bypasses flush_if requirement
            flush_id = 1'b1;
            flush_ex = 1'b1;
            stall_if = 1'b0;
            stall_id = 1'b0;
            stall_ex = 1'b0;
        end
        else if (branch_taken) begin
            flush_if = 1'b0; // Comb fetch bypasses flush_if requirement
            flush_id = 1'b1;
            stall_if = 1'b0;
            stall_id = 1'b0;
        end
    end

endmodule
