# UART Implementation Guide

This document describes how the newly implemented UART (`uart.v`) works, how it maps into the RISC-V memory space natively, and exactly how you can compile and deploy your processor onto the Nexys A7 FPGA (Artix-7 xc7a100t) to send and receive characters!

---

## 1. How the UART Controller Works

### Baud Rate Division (The Master Clock)

The UART is now fully synchronized to the main `100MHz` FPGA oscillator clock. Because 115200 baud physically expects one bit every `8.680 microseconds`, the hardware generator divides `100MHz` mathematically to find that `868` clock cycles perfectly equals one transmission bit width.

### Transmit Stage (TX FSM)

When the pipeline wishes to transmit a character, it writes an 8-bit block to the memory bus.

1. `top_fpga.v` intercepts this write, pulls out the 8 bits of data, and strokes `tx_start` strictly high for one cycle.
2. The UART captures the 8 bits into `tx_shift_reg`.
3. It forces the TX wire `Low` marking the start.
4. It iterates 8 times, shooting out the shifted registry LSB-first.
5. It returns the TX wire gracefully `High` marking the Stop bit checkout.
   While this is operating, the `tx_busy` logic remains High and restricts further transmission.

### Over-sampling Receiver (RX FSM)

Detecting logic coming over a physical copper wire is notoriously noisy. To combat this, the RX module uses a `16x Oversampler`. This means we sample the line `16` times per bit instead of just once.
When the line is detected falling, it waits exactly `7` ticks to arrive perfectly at the **dead-center** of the start bit. Once aligned cleanly away from the noisy edge, it loops exactly 16 ticks repeatedly, plucking the precise midpoint voltage of all subsequential data bounds!

---

## 2. Testing the UART using Assembly

Because UART acts merely like standard RAM inside your CPU, you can simply read data out or write characters natively into it using your exact normal `lw` and `sw` assembly techniques without any custom instruction extensions!
This Memory-Map address is structured identically to standard industry peripherals:

- **UART Base:** `0x8000_0000`
- **Offset `0x00` (Write):** Write 8-bit data here to blast a character out the TX pin.
- **Offset `0x04` (Read):** Read 32-bits here to fetch the most recently arrived UART data block.
- **Offset `0x08` (Read):** Read Status Register. `Bit 0` goes High when TX is currently blocking/transmitting. `Bit 1` goes High when an RX data load is valid and sitting idle.

#### Looping Echo Assembly Example

If you encode the following logic into your C compiler or Assembly hex generation file, your processor will echo every character a PC types back over the wire:

```assembly
# Setup x1 pointing dynamically into UART Block
WaitRX:
  lui x1, 0x80000       # Setup UART base 0x8000_0000
  lw  x2, 8(x1)         # Read Status Block
  andi x2, x2, 2        # Extract bit 1 (rx_ready)
  beqz x2, WaitRX       # Stall endlessly waiting for a keystroke!

  lw x3, 4(x1)          # We got a keystroke! Read the character.

WaitTX:
  lw x2, 8(x1)          # Read Status Block again
  andi x2, x2, 1        # Extract bit 0 (tx_busy)
  bnez x2, WaitTX       # Wait until TX line settles

  sw x3, 0(x1)          # Blast the exact character we just buffered straight back out to the terminal!

  j WaitRX              # Restart echo listener loop
```

---

## 3. Deploying onto the Nexys A7 FPGA (Artix-7 xc7a100t)

With the clock slowed-down debug routines abolished out of `top_fpga.v` completely, the processor runs wildly at a fluid `100MHz`.
The FPGA relies strictly on a constraints file `.xdc` resolving port names to exact pinouts!

### Step 1. Update the Constraint File (`.xdc`)

Inside your Vivado `constraint.xdc` file, ensure the UART TX/RX lines are accurately tracked to the Nexys board's micro-USB bridge port and set to standard IO standard `LVCMOS33`.

```tcl
# 100MHz Main Clock
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {clk}];

# Reset Pin (Assuming CPU_RESETN)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { reset }];

# Hardware Serial UART Micro-USB Bridge Pins
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];

# Diagnostic PC vs UART LEDs
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7] }];

set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];
```

### Step 2. Run Implementation

Inside Vivado GUI, click **"Generate Bitstream"**. Vivado will transparently run Synthesis, Place and Route, and finally stream compression.

### Step 3. Flash Hardware

Once the bitstream completes successfully (`top_fpga.bit`):

1. Plug your Artix-7 into your computer.
2. Select **Open Hardware Manager** -> **Open Target** -> **Auto Connect**.
3. Right click your target -> **Program Device** and select `top_fpga.bit`.

### Step 4. Communicate via PuTTY!

Once booted, the processor pipeline will execute instructions dynamically counting down your ROM. The **Bottom 8 LEDs** will blink wildly mapping directly to CPU operations tracing your PC address!

To start typing keys directly into the processor memory buffer:

1. Open up **Device Manager** and check which `COM` Port was generated by the FPGA (e.g. `COM4`).
2. Download and open a serial interceptor like **PuTTY**.
3. Select `Serial` connection, type your port targeting `COM4`, and enter `115200` into Speed.
4. Hit Open. Instantly, any keystroke tapped on your desktop will dynamically route 1/0 bits across the RX line into the Over-sampler.

Once the `START` string stops buffering, the physical **Top 8 LEDs** on the FPGA will visually toggle lighting up mathematically matching the literal ASCII letter configuration you just typed on your desktop! If you run the `Echo` script inside your RAM, PuTTY will seamlessly route the keystroke character straight back up to your PC screen visually completing the hardware loop.
