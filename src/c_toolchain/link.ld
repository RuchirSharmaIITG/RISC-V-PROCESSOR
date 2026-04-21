OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
  /* Boot Address where processor PC starts perfectly at reset */
  . = 0x00000000;
  
  .text : {
    *(.init)    /* Force start.S to sit EXACTLY at 0x00000000 */
    *(.text*)   /* Followed by the rest of functions */
  }
  
  /* NOTE: Because our IMEM and DMEM memories are uniquely segregated in the Verilog array,
   * normal '.data' initialization variables won't magically appear in DMEM!
   * Bare-metal systems usually require a bootloader to copy block memory, but for now we 
   * just map everything seamlessly into the IMEM logic stream (or avoid global initializations). */
  
  .data : {
    *(.rodata*) /* Read-only data (like strings) dynamically dumped into dmem.hex! */
    *(.data*)
    *(.sdata*)
  }
  
  .bss : {
    *(.bss*)
    *(.sbss*)
    *(COMMON)
  }
}
