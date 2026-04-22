`timescale 1ns / 1ps

module tb_uart_soc;
    reg clk;
    reg reset;

    reg  uart_rx;
    wire uart_tx; 
    wire [15:0] led;

    // Swift Baud Rate (100MHz / 3.125M = 32 clocks per bit, perfect divisor for '16' oversampling)
    top_fpga #(
        .BAUD_RATE(3125000)
    ) dut (
        .clk(clk),
        .reset(reset),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led)
    );

    always #5 clk = ~clk; // 100 MHz clock

    localparam CLKS_PER_BIT = 32;
    
    // UART TX Task (to send data simulating python script)
    task send_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 0; // Start bit
            #(CLKS_PER_BIT * 10);
            
            for (i=0; i<8; i=i+1) begin
                uart_rx = data[i]; // Data bits
                #(CLKS_PER_BIT * 10);
            end
            
            uart_rx = 1; // Stop bit
            #(CLKS_PER_BIT * 10);
        end
    endtask

    // UART RX Task (to receive data from FPGA)
    reg [7:0] rx_catch;
    task receive_byte;
        integer i;
        begin
            @(negedge uart_tx); // Wait for start bit
            #(CLKS_PER_BIT * 10 / 2); // Wait to center
            #(CLKS_PER_BIT * 10);
            for (i=0; i<8; i=i+1) begin
                rx_catch[i] = uart_tx;
                #(CLKS_PER_BIT * 10);
            end
            #(CLKS_PER_BIT * 10); // Wait out stop bit
            $write("%c", rx_catch); // Print to console!
        end
    endtask

    initial begin
        clk = 0;
        reset = 0;
        uart_rx = 1;
        
        $dumpfile("tb_uart_soc.vcd");
        $dumpvars(0, tb_uart_soc);
        
        #15 reset = 1;

        // Give the bootloader a moment to reset
        #500;
        
        $display("[SIM] Sending DEADBEEF Header...");
        send_byte(8'hDE); send_byte(8'hAD); send_byte(8'hBE); send_byte(8'hEF);
        
        // Dynamically find size of program.bin!
        begin : load_bin
            integer fd;
            integer size;
            integer byte;
            fd = $fopen("c_toolchain/program.bin", "rb");
            if (fd == 0) begin
                $display("ERROR: Could not open program.bin!");
                $finish;
            end
            
            // Just assume around 5000 bytes maximum, we dynamically read until EOF over 2 passes
            // Wait, we can't easily find size in pure Verilog 2001. Let's just send a massive padded size or precalculate it.
            // Oh right, we can count the bytes first!
            size = 0;
            while (!$feof(fd)) begin
                byte = $fgetc(fd);
                if (byte != -1) size = size + 1;
            end
            
            while ((size % 4) != 0) size = size + 1;
            
            $display("[SIM] Found program.bin size: %0d bytes", size);
            
            // Send size (Little Endian)
            send_byte(size & 8'hFF);
            send_byte((size >> 8) & 8'hFF);
            send_byte((size >> 16) & 8'hFF);
            send_byte((size >> 24) & 8'hFF);
            
            // Send payload
            $fclose(fd);
            fd = $fopen("c_toolchain/program.bin", "rb");
            while (size > 0) begin
                byte = $fgetc(fd);
                if (byte == -1) send_byte(8'h00);
                else send_byte(byte[7:0]);
                size = size - 1;
            end
            $fclose(fd);
        end
        
        $display("[SIM] Binary transmitted. Waiting for Bootloader to release CPU...");
        
        wait (dut.cpu_reset == 1'b1);
        $display("[SIM] CPU BOOTED AND EXECUTING!");
        
        #200000; 
        
        $display("\n[SIM] Sending formula: add 15.5 24.5");
        send_byte("a"); send_byte("d"); send_byte("d"); send_byte(" ");
        send_byte("1"); send_byte("5"); send_byte("."); send_byte("5"); send_byte(" ");
        send_byte("2"); send_byte("4"); send_byte("."); send_byte("5"); send_byte("\r");
        
        #100000;
        
        $display("\n[SIM] Sending formula: div 5 0");
        send_byte("d"); send_byte("i"); send_byte("v"); send_byte(" ");
        send_byte("5"); send_byte(" ");
        send_byte("0"); send_byte("\r");
        
        #500000;
        
        $finish;
    end

    // Monitor CPU reset and boot loader writes
    always @(posedge dut.cpu_reset) begin
        $display("============ CPU BOOTLOADER FINISHED, CORE IS RELEASED ============");
    end

    integer pc_limit = 0;
    always @(posedge clk) begin
        if (dut.boot_we)
            if (dut.boot_addr[12:0] < 12) $display("[BOOT] Writing Mem[%0h] = %08h", dut.boot_addr, dut.boot_wdata);
            
        if (dut.cpu_reset == 1'b1 && pc_limit < 10) begin
            $display("[CPU] PC = %08h, Inst = %08h", dut.pipe_u.if_pc_out, dut.inst_mem_read_data);
            pc_limit = pc_limit + 1;
        end
    end

    initial begin
        // UART RX thread
        #100;
        forever begin
            receive_byte();
        end
    end

    // Failsafe Timeout
    initial begin
        #50_000_000;
        $display("\n[SIM FAIL] Test Timeout Occurred.");
        $finish;
    end

endmodule
