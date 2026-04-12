module UART_TX (
    input clk,
    input rst,
    input start,
    input [7:0] data,
    output reg tx,
    output reg ready
);
    // Assuming 50MHz clk, 115200 baud -> 434 clocks per bit. Adjust for actual clock.
    parameter CLKS_PER_BIT = 434;

    reg [2:0] state; // 0: IDLE, 1: START, 2: DATA, 3: STOP
    reg [12:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] tx_data;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= 0;
            tx <= 1'b1;
            ready <= 1'b1;
            clk_count <= 0;
            bit_index <= 0;
            tx_data <= 0;
        end else begin
            case (state)
                0: begin
                    tx <= 1'b1;
                    ready <= 1'b1;
                    if (start) begin
                        state <= 1;
                        tx_data <= data;
                        clk_count <= 0;
                        ready <= 1'b0;
                    end
                end
                1: begin // Start Bit
                    tx <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= 2;
                        bit_index <= 0;
                    end
                end
                2: begin // Data Bits
                    tx <= tx_data[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= 3;
                        end
                    end
                end
                3: begin // Stop Bit
                    tx <= 1'b1;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= 0; // go back to IDLE
                        ready <= 1'b1;
                    end
                end
            endcase
        end
    end
endmodule