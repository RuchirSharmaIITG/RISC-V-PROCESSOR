# CORDIC Hardware Accelerator — Complete Design Documentation

> **Design:** Iterative CORDIC engine exposed over AXI4-Lite, integrated into a RISC-V soft-core FPGA SoC.  
> **Fixed-Point Format:** Q4.28 throughout (1 sign bit, 4 integer bits, 28 fractional bits).

---

## Table of Contents

1. [CORDIC Algorithm — Theory](#1-cordic-algorithm--theory)
2. [Module: `cordic_iterative`](#2-module-cordic_iterative)
   - [Ports](#ports)
   - [Fixed-Point Representation](#fixed-point-representation)
   - [Quadrant Pre-processing](#quadrant-pre-processing)
   - [Iterative Rotation Engine](#iterative-rotation-engine)
   - [CORDIC Gain Compensation](#cordic-gain-compensation)
   - [The Arctangent LUT](#the-arctangent-lut)
   - [FSM: cordic_iterative](#fsm-cordic_iterative)
3. [Module: `axi_cordic_slave`](#3-module-axi_cordic_slave)
   - [Register Map](#register-map)
   - [Write Path — Trigger a Computation](#write-path--trigger-a-computation)
   - [Read Path — Poll and Collect Results](#read-path--poll-and-collect-results)
   - [Result Latch Logic](#result-latch-logic)
4. [Module: `axi4_lite_master`](#4-module-axi4_lite_master)
   - [FSM: axi4_lite_master](#fsm-axi4_lite_master)
   - [Busy Signal Design](#busy-signal-design)
5. [Module: `top_fpga` — System Integration](#5-module-top_fpga--system-integration)
   - [Memory Map](#memory-map)
   - [Data Path: CPU → CORDIC → CPU](#data-path-cpu--cordic--cpu)
   - [Pipeline Stall Mechanism](#pipeline-stall-mechanism)
   - [Read Multiplexer](#read-multiplexer)
6. [End-to-End Transaction Walkthrough](#6-end-to-end-transaction-walkthrough)
7. [Numerical Example](#7-numerical-example)

---

## 1. CORDIC Algorithm — Theory

**CORDIC** (COordinate Rotation DIgital Computer) computes trigonometric functions using only bit-shifts and additions — no multipliers required. This makes it ideal for FPGA fabric, which is rich in LUTs and registers but where DSP multipliers are limited.

### Core Idea

CORDIC operates in **rotation mode**: given a target angle `θ`, it starts from a known initial vector `(x₀, y₀) = (1/K, 0)` on the unit circle and rotates it toward `θ` through a series of micro-rotations:

```
xᵢ₊₁ = xᵢ − dᵢ · yᵢ · 2⁻ⁱ
yᵢ₊₁ = yᵢ + dᵢ · xᵢ · 2⁻ⁱ
zᵢ₊₁ = zᵢ − dᵢ · arctan(2⁻ⁱ)
```

where `dᵢ = +1` if `zᵢ ≥ 0`, and `dᵢ = −1` otherwise.

At convergence (after N iterations), `z ≈ 0` and:

```
x_N ≈ K · cos(θ)
y_N ≈ K · sin(θ)
```

The constant **K** (≈ 1.6468) is the product of all the `1/cos(arctan(2⁻ⁱ))` scale factors accumulated across iterations. By pre-scaling the initial `x₀` by `1/K`, the outputs emerge already normalised to the unit circle.

### Why 32 Iterations?

Each iteration adds approximately one bit of precision. With 32 iterations on a 32-bit fixed-point datapath, the design achieves approximately **28–29 bits** of angular resolution, consistent with the Q4.28 format used throughout.

---

## 2. Module: `cordic_iterative`

**File:** `cordic.v`  
**Purpose:** The bare-metal CORDIC engine. Takes a Q4.28 angle, runs 32 iterative rotation steps, and outputs Q4.28 sine and cosine.

### Ports

| Direction | Name           | Width | Description                              |
|-----------|----------------|-------|------------------------------------------|
| `input`   | `clk`          | 1     | System clock                             |
| `input`   | `reset`        | 1     | Active-low synchronous reset             |
| `input`   | `start`        | 1     | Pulse high for one cycle to begin        |
| `input`   | `target_angle` | 32    | Input angle in Q4.28 (−π to +π)         |
| `output`  | `valid_out`    | 1     | Pulses high for one cycle when done      |
| `output`  | `sin_out`      | 32    | sin(θ) result in Q4.28                  |
| `output`  | `cos_out`      | 32    | cos(θ) result in Q4.28                  |

### Fixed-Point Representation

All angles and values use **Q4.28** format:

```
Bit 31:     Sign bit
Bits 30–28: Integer part (4 bits total including sign)
Bits 27–0:  28-bit fractional part
```

Key constants baked into the design:

| Constant          | Hex Value    | Decimal Meaning           |
|-------------------|-------------|---------------------------|
| `CORDIC_GAIN_INV` | `0x09B74EDA` | 1/K ≈ 0.60725 in Q4.28   |
| `PI_OVER_2`       | `0x1921FB54` | π/2 ≈ 1.5708 in Q4.28    |
| `NEG_PI_OVER_2`   | `0xE6DE04AC` | −π/2 in Q4.28 (signed)   |
| `PI`              | `0x3243F6A8` | π ≈ 3.14159 in Q4.28     |

### Quadrant Pre-processing

The CORDIC rotation kernel only converges reliably for angles in **[−π/2, +π/2]**. Inputs outside this range are folded:

```
if   θ > +π/2 :  z_init = θ − π,  flip_signs = 1
elif θ < −π/2 :  z_init = θ + π,  flip_signs = 1
else           :  z_init = θ,      flip_signs = 0
```

After computation, if `flip_signs = 1`, both `sin` and `cos` are negated (equivalent to rotating by 180°):

```verilog
if (flip_signs) begin
    cos_out <= -x;
    sin_out <= -y;
end else begin
    cos_out <= x;
    sin_out <= y;
end
```

This correctly handles all four quadrants of the unit circle.

### Iterative Rotation Engine

The combinational shift wires are computed each clock from the current iteration count:

```verilog
wire signed [31:0] x_shifted = (x >>> iteration);
wire signed [31:0] y_shifted = (y >>> iteration);
```

The rotation step in `STATE_CALC`:

```verilog
if (z >= 0) begin          // rotate counter-clockwise
    x <= x - y_shifted;
    y <= y + x_shifted;
    z <= z - atan_lut_val;
end else begin             // rotate clockwise
    x <= x + y_shifted;
    y <= y - x_shifted;
    z <= z + atan_lut_val;
end
```

The arithmetic right-shift (`>>>`) is critical — it preserves the sign bit, implementing true division by `2ⁱ` for signed fixed-point numbers.

### CORDIC Gain Compensation

Rather than applying a correction factor after the loop, the gain is pre-applied at initialisation:

```verilog
x <= CORDIC_GAIN_INV;   // 1/K in Q4.28
y <= 32'sd0;
```

This is an efficient trick: since K is a known constant, pre-seeding x with 1/K means the final outputs are already gain-corrected to sit on the unit circle.

### The Arctangent LUT

The `atan_lut_val` register is driven by a combinational `case` block indexed by `iteration`. Each entry stores `arctan(2⁻ⁱ)` in Q4.28:

| Iter `i` | Hex Value      | arctan(2⁻ⁱ) (approx.) |
|----------|---------------|------------------------|
| 0        | `0x0C90FDAA`  | 45.000°                |
| 1        | `0x076B19C1`  | 26.565°                |
| 2        | `0x03EB6EBF`  | 14.036°                |
| 3        | `0x01FD5BAA`  | 7.125°                 |
| 4        | `0x00FFAADE`  | 3.576°                 |
| 5        | `0x007FF557`  | 1.789°                 |
| …        | …             | …                      |
| 10       | `0x00040000`  | ≈ 0.056°               |
| 15       | `0x00002000`  | ≈ 0.0018°              |
| 28       | `0x00000001`  | ≈ sub-LSB              |
| 29–31    | `0x00000000`  | 0 (negligible)         |

Notice how the values become powers of two from iteration 10 onward — `arctan(2⁻ⁱ) ≈ 2⁻ⁱ` for small angles. The LUT in `lut.txt` is the same table embedded directly into the `case` statement of `cordic.v`.

### FSM: `cordic_iterative`

```
         ┌─────────────────────────────────────────────────────────┐
         │                                                         │
         ▼                                                         │
   ┌──────────┐  start=1    ┌──────────┐  iter==31   ┌──────────┐  │
   │          │────────────▶│          │────────────▶│         │  │
   │  STATE_  │             │  STATE_  │             │  STATE_  │  │
   │  IDLE    │             │  CALC    │             │  DONE    │──┘
   │          │◀────────────│          │             │          │
   └──────────┘  start=0    └──────────┘             └──────────┘
                             (loops for
                             32 cycles)
```

| State        | Entry Condition            | Action                                                       | Exit Condition    |
|--------------|----------------------------|--------------------------------------------------------------|-------------------|
| `STATE_IDLE` | Reset / computation done   | Wait for `start`. Pre-process angle, seed `x`, `y`, `z`.    | `start = 1`       |
| `STATE_CALC` | `start` received           | Execute one CORDIC micro-rotation per cycle. Increment `iteration`. | `iteration == 31` |
| `STATE_DONE` | 32 iterations complete     | Assert `valid_out`. Apply sign flip if needed. Output `sin_out`, `cos_out`. | Always (1 cycle)  |

The FSM takes exactly **34 clock cycles** per computation: 1 cycle in IDLE (on `start`), 32 cycles in CALC, 1 cycle in DONE.

---

## 3. Module: `axi_cordic_slave`

**File:** `axi_cordic_slave.v`  
**Purpose:** AXI4-Lite slave wrapper around `cordic_iterative`. Provides a memory-mapped register interface so software can trigger computations and read results.

### Register Map

| Offset | Access | Name            | Description                                      |
|--------|--------|-----------------|--------------------------------------------------|
| `0x00` | **W**  | `ANGLE_IN`      | Write the Q4.28 target angle here to start CORDIC |
| `0x04` | **R**  | `STATUS`        | Bit 0 = `latched_valid` (1 = result ready)       |
| `0x08` | **R**  | `SIN_OUT`       | sin(θ) result in Q4.28                           |
| `0x0C` | **R**  | `COS_OUT`       | cos(θ) result in Q4.28                           |

### Write Path — Trigger a Computation

The AXI write path follows standard AXI4-Lite handshaking with independent AW and W channel latching:

```
1. Master asserts AWVALID + WVALID (address and data channels)
2. Slave independently accepts AW → sets aw_en
3. Slave independently accepts W  → sets w_en
4. When BOTH aw_en AND w_en are set:
     - If waddr[7:0] == 0x00: latch angle, pulse cordic_start for 1 cycle
     - Assert BVALID with BRESP = 2'b00 (OKAY)
5. On BREADY: deassert BVALID, clear aw_en, w_en
```

The two channels being accepted independently is key — AXI4-Lite does not guarantee that AW and W arrive in the same cycle.

### Read Path — Poll and Collect Results

```
1. Master asserts ARVALID
2. Slave: assert ARREADY for 1 cycle, latch address into read_addr_buf
3. Next cycle: assert RVALID, drive RDATA from read_addr_buf decode:
     0x04 → {31'b0, latched_valid}
     0x08 → cordic_sin_out
     0x0C → cordic_cos_out
4. On RREADY: deassert RVALID
```

> **Design note:** `read_addr_buf` is latched one cycle before the data is driven. This prevents a race where `s_axi_araddr` could change (e.g., the master de-asserts ARVALID) between the address-accepted cycle and the data-driven cycle.

### Result Latch Logic

```verilog
always @(posedge clk) begin
    if (!reset)              latched_valid <= 0;
    else if (cordic_start)   latched_valid <= 0;  // Clear on new request
    else if (cordic_valid_out) latched_valid <= 1; // Set when done
end
```

`cordic_start` has **higher priority** than `cordic_valid_out`. If both fire in the same cycle (a new request arrives exactly when the previous computation finishes), the flag is cleared first. This prevents software from reading a stale "ready" flag from the old computation before the new one completes.

---

## 4. Module: `axi4_lite_master`

**File:** `axi4_lite_master.v`  
**Purpose:** Generic AXI4-Lite master. Translates a simple request-based CPU interface (one enable, one read/write signal, one address) into a fully compliant AXI4-Lite bus transaction.

### Ports (CPU-side)

| Port         | Dir    | Description                                    |
|--------------|--------|------------------------------------------------|
| `req_enable` | Input  | High for one cycle to initiate a transaction   |
| `req_write`  | Input  | 1 = write, 0 = read                            |
| `req_addr`   | Input  | 32-bit byte address                            |
| `req_wdata`  | Input  | Write data                                     |
| `req_wstrb`  | Input  | Byte strobes (4 bits)                          |
| `axi_busy`   | Output | High while transaction is in flight            |
| `axi_rdata`  | Output | Captured read data after transaction completes |

### FSM: `axi4_lite_master`

```
                             ┌────────────────────────┐
                             │                        │
                             ▼                        │
                       ┌──────────┐                   │
          req_enable=0 │          │                   │
          ┌────────────│  IDLE    │                   │
          │            │          │                   │
          │            └──────────┘                   │
          │           req_write=1 │  req_write=0        │
          │                       │                   │
          │            ┌──────────▼──┐   ┌───────────▼─┐
          │            │   WADDR     │   │   RADDR      │
          │            │ (AW+W chans)│   │ (AR channel) │
          │            └──────┬──────┘   └──────┬───────┘
          │            both   │ accepted        │ ARREADY
          │            ┌──────▼──────┐   ┌──────▼───────┐
          │            │   BRESP     │   │   RDATA       │
          │            │(wait BVALID)│   │(wait RVALID)  │
          │            └──────┬──────┘   └──────┬───────┘
          │                   │ BVALID           │ RVALID
          │            ┌──────▼──────────────────▼───────┐
          │            │              DONE                │
          │            └──────────────┬───────────────────┘
          │                           │ (1 cycle)
          │            ┌──────────────▼───────────────────┐
          └────────────│           COOLDOWN               │
                       │    (axi_busy = 0, pipeline adv.) │
                       └──────────────────────────────────┘
```

| State        | Description                                                                  |
|--------------|------------------------------------------------------------------------------|
| `IDLE`       | Awaits `req_enable`. Simultaneously asserts `axi_busy` if enable is seen.   |
| `WADDR`      | Drives AWVALID + WVALID. Both channels may complete in any order.             |
| `BRESP`      | Asserts BREADY, waits for BVALID from slave.                                 |
| `RADDR`      | Drives ARVALID, waits for ARREADY from slave.                                |
| `RDATA`      | Asserts RREADY, captures RDATA when RVALID arrives.                          |
| `DONE`       | One-cycle stall; `axi_busy` still high so pipeline is held.                  |
| `COOLDOWN`   | `axi_busy` drops to 0, allowing the pipeline to advance and sample `axi_rdata`. |

### Busy Signal Design

```verilog
assign axi_busy = ((state != STATE_IDLE) && (state != STATE_COOLDOWN))
                  || (state == STATE_IDLE && req_enable);
```

This has an intentional combinational path: if `req_enable` fires while in IDLE, `axi_busy` goes high **immediately** in the same cycle (before the FSM even registers it). This prevents a pipeline stage from advancing past a memory request before the AXI machine has latched it.

The `COOLDOWN` state is the crucial "release window" — it is the only cycle where the pipeline can advance and safely read `axi_rdata`.

---

## 5. Module: `top_fpga` — System Integration

**File:** `top_fpga.v`  
**Purpose:** Top-level SoC integration. Connects a RISC-V pipeline CPU, instruction/data memories, UART, bootloader, AXI4-Lite master (CORDIC), and AXI4-Lite master (Systolic Array).

### Memory Map

| Base Address  | Size   | Peripheral          | Notes                            |
|---------------|--------|---------------------|----------------------------------|
| `0x0000_0000` | 8 KB   | Instruction Memory  | BRAM, bootloader-writable        |
| `0x2000_0000` | 8 KB   | Data Memory (BRAM)  | General-purpose heap/stack       |
| `0x4000_0000` | 256 B  | **CORDIC**          | AXI4-Lite slave, regs at +0/4/8/C |
| `0x5000_0000` | 256 B  | Systolic Array      | AXI4-Lite slave (4×4 matrix)     |
| `0x8000_0000` | 256 B  | UART                | TX at +0x00, RX at +0x04, Status at +0x08 |

Address decoding uses the top nibble of the address:

```verilog
wire is_cordic_read  = (dmem_read_address[31:28]  == 4'h4);
wire is_cordic_write = (dmem_write_address[31:28] == 4'h4);
```

Read and write address decoders are **independent** to prevent crosstalk (e.g. a UART write at `0x8...` must never set a CORDIC read flag).

### Data Path: CPU → CORDIC → CPU

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          top_fpga                                       │
│                                                                         │
│   ┌─────────┐   dmem_write_*   ┌────────────────┐   AXI4-Lite Bus       │
│   │         │─────────────────▶│ axi4_lite_      │◀──────────────────▶│
│   │  RISC-V │                  │ master          │                      │
│   │  pipe   │   dmem_read_*    │ (axi_master_    │    ┌──────────────┐  │
│   │         │◀─────────────────│  inst)          │──▶│ axi_cordic_  │  │
│   │         │                  └────────────────┘     │ slave        │  │
│   │         │   stall ◀──── cordic_busy              │              │   │
│   │         │                                         │ ┌──────────┐ │  │
│   └─────────┘                                         │ │ cordic_  │ │  │
│                                                       │ │iterative │ │  │
│                                                       │ └──────────┘ │  │
│                                                       └──────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

The full chain for a **write** (trigger computation):

```
CPU store → dmem_write_address = 0x4000_0000
         → is_cordic_write = 1
         → axi_master_inst.req_enable = 1, req_write = 1
         → AXI4-Lite: AWVALID + WVALID → slave
         → axi_cordic_slave: latches angle, pulses cordic_start
         → cordic_iterative: begins STATE_CALC for 32 cycles
         → cordic_busy stalls pipeline throughout
```

The full chain for a **read** (poll status / get result):

```
CPU load → dmem_read_address = 0x4000_0004  (STATUS)
        → is_cordic_read = 1
        → axi_master_inst.req_enable = 1, req_write = 0
        → AXI4-Lite: ARVALID → slave
        → axi_cordic_slave: drives {31'b0, latched_valid} on RDATA
        → axi_master_inst: captures into axi_rdata (= cordic_rdata_out)
        → COOLDOWN: cordic_busy = 0, pipeline advances
        → is_cordic_read_r = 1 → dmem_read_data_pipe = cordic_rdata_out
```

### Pipeline Stall Mechanism

```verilog
.stall (cordic_busy || systolic_busy)
```

The RISC-V pipeline has a global stall input. Both AXI masters drive a `busy` signal that holds the pipeline frozen during any in-flight AXI transaction. This is a **blocking** model: the CPU cannot issue another memory instruction until the peripheral transaction is complete.

Because `axi_busy` asserts combinationally on the same cycle as `req_enable`, there is no window where the pipeline could advance before the AXI master has registered the request.

### Read Multiplexer

The pipeline write-back stage sources read data from one of four paths:

```verilog
assign dmem_read_data_pipe =
    is_uart_read_r     ? uart_read_data_r    :
    is_cordic_read_r   ? cordic_rdata_out    :
    is_systolic_read_r ? systolic_rdata_out  :
                         dmem_read_data_bram ;
```

The `_r` suffix indicates these flags are **registered** — they are delayed one cycle to align with BRAM's one-cycle read latency. Without this pipeline register the mux selection would be one cycle early, causing the CPU to read `dmem_read_data_bram` (stale/invalid) instead of the peripheral's data.

---

## 6. End-to-End Transaction Walkthrough

Below is the complete cycle-by-cycle flow when a CPU program computes `sin(π/4)`:

### Phase 1 — Write Angle (Trigger)

```
Cycle  0: CPU executes SW to 0x4000_0000 with value 0x1921FB54 (π/4 in Q4.28)
Cycle  0: is_cordic_write=1 → req_enable=1 → axi_busy asserts (combinational)
           Pipeline STALLS
Cycle  1: FSM → STATE_WADDR. AWVALID=1, WVALID=1 drive slave.
Cycle  1: axi_cordic_slave: AW handshake → aw_en=1
Cycle  2: axi_cordic_slave: W  handshake → w_en=1. aw_en & w_en → cordic_start pulse
           cordic_iterative: STATE_IDLE → STATE_CALC. x=0x09B74EDA, y=0, z=0x1921FB54
Cycle  3: FSM → STATE_BRESP. BREADY=1.
Cycle  4: BVALID received. FSM → STATE_DONE → STATE_COOLDOWN.
Cycle  5: COOLDOWN: axi_busy=0. Pipeline resumes.
```

### Phase 2 — CORDIC Computation (background, 32 cycles)

```
Cycles 2–33: cordic_iterative runs STATE_CALC. 
             Each cycle: one micro-rotation using x_shifted, y_shifted, atan_lut_val.
Cycle  34: cordic_iterative → STATE_DONE.
             valid_out pulses. flip_signs=0 (π/4 is in [−π/2, +π/2]).
             sin_out ≈ 0x1B504F33 (≈ 0.7071 in Q4.28)
             cos_out ≈ 0x1B504F33 (≈ 0.7071 in Q4.28)
             latched_valid ← 1
```

### Phase 3 — Poll Status

```
CPU executes LW from 0x4000_0004 (STATUS register)
AXI read transaction → slave drives {31'b0, 1} → CPU reads 0x00000001 (done)
```

### Phase 4 — Read Results

```
CPU executes LW from 0x4000_0008 (SIN_OUT)
AXI read → slave drives cordic_sin_out → CPU receives ≈ 0x1B504F33

CPU executes LW from 0x4000_000C (COS_OUT)
AXI read → slave drives cordic_cos_out → CPU receives ≈ 0x1B504F33
```

---

## 7. Numerical Example

### Input: θ = π/4

| Parameter       | Value            |
|-----------------|------------------|
| Input angle     | `0x1921FB54` = π/4 = 0.785398... |
| Quadrant fold   | None (within [−π/2, +π/2])       |
| Initial x       | `0x09B74EDA` = 1/K ≈ 0.607253    |
| Initial y       | `0x00000000` = 0                  |
| Initial z       | `0x1921FB54` = π/4               |

### First 4 Iterations (illustrative)

| Iter | arctan(2⁻ⁱ) | dᵢ | Action        | z after             |
|------|------------|-----|---------------|---------------------|
| 0    | 45.000°    | +1  | Rotate +45°   | z = 0° (approx.)   |
| 1    | 26.565°    | +1  | Rotate +26.6° | z = −26.6°          |
| 2    | 14.036°    | −1  | Rotate −14.0° | z = −12.5°          |
| 3    | 7.125°     | −1  | Rotate −7.1°  | z = −5.4°           |

After 32 iterations z converges to ≈ 0, leaving:

```
x_32 ≈ cos(π/4) ≈ 0.70711
y_32 ≈ sin(π/4) ≈ 0.70711
```

In Q4.28: `0x1B504F33` for both sin and cos.

### LUT Values Decoded

The first few LUT entries illustrate the arctan sequence in degrees:

```
atan_lut[0]  = 0x0C90FDAA = π/4      = 45.0000°
atan_lut[1]  = 0x076B19C1 = 26.5651°
atan_lut[2]  = 0x03EB6EBF = 14.0362°
atan_lut[3]  = 0x01FD5BAA =  7.1250°
atan_lut[4]  = 0x00FFAADE =  3.5763°
atan_lut[5]  = 0x007FF557 =  1.7899°
```

From iteration 10 onward, `arctan(2⁻ⁱ) ≈ 2⁻ⁱ` (small-angle approximation holds), so the LUT entries become exact powers of two:

```
atan_lut[10] = 0x00040000 = 2⁻¹⁰ × 2²⁸ (in Q4.28)
atan_lut[11] = 0x00020000 = 2⁻¹¹ × 2²⁸
...
```

---
