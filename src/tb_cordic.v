`timescale 1ns/1ps

module tb_cordic;
    reg clk;
    reg reset;
    reg start;
    reg [31:0] target_angle;
    
    wire valid_out;
    wire [31:0] sin_out;
    wire [31:0] cos_out;

    cordic_iterative uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .target_angle(target_angle),
        .valid_out(valid_out),
        .sin_out(sin_out),
        .cos_out(cos_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 0;
        start = 0;
        target_angle = 32'h0;
        
        #20 reset = 1;
        
        // Test 1: Angle = pi/2
        // pi/2 in Q4.28 = 1.570796326 * 2^28 = 421657428 = 32'h1921FB54
        #20;
        target_angle = 32'h1921FB54;
        start = 1;
        #10 start = 0;
        
        wait(valid_out == 1);
        $display("PI/2 -> Sine: %h (Expected ~1.0 in Q4.28 = 10000000), Cosine: %h (Expected ~0)", sin_out, cos_out);
        
        // Test 2: Angle = pi/4
        // pi/4 = 0.78539816 * 2^28 = 210828714 = 32'h0C90FDAB
        #20;
        target_angle = 32'h0C90FDAB;
        start = 1;
        #10 start = 0;
        
        wait(valid_out == 1);
        $display("PI/4 -> Sine: %h, Cosine: %h (Both should equal ~0.707 => 0x0B504F33)", sin_out, cos_out);

        // Test 3: Angle = -pi/2
        // -pi/2 in signed hex = 32'hE6DE04AC
        #20;
        target_angle = 32'hE6DE04AC;
        start = 1;
        #10 start = 0;
        
        wait(valid_out == 1);
        $display("-PI/2 -> Sine: %h (Expected ~-1.0), Cosine: %h (Expected ~0)", sin_out, cos_out);

        // Test 4: Angle = 0
        #20;
        target_angle = 32'h00000000;
        start = 1;
        #10 start = 0;
        
        wait(valid_out == 1);
        $display("ZERO -> Sine: %h (Expected 0), Cosine: %h (Expected ~1.0)", sin_out, cos_out);
        
        #50 $finish;
    end
endmodule
