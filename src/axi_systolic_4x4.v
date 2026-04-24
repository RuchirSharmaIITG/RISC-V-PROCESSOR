`timescale 1ns/1ps

module processing_element #(
    parameter DWIDTH = 32
)(
    input  wire              clk,
    input  wire              reset,
    input  wire              en,
    
    // The stationary weight (Matrix B) pre-loaded into this cell
    input  wire [DWIDTH-1:0] weight,
    
    // Activations (Matrix A) flowing from Left to Right
    input  wire [DWIDTH-1:0] act_in,
    output reg  [DWIDTH-1:0] act_out,
    
    // Partial Sums flowing from Top to Bottom
    input  wire [DWIDTH-1:0] psum_in,
    output reg  [DWIDTH-1:0] psum_out
);

    always @(posedge clk) begin
        if (!reset) begin
            act_out  <= 0;
            psum_out <= 0;
        end else if (en) begin
            // 1. Pass the activation straight through to the PE on the right
            act_out <= act_in;
            
            // 2. Multiply-Accumulate (MAC): Add the top sum to (Activation * Weight)
            psum_out <= psum_in + (act_in * weight);
        end
    end

endmodule

module systolic_array_4x4 #(
    parameter DWIDTH = 32
)(
    input  wire clk,
    input  wire reset,
    input  wire en,
    
    // Weights (16 weights flattened into one giant wire for easy loading)
    input  wire [(16 * DWIDTH)-1:0] weights_flat,
    
    // 4 rows of Activations entering the left side of the grid
    input  wire [DWIDTH-1:0] act_in_0,
    input  wire [DWIDTH-1:0] act_in_1,
    input  wire [DWIDTH-1:0] act_in_2,
    input  wire [DWIDTH-1:0] act_in_3,
    
    // 4 columns of Partial Sums entering the top of the grid
    input  wire [DWIDTH-1:0] psum_in_0,
    input  wire [DWIDTH-1:0] psum_in_1,
    input  wire [DWIDTH-1:0] psum_in_2,
    input  wire [DWIDTH-1:0] psum_in_3,
    
    // 4 columns of Final Results exiting the bottom of the grid
    output wire [DWIDTH-1:0] psum_out_0,
    output wire [DWIDTH-1:0] psum_out_1,
    output wire [DWIDTH-1:0] psum_out_2,
    output wire [DWIDTH-1:0] psum_out_3
);

    wire [DWIDTH-1:0] act_wires  [0:3][0:4]; 
    wire [DWIDTH-1:0] psum_wires [0:4][0:3]; 
    
    assign act_wires[0][0] = act_in_0;
    assign act_wires[1][0] = act_in_1;
    assign act_wires[2][0] = act_in_2;
    assign act_wires[3][0] = act_in_3;
    
    assign psum_wires[0][0] = psum_in_0;
    assign psum_wires[0][1] = psum_in_1;
    assign psum_wires[0][2] = psum_in_2;
    assign psum_wires[0][3] = psum_in_3;
    
    assign psum_out_0 = psum_wires[4][0];
    assign psum_out_1 = psum_wires[4][1];
    assign psum_out_2 = psum_wires[4][2];
    assign psum_out_3 = psum_wires[4][3];

    genvar row, col;
    generate
        for (row = 0; row < 4; row = row + 1) begin : row_gen
            for (col = 0; col < 4; col = col + 1) begin : col_gen
                
                processing_element #(
                    .DWIDTH(DWIDTH)
                ) PE (
                    .clk     (clk),
                    .reset   (reset),
                    .en      (en),
                    .weight  (weights_flat[((row*4 + col)*DWIDTH) +: DWIDTH]),
                    .act_in  (act_wires[row][col]),
                    .act_out (act_wires[row][col+1]),
                    .psum_in (psum_wires[row][col]),
                    .psum_out(psum_wires[row+1][col])
                );
                
            end
        end
    endgenerate

endmodule

module axi_systolic_4x4 #(
    parameter DWIDTH = 32
)(
    input clk, reset,
    
    // AXI4-Lite Slave interface 
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    reg [31:0] weight_reg [0:15];
    reg [31:0] act_reg [0:3];
    reg step_trigger;
    
    wire [511:0] weights_flat = {
        weight_reg[15], weight_reg[14], weight_reg[13], weight_reg[12],
        weight_reg[11], weight_reg[10], weight_reg[9],  weight_reg[8],
        weight_reg[7],  weight_reg[6],  weight_reg[5],  weight_reg[4],
        weight_reg[3],  weight_reg[2],  weight_reg[1],  weight_reg[0]
    };
    
    // Wavefront Generator (Skew Buffers)
    reg [31:0] wf_row1_d1;
    reg [31:0] wf_row2_d1, wf_row2_d2;
    reg [31:0] wf_row3_d1, wf_row3_d2, wf_row3_d3;
    
    always @(posedge clk) begin
        if (!reset) begin
            wf_row1_d1 <= 0;
            wf_row2_d1 <= 0; wf_row2_d2 <= 0;
            wf_row3_d1 <= 0; wf_row3_d2 <= 0; wf_row3_d3 <= 0;
        end else if (step_trigger) begin
            wf_row1_d1 <= act_reg[1];
            wf_row2_d1 <= act_reg[2]; wf_row2_d2 <= wf_row2_d1;
            wf_row3_d1 <= act_reg[3]; wf_row3_d2 <= wf_row3_d1; wf_row3_d3 <= wf_row3_d2;
        end
    end

    // Accumulators to capture result as they slide out
    reg [31:0] final_out_0, final_out_1, final_out_2, final_out_3;
    reg step_trigger_d1;
    always @(posedge clk) begin
        if (!reset) begin
            step_trigger_d1 <= 0;
        end else begin
            step_trigger_d1 <= step_trigger;
        end
    end
    
    wire [31:0] psum_out_0, psum_out_1, psum_out_2, psum_out_3;
    
    systolic_array_4x4 #(
        .DWIDTH(32)
    ) ARRAY (
        .clk(clk),
        .reset(reset),
        .en(step_trigger),
        .weights_flat(weights_flat),
        .act_in_0(act_reg[0]),
        .act_in_1(wf_row1_d1),
        .act_in_2(wf_row2_d2),
        .act_in_3(wf_row3_d3),
        .psum_in_0(32'd0), .psum_in_1(32'd0), .psum_in_2(32'd0), .psum_in_3(32'd0),
        .psum_out_0(psum_out_0), .psum_out_1(psum_out_1), .psum_out_2(psum_out_2), .psum_out_3(psum_out_3)
    );

    reg aw_en;
    reg w_en;
    reg [31:0] waddr_latched;
    reg [31:0] read_addr_buf;

    // AXI WRITE logic
    always @(posedge clk) begin
        step_trigger <= 0;
        
        if (!reset) begin
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;
            aw_en <= 0;
            w_en <= 0;
            waddr_latched <= 0;
            final_out_0 <= 0; final_out_1 <= 0; final_out_2 <= 0; final_out_3 <= 0;
            // Initialize memory arrays minimally
        end else begin
            // Handshake AW
            if (s_axi_awvalid && !s_axi_awready && !aw_en) begin
                s_axi_awready <= 1;
                aw_en <= 1;
                waddr_latched <= s_axi_awaddr;
            end else if (s_axi_awready) begin
                s_axi_awready <= 0;
            end

            // Handshake W
            if (s_axi_wvalid && !s_axi_wready && !w_en) begin
                s_axi_wready <= 1;
                w_en <= 1;
            end else if (s_axi_wready) begin
                s_axi_wready <= 0;
            end
            
            // Capture results one cycle after step_trigger
            if (step_trigger_d1) begin
                final_out_0 <= psum_out_0;
                final_out_1 <= psum_out_1;
                final_out_2 <= psum_out_2;
                final_out_3 <= psum_out_3;
            end

            // Perform actual memory write mapped at 0x5... base when BOTH latched
            if (aw_en && w_en && !s_axi_bvalid) begin
                if (waddr_latched[7:0] >= 8'h00 && waddr_latched[7:0] <= 8'h3C) begin
                    weight_reg[waddr_latched[7:0] >> 2] <= s_axi_wdata; // Write Weights
                end else if (waddr_latched[7:0] >= 8'h40 && waddr_latched[7:0] <= 8'h4C) begin
                    act_reg[(waddr_latched[7:0] - 8'h40) >> 2] <= s_axi_wdata; // Write Activations
                    if (waddr_latched[7:0] == 8'h40) begin
                        final_out_0 <= 0; final_out_1 <= 0; final_out_2 <= 0; final_out_3 <= 0;
                    end
                end else if (waddr_latched[7:0] == 8'h50) begin
                    step_trigger <= 1; // Trigger One Step Pulse
                end
                
                s_axi_bvalid <= 1;
                s_axi_bresp <= 2'b00;
                aw_en <= 0;
                w_en <= 0;
            end else if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
        end
    end

// AXI READ logic
    always @(posedge clk) begin
        if (!reset) begin
            s_axi_arready <= 0;
            s_axi_rvalid <= 0;
        end else begin
            // 1. Acknowledge address and latch it
            if (s_axi_arvalid && !s_axi_arready) begin
                s_axi_arready <= 1;
                read_addr_buf <= s_axi_araddr;
            end else begin
                s_axi_arready <= 0;
            end
            
            // 2. Assert valid and present data on the NEXT cycle
            if (s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= 2'b00;
                
                // Decode from the latched buffer
                if (read_addr_buf[7:0] == 8'h60) s_axi_rdata <= final_out_0;
                else if (read_addr_buf[7:0] == 8'h64) s_axi_rdata <= final_out_1;
                else if (read_addr_buf[7:0] == 8'h68) s_axi_rdata <= final_out_2;
                else if (read_addr_buf[7:0] == 8'h6C) s_axi_rdata <= final_out_3;
                else s_axi_rdata <= 32'h0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 0;
            end
        end
    end
endmodule
