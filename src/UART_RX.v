module UART_RX (
    input clk,
    input rst,
    input rx,
    output reg [7:0] data,
    output reg valid
);
    parameter CLKS_PER_BIT = 434;

    reg [2:0] state; // 0: IDLE, 1: START, 2: DATA, 3: STOP
    reg [12:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] rx_data;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= 0;
            data <= 0;
            valid <= 0;
            clk_count <= 0;
            bit_index <= 0;
            rx_data <= 0;
        end else begin
            case (state)
                0: begin
                    valid <= 1'b0;
                    if (rx == 1'b0) begin // Start bit detected
                        state <= 1;
                        clk_count <= 0;
                    end
                end
                1: begin // Wait half a bit period to sample in the middle
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx == 1'b0) begin // Verify still low
                            clk_count <= 0;
                            state <= 2;
                            bit_index <= 0;
                        end else begin
                            state <= 0; // False start
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                2: begin // Read Data Bits
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        rx_data[bit_index] <= rx;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= 3;
                        end
                    end
                end
                3: begin // Stop Bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= 0; // go back to IDLE
                        if (rx == 1'b1) begin // valid stop bit
                            data <= rx_data;
                            valid <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
