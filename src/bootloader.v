`timescale 1ns / 1ps

module bootloader (
    input  wire        clk,
    input  wire        reset,         // System reset (active low)
    input  wire        uart_rx_ready, // High for 1 cycle when new byte is received
    input  wire [7:0]  uart_rx_data,
    
    output reg         cpu_reset,     // Active low reset for the CPU pipeline
    output reg         boot_we,       // Write enable for memory
    output reg [31:0]  boot_addr,     // Address for memory
    output reg [31:0]  boot_wdata     // Data for memory
);

    // States
    localparam S_IDLE       = 3'd0;
    localparam S_SYNC_1     = 3'd1;
    localparam S_SYNC_2     = 3'd2;
    localparam S_SYNC_3     = 3'd3;
    localparam S_SIZE       = 3'd4;
    localparam S_PAYLOAD    = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [2:0] state;
    reg [2:0] byte_idx;
    reg [31:0] payload_size;
    reg [31:0] bytes_received;

    // Synchronous reset: Xilinx BRAM write/address pins fed by this FSM
    // must not see asynchronous reset release (DRC warning, can glitch BRAM
    // contents at reset de-assertion). The external `reset` is still the
    // board reset button; a double-synchronised `reset_sync` drives the FSM
    // fully synchronously off clk.
    reg reset_sync_0, reset_sync_1;
    always @(posedge clk) begin
        reset_sync_0 <= reset;
        reset_sync_1 <= reset_sync_0;
    end
    wire reset_n = reset_sync_1;   // active-low, sync

    always @(posedge clk) begin
        if (!reset_n) begin
            state <= S_IDLE;
            cpu_reset <= 1'b0; // Hold CPU in reset
            boot_we <= 1'b0;
            boot_addr <= 32'b0;
            boot_wdata <= 32'b0;
            byte_idx <= 0;
            payload_size <= 0;
            bytes_received <= 0;
        end else begin
            boot_we <= 1'b0; // Default to 0

            if (uart_rx_ready) begin
                case (state)
                    S_IDLE: begin
                        if (uart_rx_data == 8'hDE) state <= S_SYNC_1;
                        else state <= S_IDLE;
                    end
                    S_SYNC_1: begin
                        if (uart_rx_data == 8'hAD) state <= S_SYNC_2;
                        else state <= S_IDLE;
                    end
                    S_SYNC_2: begin
                        if (uart_rx_data == 8'hBE) state <= S_SYNC_3;
                        else state <= S_IDLE;
                    end
                    S_SYNC_3: begin
                        if (uart_rx_data == 8'hEF) begin
                            state <= S_SIZE;
                            byte_idx <= 0;
                            payload_size <= 0;
                        end else state <= S_IDLE;
                    end
                    S_SIZE: begin
                        payload_size <= payload_size | ({24'b0, uart_rx_data} << (byte_idx * 8));
                        if (byte_idx == 3) begin
                            state <= S_PAYLOAD;
                            byte_idx <= 0;
                            bytes_received <= 0;
                            boot_addr <= 32'b0;
                            boot_wdata <= 32'b0;
                            
                            $display("[BOOT FSM] Header size captured: %0d", payload_size | ({24'b0, uart_rx_data} << 24));
                            
                            // If zero size, done immediately
                            if (payload_size == 0 || (payload_size | ({24'b0, uart_rx_data} << 24)) == 0) begin
                                state <= S_DONE;
                                cpu_reset <= 1'b1;
                            end
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                    S_PAYLOAD: begin
                        if (byte_idx == 0) begin
                            boot_wdata <= {24'b0, uart_rx_data};
                        end else begin
                            boot_wdata <= boot_wdata | ({24'b0, uart_rx_data} << (byte_idx * 8));
                        end
                        
                        if (byte_idx == 3) begin
                            boot_we <= 1'b1; // Trigger write
                            byte_idx <= 0;
                            bytes_received <= bytes_received + 4;
                            // Clear boot_wdata for next iteration in 1 cycle
                            
                            if (bytes_received + 4 >= payload_size) begin
                                state <= S_DONE;
                                cpu_reset <= 1'b1; // Release CPU!
                            end
                        end else begin
                            byte_idx <= byte_idx + 1;
                        end
                    end
                    S_DONE: begin
                        // Stay here, CPU is running
                        cpu_reset <= 1'b1;
                    end
                endcase
            end else if (boot_we) begin
                // Increment address after the write is pulsed
                boot_addr <= boot_addr + 4;
            end
        end
    end

endmodule
