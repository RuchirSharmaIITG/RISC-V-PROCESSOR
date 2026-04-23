`timescale 1ns/1ps

module axi_cordic_slave (
    input clk, reset,

    // AXI4-Lite Slave Interface 
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

    reg cordic_start;
    reg [31:0]  cordic_target_angle;
    wire        cordic_valid_out;
    wire [31:0] cordic_sin_out;
    wire [31:0] cordic_cos_out;

    reg [31:0] read_addr_buf;
    
    cordic_iterative CORDIC_CORE (
        .clk(clk),
        .reset(reset),
        .start(cordic_start),
        .target_angle(cordic_target_angle),
        .valid_out(cordic_valid_out),
        .sin_out(cordic_sin_out),
        .cos_out(cordic_cos_out)
    );

    // Track when status read occurs.
    // IMPORTANT: cordic_start must have HIGHER priority than cordic_valid_out.
    // If both fire in the same cycle (new request arrives same cycle computation ends),
    // we must clear the flag so the CPU correctly waits for the new result.
    reg latched_valid;
    always @(posedge clk) begin
        if (!reset)         latched_valid <= 0;
        else if (cordic_start) latched_valid <= 0; // New request: always clear first
        else if (cordic_valid_out) latched_valid <= 1; // Only set when no new request
    end

    reg aw_en;
    reg w_en;
    reg [31:0] waddr_latched;

    // AXI WRITE logic
    always @(posedge clk) begin
        cordic_start <= 0;
        if (!reset) begin
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;
            aw_en <= 0;
            w_en <= 0;
            waddr_latched <= 0;
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
            
            // Perform write when BOTH have been latched and bvalid isn't asserting 
            if (aw_en && w_en && !s_axi_bvalid) begin
                if (waddr_latched[7:0] == 8'h00) begin
                    cordic_target_angle <= s_axi_wdata;
                    cordic_start <= 1;
                    $display("[CORDIC] Start triggered with angle: %h", s_axi_wdata);
                end
                s_axi_bvalid <= 1;
                s_axi_bresp <= 2'b00;
                aw_en <= 0;
                w_en <= 0;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 0;
            end
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
                read_addr_buf <= s_axi_araddr; // Latch the address
            end else begin
                s_axi_arready <= 0;
            end
            
            // 2. Assert valid and present data on the NEXT cycle
            if (s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= 2'b00;
                
                // CRITICAL: Use the latched buffer here, not s_axi_araddr!
                case (read_addr_buf[7:0])
                    8'h04: s_axi_rdata <= {31'b0, latched_valid};
                    8'h08: s_axi_rdata <= cordic_sin_out;
                    8'h0C: s_axi_rdata <= cordic_cos_out;
                    default: s_axi_rdata <= 32'h0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 0;
            end
        end
    end

endmodule
