`timescale 1ns / 1ps

module clk_div (
    input  wire clk_in,   // 100MHz from the board
    input  wire reset,    // Active-high reset
    output wire clk_out   // 50MHz output
);

    wire clkfb;
    wire clk_out_unbuf;

    // Use Xilinx's built-in Mixed-Mode Clock Manager (MMCM)
    // This is the cleanest way to divide a clock in Vivado and 
    // requires ZERO manual create_generated_clock constraints!
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.0),    // Multiply 100MHz by 10 = 1000MHz VCO
        .CLKIN1_PERIOD(10.0),      // 100MHz input = 10ns period
        .CLKOUT0_DIVIDE_F(20.0)    // Divide 1000MHz by 20 = 50MHz output
    ) mmcm_inst (
        .CLKIN1(clk_in),
        .CLKOUT0(clk_out_unbuf),
        .CLKFBOUT(clkfb),
        .CLKFBIN(clkfb),
        .RST(reset),
        .PWRDWN(1'b0)
    );

    // Buffer the output onto the global clock tree
    BUFG bufg_inst (
        .I(clk_out_unbuf),
        .O(clk_out)
    );

endmodule
