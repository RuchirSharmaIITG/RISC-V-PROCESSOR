#include "workload_alu.h"
#include "util.h"

int run_alu_diagnostic() {
    int errors = 0;
    print_string("\r\n--- STARTING ALU & RV32M DIAGNOSTIC ---\r\n");

    volatile int rs1, rs2, rd;

    // --- Basic ALU Pathways ---
    if ((2147483640 + 5) != 2147483645) errors++;
    if ((10 - 20) != -10) errors++;
    if ((~0) != -1) errors++;
    if ((0xA0000000 | 0x0000000B) != ((int)0xA000000B)) errors++;
    if ((0x55555555 ^ 0xFFFFFFFF) != ((int)0xAAAAAAAA)) errors++;
    if ((1 << 30) != 1073741824) errors++;
    if (((unsigned int)0x80000000 >> 31) != 1) errors++;
    if ((((int)0x80000000) >> 31) != -1) errors++;
    if (!(-10 < 5)) errors++;
    if (!((unsigned int)5 < (unsigned int)-10)) errors++;

    // === RV32M 8 Golden Ops Strict Hardware Verification ===
    
    // 11. MUL: Generic limits
    rs1 = 50000; rs2 = 400;
    asm volatile("mul %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != 20000000) errors++;

    // 12. MULH (Signed * Signed): Asymmetric crossing
    rs1 = -2; rs2 = 3;  // -6 = 0xFFFFFFFFFFFFFFFA. High = -1
    asm volatile("mulh %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != -1) errors++;

    // 13. MULHSU (Signed * Unsigned): Asymmetric Signs
    rs1 = -2; rs2 = 3; 
    asm volatile("mulhsu %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != -1) errors++;

    // 14. MULHU (Unsigned * Unsigned):
    rs1 = -1; rs2 = 2; // 0xFFFFFFFF * 2 = 0x00000001FFFFFFFE. High is 1.
    asm volatile("mulhu %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != 1) errors++;

    // 15. DIV (Signed): -2^31 / -1 (Golden Overflow Rule)
    rs1 = 0x80000000; rs2 = -1;
    asm volatile("div %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != 0x80000000) errors++; // Overflow rule mandates outputting dividend!

    // 16. DIVU (Unsigned): Division by Zero
    rs1 = 50; rs2 = 0;
    asm volatile("divu %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != -1) errors++; // Unsigned div by zero strictly returns max unsigned (-1)

    // 17. REM (Signed): -2^31 % -1 (Golden Overflow Rule)
    rs1 = 0x80000000; rs2 = -1;
    asm volatile("rem %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != 0) errors++; // Overflow rule mandates remainder must be cleanly 0!

    // 18. REMU (Unsigned): Division by Zero
    rs1 = 50; rs2 = 0;
    asm volatile("remu %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2));
    if (rd != 50) errors++; // Zero-division mandates returning the original dividend unconditionally!

    if (errors == 0) {
        print_string("RESULT: [PASSED] 18/18 (All 8 RV32M Golden Edge Cases Validated!)\r\n");
    } else {
        print_string("RESULT: [FAILED] Errors Detected: ");
        print_int(errors);
        print_string("\r\n");
    }
    return errors;
}
