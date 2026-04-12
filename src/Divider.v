module Divider (
    input clk,
    input rst,
    input start,
    input [31:0] A,
    input [31:0] B,
    input [2:0] funct3, // 100=DIV, 101=DIVU, 110=REM, 111=REMU
    output reg [31:0] Result,
    output reg ready
);
    wire is_signed = (funct3 == 3'b100) || (funct3 == 3'b110);
    wire is_rem    = (funct3 == 3'b110) || (funct3 == 3'b111);
    
    reg [5:0] count;
    reg [63:0] AQ;
    reg [31:0] M;
    reg state; // 0: IDLE, 1: DIVIDING
    
    reg sign_res, sign_rem;
    
    wire [32:0] sub_res = {1'b0, AQ[62:31]} - {1'b0, M};
    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= 0;
            ready <= 0;
            count <= 0;
            Result <= 0;
        end else begin
            if (state == 0) begin
                ready <= 0;
                if (start) begin
                    if (B == 0) begin
                        // Divide by zero exception behavior
                        Result <= is_rem ? A : 32'hFFFFFFFF;
                        ready <= 1;
                    end else begin
                        state <= 1;
                        count <= 32;
                        sign_res <= is_signed & (A[31] ^ B[31]);
                        sign_rem <= is_signed & A[31];
                        AQ <= {32'b0, (is_signed & A[31]) ? -A : A};
                        M <= (is_signed & B[31]) ? -B : B;
                    end
                end
            end else begin
                // shift and subtract
                if (count > 0) begin
                    if (sub_res[32]) begin // A < M 
                        AQ <= {AQ[62:0], 1'b0}; // Restore
                    end else begin
                        AQ <= {sub_res[31:0], AQ[30:0], 1'b1}; // Set Q[0]
                    end
                    count <= count - 1;
                end else begin
                    state <= 0;
                    ready <= 1;
                    if (is_rem) begin
                        Result <= sign_rem ? -AQ[63:32] : AQ[63:32];
                    end else begin
                        Result <= sign_res ? -AQ[31:0] : AQ[31:0];
                    end
                end
            end
        end
    end
endmodule