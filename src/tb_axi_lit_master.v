`timescale 1ns/1ps

module tb_axi4_lite_master;

    // -----------------------------------------
    // Clock and Reset Generation
    // -----------------------------------------
    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz Clock (10ns period)
    end

    initial begin
        reset = 0;
        #20 reset = 1; // Release reset after 20ns
    end

    // -----------------------------------------
    // DUT Signals
    // -----------------------------------------
    // CPU Interface
    reg         req_enable;
    reg         req_write;
    reg  [31:0] req_addr;
    reg  [31:0] req_wdata;
    reg  [3:0]  req_wstrb;
    wire        axi_busy;
    wire [31:0] axi_rdata;

    // AXI4-Lite Interface
    wire [31:0] m_axi_awaddr;
    wire [2:0]  m_axi_awprot;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    
    wire [31:0] m_axi_araddr;
    wire [2:0]  m_axi_arprot;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    
    reg  [31:0] m_axi_rdata_in;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rvalid;
    wire        m_axi_rready;

    // -----------------------------------------
    // Address Decoding (For Waveform Visibility)
    // -----------------------------------------
    wire sel_uart   = (req_addr[31:28] == 4'h8); // 0x8000_0000 range
    wire sel_cordic = (req_addr[31:28] == 4'h9); // 0x9000_0000 range

    // -----------------------------------------
    // DUT Instantiation
    // -----------------------------------------
    axi4_lite_master dut (
        .clk(clk),
        .reset(reset),
        .req_enable(req_enable),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),
        .axi_busy(axi_busy),
        .axi_rdata(axi_rdata),
        
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata_in(m_axi_rdata_in),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    // -----------------------------------------
    // Custom Mock Slave (Matches Timing Diagram)
    // -----------------------------------------
    reg [1:0] w_delay_cnt;
    reg [2:0] r_delay_cnt;

    initial begin
        m_axi_bresp = 2'b00; // OKAY
        m_axi_rresp = 2'b00; // OKAY
    end

    always @(posedge clk) begin
        if (!reset) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid  <= 0;
            m_axi_arready <= 0;
            m_axi_rvalid  <= 0;
            m_axi_rdata_in<= 0;
            w_delay_cnt   <= 0;
            r_delay_cnt   <= 0;
        end else begin
            
            // --- WRITE CHANNEL (UART Timing) ---
            
            // AWREADY: 0-cycle delay (Combinatorial-like response in diagram)
            m_axi_awready <= m_axi_awvalid;

            // WREADY: 1-cycle delay from WVALID assertion
            if (m_axi_wvalid && !m_axi_wready) begin
                w_delay_cnt <= w_delay_cnt + 1;
                if (w_delay_cnt == 0) m_axi_wready <= 1; // Asserts on the next cycle
            end else begin
                m_axi_wready <= 0;
                w_delay_cnt <= 0;
            end

            // BVALID: 1-cycle delay after Write Data finishes
            if (m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1; 
            end else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid <= 0; // Handshake complete, drop response
            end

            
            // --- READ CHANNEL (CORDIC Timing) ---
            
            // ARREADY: 1-cycle delay from ARVALID assertion
            if (m_axi_arvalid && !m_axi_arready) begin
                 m_axi_arready <= 1; 
            end else begin
                 m_axi_arready <= 0;
            end

            // RVALID: Simulate CORDIC processing time (2 cycles after AR completes)
            if (m_axi_arvalid && m_axi_arready) begin
                r_delay_cnt <= 1;
            end else if (r_delay_cnt > 0) begin
                if (r_delay_cnt == 2) begin
                    m_axi_rvalid <= 1;
                    m_axi_rdata_in <= 32'h00003FFF; // Hardcoded CORDIC response
                    r_delay_cnt <= 0;
                end else begin
                    r_delay_cnt <= r_delay_cnt + 1;
                end
            end else if (m_axi_rready && m_axi_rvalid) begin
                m_axi_rvalid <= 0; // Handshake complete
            end
        end
    end

    // -----------------------------------------
    // CPU Stimulus Tasks
    // -----------------------------------------
    task cpu_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            req_enable = 1;
            req_write  = 1;
            req_addr   = addr;
            req_wdata  = data;
            req_wstrb  = 4'hF;
            
            @(posedge clk);
            req_enable = 0; // CPU drops request
            
            wait(!axi_busy);
            $display("[%0t] CPU WRITE Complete: Addr = 0x%h, Data = 0x%h", $time, addr, data);
        end
    endtask

    task cpu_read(input [31:0] addr);
        begin
            @(posedge clk);
            req_enable = 1;
            req_write  = 0;
            req_addr   = addr;
            
            @(posedge clk);
            req_enable = 0;
            
            wait(!axi_busy);
            $display("[%0t] CPU READ  Complete: Addr = 0x%h, Data = 0x%h", $time, addr, axi_rdata);
        end
    endtask

    // -----------------------------------------
    // Main Test Sequence
    // -----------------------------------------
    initial begin
        req_enable = 0;
        req_write  = 0;
        req_addr   = 0;
        req_wdata  = 0;
        req_wstrb  = 0;

        // Cycle 0-1: Await Reset
        wait(reset);
        
        // Cycles 1-2: Idle Buffer
        #15; 

        $display("\n--- Starting Diagram-Accurate Simulation ---\n");

        // Transaction 1: UART Write
        // Starts effectively at Cycle 2/3 of the diagram
        cpu_write(32'h8000_0000, 32'hDEADC0DE);
        
        // Idle Cycles (Wait between transactions)
        #50;

        // Transaction 2: CORDIC Read
        cpu_read(32'h9000_0004);
        if (axi_rdata !== 32'h00003FFF) $error("Read Failed: Did not receive CORDIC data!");
        
        // Final Idle Cycles
        #50;

        $display("\n--- Tests Finished Successfully ---\n");
        $finish;
    end

endmodule