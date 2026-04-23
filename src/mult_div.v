`timescale 1ns/1ps


module mult_div (
    input  wire        clk,
    input  wire        reset,
    
    input  wire        start,     // Assert high to begin operation
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [2:0]  op,        // 000: MUL, 001: MULH, 010: MULHSU, 011: MULHU, 100: DIV, 101: DIVU, 110: REM, 111: REMU
    
    output reg  [31:0] result,
    output wire        ready,     // High when calculation is complete. Held until start is deasserted.
    output wire        busy,      // High while calculation is running
    output reg         div_zero_fault // High if division by zero occurs
);

    localparam STATE_IDLE = 2'b00;
    localparam STATE_MULT = 2'b01;
    localparam STATE_DIV  = 2'b10;
    localparam STATE_DONE = 2'b11;

    reg [1:0]  state;
    reg [5:0]  counter;

    // Working registers
    reg [63:0] accumulator; // Holds product for Mult, {remainder, quotient} for Div
    reg [31:0] divisor;
    
    // Sign tracking
    reg out_sign;
    reg rem_sign;
    
    wire is_div = op[2];
    wire is_rem = (op[2:1] == 2'b11);
    wire is_signed_div = (op == 3'b100 || op == 3'b110);
    wire is_upper_mult = (op == 3'b001 || op == 3'b010 || op == 3'b011);
    
    assign busy = (state != STATE_IDLE);

    assign ready = (state == STATE_DONE);

    // -----------------------------------------------------------------
    // Combinatorial Pre-calculations (removes internal sequential variables)
    // -----------------------------------------------------------------
    wire [31:0] abs_rs1 = rs1_data[31] ? (~rs1_data + 1) : rs1_data;
    wire [31:0] abs_rs2 = rs2_data[31] ? (~rs2_data + 1) : rs2_data;
    
    // Multiply signatures
    wire mult_sign_ss = rs1_data[31] ^ rs2_data[31];
    wire mult_sign_su = rs1_data[31];
    
    // Division signatures
    wire div_sign_quo = rs1_data[31] ^ rs2_data[31];
    wire div_sign_rem = rs1_data[31];
    
    // Division step logic
    wire [63:0] div_shifted = accumulator << 1;
    wire [31:0] div_upper   = div_shifted[63:32];
    wire        div_sub_ok  = (div_upper >= divisor);
    wire [31:0] div_sub_val = div_upper - divisor;
    
    // Multiply step logic
    wire [32:0] mult_step_sum =  {1'b0, accumulator[63:32]} + {1'b0, divisor};
    
    // Output formatting logic
    wire [63:0] mult_final_acc = out_sign ? (~accumulator + 1) : accumulator;
    wire [31:0] mult_final_out = is_upper_mult ? mult_final_acc[63:32] : mult_final_acc[31:0];
    
    wire [31:0] div_quo_raw =  accumulator[31:0];
    wire [31:0] div_mod_raw =  accumulator[63:32];
    wire [31:0] div_quo_out =  out_sign ? (~div_quo_raw + 1) : div_quo_raw;
    wire [31:0] div_mod_out =  rem_sign ? (~div_mod_raw + 1) : div_mod_raw;

    // -----------------------------------------------------------------
    // Sequential State Machine
    // -----------------------------------------------------------------
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state   <= STATE_IDLE;
            result  <= 32'h0;
            counter <= 6'h0;
            accumulator <= 64'h0;
            divisor <= 32'h0;
            out_sign <= 1'b0;
            rem_sign <= 1'b0;
            div_zero_fault <= 1'b0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    div_zero_fault <= 1'b0;
                    if (start) begin
                        counter <= 6'd32;
                        
                        if (!is_div) begin
                            // Multiplication Setup
                            state <=  STATE_MULT;
                            
                            if (op == 3'b001) begin // MULH (signed x signed)
                                out_sign    <= mult_sign_ss;
                                accumulator <= {32'h0, abs_rs2};
                                divisor     <= abs_rs1;
                            end else if (op == 3'b010) begin // MULHSU (signed x unsigned)
                                out_sign    <= mult_sign_su;
                                accumulator <= {32'h0, rs2_data}; // unsigned rs2
                                divisor     <= abs_rs1;
                            end else begin // MUL, MULHU (unsigned x unsigned effectively)
                                out_sign    <= 1'b0;
                                accumulator <= {32'h0, rs2_data};
                                divisor     <= rs1_data;
                            end
                        end
                        else begin
                            // Division Setup
                            state <=  STATE_DIV;
                            
                            if (is_signed_div) begin
                                out_sign <=  div_sign_quo;
                                rem_sign <=  div_sign_rem;
                                
                                if (rs2_data == 0) begin
                                    // Divide by zero fault
                                    div_zero_fault <=  1'b1;
                                    result <= is_rem ?  rs1_data : 32'hFFFF_FFFF;
                                    state  <=  STATE_DONE;
                                end else begin
                                    accumulator <=  {32'h0, abs_rs1};
                                    divisor     <=  abs_rs2;
                                end
                            end else begin
                                out_sign <=  1'b0;
                                rem_sign <=  1'b0;
                                
                                if (rs2_data == 0) begin
                                    // Divide by zero fault
                                    div_zero_fault <=  1'b1;
                                    result <= is_rem ?  rs1_data : 32'hFFFF_FFFF;
                                    state  <=  STATE_DONE;
                                end else begin
                                    accumulator <= {32'h0, rs1_data};
                                    divisor     <= rs2_data;
                                end
                            end
                        end
                    end
                end


                
                STATE_MULT: begin
                    // Shift and Add
                    if (counter > 0) begin
                        if (accumulator[0] == 1'b1) begin
                            accumulator <= { mult_step_sum, accumulator[31:1] };
                        end else begin
                            accumulator <= { 1'b0, accumulator[63:1] };
                        end
                        counter <= counter - 1;
                    end
                    else begin
                        // Finalize result using pre-calculated combinatorial output
                        result <= mult_final_out;
                        state  <= STATE_DONE;
                    end
                end


                
                STATE_DIV: begin
                    // Restoring Division Algorithm optimized
                    if (counter > 0) begin
                        if ( div_sub_ok ) begin
                            accumulator <= { div_sub_val, div_shifted[31:1], 1'b1 };
                        end else begin
                            accumulator <= { div_upper, div_shifted[31:1], 1'b0 };
                        end
                        counter <= counter - 1;
                    end
                    else begin
                        // Finalize result using pre-calculated combinatorial output
                        result <= is_rem ? div_mod_out :  div_quo_out;
                        state  <=  STATE_DONE;
                    end
                end
                


                STATE_DONE: begin
                    if ( start ) state <= STATE_DONE; // Stay here while start is high
                    else state <=  STATE_IDLE;      // Only return to idle when start is dropped
                end


            endcase
        end
    end



endmodule
