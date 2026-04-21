`timescale 1ns/1ps
//============================================================================
// PE_MAC — Output-Stationary Systolic Processing Element
//
// Each clock cycle when `vld` is high:
//   acc  <= acc + a_in * b_in   (16×16 → 32-bit MAC, maps to one DSP48E1)
//   a_out <= a_in               (pass A rightward)
//   b_out <= b_in               (pass B downward)
//
// `clr` resets only the accumulator (used between matrix tiles).
// `rst_n` is the global active-low reset.
//============================================================================

module pe_mac #(
    parameter DW = 16,   // operand width  (A and B)
    parameter AW = 32    // accumulator width (C)
)(
    input  wire              clk,
    input  wire              rst_n,   // active-low global reset
    input  wire              clr,     // clear accumulator (active-high)
    input  wire              vld,     // data-valid / enable

    input  wire signed [DW-1:0] a_in,
    input  wire signed [DW-1:0] b_in,

    output reg  signed [DW-1:0] a_out,
    output reg  signed [DW-1:0] b_out,
    output reg  signed [AW-1:0] acc
);

    always @(posedge clk) begin
        if (!rst_n || clr) begin
            a_out <= {DW{1'b0}};
            b_out <= {DW{1'b0}};
            acc   <= {AW{1'b0}};
        end else if (vld) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= acc + a_in * b_in;
        end
    end

endmodule
