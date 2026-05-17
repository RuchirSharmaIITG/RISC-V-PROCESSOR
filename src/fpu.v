`timescale 1ns / 1ps

module fpu(
    input wire clk,
    input wire reset,
    
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [4:0]  funct5,
    input wire [2:0]  funct3,
    input wire [4:0]  rs2_sel,
    input wire        fp_en,
    
    output wire [31:0] result,
    output wire        stall_fpu,
    output wire        fpu_exception
);
    `include "opcode.vh"
    
    // FIX: Added DONE_STATE=6 to break the stall deadlock
    localparam IDLE=0, ALIGN=1, DO_ADD=2, ITERATE=3, NORMALIZE=4, PACK=5, DONE_STATE=6;
    reg [2:0] state;
    
    reg [31:0] final_res;
    reg        final_exc;
    reg        computing;

    reg sign_res;
    reg signed [9:0] exp_res;
    reg [47:0] mant_res; 
    
    wire sign_a = a[31];
    wire sign_b = funct5 == FSUB_S ? ~b[31] : b[31];
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [24:0] mant_a = (a[30:23] == 0) ? {2'b00, a[22:0]} : {2'b01, a[22:0]};
    wire [24:0] mant_b = (b[30:23] == 0) ? {2'b00, b[22:0]} : {2'b01, b[22:0]};

    reg [52:0] iter_acc;        // FIX: Widened to 53 bits (52:0)
    reg [25:0] iter_div;
    reg [5:0]  iter_count;
    reg [7:0]  exp_b_reg;
    
    wire [52:0] div_shifted = iter_acc << 1;                     // FIX: 53 bits
    wire [26:0] div_upper   = div_shifted[52:26];                // FIX: 27 bits
    wire        div_sub_ok  = (div_upper >= {1'b0, iter_div});   // FIX: Zero-pad iter_div for 27-bit safe comparison

    // --- CUSTOM FCVT.S.W BYPASS ---
    reg [31:0] cvt_sw_result;
    reg [31:0] abs_val;
    reg        cvt_sign;
    reg [7:0]  cvt_exp;
    reg [4:0]  leading_zeros;
    reg [31:0] shifted_abs;
    integer j;
    
    always @(*) begin
        // Prevent latches by assigning defaults
        cvt_sw_result = 32'h0;
        cvt_sign      = 1'b0;
        abs_val       = 32'h0;
        leading_zeros = 5'd0;
        cvt_exp       = 8'd0;
        shifted_abs   = 32'h0;

        if (rs2_sel[0]) begin // FCVT.S.WU
            cvt_sign = 1'b0; abs_val  = a;
        end else begin        // FCVT.S.W
            cvt_sign = a[31]; abs_val  = a[31] ? (~a + 1) : a;
        end
        if (abs_val != 0) begin
            for (j = 31; j >= 0; j = j - 1) begin
                if (abs_val[j] == 1'b0 && leading_zeros == (5'd31 - j[4:0])) leading_zeros = leading_zeros + 5'd1;
            end
            cvt_exp = 8'd158 - {3'd0, leading_zeros};
            shifted_abs = abs_val << (leading_zeros + 1);
            if (leading_zeros < 8) cvt_sw_result = {cvt_sign, cvt_exp, abs_val[30-leading_zeros -: 23]};
            else cvt_sw_result = {cvt_sign, cvt_exp, shifted_abs[31:9]};
        end
    end

    // --- MAIN FSM ---
    wire is_multi_cycle = (funct5 == FADD_S || funct5 == FSUB_S || funct5 == FMUL_S || funct5 == FDIV_S || funct5 == FSQRT_S);

    // Reset all FSM-owned state in one block so the synthesiser sees a clear
    // priority between reset and the case-branch assignments (resolves Synth
    // 8-7137 "set and reset with same priority" on exp_res / mant_res etc.).
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state     <= IDLE;
            computing <= 1'b0;
            final_res <= 32'b0;
            final_exc <= 1'b0;
            sign_res  <= 1'b0;
            exp_res   <= 10'sd0;
            mant_res  <= 48'b0;
            iter_acc  <= 52'b0;
            iter_div  <= 26'b0;
            iter_count<= 6'b0;
            exp_b_reg <= 8'b0;
        end else begin
            case(state)
                IDLE: begin
                    if (fp_en && !computing && is_multi_cycle) begin
                        computing <= 1;
                        if (funct5 == FADD_S || funct5 == FSUB_S) begin
                            if (a[30:0] == 0) begin final_res <= {sign_b, b[30:0]}; state <= DONE_STATE; end
                            else if (b[30:0] == 0) begin final_res <= a; state <= DONE_STATE; end
                            else begin exp_res <= exp_a; exp_b_reg <= exp_b; mant_res <= {23'b0, mant_a}; iter_div <= mant_b; state <= ALIGN; end
                        end 
                        else if (funct5 == FMUL_S) begin
                            sign_res <= sign_a ^ b[31]; exp_res <= exp_a + exp_b - 127;
                            mant_res <= {1'b1, a[22:0]} * {1'b1, b[22:0]}; state <= NORMALIZE;
                        end
                        else if (funct5 == FDIV_S) begin
                            if (b[30:0] == 0) begin 
                                if (a[30:0] == 0) final_res <= 32'h7FC00000; // NaN for 0 / 0
                                else final_res <= {sign_a ^ b[31], 8'hFF, 23'b0}; // +/- Infinity
                                final_exc <= 0; // RV32F standard sets CSR flags, but does not hard-trap
                                state <= DONE_STATE; 
                            end
                            else begin
                                sign_res <= sign_a ^ b[31]; exp_res <= exp_a - exp_b + 127;
                                iter_div <= {2'b0, 1'b1, b[22:0]}; iter_acc <= {4'b0, 1'b1, a[22:0], 25'b0}; // FIX: 4'b0 instead of 3'b0 to make 53 bits total
                                iter_count <= 26; state <= ITERATE;
                            end
                        end
                    end
                end
                
                ALIGN: begin
                    if (exp_res > exp_b_reg) begin
                        iter_div <= iter_div >> 1;
                        exp_b_reg <= exp_b_reg + 1;
                    end else if (exp_res < exp_b_reg) begin 
                        exp_res <= exp_res + 1; 
                        mant_res <= mant_res >> 1; 
                    end else begin
                        state <= DO_ADD;
                    end
                end
                
                DO_ADD: begin
                    if (sign_a == sign_b) begin 
                        mant_res <= ({23'b0, mant_res[24:0]} + {23'b0, iter_div[24:0]}) << 23; 
                        sign_res <= sign_a; 
                    end else begin
                        if (mant_res[24:0] >= iter_div[24:0]) begin 
                            mant_res <= ({23'b0, mant_res[24:0]} - {23'b0, iter_div[24:0]}) << 23; 
                            sign_res <= sign_a; 
                        end else begin 
                            mant_res <= ({23'b0, iter_div[24:0]} - {23'b0, mant_res[24:0]}) << 23; 
                            sign_res <= sign_b; 
                        end
                    end
                    state <= NORMALIZE;
                end
                
                ITERATE: begin
                    if (iter_count > 0) begin
                        if (div_sub_ok) iter_acc <= { (div_upper - {1'b0, iter_div}), div_shifted[25:1], 1'b1 }; // FIX: Zero-padded subtraction
                        else iter_acc <= { div_upper, div_shifted[25:1], 1'b0 };
                        iter_count <= iter_count - 1;
                    end else begin mant_res <= {1'b0, iter_acc[25:0], 21'b0}; state <= NORMALIZE; end
                end
                
                NORMALIZE: begin
                    if (mant_res[47]) begin mant_res <= mant_res >> 1; exp_res <= exp_res + 1; state <= PACK; end 
                    else if (mant_res[46] == 0 && mant_res != 0) begin mant_res <= mant_res << 1; exp_res <= exp_res - 1; end 
                    else state <= PACK;
                end
                
                PACK: begin
                    if (mant_res == 0 || $signed(exp_res) <= 0) final_res <= {sign_res, 31'b0};
                    else if (exp_res >= 255) final_res <= {sign_res, 8'hFF, 23'b0};
                    else final_res <= {sign_res, exp_res[7:0], mant_res[45:23]};
                    state <= DONE_STATE; 
                end
                
                DONE_STATE: begin
                    state <= IDLE;
                    computing <= 0;
                end
            endcase
            
            if (!computing && state != DONE_STATE) final_exc <= 0;
        end
    end

    // FIX: The stall completely drops when we reach DONE_STATE, allowing the pipeline to advance
    assign stall_fpu = (fp_en && is_multi_cycle && state != DONE_STATE);
    
    wire [31:0] sgnj_result = (funct3 == 3'b000) ? {b[31], a[30:0]} :          // FSGNJ.S
                              (funct3 == 3'b001) ? {~b[31], a[30:0]} :         // FSGNJN.S
                              (funct3 == 3'b010) ? {a[31] ^ b[31], a[30:0]} :  // FSGNJX.S
                              32'h0;

    reg [31:0] cvt_ws_result;
    reg [7:0] t_exp;
    reg [63:0] expanded_mant;
    reg [63:0] shifted_up;
    reg [31:0] int_mag;
    
    always @(*) begin
        cvt_ws_result = 32'd0;
        t_exp = 8'd0;
        expanded_mant = 64'd0;
        shifted_up = 64'd0;
        int_mag = 32'd0;

        if (funct5 == FCVT_W_S) begin // FCVT.W.S (Float to Int)
            if (a[30:23] < 127) begin
                cvt_ws_result = 32'd0;
            end else if (a[30:23] >= 127 + 31) begin
                cvt_ws_result = a[31] ? 32'h80000000 : 32'h7FFFFFFF;
            end else begin
                // Use a standard left-shift to avoid variable right-shift signedness issues in synthesis
                t_exp = a[30:23] - 8'd127;
                expanded_mant = {40'd0, 1'b1, a[22:0]};
                shifted_up = expanded_mant << t_exp;
                int_mag = shifted_up[54:23];
                
                cvt_ws_result = a[31] ? (~int_mag + 1) : int_mag;
            end
        end
    end

    assign result = (fp_en && funct5 == FCVT_S_W) ? cvt_sw_result : 
                    (fp_en && funct5 == FCVT_W_S) ? cvt_ws_result :
                    (fp_en && funct5 == 5'b00100) ? sgnj_result   : // FSGNJ.S
                    (fp_en && funct5 == FCMP_S)   ? {31'b0, (funct3 == 3'b010 ? (a == b) : ($signed(a) < $signed(b)))} : 
                    (fp_en && funct5 == FMV_X_W)  ? a :             // FMV.X.W
                    (fp_en && funct5 == FMV_W_X)  ? a :             // FMV.W.X
                    final_res;
                    
    assign fpu_exception = final_exc;

endmodule
