# `bootloader.v` — Documentation

## What It Does

`bootloader.v` is a hardware FSM (Finite State Machine) written in Verilog that receives a binary program over UART and writes it into the FPGA's memory — then releases the CPU to execute it.

In plain terms: before the CPU runs anything, the bootloader listens on the UART serial line, waits for a specifically formatted binary image to arrive from a host computer (sent via `terminal.py`), loads that image word-by-word into RAM starting at address `0x00000000`, and finally de-asserts the CPU reset so the CPU boots into the freshly loaded program.

---

## Why It Exists

The FPGA's CPU has no persistent flash storage. Every time the board powers up or resets, it starts with blank memory. The bootloader solves this by acting as a hardware-level program loader: it holds the CPU in reset while it populates RAM over the serial port, then hands control to the CPU once loading is complete.

This avoids the need to re-synthesise and re-flash the FPGA bitstream every time the program changes — only the `.bin` file needs to be re-sent over UART.

---

## Inputs and Outputs

| Signal | Direction | Description |
|---|---|---|
| `clk` | Input | System clock |
| `reset` | Input | Active-low board reset button |
| `uart_rx_ready` | Input | Pulses high for one cycle when a new byte has arrived from UART |
| `uart_rx_data[7:0]` | Input | The byte delivered by the UART receiver |
| `cpu_reset` | Output | Active-low reset held to the CPU (`0` = held in reset, `1` = running) |
| `boot_we` | Output | Write-enable pulse to RAM |
| `boot_addr[31:0]` | Output | Word address in RAM being written |
| `boot_wdata[31:0]` | Output | 32-bit word being written to RAM |

---

## Protocol

The host (`terminal.py`) sends a packet with the following structure over UART at 115200 baud:

```
[ 0xDE 0xAD 0xBE 0xEF ]  — 4-byte magic header (sync word)
[ SIZE (4 bytes, little-endian) ]  — total payload size in bytes (padded to 4-byte boundary)
[ PAYLOAD (SIZE bytes) ]  — raw binary program image
```

The bootloader validates the magic header byte-by-byte before accepting any data. Any mismatch resets back to the idle state, making the protocol noise-tolerant.

---

## State Machine

The FSM has 7 states:

```
S_IDLE → S_SYNC_1 → S_SYNC_2 → S_SYNC_3 → S_SIZE → S_PAYLOAD → S_DONE
```

| State | What Happens |
|---|---|
| `S_IDLE` | Waits for the first magic byte `0xDE`. Any other byte keeps it here. |
| `S_SYNC_1` | Expects `0xAD`. Mismatch → back to `S_IDLE`. |
| `S_SYNC_2` | Expects `0xBE`. Mismatch → back to `S_IDLE`. |
| `S_SYNC_3` | Expects `0xEF`, completing the magic word `0xDEADBEEF`. Advances to size reception. |
| `S_SIZE` | Collects 4 bytes (little-endian) to form the 32-bit payload size. |
| `S_PAYLOAD` | Collects bytes 4 at a time, assembles each into a 32-bit word, and writes it to RAM via `boot_we`. Advances `boot_addr` by 4 after each write. |
| `S_DONE` | All bytes received. Asserts `cpu_reset = 1` to release the CPU. Stays here permanently. |

---

## Reset Synchronisation

The external `reset` signal (from a physical board button) is passed through a two-stage synchroniser before driving the FSM:

```verilog
reset_sync_0 <= reset;
reset_sync_1 <= reset_sync_0;
wire reset_n = reset_sync_1;
```

**Why:** Xilinx BRAM control signals (write-enable, address) must never see an asynchronous reset release — it can corrupt BRAM contents. The double-flop synchroniser ensures the reset de-assertion is always aligned to the clock edge, preventing metastability and DRC violations.

---

## Memory Write Mechanism

Bytes arrive serially. The FSM accumulates them 4 at a time into `boot_wdata`, assembling in little-endian order:

```
byte 0 → bits [7:0]
byte 1 → bits [15:8]
byte 2 → bits [23:16]
byte 3 → bits [31:24]
```

On the 4th byte, `boot_we` is pulsed high for exactly one clock cycle to commit the word to RAM. The address (`boot_addr`) is then incremented by 4 on the next cycle (when `boot_we` is seen high but no new byte has arrived yet).

---

## Relationship to Other Files

| File | Role |
|---|---|
| `terminal.py` | Host-side script that sends the magic header, size, and binary payload over serial |
| `uart.v` | Provides `uart_rx_ready` and `uart_rx_data` signals consumed by the bootloader |
| `top_fpga.v` | Instantiates the bootloader and connects it to the CPU reset and memory bus |
| `start.S` | Entry point of the program that gets loaded and executed after bootloading |
