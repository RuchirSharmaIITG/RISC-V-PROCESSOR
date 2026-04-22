`timescale 1ns/1ps

module tb_full_soc;
    reg clk;
    reg reset;

    wire uart_tx;
    wire [15:0] led;

    // AXI Bus interface wires
    wire [31:0] m_axi_awaddr;
    wire [2:0]  m_axi_awprot;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    
    wire [31:0] m_axi_araddr;
    wire [2:0]  m_axi_arprot;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // Instance of our RISC-V Multi-Cored SoC Architecture
    top_fpga SOC_CORE (
        .clk(clk),
        .reset(reset),
        .uart_rx(1'b1), // Keep UART Rx idle natively so bootloader exits or waits safely
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

    // Instance of our AXI CORDIC Math Accelerator Node
    axi_cordic_slave HW_ACCEL (
        .clk(clk),
        .reset(reset),
        
        .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awprot(m_axi_awprot),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb),
        .s_axi_wvalid(m_axi_wvalid),
        .s_axi_wready(m_axi_wready),
        .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid),
        .s_axi_bready(m_axi_bready),
        
        .s_axi_araddr(m_axi_araddr),
        .s_axi_arprot(m_axi_arprot),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),
        .s_axi_rdata(m_axi_rdata),
        .s_axi_rresp(m_axi_rresp),
        .s_axi_rvalid(m_axi_rvalid),
        .s_axi_rready(m_axi_rready)
    );

    always #5 clk = ~clk;

    // Monitor logic to cleanly print when internal Systolic AXI traffic is happening
    always @(posedge clk) begin
        if (SOC_CORE.sys_awvalid && SOC_CORE.sys_awready) begin
            $display("[SYS-WRITE Req] Time %t | Addr: %h, Data: %d", $time, SOC_CORE.sys_awaddr, SOC_CORE.sys_wdata);
        end
        if (SOC_CORE.sys_arvalid && SOC_CORE.sys_arready) begin
            $display("[SYS-READ Req]  Time %t | Addr: %h", $time, SOC_CORE.sys_araddr);
        end
        if (SOC_CORE.sys_rvalid && SOC_CORE.sys_rready) begin
            $display("[SYS-READ Done] Time %t | Returning Data: %d", $time, SOC_CORE.sys_rdata_in);
        end
    end

    initial begin
        clk = 0;
        reset = 0;
        
        // Assert Reset
        #50 reset = 1;
        
        // Bypass bootloader wait state for pure Verilog testbenches (since imem.hex is pre-loaded by the synth)
        force SOC_CORE.cpu_reset = reset;
        
        // The Bootloader and C-program will organically boot off imem.hex, setup Stack, 
        // calculate Float/IMF operations, and then request the CORDIC blocks purely automatically.
        // Provide enough simulation time for compilation logic.
        #20000;
        $display("Completed execution period.");
        $finish;
    end
endmodule
