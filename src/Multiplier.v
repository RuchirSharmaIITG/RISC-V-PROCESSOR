module Multiplier (
    input clk,
    input rst,
    input start,
    input [31:0] A,
    input [31:0] B,
    input [2:0] funct3, // 000=MUL, 001=MULH, 010=MULHSU, 011=MULHU
    output [31:0] Result,
    output ready
);

    wire a_is_signed = (funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010);
    wire b_is_signed = (funct3 == 3'b000) || (funct3 == 3'b001);

    // Sign extend inputs to 33 bits to handle unsigned vs signed seamlessly
    wire [32:0] A_ext = {a_is_signed & A[31], A};
    wire [32:0] B_ext = {b_is_signed & B[31], B};

    // Absolute values for unsigned shift and add
    wire [32:0] A_abs = (A_ext[32]) ? -A_ext : A_ext;
    wire [32:0] B_abs = (B_ext[32]) ? -B_ext : B_ext;

    // Result will be negative if signs differ and it's a signed operation
    wire neg_result = A_ext[32] ^ B_ext[32];

    localparam IDLE = 2'd0, CALC = 2'd1, DONE = 2'd2;
    reg [1:0] state, next_state;

    reg [65:0] acc;
    reg [32:0] multiplicand;
    reg neg_result_r;
    reg [5:0] count;
    reg [2:0] funct3_r;

    // FSM State Update
    always @(posedge clk or negedge rst) begin
        if (!rst) state <= IDLE;
        else state <= next_state;
    end

    // FSM Next State Logic
    always @* begin
        case(state)
            IDLE: if(start) next_state = CALC; else next_state = IDLE;
            CALC: if(count == 6'd32) next_state = DONE; else next_state = CALC;
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Computation
    wire [33:0] add_result = acc[65:33] + multiplicand; // 34-bit add result

    always @(posedge clk) begin
        if (state == IDLE && start) begin
            acc <= {33'b0, B_abs};
            multiplicand <= A_abs;
            neg_result_r <= neg_result;
            funct3_r <= funct3;
            count <= 0;
        end
        else if (state == CALC) begin
            // Shift operations for un-signed 33x33 multiplication
            acc <= { (acc[0] ? add_result : {1'b0, acc[65:33]}), acc[32:1] };
            count <= count + 1;
        end
    end

    // Determine finalized product by checking the stored negative bit
    wire [65:0] final_product = neg_result_r ? -acc : acc;
    assign ready = (state == DONE);

    assign Result = (funct3_r == 3'b000) ? final_product[31:0]  : 
                    (funct3_r == 3'b001) ? final_product[63:32] : 
                    (funct3_r == 3'b010) ? final_product[63:32] : 
                    (funct3_r == 3'b011) ? final_product[63:32] : 
                    32'h0;

endmodule
