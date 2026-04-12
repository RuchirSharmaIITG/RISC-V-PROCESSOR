`timescale 1ns/1ps
module tb_mult_div;
    reg clk;
    reg reset;
    reg start;
    reg [31:0] rs1_data;
    reg [31:0] rs2_data;
    reg [2:0] op;
    wire [31:0] result;
    wire ready;
    wire busy;

    integer outfile;

    mult_div dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .op(op),
        .result(result),
        .ready(ready),
        .busy(busy)
    );

    always #5 clk = ~clk;

    task do_op;
        input [31:0] in_rs1;
        input [31:0] in_rs2;
        input [2:0]  in_op;
        input [80*8:1] op_name; // string
        begin
            @(posedge clk);
            #1; // Output after clock edge to avoid race conditions
            rs1_data = in_rs1;
            rs2_data = in_rs2;
            op = in_op;
            start = 1;
            
            @(posedge clk);
            #1;
            start = 0;
            
            wait(ready == 1'b1);
            @(posedge clk);
            
            $display("%0s: %d, %d -> Result: %d (0x%08X)", op_name, $signed(in_rs1), $signed(in_rs2), $signed(result), result);
            $fdisplay(outfile, "%0s: %d, %d -> Result: %d (0x%08X)", op_name, $signed(in_rs1), $signed(in_rs2), $signed(result), result);
            
            #20; // Wait before next OP
        end
    endtask

    initial begin
        clk = 0;
        reset = 0;
        start = 0;
        rs1_data = 0;
        rs2_data = 0;
        op = 0;
        
        $dumpfile("tb_mult_div.vcd");
        $dumpvars(0, tb_mult_div);
        
        outfile = $fopen("simulation_results.txt", "w");
        
        #15 reset = 1;
        #20;

        $display("=== STARTING MULT/DIV TESTS ===");
        $fdisplay(outfile, "=== STARTING MULT/DIV TESTS ===");

        // 3 Divisions
        do_op(7, 3, 3'b100, "DIV ( 7 / 3)");
        do_op(-8, 3, 3'b100, "DIV (-8 / 3)");
        do_op(-8, -3, 3'b100, "DIV (-8 / -3)");
        
        // 3 Remainders
        do_op(7, 3, 3'b110, "REM ( 7 % 3)");
        do_op(-8, 3, 3'b110, "REM (-8 % 3)");
        do_op(-8, -3, 3'b110, "REM (-8 % -3)");
        
        // 3 Multiplications
        do_op(7, 3, 3'b000, "MUL ( 7 * 3)");
        do_op(-8, 3, 3'b000, "MUL (-8 * 3)");
        do_op(-8, -3, 3'b000, "MUL (-8 * -3)");

        $display("=== TESTS COMPLETE ===");
        $fdisplay(outfile, "=== TESTS COMPLETE ===");
        $fclose(outfile);
        
        $finish;
    end
endmodule
