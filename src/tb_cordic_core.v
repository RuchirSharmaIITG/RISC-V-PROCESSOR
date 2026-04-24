`timescale 1ns/1ps

module tb_cordic_core;

    reg         clk;
    reg         reset;
    reg         start;
    reg  [31:0] target_angle;
    
    wire        valid_out;
    wire [31:0] sin_out;
    wire [31:0] cos_out;

    // Instantiate the raw math core
    cordic_iterative UUT_CORE (
        .clk(clk),
        .reset(reset),
        .start(start),
        .target_angle(target_angle),
        .valid_out(valid_out),
        .sin_out(sin_out),
        .cos_out(cos_out)
    );

    // 100 MHz Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Q4.28 Constants
    // pi/6 (30 degrees) = 0.5235987756 * 2^28 = 32'h0860A98B
    // pi/4 (45 degrees) = 0.7853981634 * 2^28 = 32'h0C90FDAA
    localparam [31:0] ANGLE_PI_OVER_6 = 32'h0860A98B;
    localparam [31:0] ANGLE_PI_OVER_4 = 32'h0C90FDAA;

    initial begin
        reset = 0;
        start = 0;
        target_angle = 0;
        
        #50 reset = 1;
        #20;

        // --- Test 1: 30 Degrees ---
        $display("[CORE TB] Starting Test 1: 30 Degrees (pi/6)");
        target_angle = ANGLE_PI_OVER_6;
        start = 1;
        #10 start = 0; // Pulse start for 1 cycle

        wait(valid_out);
        @(posedge clk);
        $display("[CORE TB] Test 1 Complete.");
        $display("          Sine Result (Exp: ~0.500) : %h", sin_out);
        $display("          Cos Result  (Exp: ~0.866) : %h", cos_out);

        #50;

        // --- Test 2: 45 Degrees ---
        $display("[CORE TB] Starting Test 2: 45 Degrees (pi/4)");
        target_angle = ANGLE_PI_OVER_4;
        start = 1;
        #10 start = 0;

        wait(valid_out);
        @(posedge clk);
        $display("[CORE TB] Test 2 Complete.");
        $display("          Sine Result (Exp: ~0.707) : %h", sin_out);
        $display("          Cos Result  (Exp: ~0.707) : %h", cos_out);

        #100 $finish;
    end

endmodule
