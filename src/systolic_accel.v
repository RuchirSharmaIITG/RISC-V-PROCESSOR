`timescale 1ns/1ps
//============================================================================
// SYSTOLIC_ACCEL — Memory-Mapped 4×4 Systolic Array Accelerator
//
// Computes C = A × B for NxN matrices (N = 1..4) using an output-stationary
// 4×4 PE grid.  The CPU writes A and B elements, sets the dimension, and
// pulses a start bit.  An internal FSM feeds the skewed data wavefront
// through the PE array in 3N−2 clock cycles, then signals done.
//
// Memory Map (byte offsets from base 0x9000_0000):
//   0x000  CTRL    [W]   bit 0 = start
//   0x004  STATUS  [R]   bit 0 = done, bit 1 = busy
//   0x008  DIM_N   [RW]  matrix dimension (1–4), default 4
//   0x100  MAT_A   [W]   A[i*4+j] at offset 0x100 + (i*4+j)*4
//   0x200  MAT_B   [W]   B[i*4+j] at offset 0x200 + (i*4+j)*4
//   0x300  MAT_C   [R]   C[i*4+j] at offset 0x300 + (i*4+j)*4
//============================================================================

module systolic_accel #(
    parameter N  = 4,       // fixed grid size
    parameter DW = 16,      // operand width
    parameter AW = 32       // accumulator / result width
)(
    input  wire        clk,
    input  wire        rst_n,       // active-low reset (matches SoC)

    // CPU write port
    input  wire        wr_en,
    input  wire [11:0] wr_addr,     // byte offset from base
    input  wire [31:0] wr_data,

    // CPU read port (combinational output, latched by top_fpga)
    input  wire [11:0] rd_addr,
    output reg  [31:0] rd_data
);

    // ================================================================
    // Matrix storage (16-bit signed, 16 elements each)
    // ================================================================
    reg signed [DW-1:0] mat_a [0:N*N-1];
    reg signed [DW-1:0] mat_b [0:N*N-1];

    // Configuration
    reg [2:0] dim_n;   // actual matrix dimension (1–4)

    // ================================================================
    // FSM
    // ================================================================
    localparam [1:0] S_IDLE  = 2'd0,
                     S_CLEAR = 2'd1,
                     S_FEED  = 2'd2,
                     S_DONE  = 2'd3;

    reg  [1:0] state;
    reg  [3:0] tick;                              // feed-cycle counter
    wire [3:0] last_tick = dim_n * 3 - 3;         // 3N−3  (0-based end)

    // Start pulse — detected combinationally from the CPU store
    wire start_cmd = wr_en
                   && (wr_addr[11:8] == 4'h0)
                   && (wr_addr[7:0]  == 8'h00)
                   && wr_data[0];

    // PE control
    wire pe_clr = (state == S_CLEAR);
    wire pe_vld = (state == S_FEED);

    // ================================================================
    // Skewed edge inputs  (combinational from tick + stored matrices)
    //
    // Row i  of A is delayed by i cycles   → a_edge[i]
    // Col j  of B is delayed by j cycles   → b_edge[j]
    // ================================================================
    reg signed [DW-1:0] a_edge [0:N-1];
    reg signed [DW-1:0] b_edge [0:N-1];

    always @(*) begin
        // Defaults — zero when not feeding
        a_edge[0] = {DW{1'b0}};  a_edge[1] = {DW{1'b0}};
        a_edge[2] = {DW{1'b0}};  a_edge[3] = {DW{1'b0}};
        b_edge[0] = {DW{1'b0}};  b_edge[1] = {DW{1'b0}};
        b_edge[2] = {DW{1'b0}};  b_edge[3] = {DW{1'b0}};

        if (state == S_FEED) begin
            // ---- Row / Col 0 : no skew ----
            if (tick < dim_n) begin
                a_edge[0] = mat_a[tick];            // A[0][k]
                b_edge[0] = mat_b[tick * 4];        // B[k][0]
            end
            // ---- Row / Col 1 : 1-cycle skew ----
            if (tick >= 1 && (tick - 1) < dim_n) begin
                a_edge[1] = mat_a[4  + tick - 1];           // A[1][k]
                b_edge[1] = mat_b[(tick - 1) * 4 + 1];     // B[k][1]
            end
            // ---- Row / Col 2 : 2-cycle skew ----
            if (tick >= 2 && (tick - 2) < dim_n) begin
                a_edge[2] = mat_a[8  + tick - 2];           // A[2][k]
                b_edge[2] = mat_b[(tick - 2) * 4 + 2];     // B[k][2]
            end
            // ---- Row / Col 3 : 3-cycle skew ----
            if (tick >= 3 && (tick - 3) < dim_n) begin
                a_edge[3] = mat_a[12 + tick - 3];           // A[3][k]
                b_edge[3] = mat_b[(tick - 3) * 4 + 3];     // B[k][3]
            end
        end
    end

    // ================================================================
    // 4×4 PE grid  (generate)
    // ================================================================
    wire signed [AW-1:0] c_flat [0:N*N-1];   // flat result tap

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : ROW
            for (gj = 0; gj < N; gj = gj + 1) begin : COL

                // ---- wires local to this PE ----
                wire signed [DW-1:0] pe_a_out;
                wire signed [DW-1:0] pe_b_out;
                wire signed [AW-1:0] pe_acc;

                // ---- A input : left edge or left neighbour ----
                wire signed [DW-1:0] pe_a_in;
                if (gj == 0) begin : A_EDGE
                    assign pe_a_in = a_edge[gi];
                end else begin : A_CHAIN
                    assign pe_a_in = ROW[gi].COL[gj-1].pe_a_out;
                end

                // ---- B input : top edge or upper neighbour ----
                wire signed [DW-1:0] pe_b_in;
                if (gi == 0) begin : B_EDGE
                    assign pe_b_in = b_edge[gj];
                end else begin : B_CHAIN
                    assign pe_b_in = ROW[gi-1].COL[gj].pe_b_out;
                end

                // ---- PE instance ----
                pe_mac #(.DW(DW), .AW(AW)) u_pe (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .clr   (pe_clr),
                    .vld   (pe_vld),
                    .a_in  (pe_a_in),
                    .b_in  (pe_b_in),
                    .a_out (pe_a_out),
                    .b_out (pe_b_out),
                    .acc   (pe_acc)
                );

                // ---- result tap ----
                assign c_flat[gi * N + gj] = pe_acc;
            end
        end
    endgenerate

    // ================================================================
    // FSM + MMIO Write Logic
    // ================================================================
    integer idx;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            tick  <= 4'd0;
            dim_n <= 3'd4;
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                mat_a[idx] <= {DW{1'b0}};
                mat_b[idx] <= {DW{1'b0}};
            end
        end else begin

            // ---- MMIO writes (active in any state) ----
            if (wr_en) begin
                case (wr_addr[11:8])
                    4'h0: begin
                        if (wr_addr[7:0] == 8'h08)
                            dim_n <= wr_data[2:0];
                    end
                    4'h1: mat_a[wr_addr[5:2]] <= wr_data[DW-1:0];
                    4'h2: mat_b[wr_addr[5:2]] <= wr_data[DW-1:0];
                    default: ;
                endcase
            end

            // ---- FSM transitions ----
            case (state)
                S_IDLE: begin
                    tick <= 4'd0;
                    if (start_cmd)
                        state <= S_CLEAR;
                end

                S_CLEAR: begin          // 1 cycle : pe_clr resets accumulators
                    tick  <= 4'd0;
                    state <= S_FEED;
                end

                S_FEED: begin           // 3N-2 cycles : skewed data wavefront
                    if (tick == last_tick)
                        state <= S_DONE;
                    else
                        tick <= tick + 4'd1;
                end

                S_DONE: begin           // hold until next start
                    tick <= 4'd0;
                    if (start_cmd)
                        state <= S_CLEAR;
                end
            endcase
        end
    end

    // ================================================================
    // MMIO Read (Combinational — latched by top_fpga.v)
    // ================================================================
    always @(*) begin
        rd_data = 32'd0;
        case (rd_addr[11:8])
            4'h0: begin
                case (rd_addr[7:0])
                    8'h04: rd_data = {30'd0,
                                      (state == S_CLEAR || state == S_FEED) ? 1'b1 : 1'b0,  // bit 1 busy
                                      (state == S_DONE) ? 1'b1 : 1'b0};                       // bit 0 done
                    8'h08: rd_data = {29'd0, dim_n};
                    default: rd_data = 32'd0;
                endcase
            end
            4'h3: rd_data = c_flat[rd_addr[5:2]];   // C result
            default: rd_data = 32'd0;
        endcase
    end

endmodule
