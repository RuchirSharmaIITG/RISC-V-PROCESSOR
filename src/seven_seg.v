`timescale 1ns / 1ps

module seven_seg (
    input wire clk,          // 100MHz clock
    input wire reset,        // active low
    input wire [31:0] data,  // 32-bit data to display (8 hex digits)
    output reg [6:0] seg,    // 7 segments (active low usually)
    output reg [7:0] an,     // 8 anodes (active low)
    output wire dp           // decimal point
);

    // Decimal point off
    assign dp = 1'b1;

    // Refresh counter to multiplex the 8 displays
    // At 100MHz, a 17-bit counter overflows at ~762Hz. 
    // The top 3 bits [19:17] will cycle through 0-7 at ~762Hz.
    reg [19:0] refresh_counter;
    always @(posedge clk) begin
        if (!reset)
            refresh_counter <= 0;
        else
            refresh_counter <= refresh_counter + 1;
    end

    wire [2:0] led_activating_counter = refresh_counter[19:17];

    // Anode activation
    always @(*) begin
        case(led_activating_counter)
            3'b000: an = 8'b11111110; // digit 0 (rightmost)
            3'b001: an = 8'b11111101; // digit 1
            3'b010: an = 8'b11111011; // digit 2
            3'b011: an = 8'b11110111; // digit 3
            3'b100: an = 8'b11101111; // digit 4
            3'b101: an = 8'b11011111; // digit 5
            3'b110: an = 8'b10111111; // digit 6
            3'b111: an = 8'b01111111; // digit 7 (leftmost)
            default: an = 8'b11111111;
        endcase
    end

    // Data multiplexer
    reg [3:0] hex_digit;
    always @(*) begin
        case(led_activating_counter)
            3'b000: hex_digit = data[3:0];
            3'b001: hex_digit = data[7:4];
            3'b010: hex_digit = data[11:8];
            3'b011: hex_digit = data[15:12];
            3'b100: hex_digit = data[19:16];
            3'b101: hex_digit = data[23:20];
            3'b110: hex_digit = data[27:24];
            3'b111: hex_digit = data[31:28];
            default: hex_digit = 4'h0;
        endcase
    end

    // Hex to 7-segment decoder (active low segments)
    always @(*) begin
        case(hex_digit)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
