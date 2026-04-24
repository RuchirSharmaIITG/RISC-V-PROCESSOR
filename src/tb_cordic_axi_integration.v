`timescale 1ns/1ps

module tb_axi_integration;

    reg clk;
    reg reset;

    // CPU-to-Master Interface Signals (Mimicking RISC-V Pipeline)
    reg         req_enable;
    reg         req_write;
    reg  [31:0] req_addr;
    reg  [31:0] req_wdata;
    reg  [3:0]  req_wstrb;
    wire        axi_busy;
    wire [31:0] axi_rdata;

    // Internal AXI Bus connecting Master and Slave
    wire [31:0] axi_awaddr;
    wire [2:0]  axi_awprot;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [31:0] axi_araddr;
    wire [2:0]  axi_arprot;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata_bus;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;

    // Instantiate AXI Master
    axi4_lite_master MASTER (
        .clk(clk),
        .reset(reset),
        
        // CPU Interface
        .req_enable(req_enable),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),
        .axi_busy(axi_busy),
        .axi_rdata(axi_rdata),

        // AXI Interface Out
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awprot(axi_awprot),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_araddr(axi_araddr),
        .m_axi_arprot(axi_arprot),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rdata_in(axi_rdata_bus),
        .m_axi_rresp(axi_rresp),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready)
    );

    // Instantiate AXI Slave (CORDIC)
    axi_cordic_slave SLAVE (
        .clk(clk),
        .reset(reset),
        
        // AXI Interface In
        .s_axi_awaddr(axi_awaddr),
        .s_axi_awprot(axi_awprot),
        .s_axi_awvalid(axi_awvalid),
        .s_axi_awready(axi_awready),
        .s_axi_wdata(axi_wdata),
        .s_axi_wstrb(axi_wstrb),
        .s_axi_wvalid(axi_wvalid),
        .s_axi_wready(axi_wready),
        .s_axi_bresp(axi_bresp),
        .s_axi_bvalid(axi_bvalid),
        .s_axi_bready(axi_bready),
        .s_axi_araddr(axi_araddr),
        .s_axi_arprot(axi_arprot),
        .s_axi_arvalid(axi_arvalid),
        .s_axi_arready(axi_arready),
        .s_axi_rdata(axi_rdata_bus),
        .s_axi_rresp(axi_rresp),
        .s_axi_rvalid(axi_rvalid),
        .s_axi_rready(axi_rready)
    );

    // 100 MHz Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- CPU Bus Request Tasks ---
    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            req_enable = 1;
            req_write  = 1;
            req_addr   = addr;
            req_wdata  = data;
            req_wstrb  = 4'hF;
            
            // Hold request until master acknowledges (leaves IDLE)
            @(posedge clk);
            req_enable = 0;
            
            // Wait for master to finish transaction (busy drops)
            wait(!axi_busy);
        end
    endtask

    task cpu_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            req_enable = 1;
            req_write  = 0;
            req_addr   = addr;
            
            @(posedge clk);
            req_enable = 0;
            
            wait(!axi_busy);
            data = axi_rdata; // Capture data when busy drops
        end
    endtask

    // Main Integration Test
    reg [31:0] read_val;
    localparam [31:0] ANGLE_PI_OVER_6 = 32'h0860A98B; // 30 degrees

    initial begin
        // Init CPU signals
        req_enable = 0;
        req_write  = 0;
        req_addr   = 0;
        req_wdata  = 0;
        req_wstrb  = 0;
        
        reset = 0;
        #50 reset = 1;
        #50;

        $display("[INT TB] --- Starting AXI Master/Slave Integration Test ---");

        // 1. Write Angle to trigger CORDIC
        $display("[INT TB] CPU Writing Angle to 0x00...");
        cpu_write(32'h0000_0000, ANGLE_PI_OVER_6);

        // 2. Poll Status Register
        read_val = 0;
        while (read_val[0] == 1'b0) begin
            $display("[INT TB] CPU Polling Status (0x04)...");
            cpu_read(32'h0000_0004, read_val);
            if (read_val[0] == 1'b0) #20; 
        end
        $display("[INT TB] Status OK! Computation Complete.");

        // 3. Read Sine
        cpu_read(32'h0000_0008, read_val);
        $display("[INT TB] Read Sine  (0x08): %h", read_val);

        // 4. Read Cosine
        cpu_read(32'h0000_000C, read_val);
        $display("[INT TB] Read Cosine (0x0C): %h", read_val);

        $display("[INT TB] --- Test Finished ---");
        #100 $finish;
    end

endmodule
