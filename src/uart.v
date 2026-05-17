`timescale 1ns / 1ps

module uart #(
    parameter CLK_FREQ = 50_000_000, // 100 MHz default
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset,

    // UART Physical pins
    input  wire       rx,
    output reg        tx,

    // TX Interface
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output wire       tx_full,

    // RX Interface
    output reg  [7:0] rx_data,
    output reg        rx_ready,
    input  wire       rx_ack     // Strobe high to clear rx_ready after reading
);

    // ----------------------------------------------------
    // Baud Rate Generator Parameters
    // ----------------------------------------------------
    localparam CLOCKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam OVERSAMPLE      = 16;
    localparam CLOCKS_PER_TICK = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);

    // ----------------------------------------------------
    // TX FSM
    // ----------------------------------------------------
    localparam TX_IDLE  = 2'b00;
    localparam TX_START = 2'b01;
    localparam TX_DATA  = 2'b10;
    localparam TX_STOP  = 2'b11;

    reg [1:0]  tx_state;
    reg [31:0] tx_timer;
    reg [2:0]  tx_bit_idx;
    reg [7:0]  tx_shift_reg;

    // FIFO Interface Wires
    wire [7:0] fifo_read_data;
    wire       fifo_empty;
    reg        fifo_read_en;

    uart_tx_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(1024)
    ) tx_fifo (
        .clk(clk),
        .reset(reset),
        .write_data(tx_data),
        .write_en(tx_start),
        .full(tx_full),
        .read_data(fifo_read_data),
        .read_en(fifo_read_en),
        .empty(fifo_empty)
    );

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            tx_state     <= TX_IDLE;
            tx_timer     <= 0;
            tx_bit_idx   <= 0;
            tx_shift_reg <= 0;
            tx           <= 1'b1;
            fifo_read_en <= 1'b0;
        end else begin
            // Default: do not read from FIFO unless we decide to this cycle
            fifo_read_en <= 1'b0;
            
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1; // Drive line high when idle
                    tx_timer <= 0;
                    tx_bit_idx <= 0;
                    if (!fifo_empty) begin
                        tx_shift_reg <= fifo_read_data;
                        fifo_read_en <= 1'b1; // Pop exactly one item
                        tx_state     <= TX_START;
                    end
                end
                
                TX_START: begin
                    tx <= 1'b0; // Drive low for Start bit
                    if (tx_timer == CLOCKS_PER_BIT - 1) begin
                        tx_timer <= 0;
                        tx_state <= TX_DATA;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end
                
                TX_DATA: begin
                    tx <= tx_shift_reg[tx_bit_idx]; // LSB first
                    if (tx_timer == CLOCKS_PER_BIT - 1) begin
                        tx_timer <= 0;
                        if (tx_bit_idx == 7) begin
                            tx_bit_idx <= 0;
                            tx_state   <= TX_STOP;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1;
                        end
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end
                
                TX_STOP: begin
                    tx <= 1'b1; // Drive high for Stop bit
                    if (tx_timer == CLOCKS_PER_BIT - 1) begin
                        tx_timer <= 0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end
            endcase
        end
    end

    // ----------------------------------------------------
    // RX FSM (16x Oversampling)
    // ----------------------------------------------------
    localparam RX_IDLE  = 2'b00;
    localparam RX_START = 2'b01;
    localparam RX_DATA  = 2'b10;
    localparam RX_STOP  = 2'b11;

    reg [1:0]  rx_state;
    reg [31:0] rx_tick_timer;
    reg [3:0]  rx_ticks;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift_reg;
    
    // Double-flop synchronizer to prevent metastability on asynchronous RX input
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            rx_state      <= RX_IDLE;
            rx_tick_timer <= 0;
            rx_ticks      <= 0;
            rx_bit_idx    <= 0;
            rx_shift_reg  <= 0;
            rx_data       <= 0;
            rx_ready      <= 1'b0;
        end else begin
            // Handshake logic: Clear the ready flag when the pipeline acknowledges reading
            if (rx_ack) begin
                rx_ready <= 1'b0;
            end
            
            // Generate ticks precisely at OVERSAMPLE rate (e.g., 16 ticks per bit)
            if (rx_tick_timer == CLOCKS_PER_TICK - 1) begin
                rx_tick_timer <= 0;
                
                case (rx_state)
                    RX_IDLE: begin
                        rx_ticks   <= 0;
                        rx_bit_idx <= 0;
                        // Falling edge detected (Start bit candidate)
                        if (rx_sync2 == 1'b0) begin 
                            rx_state <= RX_START;
                        end
                    end
                    
                    RX_START: begin
                        if (rx_ticks == 7) begin // Sample precisely in the middle of the start bit
                            if (rx_sync2 == 1'b0) begin // Verify it's a real start bit
                                rx_ticks <= 0;
                                rx_state <= RX_DATA;
                            end else begin
                                rx_state <= RX_IDLE; // Glitch detected, abort
                            end
                        end else begin
                            rx_ticks <= rx_ticks + 1;
                        end
                    end
                    
                    RX_DATA: begin
                        if (rx_ticks == 15) begin // Sample in the middle of subsequent bits (16 ticks later)
                            rx_ticks <= 0;
                            // Shift in LSB first
                            rx_shift_reg <= {rx_sync2, rx_shift_reg[7:1]};
                            if (rx_bit_idx == 7) begin
                                rx_state <= RX_STOP;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 1;
                            end
                        end else begin
                            rx_ticks <= rx_ticks + 1;
                        end
                    end
                    
                    RX_STOP: begin
                        if (rx_ticks == 15) begin // Sample middle of the stop bit
                            rx_ticks <= 0;
                            rx_state <= RX_IDLE;
                            // Verify stop bit is High (valid stop)
                            if (rx_sync2 == 1'b1) begin 
                                rx_data  <= rx_shift_reg;
                                rx_ready <= 1'b1; // Assert ready mapping to pipeline register full
                            end
                        end else begin
                            rx_ticks <= rx_ticks + 1;
                        end
                    end
                endcase
                
            end else begin
                // Turn on the tick timer if we're parsing RX or if we see a candidate start edge
                if (rx_state != RX_IDLE || rx_sync2 == 1'b0) begin
                    rx_tick_timer <= rx_tick_timer + 1;
                end else begin
                    rx_tick_timer <= 0; // Hold at 0 whilst line is idle (keeps start-edge aligned!)
                end
            end
        end
    end

endmodule
