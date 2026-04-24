#include "workload_mext.h"
#include "util.h"

// Macro to wrap assembly for clean instruction-specific calls
#define RV32M_EXEC(inst, rs1, rs2, rd) \
    asm volatile(inst " %0, %1, %2" : "=r"(rd) : "r"(rs1), "r"(rs2))

int run_mext_diagnostic() {
    int total_errors = 0;
    int32_t rd_low, rd_high;

    print_string("\r\n>>> [M-EXTENSION] Industry-Grade Diagnostic Init...\r\n");

    // --- CASE A: MULTIPLICATION SIGNED/UNSIGNED BOUNDARIES ---
    print_string("[TEST] Multiplier Corner Cases: ");
    
    // 1. Signed x Signed (Max capacity)
    // 0x7FFFFFFF * 2 = 0x00000000FFFFFFFE -> Low=0xFFFFFFFE, High=0x00000000
    int32_t s_max = 0x7FFFFFFF;
    RV32M_EXEC("mul", s_max, 2, rd_low);
    RV32M_EXEC("mulh", s_max, 2, rd_high);
    if (rd_low != (int32_t)0xFFFFFFFE || rd_high != 0) total_errors++;

    // 2. Signed x Unsigned (Asymmetric)
    // -2 * 2 (Unsigned) = 0xFFFFFFFC (64-bit: 0xFFFFFFFFFFFFFFFC) -> Low=0xFFFFFFFC, High=-1
    RV32M_EXEC("mul", -2, 2, rd_low);
    RV32M_EXEC("mulhsu", -2, 2, rd_high);
    if (rd_low != (int32_t)0xFFFFFFFC || rd_high != -1) total_errors++;

    // 3. Unsigned x Unsigned (Rollover)
    // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001
    uint32_t u_max = 0xFFFFFFFF;
    RV32M_EXEC("mul", u_max, u_max, rd_low);
    RV32M_EXEC("mulhu", u_max, u_max, rd_high);
    if (rd_low != 0x00000001 || rd_high != (int32_t)0xFFFFFFFE) total_errors++;

    if (total_errors == 0) print_string("PASS\r\n"); else print_string("FAIL\r\n");


    // --- CASE B: DIVISION ARCHITECTURAL EXCEPTIONS ---
    print_string("[TEST] Divider Arch Exceptions: ");
    int div_errors = 0;

    // 1. Division by Zero (Mandated to return -1)
    RV32M_EXEC("div", 100, 0, rd_low);
    if (rd_low != -1) div_errors++;

    // 2. Remainder by Zero (Mandated to return Dividend)
    RV32M_EXEC("rem", 100, 0, rd_low);
    if (rd_low != 100) div_errors++;

    // 3. Unsigned Div by Zero (Mandated to return 0xFFFFFFFF)
    RV32M_EXEC("divu", 100, 0, rd_low);
    if ((uint32_t)rd_low != 0xFFFFFFFF) div_errors++;

    // 4. Signed Overflow (-2^31 / -1)
    // Mandated to return -2^31 (Dividend) instead of trapping
    int32_t min_int = 0x80000000;
    RV32M_EXEC("div", min_int, -1, rd_low);
    if (rd_low != min_int) div_errors++;

    if (div_errors == 0) print_string("PASS\r\n"); else { print_string("FAIL\r\n"); total_errors += div_errors; }


    // --- CASE C: MATHEMATICAL CONSISTENCY (Property Check) ---
    // Formula: a = (a/b)*b + (a%b)
    print_string("[TEST] Consistency Property: ");
    int32_t test_vals[] = {1234, -5678, 0x7FFFFFFF, -1, 42};
    int prop_errors = 0;

    for(int i=0; i<4; i++) {
        int32_t a = test_vals[i];
        int32_t b = test_vals[i+1];
        int32_t q, r;
        RV32M_EXEC("div", a, b, q);
        RV32M_EXEC("rem", a, b, r);
        if (a != (q * b + r)) prop_errors++;
    }

    if (prop_errors == 0) print_string("PASS\r\n"); else { print_string("FAIL\r\n"); total_errors += prop_errors; }

    // Final Reporting
    if (total_errors == 0) {
        print_string(">>> RESULT: ALL RV32M HARDWARE UNITS VERIFIED [OK]\r\n");
    } else {
        print_string(">>> RESULT: HW ERROR DETECTED! Count: ");
        print_int(total_errors);
        print_string("\r\n");
    }

    return total_errors;
}
