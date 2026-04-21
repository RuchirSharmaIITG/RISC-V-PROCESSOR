`timescale 1ns/1ps

module fp_regfile (
    input  wire        clk,
    input  wire        reset,
    
    // Read Port 1
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,
    
    // Read Port 2
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,
    
    // Write Port
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);

    // RV32F has 32 independent floating-point registers.
    // Unlike the integer register x0, the floating-point register f0 is NOT hardwired to zero.
    reg [31:0] fp_regs [31:0];
    
    integer i;

    // Synchronous write
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            for (i = 0; i < 32; i = i + 1) begin
                fp_regs[i] <= 32'b0;
            end
        end else if (we) begin
            fp_regs[waddr] <= wdata;
        end
    end

    // Asynchronous read (with bypass/forwarding logic is usually handled at the pipeline level,
    // but the raw read from the array happens here).
    assign rdata1 = fp_regs[raddr1];
    assign rdata2 = fp_regs[raddr2];

endmodule
