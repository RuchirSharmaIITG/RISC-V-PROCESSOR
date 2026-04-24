`timescale 1ns/1ps

module csr_file (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [11:0] csr_raddr,
    output reg  [31:0] csr_rdata,
    
    input  wire        csr_we,
    input  wire [11:0] csr_waddr,
    input  wire [31:0] csr_wdata,
    
    // Exception hooks
    input  wire        exception_trigger,
    input  wire [31:0] exception_cause,
    input  wire [31:0] exception_pc,
    output wire [31:0] exception_vector
);

    // Standard CSR addresses
    localparam MSTATUS = 12'h300;
    localparam MISA    = 12'h301;
    localparam MTVEC   = 12'h305;
    localparam MEPC    = 12'h341;
    localparam MCAUSE  = 12'h342;

    reg [31:0] mstatus; // Machine status
    reg [31:0] mtvec;   // Machine trap-handler base address
    reg [31:0] mepc;    // Machine exception program counter
    reg [31:0] mcause;  // Machine trap cause

    assign exception_vector = mtvec;

    // CSR Read (Combinational)
    always @(*) begin
        case (csr_raddr)
            MSTATUS: csr_rdata = mstatus;
            // 0x40001120 = RV32 (Bit 30=1), plus I (Bit 8=1), M (Bit 12=1), F (Bit 5=1)
            MISA:    csr_rdata = 32'h40001120; 
            MTVEC:   csr_rdata = mtvec;
            MEPC:    csr_rdata = mepc;
            MCAUSE:  csr_rdata = mcause;
            default: csr_rdata = 32'h0;
        endcase
    end

    // CSR Write & Exception Trapping (Sequential)
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mstatus <= 32'h0;
            mtvec   <= 32'h0;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
        end
        else begin
            // Hardware Exception takes highest priority
            if (exception_trigger) begin
                mepc    <= exception_pc;
                mcause  <= exception_cause;
                // typically disable interrupts in mstatus here
            end
            // Software Write takes secondary priority
            else if (csr_we) begin
                case (csr_waddr)
                    MSTATUS: mstatus <= csr_wdata;
                    MTVEC:   mtvec   <= csr_wdata;
                    MEPC:    mepc    <= csr_wdata; // ALLOWS SOFTWARE TO ADVANCE PC!
                    MCAUSE:  mcause  <= csr_wdata;
                endcase
            end
        end
    end

endmodule
