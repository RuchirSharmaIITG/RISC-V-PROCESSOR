@echo off
echo COMPILING RISC-V C CODE...
riscv-none-elf-gcc -O2 -march=rv32imf -mabi=ilp32 -ffp-contract=off -ffreestanding -nostdlib -mcmodel=medany -Wl,--no-warn-rwx-segments -T link.ld start.S *.c -o program.elf

echo EXTRACTING BINARY...
riscv-none-elf-objcopy -O binary program.elf program.bin

echo CONVERTING TO VERILOG HEX...
python bin2hex.py program.bin imem.hex

echo INSTALLING INTO WORKSPACE...
copy imem.hex ..\imem.hex
copy imem.hex ..\dmem.hex

echo DONE!
