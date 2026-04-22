`timescale 1ns/1ps

module tb_axi_soc;

    reg clk;
    reg reset;
    
    // AXI Bus Hooks
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
    reg  [31:0] m_axi_rdata;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    
    wire        uart_tx;
    wire [15:0] led;

    top_fpga uut (
        .clk(clk),
        .reset(reset),
        .uart_rx(1'b1), // IDLE
        .uart_tx(uart_tx),
        .led(led),
        
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
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    // Initial clk 
    always #10 clk = ~clk;

    // Simulate standard 1-cycle AXI slave response
    always @(posedge clk) begin
        if (!reset) begin
            m_axi_awready <= 0;
            m_axi_wready  <= 0;
            m_axi_bvalid  <= 0;
            m_axi_arready <= 0;
            m_axi_rvalid  <= 0;
            m_axi_rdata   <= 0;
        end else begin
            // Write Channel Handle
            if (m_axi_awvalid && !m_axi_awready) m_axi_awready <= 1;
            else m_axi_awready <= 0;
            
            if (m_axi_wvalid && !m_axi_wready) m_axi_wready <= 1;
            else m_axi_wready <= 0;
            
            // Send Bresp after AW and W are serviced
            if (m_axi_awready && m_axi_wready) begin
                m_axi_bvalid <= 1;
                m_axi_bresp <= 2'b00; // OKAY
            end else if (m_axi_bready && m_axi_bvalid) begin
                m_axi_bvalid <= 0;
            end
            
            // Read Channel Handle
            if (m_axi_arvalid && !m_axi_arready) m_axi_arready <= 1;
            else m_axi_arready <= 0;
            
            if (m_axi_arready) begin
                m_axi_rvalid <= 1;
                m_axi_rdata  <= 32'hDEADBEEF; // Dummy accelerator read
                m_axi_rresp  <= 2'b00;
            end else if (m_axi_rready && m_axi_rvalid) begin
                m_axi_rvalid <= 0;
            end
        end
    end

    integer index;

    initial begin
        clk = 0;
        reset = 0;
        
        // Let it reset
        #50 reset = 1;
        
        // Provide enough time to let some boot sequence or logic finish
        #1000;
        
        $display("INFO: tb_axi_soc setup successfully! Verilog compilation checks passed.");
        $finish;
    end

endmodule
