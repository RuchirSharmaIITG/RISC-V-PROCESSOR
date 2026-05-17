`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 8192,
    parameter DMEMSIZE = 8192,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,        // fast board clock (e.g. 100 MHz)
    input  wire reset,      // active-low reset
    input  wire uart_rx,    // UART Receive line
    output wire uart_tx,    // UART Transmit line
    output wire [15:0] led, // Diagnostic LEDs
    output wire [6:0] seg,  // 7-segment segments
    output wire [7:0] an,   // 7-segment anodes
    output wire dp          // 7-segment decimal point
);

    // AXI4-Lite Internal Wires for CORDIC
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

    wire [31:0] current_pc;
    wire exception;

    // Declare bootloader control nets up front so later logic (uart_rx_ack
    // in particular) can reference cpu_reset without triggering a
    // "used-before-declaration" Synth 8-6901 warning.
    wire        cpu_reset;
    wire        boot_we;
    wire [31:0] boot_addr;
    wire [31:0] boot_wdata;

    // --- CLOCKING ---
    wire clk_50mhz;
    
    // Instantiate your custom pure-Verilog clock divider
    clk_div my_divider (
        .clk_in(clk),       // 100MHz from the Nexys A7 board
        .reset(1'b0),       // Tied to 0 to ensure the clock is always free-running
        .clk_out(clk_50mhz) // The output is now a clean 50MHz!
    );
    
    // Route the new 50MHz clock to the entire processor system to prevent Clock Skew
    wire cpu_clk = clk_50mhz; 

    ////////////////////////////////////////////////////////////
    // PIPE ↔ MEMORY WIRES
    ////////////////////////////////////////////////////////////
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_valid = 1'b1;

    wire [31:0] inst_mem_address;
    wire        inst_mem_is_ready;
    wire [31:0] dmem_read_address;
    wire        dmem_read_ready;
    wire [31:0] dmem_write_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;
    wire        dmem_read_valid = 1'b1;
    wire        dmem_write_valid = 1'b1;

    wire [31:0] dmem_read_data_bram;
    wire [31:0] dmem_read_data_pipe;

    ////////////////////////////////////////////////////////////
    // MEMORY MAPPED I/O (UART) at 0x8000_0000
    // AXI4-Lite Master at 0x4000_0000
    ////////////////////////////////////////////////////////////
    // Decode read and write addresses INDEPENDENTLY to avoid cross-talk.
    // e.g. a UART write at 0x8... must never assert a CORDIC read flag.
    wire is_uart_read     = (dmem_read_address[31:28]  == 4'h8);
    wire is_uart_write    = (dmem_write_address[31:28] == 4'h8);
    wire is_cordic_read   = (dmem_read_address[31:28]  == 4'h4);
    wire is_cordic_write  = (dmem_write_address[31:28] == 4'h4);
    wire is_systolic_read = (dmem_read_address[31:28]  == 4'h5);
    wire is_systolic_write= (dmem_write_address[31:28] == 4'h5);

    // Convenience aliases used in a few legacy spots below
    wire is_uart_addr     = is_uart_read  || is_uart_write;
    wire is_cordic_addr   = is_cordic_read  || is_cordic_write;
    wire is_systolic_addr = is_systolic_read || is_systolic_write;

    wire uart_we       = is_uart_write && dmem_write_ready;
    wire uart_re       = is_uart_read  && dmem_read_ready;
    
    // UART hardware wires
    wire [7:0] uart_rx_data;
    wire       uart_rx_ready;
    wire       uart_tx_full;
    
    // Write registers (0x8000_0000 = TX Data transfer)
    wire uart_tx_start = uart_we && (dmem_write_address[7:0] == 8'h00);
    
    // Read registers (0x8000_0004 = RX Data fetch)
    wire uart_rx_ack = (!cpu_reset) ? uart_rx_ready : (uart_re && (dmem_read_address[7:0] == 8'h04));
    
    // Read Multiplexer (Synchronized to exactly match BRAM's 1-cycle latency)
    reg [31:0] uart_read_data_r;
    reg        is_uart_read_r;
    reg        is_cordic_read_r;
    reg        is_systolic_read_r;
    
    always @(posedge cpu_clk) begin
        // Carry the UART/AXI-read state into the Write-Back stage cycle
        is_uart_read_r     <= uart_re;
        // Use ONLY the read-side address signal so a concurrent write to a
        // different peripheral never sets these flags.
        is_cordic_read_r   <= is_cordic_read  && dmem_read_ready;
        is_systolic_read_r <= is_systolic_read && dmem_read_ready;
        
        // Sample the UART Hardware wires dynamically exactly when a Read is requested
        if (uart_re) begin
            uart_read_data_r <= (dmem_read_address[7:0] == 8'h08) ? {30'b0, uart_rx_ready, uart_tx_full} : 
                                (dmem_read_address[7:0] == 8'h04) ? {24'b0, uart_rx_data} : 32'h0;
        end
    end
    
    wire [31:0] cordic_rdata_out;
    wire [31:0] systolic_rdata_out;
    
    // During the pipeline WB stage, output either the safely latched UART data, AXI data, or native BRAM data.
    assign dmem_read_data_pipe = is_uart_read_r ? uart_read_data_r : 
                                 is_cordic_read_r  ? cordic_rdata_out : 
                                 is_systolic_read_r ? systolic_rdata_out :
                                 dmem_read_data_bram;

    // A visible heartbeat counter for the LEDs
    reg [31:0] blink_counter;
    always @(posedge cpu_clk) begin // FIX: Now on 50MHz cpu_clk
        if (!reset)
            blink_counter <= 0;
        else
            blink_counter <= blink_counter + 1;
    end

    // LED mappings! Top 8 bits = Most recently received character. 
    // Bottom 8 bits = Visible binary counter (bits 29:22 of blink_counter).
    reg [7:0] led_upper;
    always @(posedge cpu_clk) begin // FIX: Now on 50MHz cpu_clk
        if (uart_rx_ready)
            led_upper <= uart_rx_data;
    end
    assign led = {led_upper, blink_counter[28:21]}; // Shifted down one bit to keep the same blink speed at 50MHz!

    // 7-Segment Display Controller
    // Showing the current PC value on the 8 hex digits!
    seven_seg SEVEN_SEG_INST (
        .clk(cpu_clk), // FIX: Now on 50MHz cpu_clk
        .reset(reset),
        .data(current_pc), 
        .seg(seg),
        .an(an),
        .dp(dp)
    );

    ////////////////////////////////////////////////////////////
    // UART CONTROLLER INTERFACING
    ////////////////////////////////////////////////////////////
    uart #(
        .CLK_FREQ(50_000_000), // FIX: Alert the UART that the clock is now 50MHz so baud rates stay accurate
        .BAUD_RATE(BAUD_RATE)
    ) UART_INST (
        .clk        (cpu_clk),
        .reset      (reset),
        .rx         (uart_rx),
        .tx         (uart_tx),
        .tx_data    (dmem_write_data[7:0]),
        .tx_start   (uart_tx_start),
        .tx_full    (uart_tx_full),
        .rx_data    (uart_rx_data),
        .rx_ready   (uart_rx_ready),
        .rx_ack     (uart_rx_ack)
    );

    ////////////////////////////////////////////////////////////
    // HARDWARE BOOTLOADER
    ////////////////////////////////////////////////////////////
    bootloader boot_inst (
        .clk(cpu_clk),
        .reset(reset),
        .uart_rx_ready(uart_rx_ready),
        .uart_rx_data(uart_rx_data),
        .cpu_reset(cpu_reset),
        .boot_we(boot_we),
        .boot_addr(boot_addr),
        .boot_wdata(boot_wdata)
    );

    ////////////////////////////////////////////////////////////
    // AXI4-LITE MASTER CONTROLLER (EXTERNAL - CORDIC)
    ////////////////////////////////////////////////////////////
    wire cordic_busy;
    
    axi4_lite_master axi_master_inst (
        .clk           (cpu_clk),
        .reset         (cpu_reset),
        // req_enable fires when either a read or write to the CORDIC space is valid
        .req_enable    ((is_cordic_read && dmem_read_ready) || (is_cordic_write && dmem_write_ready)),
        // req_write: purely driven by the write path flag
        .req_write     (is_cordic_write && dmem_write_ready),
        // Address: use write address when writing, read address when reading.
        // CRITICAL: only use write_address when ACTUALLY writing, not just when dmem_write_ready
        .req_addr      (is_cordic_write && dmem_write_ready ? dmem_write_address : dmem_read_address),
        .req_wdata     (dmem_write_data),
        .req_wstrb     (dmem_write_byte),
        .axi_busy      (cordic_busy),
        .axi_rdata     (cordic_rdata_out),
        
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awprot  (m_axi_awprot),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arprot  (m_axi_arprot),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_rdata_in(m_axi_rdata),
        .m_axi_rresp   (m_axi_rresp),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready)
    );

    // Instantiate the CORDIC Logic directly inside the Top Level!
    axi_cordic_slave HW_CORDIC (
        .clk          (cpu_clk),
        .reset        (cpu_reset),
        .s_axi_awaddr (m_axi_awaddr),
        .s_axi_awprot (m_axi_awprot),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        .s_axi_wdata  (m_axi_wdata),
        .s_axi_wstrb  (m_axi_wstrb),
        .s_axi_wvalid (m_axi_wvalid),
        .s_axi_wready (m_axi_wready),
        .s_axi_bresp  (m_axi_bresp),
        .s_axi_bvalid (m_axi_bvalid),
        .s_axi_bready (m_axi_bready),
        .s_axi_araddr (m_axi_araddr),
        .s_axi_arprot (m_axi_arprot),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),
        .s_axi_rdata  (m_axi_rdata),
        .s_axi_rresp  (m_axi_rresp),
        .s_axi_rvalid (m_axi_rvalid),
        .s_axi_rready (m_axi_rready)
    );

    ////////////////////////////////////////////////////////////
    // AXI4-LITE MASTER CONTROLLER (INTERNAL - SYSTOLIC)
    ////////////////////////////////////////////////////////////
    wire systolic_busy;
    
    wire [31:0] sys_awaddr;
    wire [2:0]  sys_awprot;
    wire        sys_awvalid;
    wire        sys_awready;
    wire [31:0] sys_wdata;
    wire [3:0]  sys_wstrb;
    wire        sys_wvalid;
    wire        sys_wready;
    wire [1:0]  sys_bresp;
    wire        sys_bvalid;
    wire        sys_bready;
    wire [31:0] sys_araddr;
    wire [2:0]  sys_arprot;
    wire        sys_arvalid;
    wire        sys_arready;
    wire [31:0] sys_rdata_in;
    wire [1:0]  sys_rresp;
    wire        sys_rvalid;
    wire        sys_rready;

    // Second Master dedicated to the Systolic array bounds
    axi4_lite_master axi_master_systolic_inst (
        .clk           (cpu_clk),
        .reset         (cpu_reset),
        // req_enable fires when either a read or write to the Systolic space is valid
        .req_enable    ((is_systolic_read && dmem_read_ready) || (is_systolic_write && dmem_write_ready)),
        // req_write: purely driven by the write path flag
        .req_write     (is_systolic_write && dmem_write_ready),
        // Address: use write address when writing, read address when reading.
        .req_addr      (is_systolic_write && dmem_write_ready ? dmem_write_address : dmem_read_address),
        .req_wdata     (dmem_write_data),
        .req_wstrb     (dmem_write_byte),
        .axi_busy      (systolic_busy),
        .axi_rdata     (systolic_rdata_out),
        
        // Loopback bus explicitly for internal arrays
        .m_axi_awaddr  (sys_awaddr),  .m_axi_awprot  (sys_awprot),
        .m_axi_awvalid (sys_awvalid), .m_axi_awready (sys_awready),
        .m_axi_wdata   (sys_wdata),   .m_axi_wstrb   (sys_wstrb),
        .m_axi_wvalid  (sys_wvalid),  .m_axi_wready  (sys_wready),
        .m_axi_bresp   (sys_bresp),   .m_axi_bvalid  (sys_bvalid),
        .m_axi_bready  (sys_bready),  .m_axi_araddr  (sys_araddr),
        .m_axi_arprot  (sys_arprot),  .m_axi_arvalid (sys_arvalid),
        .m_axi_arready (sys_arready), .m_axi_rdata_in(sys_rdata_in),
        .m_axi_rresp   (sys_rresp),   .m_axi_rvalid  (sys_rvalid),
        .m_axi_rready  (sys_rready)
    );

    // Instantiate the 4x4 Systolic Array mapped perfectly to the sub-bus!
    axi_systolic_4x4 HW_SYSTOLIC (
        .clk(cpu_clk),
        .reset(cpu_reset),
        .s_axi_awaddr (sys_awaddr),  .s_axi_awprot (sys_awprot),
        .s_axi_awvalid(sys_awvalid), .s_axi_awready(sys_awready),
        .s_axi_wdata  (sys_wdata),   .s_axi_wstrb  (sys_wstrb),
        .s_axi_wvalid (sys_wvalid),  .s_axi_wready (sys_wready),
        .s_axi_bresp  (sys_bresp),   .s_axi_bvalid (sys_bvalid),
        .s_axi_bready (sys_bready),  .s_axi_araddr (sys_araddr),
        .s_axi_arprot (sys_arprot),  .s_axi_arvalid(sys_arvalid),
        .s_axi_arready(sys_arready), .s_axi_rdata  (sys_rdata_in),
        .s_axi_rresp  (sys_rresp),   .s_axi_rvalid (sys_rvalid),
        .s_axi_rready (sys_rready)
    );


    ////////////////////////////////////////////////////////////
    // PIPELINE CPU
    ////////////////////////////////////////////////////////////

    pipe pipe_u (
        .clk               (cpu_clk),
        .reset             (cpu_reset),
        // The newly updated AXI Masters natively assert combinatorial immediate busy signals!
        .stall (cordic_busy || systolic_busy),

        .exception         (exception),
        .pc_out            (current_pc), 
        .inst_mem_address  (inst_mem_address),
        .inst_mem_is_valid (inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),
        .inst_mem_is_ready (inst_mem_is_ready),

        .dmem_read_address (dmem_read_address),
        .dmem_read_ready   (dmem_read_ready),
        // Connect the multiplexed BRAM/UART data bus back into the pipeline
        .dmem_read_data_temp(dmem_read_data_pipe), 
        .dmem_read_valid   (dmem_read_valid),
        .dmem_write_address(dmem_write_address),
        .dmem_write_ready  (dmem_write_ready),
        .dmem_write_data   (dmem_write_data),
        .dmem_write_byte   (dmem_write_byte),
        .dmem_write_valid  (dmem_write_valid)
    );


    ////////////////////////////////////////////////////////////
    // INSTRUCTION MEMORY
    ////////////////////////////////////////////////////////////
    instr_mem IMEM (
        .clk  (cpu_clk), // FIX: Now on 50MHz cpu_clk to prevent fetch corruption
        .pc   (inst_mem_address),
        .instr(inst_mem_read_data),
        .boot_we(boot_we),
        .boot_addr(boot_addr),
        .boot_wdata(boot_wdata)
    );


    ////////////////////////////////////////////////////////////
    // DATA MEMORY
    ////////////////////////////////////////////////////////////
    // Bootloader also mirrors every payload word into DMEM so that .rodata /
    // .data living past the .text segment is coherent with the freshly loaded
    // program. Without this, DMEM keeps whatever was baked into the bitstream
    // via $readmemh and the CPU reads garbage for every string / constant.
    // The CPU is held in reset while boot_we pulses, so the two producers of
    // these write signals are mutually exclusive.
    // Use ONLY the write-side signals for the BRAM write-enable.
    // This ensures that a CORDIC read happening in the same cycle doesn't disable BRAM writes.
    wire bram_we           = boot_we || (dmem_write_ready && !is_uart_write && !is_cordic_write && !is_systolic_write);
    wire [31:0] bram_waddr = boot_we ? boot_addr  : dmem_write_address;
    wire [31:0] bram_wdata = boot_we ? boot_wdata : dmem_write_data;
    wire [3:0]  bram_wstrb = boot_we ? 4'b1111    : dmem_write_byte;

    data_mem DMEM (
        .clk   (cpu_clk), 
        // Use ONLY the read-side signals for the BRAM read-enable.
        // This ensures that a UART write happening in the same cycle doesn't disable BRAM reads.
        .re    (dmem_read_ready && !is_uart_read && !is_cordic_read && !is_systolic_read), 
        .raddr (dmem_read_address),
        .rdata (dmem_read_data_bram), 
        .we    (bram_we),
        .waddr (bram_waddr),
        .wdata (bram_wdata),
        .wstrb (bram_wstrb)
    );
endmodule
