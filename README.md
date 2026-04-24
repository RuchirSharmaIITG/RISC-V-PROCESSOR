# RV32IMF SoC with AXI4-Lite Hardware Accelerators

A complete, synthesizable 5-stage pipelined RISC-V System-on-Chip built in Verilog. It supports the **RV32IMF** instruction set (Base Integer, Multiply/Divide, and Single-Precision Floating Point) and features a fully operational **dual-accelerator AXI4-Lite Control Plane** for hardware-accelerated trigonometry (CORDIC) and matrix multiplication (4×4 Systolic Array).

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          top_fpga.v (SoC Top)                       │
│                                                                     │
│  ┌──────────────┐    ┌────────────────────────────────────────────┐ │
│  │  Bootloader  │    │             pipeline.v (CPU)               │ │
│  │  (UART RX)   │───▶│  IF → ID → EX → MEM → WB  (Hazard Unit)  │ │
│  └──────────────┘    └──────────────────┬─────────────────────────┘ │
│                                         │ Load/Store                 │
│  ┌──────────────┐    ┌──────────────────▼──────────────────────────┐│
│  │   UART TX    │    │              Address Decoder                ││
│  │  (0x8000...) │    │  0x0... → BRAM  │  0x4... → CORDIC (AXI)  ││
│  └──────────────┘    │  0x8... → UART  │  0x5... → Systolic (AXI)││
│                       └─────────────────────────────────────────────┘│
│                                                                     │
│  ┌──────────────────────┐   ┌──────────────────────────────────────┐│
│  │  axi_cordic_slave    │   │       axi_systolic_4x4               ││
│  │  (0x4000_0000)       │   │       (0x5000_0000)                  ││
│  │  ┌──────────────┐    │   │  ┌──────────────────────────────┐    ││
│  │  │  cordic.v    │    │   │  │  4×4 Processing Element Grid │    ││
│  │  │ (32-iter SM) │    │   │  │  + Wavefront Skew Buffers    │    ││
│  │  └──────────────┘    │   │  └──────────────────────────────┘    ││
│  └──────────────────────┘   └──────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Properties

| Property         | Value                             |
| ---------------- | --------------------------------- |
| ISA              | RV32IMF                           |
| Pipeline Stages  | 5 (IF, ID, EX, MEM, WB)           |
| Clock            | 50 MHz (external MMCM/PLL input)  |
| IMEM/DMEM        | Block RAM (8 KB each)             |
| UART Baud Rate   | 115,200                           |
| AXI Version      | AXI4-Lite                         |
| CORDIC Precision | Q4.28 fixed-point, 32 iterations  |
| Systolic Array   | 4×4 MAC grid, wavefront-scheduled |
| Target FPGA      | Nexys A7-100T (Artix-7)           |

---
