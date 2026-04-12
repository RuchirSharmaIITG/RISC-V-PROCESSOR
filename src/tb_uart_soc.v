`timescale 1ns / 1ps

module tb_uart_soc;
    reg clk;
    reg reset;

    // Loopback! Connect TX directly to RX
    wire uart_tx;
    wire uart_rx = uart_tx; 
    
    wire [15:0] led;

    top_fpga dut (
        .clk(clk),
        .reset(reset),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led)
    );

    always #5 clk = ~clk; // 100 MHz clock

    initial begin
        clk = 0;
        reset = 0;
        
        $dumpfile("tb_uart_soc.vcd");
        $dumpvars(0, tb_uart_soc);
        
        #15 reset = 1;

        // Since the CPU will fetch instructions from memory we just let the simulated clock run
        // for an extended period of time to allow the pipelined code to execute a loopback transfer.
        // It takes around ~8680 clocks to transfer one byte at 115200 Baud over 100MHz!
        #500_000;
        
        $finish;
    end
endmodule
