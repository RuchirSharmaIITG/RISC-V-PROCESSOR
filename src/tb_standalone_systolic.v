`timescale 1ns/1ps

// Standalone Systolic Array test: AXI Master -> AXI Slave -> 4x4 Array
// Tests Identity*Vector and Scale-by-2 without CPU involvement.
module tb_standalone_systolic;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 0;

    wire [31:0] m_awaddr, m_araddr, m_wdata, m_rdata;
    wire [2:0]  m_awprot, m_arprot;
    wire        m_awvalid, m_awready, m_wvalid, m_wready;
    wire [3:0]  m_wstrb;
    wire [1:0]  m_bresp, m_rresp;
    wire        m_bvalid, m_bready;
    wire        m_arvalid, m_arready, m_rvalid, m_rready;

    reg         req_enable = 0;
    reg         req_write  = 0;
    reg  [31:0] req_addr   = 0;
    reg  [31:0] req_wdata  = 0;
    reg  [3:0]  req_wstrb  = 4'hF;
    wire        axi_busy;
    wire [31:0] axi_rdata;

    axi4_lite_master MASTER (
        .clk(clk), .reset(reset),
        .req_enable(req_enable), .req_write(req_write),
        .req_addr(req_addr), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
        .axi_busy(axi_busy), .axi_rdata(axi_rdata),
        .m_axi_awaddr(m_awaddr), .m_axi_awprot(m_awprot),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_araddr(m_araddr), .m_axi_arprot(m_arprot),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata_in(m_rdata), .m_axi_rresp(m_rresp),
        .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready)
    );

    axi_systolic_4x4 SLAVE (
        .clk(clk), .reset(reset),
        .s_axi_awaddr(m_awaddr), .s_axi_awprot(m_awprot),
        .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata), .s_axi_wstrb(m_wstrb),
        .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bresp(m_bresp), .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
        .s_axi_araddr(m_araddr), .s_axi_arprot(m_arprot),
        .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp),
        .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready)
    );

    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            req_enable <= 1; req_write <= 1;
            req_addr <= addr; req_wdata <= data;
            @(posedge clk);
            wait(axi_busy);
            wait(!axi_busy);
            @(posedge clk);
            req_enable <= 0; req_write <= 0;
            @(posedge clk);
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            req_enable <= 1; req_write <= 0;
            req_addr <= addr;
            @(posedge clk);
            wait(axi_busy);
            wait(!axi_busy);
            data = axi_rdata;
            @(posedge clk);
            req_enable <= 0;
            @(posedge clk);
        end
    endtask

    reg [31:0] rdata;
    integer i;

    initial begin
        $display("=== STANDALONE SYSTOLIC ARRAY TEST ===");
        #20 reset = 1;
        #20;

        // --- TEST 1: Identity Matrix x Vector [10, 20, 30, 40] ---
        $display("\n--- Test 1: Identity * [10, 20, 30, 40] ---");
        
        // Clear all weights to 0
        for (i = 0; i < 16; i = i + 1)
            axi_write(32'h50000000 + (i * 4), 0);
        
        // Set diagonal to 1 (identity)
        axi_write(32'h50000000, 1);       // W[0][0] = 1
        axi_write(32'h50000014, 1);       // W[1][1] = 1 (offset 5*4=0x14)
        axi_write(32'h50000028, 1);       // W[2][2] = 1 (offset 10*4=0x28)
        axi_write(32'h5000003C, 1);       // W[3][3] = 1 (offset 15*4=0x3C)
        
        // Load activations [10, 20, 30, 40]
        axi_write(32'h50000040, 10);
        axi_write(32'h50000044, 20);
        axi_write(32'h50000048, 30);
        axi_write(32'h5000004C, 40);
        
        // Pulse 7 steps (holding inputs steady for wavefront)
        for (i = 0; i < 7; i = i + 1)
            axi_write(32'h50000050, 1);
        
        // Read results (offsets 0x60-0x6C)
        axi_read(32'h50000060, rdata); $display("  Out[0] = %0d (expect 10)", rdata);
        axi_read(32'h50000064, rdata); $display("  Out[1] = %0d (expect 20)", rdata);
        axi_read(32'h50000068, rdata); $display("  Out[2] = %0d (expect 30)", rdata);
        axi_read(32'h5000006C, rdata); $display("  Out[3] = %0d (expect 40)", rdata);

        // --- TEST 2: Scale-by-2 Diagonal x [5, 10, 15, 20] ---
        $display("\n--- Test 2: Scale-by-2 * [5, 10, 15, 20] ---");
        
        for (i = 0; i < 16; i = i + 1)
            axi_write(32'h50000000 + (i * 4), 0);
        axi_write(32'h50000000, 2);       // W[0][0] = 2
        axi_write(32'h50000014, 2);       // W[1][1] = 2
        axi_write(32'h50000028, 2);       // W[2][2] = 2
        axi_write(32'h5000003C, 2);       // W[3][3] = 2

        axi_write(32'h50000040, 5);
        axi_write(32'h50000044, 10);
        axi_write(32'h50000048, 15);
        axi_write(32'h5000004C, 20);
        
        for (i = 0; i < 7; i = i + 1)
            axi_write(32'h50000050, 1);
        
        axi_read(32'h50000060, rdata); $display("  Out[0] = %0d (expect 10)", rdata);
        axi_read(32'h50000064, rdata); $display("  Out[1] = %0d (expect 20)", rdata);
        axi_read(32'h50000068, rdata); $display("  Out[2] = %0d (expect 30)", rdata);
        axi_read(32'h5000006C, rdata); $display("  Out[3] = %0d (expect 40)", rdata);

        $display("\n=== SYSTOLIC STANDALONE TESTS COMPLETE ===");
        $finish;
    end
endmodule
