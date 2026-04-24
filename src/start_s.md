# `start.S` — Documentation

## What It Does

`start.S` is the RISC-V assembly entry point of the program. It is the very first code the CPU executes after the bootloader releases it from reset. Its job is to prepare a minimal, safe runtime environment — setting up the stack and trap handler — before handing control over to the C `main()` function.

It also defines the low-level trap handler that catches any CPU exception or interrupt, delegates it to a C function, and resumes execution.

---

## Why It Exists

A C program cannot run safely on bare metal without some assembly-level setup first. The C compiler assumes:

- A valid **stack pointer** (`sp`) is already set before any function is called.
- A **trap vector** is registered so the CPU has somewhere to jump on exceptions instead of crashing silently or looping forever.

Neither of these can be set up in C itself (the stack doesn't exist yet, and CSR registers require special instructions). `start.S` bridges this gap between the bootloader releasing the CPU and the C world being ready to use.

---

## Execution Flow

```
CPU reset released (by bootloader)
        │
        ▼
     _start
        │
        ├─ 1. Set stack pointer (sp = 0x2000)
        ├─ 2. Register trap handler in mtvec CSR
        └─ 3. Call main()
                │
                ▼
           C program runs
                │
                ▼
            halt: (infinite loop — if main() ever returns)
```

---

## `_start` — Startup Routine

```asm
_start:
    li  sp, 0x2000          # Set stack pointer
    la  t0, _trap_handler   # Load address of trap handler
    csrw mtvec, t0          # Write it into the Machine Trap Vector CSR
    jal ra, main            # Call C main()

halt:
    j halt                  # Infinite loop if main() returns
```

### Step 1 — Stack Pointer Initialisation

```asm
li sp, 0x2000
```

Sets the stack pointer to `0x2000` (8 KB into RAM). The stack grows **downward** in RISC-V, so this puts the top of the stack at the highest address allocated for it. Without this, the very first C function call would push a return address to an undefined memory location, corrupting whatever is there.

### Step 2 — Trap Vector Registration

```asm
la  t0, _trap_handler
csrw mtvec, t0
```

Loads the address of `_trap_handler` into the `mtvec` CSR (Machine Trap Vector register). This tells the CPU where to jump whenever an exception or interrupt occurs. Without this, any trap (illegal instruction, memory fault, etc.) would cause the CPU to jump to address `0x00000000` — overwriting or re-executing the start of the program.

### Step 3 — Jump to `main()`

```asm
jal ra, main
```

Calls the C `main()` function. From this point on, the C runtime takes over.

### `halt` — Safety Net

```asm
halt:
    j halt
```

If `main()` ever returns (which it shouldn't in a bare-metal program), the CPU falls into this infinite loop instead of executing whatever garbage lies past the end of the program in memory.

---

## `_trap_handler` — Exception and Interrupt Handler

This routine is invoked automatically by the CPU hardware whenever a trap occurs (an exception such as an illegal instruction, or an interrupt).

### Step 1 — Save CPU State

```asm
addi sp, sp, -32
sw ra, 28(sp)
sw a0, 24(sp)
sw a1, 20(sp)
sw a2, 16(sp)
sw t0, 12(sp)
sw t1, 8(sp)
sw t2, 4(sp)
```

Allocates 32 bytes on the stack and saves the **caller-saved registers** (`ra`, `a0`–`a2`, `t0`–`t2`). This is necessary because the trap can fire at any point during normal execution — the handler must not clobber any registers that the interrupted code was using, or the program state would be corrupted on return.

### Step 2 — Call C Trap Handler

```asm
csrr a0, mcause
jal  ra, c_trap_handler
```

Reads the `mcause` CSR (Machine Cause register), which encodes **why** the trap occurred (e.g. illegal instruction, load/store fault, external interrupt). This value is passed as the first argument (`a0`) to a C function `c_trap_handler`, allowing trap logic to be written in C rather than assembly.

### Step 3 — Advance `mepc` by 4

```asm
csrr t0, mepc
addi t0, t0, 4
csrw mepc, t0
```

The `mepc` CSR (Machine Exception Program Counter) holds the address of the instruction that caused the trap. On `mret`, the CPU resumes from `mepc`. Incrementing it by 4 skips past the faulting instruction, allowing execution to continue rather than re-triggering the same trap infinitely.

> **Note:** The comment in the source (`# Requires Hardware Fix below`) suggests the CPU pipeline's `mepc` writeback may have a hardware bug that this workaround addresses.

### Step 4 — Restore CPU State

```asm
lw ra, 28(sp)
lw a0, 24(sp)
lw a1, 20(sp)
lw a2, 16(sp)
lw t0, 12(sp)
lw t1, 8(sp)
lw t2, 4(sp)
addi sp, sp, 32
```

Pops all saved registers back from the stack, restoring the CPU to exactly the state it was in before the trap fired.

### Step 5 — Resume Execution

```asm
mret
```

The `mret` (Machine Return) instruction atomically restores the privilege mode and jumps to `mepc`, resuming the program at the instruction after the one that caused the trap.

---

## Register Summary

| Register | Role in this file |
|---|---|
| `sp` | Stack pointer — initialised to `0x2000`, used for saving/restoring state in the trap handler |
| `ra` | Return address — saved/restored across the trap handler so `main()` can return normally |
| `a0`–`a2` | Argument/return registers — saved across trap handler; `a0` carries `mcause` to `c_trap_handler` |
| `t0`–`t2` | Temporaries — saved across trap handler to protect the interrupted code's values |
| `mtvec` | CSR — set to the address of `_trap_handler` at startup |
| `mcause` | CSR — read in the trap handler to identify the cause of the trap |
| `mepc` | CSR — read and incremented to skip past the faulting instruction on return |

---

## Relationship to Other Files

| File | Role |
|---|---|
| `bootloader.v` | Loads the compiled binary (which includes `_start`) into RAM and releases the CPU reset, causing the CPU to fetch from address `0x00000000` — the location of `_start` |
| `util.c` / `util.h` | Provides the C utility functions (`print_char`, etc.) available once `main()` is entered |
| `Makefile` | Links `start.S` first in the binary so `_start` lands at address `0x00000000` |
