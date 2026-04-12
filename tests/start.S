# ============================================================
# RISC-V RV32IM Verification Test Suite
# Prints operands, actual results, expected values, and Y/X
# Output format per test: "LABEL:OP1<op>OP2=RESULT/EXPECTED Y"
# ============================================================

.equ UART_TX,   0x80000000
.equ UART_STAT, 0x80000008

.section .init
.globl _start
_start:
    li sp, 0x1000           # Stack at top of 4KB DMEM

    # =============== BANNER: "=RV32=" + \r\n ===============
    li a0, '='
    jal ra, print_char
    li a0, 'R'
    jal ra, print_char
    li a0, 'V'
    jal ra, print_char
    li a0, '3'
    jal ra, print_char
    li a0, '2'
    jal ra, print_char
    li a0, '='
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 1: ADD (10 + 20 = 30 = 0x1E) ============
    li t3, 10
    li t4, 20
    add t5, t3, t4          # t5 = 30

    li a0, 'A'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # operand 1 = "0A"
    li a0, '+'
    jal ra, print_char
    mv a0, t4
    jal ra, print_hex8      # operand 2 = "14"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 30
    jal ra, print_hex8      # expected = "1E"
    li a0, ' '
    jal ra, print_char
    li t6, 30
    bne t5, t6, add_f
    li a0, 'Y'
    j add_e
add_f:
    li a0, 'X'
add_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 2: SUB (100 - 58 = 42 = 0x2A) ============
    li t3, 100
    li t4, 58
    sub t5, t3, t4          # t5 = 42

    li a0, 'S'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "64"
    li a0, '-'
    jal ra, print_char
    mv a0, t4
    jal ra, print_hex8      # "3A"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 42
    jal ra, print_hex8      # expected "2A"
    li a0, ' '
    jal ra, print_char
    li t6, 42
    bne t5, t6, sub_f
    li a0, 'Y'
    j sub_e
sub_f:
    li a0, 'X'
sub_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 3: MUL (10 * 20 = 200 = 0xC8) ============
    li t3, 10
    li t4, 20
    mul t5, t3, t4          # t5 = 200

    li a0, 'M'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "0A"
    li a0, '*'
    jal ra, print_char
    mv a0, t4
    jal ra, print_hex8      # "14"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 200
    jal ra, print_hex8      # expected "C8"
    li a0, ' '
    jal ra, print_char
    li t6, 200
    bne t5, t6, mul_f
    li a0, 'Y'
    j mul_e
mul_f:
    li a0, 'X'
mul_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 4: SLLI (2 << 2 = 8 = 0x08) ============
    li t3, 2
    slli t5, t3, 2          # t5 = 8

    li a0, 'L'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "02"
    li a0, '<'
    jal ra, print_char
    li a0, 2
    jal ra, print_hex8      # "02"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 8
    jal ra, print_hex8      # expected "08"
    li a0, ' '
    jal ra, print_char
    li t6, 8
    bne t5, t6, sll_f
    li a0, 'Y'
    j sll_e
sll_f:
    li a0, 'X'
sll_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 5: SRL (32 >> 2 = 8 = 0x08) ============
    li t3, 32
    li t4, 2
    srl t5, t3, t4          # t5 = 8

    li a0, 'R'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "20"
    li a0, '>'
    jal ra, print_char
    mv a0, t4
    jal ra, print_hex8      # "02"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 8
    jal ra, print_hex8      # expected "08"
    li a0, ' '
    jal ra, print_char
    li t6, 8
    bne t5, t6, srl_f
    li a0, 'Y'
    j srl_e
srl_f:
    li a0, 'X'
srl_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 6: ANDI (0xFA & 0x0F = 0x0A) ============
    li t3, 250              # 0xFA
    andi t5, t3, 0x0F       # t5 = 0x0A

    li a0, 'N'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "FA"
    li a0, '&'
    jal ra, print_char
    li a0, 0x0F
    jal ra, print_hex8      # "0F"
    li a0, '='
    jal ra, print_char
    mv a0, t5
    jal ra, print_hex8      # result
    li a0, '/'
    jal ra, print_char
    li a0, 0x0A
    jal ra, print_hex8      # expected "0A"
    li a0, ' '
    jal ra, print_char
    li t6, 0x0A
    bne t5, t6, and_f
    li a0, 'Y'
    j and_e
and_f:
    li a0, 'X'
and_e:
    jal ra, print_char
    jal ra, print_crlf

    # ============ TEST 7: BLT (10 < 20 → should branch) ============
    li t3, 10
    li t4, 20

    li a0, 'B'
    jal ra, print_char
    li a0, ':'
    jal ra, print_char
    mv a0, t3
    jal ra, print_hex8      # "0A"
    li a0, '<'
    jal ra, print_char
    mv a0, t4
    jal ra, print_hex8      # "14"
    li a0, ' '
    jal ra, print_char
    blt t3, t4, blt_ok
    li a0, 'X'
    j blt_end
blt_ok:
    li a0, 'Y'
blt_end:
    jal ra, print_char
    jal ra, print_crlf

    # =============== DONE ===============
    li a0, '='
    jal ra, print_char
    li a0, 'O'
    jal ra, print_char
    li a0, 'K'
    jal ra, print_char
    li a0, '='
    jal ra, print_char
    jal ra, print_crlf

halt:
    j halt

# ==========================================================
# SUBROUTINES
# ==========================================================

# ----------------------------------------------------------
# print_char: Send a0[7:0] to UART TX (polling)
# Clobbers: t0, t1, t2
# ----------------------------------------------------------
print_char:
    lui t0, 0x80000         # t0 = 0x80000000
    addi t1, t0, 8          # t1 = 0x80000008 (UART_STAT)
pc_wait:
    lw t2, 0(t1)            # read status
    andi t2, t2, 1          # check TX busy
    bnez t2, pc_wait
    sw a0, 0(t0)            # write TX data
    ret

# ----------------------------------------------------------
# print_crlf: Print \r\n
# ----------------------------------------------------------
print_crlf:
    addi sp, sp, -4
    sw ra, 0(sp)
    li a0, 13               # '\r'
    jal ra, print_char
    li a0, 10               # '\n'
    jal ra, print_char
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# ----------------------------------------------------------
# print_hex8: Print a0[7:0] as two hex digits "XX"
# Uses: s0 (saved/restored on stack)
# ----------------------------------------------------------
print_hex8:
    addi sp, sp, -8
    sw ra, 4(sp)
    sw s0, 0(sp)
    mv s0, a0
    srli a0, s0, 4
    andi a0, a0, 0xF
    jal ra, print_nib       # high nibble
    andi a0, s0, 0xF
    jal ra, print_nib       # low nibble
    lw ra, 4(sp)
    lw s0, 0(sp)
    addi sp, sp, 8
    ret

# ----------------------------------------------------------
# print_nib: Print a0[3:0] as one hex digit '0'-'F'
# ----------------------------------------------------------
print_nib:
    addi sp, sp, -4
    sw ra, 0(sp)
    li t0, 10
    blt a0, t0, pn_dig
    addi a0, a0, 55         # 'A' - 10 = 55
    j pn_out
pn_dig:
    addi a0, a0, 48         # '0' = 48
pn_out:
    jal ra, print_char
    lw ra, 0(sp)
    addi sp, sp, 4
    ret
