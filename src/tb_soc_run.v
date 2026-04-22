`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// tb_soc_run.v
//
// End-to-end behavioural simulation of the pipelined core + DMEM + UART TX.
// The bootloader path is skipped: IMEM and DMEM are pre-initialised via
// $readmemh("imem.hex", ...) exactly the way the FPGA BRAMs would be seeded
// at bitstream load. The testbench then samples the uart_tx line, decodes
// bytes at 115200-equivalent baud, and prints them to the transcript so we
// can see what characters the CPU is actually emitting.
//
// Run with:
//   cd c_toolchain && make clean && make          (produces imem.hex)
//   cd ..
//   iverilog -o sim_soc.out -g2012 tb_soc_run.v \
//       if_stage.v if_id_reg.v id_stage.v id_ex_reg.v ex_stage.v \
//       ex_mem_reg.v mem_stage.v mem_wb_reg.v wb_stage.v hazard_unit.v \
//       csr_file.v mult_div.v fpu.v fp_regfile.v pipeline.v memory.v \
//       uart.v uart_tx_fifo.v
//   vvp sim_soc.out
//-----------------------------------------------------------------------------
module tb_soc_run;

    // Use a fast baud so the simulation finishes quickly. The UART module
    // derives its bit time from CLK_FREQ/BAUD, so as long as both sides use
    // the same parameters the protocol still works. 5 MBaud at 50 MHz gives
    // 10 clocks per bit — plenty for a clean eye.
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 5_000_000;
    localparam BIT_CLKS  = CLK_FREQ / BAUD_RATE;    // 10
    localparam CLK_PERIOD_NS = 20;                   // 50 MHz

    reg clk   = 0;
    reg reset = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    //-------------------------------------------------------------------------
    // Memories (pre-seeded from the same hex file the toolchain produces).
    //-------------------------------------------------------------------------
    wire [31:0] inst_mem_address;
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_ready;

    wire [31:0] dmem_read_address;
    wire        dmem_read_ready;
    wire [31:0] dmem_read_data_pipe;

    wire [31:0] dmem_write_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;

    // Unused (wired up for bootloader signature on memory.v).
    wire        boot_we    = 1'b0;
    wire [31:0] boot_addr  = 32'b0;
    wire [31:0] boot_wdata = 32'b0;

    instr_mem IMEM (
        .clk        (clk),
        .pc         (inst_mem_address),
        .instr      (inst_mem_read_data),
        .boot_we    (boot_we),
        .boot_addr  (boot_addr),
        .boot_wdata (boot_wdata)
    );
    assign inst_mem_is_ready = 1'b1;

    //-------------------------------------------------------------------------
    // UART MMIO decode — mirrors the logic in top_fpga.v exactly.
    //-------------------------------------------------------------------------
    wire is_uart_addr = (dmem_read_address[31:28]  == 4'h8) ||
                        (dmem_write_address[31:28] == 4'h8);
    wire uart_we      = is_uart_addr && dmem_write_ready;
    wire uart_re      = is_uart_addr && dmem_read_ready;
    wire uart_tx_start = uart_we && (dmem_write_address[7:0] == 8'h00);

    wire [31:0] dmem_read_data_bram;

    wire [7:0]  uart_rx_byte;
    wire        uart_rx_ready_w;
    wire        uart_tx_full;

    wire uart_rx_ack = uart_re && (dmem_read_address[7:0] == 8'h04);

    reg [31:0] uart_read_data_r;
    reg        is_uart_read_r;
    always @(posedge clk) begin
        is_uart_read_r <= uart_re;
        if (uart_re) begin
            uart_read_data_r <= (dmem_read_address[7:0] == 8'h08) ?
                                    {30'b0, uart_rx_ready_w, uart_tx_full} :
                                (dmem_read_address[7:0] == 8'h04) ?
                                    {24'b0, uart_rx_byte} : 32'h0;
        end
    end
    assign dmem_read_data_pipe = is_uart_read_r ? uart_read_data_r
                                                : dmem_read_data_bram;

    data_mem DMEM (
        .clk   (clk),
        .re    (dmem_read_ready  && !is_uart_addr),
        .raddr (dmem_read_address),
        .rdata (dmem_read_data_bram),
        .we    (dmem_write_ready && !is_uart_addr),
        .waddr (dmem_write_address),
        .wdata (dmem_write_data),
        .wstrb (dmem_write_byte)
    );

    //-------------------------------------------------------------------------
    // UART IP — same module used on hardware.
    //-------------------------------------------------------------------------
    wire uart_tx_line;
    uart #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) U_UART (
        .clk      (clk),
        .reset    (reset),
        .rx       (1'b1),            // idle high, no RX stimulus in this sim
        .tx       (uart_tx_line),
        .tx_data  (dmem_write_data[7:0]),
        .tx_start (uart_tx_start),
        .tx_full  (uart_tx_full),
        .rx_data  (uart_rx_byte),
        .rx_ready (uart_rx_ready_w),
        .rx_ack   (uart_rx_ack)
    );

    //-------------------------------------------------------------------------
    // Pipelined CPU under test.
    //-------------------------------------------------------------------------
    pipe CPU (
        .clk                (clk),
        .reset              (reset),
        .stall              (1'b0),
        .exception          (),
        .pc_out             (),
        .inst_mem_address   (inst_mem_address),
        .inst_mem_is_valid  (1'b1),
        .inst_mem_read_data (inst_mem_read_data),
        .inst_mem_is_ready  (inst_mem_is_ready),
        .dmem_read_address  (dmem_read_address),
        .dmem_read_ready    (dmem_read_ready),
        .dmem_read_data_temp(dmem_read_data_pipe),
        .dmem_read_valid    (1'b1),
        .dmem_write_address (dmem_write_address),
        .dmem_write_ready   (dmem_write_ready),
        .dmem_write_data    (dmem_write_data),
        .dmem_write_byte    (dmem_write_byte),
        .dmem_write_valid   (1'b1)
    );

    //-------------------------------------------------------------------------
    // UART TX sniffer. Samples uart_tx_line at the centre of each bit and
    // reassembles bytes so we can see what the CPU is trying to print.
    //-------------------------------------------------------------------------
    integer sniffer_state;
    integer sniffer_bit;
    integer sniffer_count;
    reg [7:0] sniffer_shift;
    integer bytes_seen;
    initial begin
        sniffer_state = 0;
        sniffer_bit   = 0;
        sniffer_count = 0;
        sniffer_shift = 0;
        bytes_seen    = 0;
    end

    always @(posedge clk) begin
        case (sniffer_state)
            0: begin // IDLE — wait for start bit (falling edge)
                if (uart_tx_line == 1'b0) begin
                    // half-bit delay to centre on the start bit
                    sniffer_count <= (BIT_CLKS/2) - 1;
                    sniffer_state <= 1;
                end
            end
            1: begin // centre of start bit
                if (sniffer_count == 0) begin
                    if (uart_tx_line == 1'b0) begin
                        sniffer_count <= BIT_CLKS - 1;
                        sniffer_bit   <= 0;
                        sniffer_state <= 2;
                    end else begin
                        sniffer_state <= 0; // false start
                    end
                end else sniffer_count <= sniffer_count - 1;
            end
            2: begin // data bits
                if (sniffer_count == 0) begin
                    sniffer_shift <= {uart_tx_line, sniffer_shift[7:1]};
                    if (sniffer_bit == 7) begin
                        sniffer_count <= BIT_CLKS - 1;
                        sniffer_state <= 3;
                    end else begin
                        sniffer_bit   <= sniffer_bit + 1;
                        sniffer_count <= BIT_CLKS - 1;
                    end
                end else sniffer_count <= sniffer_count - 1;
            end
            3: begin // stop bit — emit byte
                if (sniffer_count == 0) begin
                    bytes_seen <= bytes_seen + 1;
                    if (sniffer_shift >= 8'h20 && sniffer_shift < 8'h7f)
                        $write("%c", sniffer_shift);
                    else if (sniffer_shift == 8'h0a)
                        $write("\n");
                    else if (sniffer_shift == 8'h0d)
                        ; // swallow CR
                    else
                        $write("<%02x>", sniffer_shift);
                    $fflush;
                    sniffer_state <= 0;
                end else sniffer_count <= sniffer_count - 1;
            end
        endcase
    end

    //-------------------------------------------------------------------------
    // Additional introspection — print the PC every time a store fires to
    // MMIO so we can correlate CPU progress with transmit events.
    //-------------------------------------------------------------------------
    integer store_count = 0;
    always @(posedge clk) begin
        if (uart_tx_start) begin
            store_count = store_count + 1;
            if (store_count < 60)
                $display("[T=%0t] uart_tx store #%0d data=0x%02h pc_ex=%08h",
                         $time, store_count, dmem_write_data[7:0],
                         CPU.u_id_ex_reg.pc_o);
        end
    end

    //-------------------------------------------------------------------------
    // Per-cycle cycle trace for a short window (~2000 cycles) after 3rd store,
    // so we can see WHY each PC lingers so long.
    //-------------------------------------------------------------------------
    integer trace_on = 0;
    integer trace_budget = 200;
    always @(posedge clk) begin
        if (reset && trace_on && trace_budget > 0) begin
            $display("[cy] pc_if=%08h if_id_inst=%08h pc_ex=%08h stall_if=%0b stall_id=%0b stall_ex=%0b flush_if=%0b flush_id=%0b flush_ex=%0b stall_exreq=%0b fp_en=%0b mult_en=%0b mem_rd=%0b mem_wr=%0b dmem_raddr=%08h",
                     CPU.u_if_stage.pc_reg,
                     CPU.u_if_id_reg.id_instruction,
                     CPU.u_id_ex_reg.pc_o,
                     CPU.stall_if_haz, CPU.stall_id_haz, CPU.stall_ex_haz,
                     CPU.flush_if_haz, CPU.flush_id_haz, CPU.flush_ex_haz,
                     CPU.u_ex_stage.stall_ex_request,
                     CPU.ex_fp_en, CPU.ex_mult_div_en,
                     CPU.ex_mem_read, CPU.ex_mem_write,
                     dmem_read_address);
            trace_budget = trace_budget - 1;
        end
    end

    //-------------------------------------------------------------------------
    // Drive reset, then let it run.
    //-------------------------------------------------------------------------
    initial begin
        $display("[tb_soc_run] Starting simulation");
        reset = 1'b0;
        #200;
        reset = 1'b1;
        // Turn on PC trace after a few stores have fired so we can see why
        // the loop between TX writes is so long.
        wait (store_count >= 3);
        trace_on = 1;
        #20_000_000;
        $display("\n[tb_soc_run] Timeout reached. bytes_seen=%0d stores=%0d",
                 bytes_seen, store_count);
        $finish;
    end

endmodule
