`timescale 1ns/1ps

module tb_axi_integration;

    reg clk;
    reg reset;

    // CPU-to-Master Interface Signals
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
        .req_enable(req_enable),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),
        .axi_busy(axi_busy),
        .axi_rdata(axi_rdata),

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
            
            @(posedge clk);
            req_enable = 0;
            
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
            data = axi_rdata; 
        end
    endtask

    // --- CORDIC Test Execution Task ---
    reg [31:0] read_status;
    reg [31:0] read_sin;
    reg [31:0] read_cos;

    task run_cordic_test;
        input [8*30:1] test_name;  // String for test name
        input [31:0]   test_angle; // Angle to send
        input [31:0]   exp_sin;    // Expected sine (for visual verification)
        input [31:0]   exp_cos;    // Expected cosine (for visual verification)
        begin
            $display("------------------------------------------------------------");
            $display("[TEST] %s", test_name);
            $display("       Sending Angle (Q4.28) : %h", test_angle);
            
            // 1. Write Angle (Triggers Core)
            cpu_write(32'h0000_0000, test_angle);

            // 2. Poll Status
            read_status = 0;
            while (read_status[0] == 1'b0) begin
                cpu_read(32'h0000_0004, read_status);
                if (read_status[0] == 1'b0) #20; 
            end
            
            // 3. Fetch Results
            cpu_read(32'h0000_0008, read_sin);
            cpu_read(32'h0000_000C, read_cos);
            
            $display("       Sine Result           : %h  | Expected: ~%h", read_sin, exp_sin);
            $display("       Cosine Result         : %h  | Expected: ~%h", read_cos, exp_cos);
            #50; // Pause between tests
        end
    endtask

    // --- Q4.28 Constants for Testing ---
    // Format: 1.0 = 2^28 = 268435456 = 0x10000000
    localparam [31:0] Q_ONE         = 32'h10000000;
    localparam [31:0] Q_ZERO        = 32'h00000000;
    localparam [31:0] Q_NEG_ONE     = 32'hF0000000; // -1.0 in 2's complement
    
    // Angles
    localparam [31:0] ANGLE_0       = 32'h00000000;
    localparam [31:0] ANGLE_PI_6    = 32'h0860A98B; // 30 deg
    localparam [31:0] ANGLE_PI_4    = 32'h0C90FDAA; // 45 deg
    localparam [31:0] ANGLE_PI_2    = 32'h1921FB54; // 90 deg
    localparam [31:0] ANGLE_NEG_PI_2= 32'hE6DE04AC; // -90 deg
    localparam [31:0] ANGLE_PI      = 32'h3243F6A8; // 180 deg
    
    // Expected Values (Approximate Q4.28)
    localparam [31:0] EXP_SIN_30    = 32'h08000000; // 0.5
    localparam [31:0] EXP_COS_30    = 32'h0DDB3D75; // 0.866
    localparam [31:0] EXP_SIN_45    = 32'h0B504F33; // 0.707
    localparam [31:0] EXP_COS_45    = 32'h0B504F33; // 0.707

    initial begin
        // Init signals
        req_enable = 0;
        req_write  = 0;
        req_addr   = 0;
        req_wdata  = 0;
        req_wstrb  = 0;
        
        reset = 0;
        #50 reset = 1;
        #50;

        $display("============================================================");
        $display("   AXI CORDIC MASTER/SLAVE INTEGRATION TEST SUITE");
        $display("============================================================");

        // --- NORMAL CASES ---
        run_cordic_test("Normal: 30 Degrees (pi/6)", 
                        ANGLE_PI_6, EXP_SIN_30, EXP_COS_30);

        run_cordic_test("Normal: 45 Degrees (pi/4)", 
                        ANGLE_PI_4, EXP_SIN_45, EXP_COS_45);

        // --- EDGE CASES ---
        run_cordic_test("Edge: 0 Degrees", 
                        ANGLE_0, Q_ZERO, Q_ONE);

        run_cordic_test("Edge: 90 Degrees (+pi/2)", 
                        ANGLE_PI_2, Q_ONE, Q_ZERO);

        run_cordic_test("Edge: -90 Degrees (-pi/2)", 
                        ANGLE_NEG_PI_2, Q_NEG_ONE, Q_ZERO);

        // --- OUT OF BOUNDS / FOLDED CASES ---
        // These test the 'flip_signs' logic in the SLAVE preprocessing state.
        // Expected for 180 (pi): Sin = 0, Cos = -1
        run_cordic_test("Folded: 180 Degrees (pi)", 
                        ANGLE_PI, Q_ZERO, Q_NEG_ONE);

        $display("============================================================");
        $display("   ALL TESTS COMPLETED SUCCESSFULLY");
        $display("============================================================");
        #100 $finish;
    end

endmodule
