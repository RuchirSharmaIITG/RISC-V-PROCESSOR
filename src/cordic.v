`timescale 1ns/1ps

module cordic_iterative (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [31:0] target_angle, // Q4.28 format (-pi to +pi)
    
    output reg         valid_out,
    output reg  [31:0] sin_out,      // Q4.28 format
    output reg  [31:0] cos_out       // Q4.28 format
);

    // Initial inverse CORDIC gain (1/K) in Q4.28
    // K ~ 1.646760258, 1/K ~ 0.607252935.
    // 0.607252935 * 2^28 = 163004818 = 32'h09B74EDA
    localparam [31:0] CORDIC_GAIN_INV = 32'h09B74EDA;
    
    // Pi/2 and Pi constants in Q4.28
    localparam signed [31:0] PI_OVER_2 = 32'h1921FB54;
    localparam signed [31:0] NEG_PI_OVER_2 = 32'hE6DE04AC;
    localparam signed [31:0] PI = 32'h3243F6A8;
    
    reg [2:0]  state;
    localparam STATE_IDLE = 3'd0;
    localparam STATE_CALC = 3'd1;
    localparam STATE_DONE = 3'd2;
    
    reg signed [31:0] x, y, z;
    reg [4:0]  iteration;
    reg        flip_signs; // Tracks if we rotated by 180 degrees
    
    wire signed [31:0] x_shifted = (x >>> iteration);
    wire signed [31:0] y_shifted = (y >>> iteration);
    
    // LUT instantiation
    reg [31:0] atan_lut_val;
    always @(*) begin
        case(iteration)
            5'd00: atan_lut_val = 32'h0C90FDAA;
            5'd01: atan_lut_val = 32'h076B19C1;
            5'd02: atan_lut_val = 32'h03EB6EBF;
            5'd03: atan_lut_val = 32'h01FD5BAA;
            5'd04: atan_lut_val = 32'h00FFAADE;
            5'd05: atan_lut_val = 32'h007FF557;
            5'd06: atan_lut_val = 32'h003FFEAB;
            5'd07: atan_lut_val = 32'h001FFFD5;
            5'd08: atan_lut_val = 32'h000FFFFB;
            5'd09: atan_lut_val = 32'h0007FFFF;
            5'd10: atan_lut_val = 32'h00040000;
            5'd11: atan_lut_val = 32'h00020000;
            5'd12: atan_lut_val = 32'h00010000;
            5'd13: atan_lut_val = 32'h00008000;
            5'd14: atan_lut_val = 32'h00004000;
            5'd15: atan_lut_val = 32'h00002000;
            5'd16: atan_lut_val = 32'h00001000;
            5'd17: atan_lut_val = 32'h00000800;
            5'd18: atan_lut_val = 32'h00000400;
            5'd19: atan_lut_val = 32'h00000200;
            5'd20: atan_lut_val = 32'h00000100;
            5'd21: atan_lut_val = 32'h00000080;
            5'd22: atan_lut_val = 32'h00000040;
            5'd23: atan_lut_val = 32'h00000020;
            5'd24: atan_lut_val = 32'h00000010;
            5'd25: atan_lut_val = 32'h00000008;
            5'd26: atan_lut_val = 32'h00000004;
            5'd27: atan_lut_val = 32'h00000002;
            5'd28: atan_lut_val = 32'h00000001;
            default: atan_lut_val = 32'h00000000;
        endcase
    end
    
    always @(posedge clk) begin
        if (!reset) begin
            state <= STATE_IDLE;
            valid_out <= 0;
            sin_out <= 0;
            cos_out <= 0;
            x <= 0; y <= 0; z <= 0;
            iteration <= 0;
            flip_signs <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    valid_out <= 0;
                    if (start) begin
                        // Quadrant preprocessing: CORDIC converges in [-pi/2, pi/2].
                        // For angles outside this range, fold by pi and negate outputs.
                        if ($signed(target_angle) > PI_OVER_2) begin
                            z <= $signed(target_angle) - PI;
                            flip_signs <= 1'b1;
                        end else if ($signed(target_angle) < NEG_PI_OVER_2) begin
                            z <= $signed(target_angle) + PI;
                            flip_signs <= 1'b1;
                        end else begin
                            z <= target_angle;
                            flip_signs <= 1'b0;
                        end
                        x <= CORDIC_GAIN_INV;
                        y <= 32'sd0;
                        iteration <= 5'd0;
                        state <= STATE_CALC;
                    end
                end
                
                STATE_CALC: begin
                    // Rotation depending on the sign of current error Z
                    if (z >= 0) begin
                        x <= x - y_shifted;
                        y <= y + x_shifted;
                        z <= z - atan_lut_val;
                    end else begin
                        x <= x + y_shifted;
                        y <= y - x_shifted;
                        z <= z + atan_lut_val;
                    end
                    
                    iteration <= iteration + 1;
                    if (iteration == 5'd31) begin
                        state <= STATE_DONE;
                    end
                end
                
                STATE_DONE: begin
                    valid_out <= 1;
                    if (flip_signs) begin
                        cos_out <= -x;
                        sin_out <= -y;
                    end else begin
                        cos_out <= x;
                        sin_out <= y;
                    end
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
