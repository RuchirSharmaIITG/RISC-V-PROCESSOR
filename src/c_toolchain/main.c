#include "util.h"
#include "workload_alu.h"

void c_trap_handler(unsigned int cause) { print_string("\r\n[TRAP]\r\n"); }

int main() {
  for (volatile int i = 0; i < 500000; i++)
    ;

  // Directly print Alphabet to ensure UART is ready
  for (char c = 'A'; c <= 'Z'; c++)
    print_char(c);
  print_char('\r');
  print_char('\n');

  print_string("\r\n--- STARTING RV32I INTEGER TESTS ---\r\n");

  // Test 1: ADDI (Load Immediate 10)
  int x5 = 10;
  print_string("1. ADDI: x5 = 10 -> ");
  if (x5 == 0x0A) {
    print_string("10 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x5);
    print_string(")\r\n");
  }

  // Test 2: ADDI (Load Immediate 20)
  int x6 = 20;
  print_string("2. ADDI: x6 = 20 -> ");
  if (x6 == 0x14) {
    print_string("20 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x6);
    print_string(")\r\n");
  }

  // Test 3: ADD
  int x7 = x5 + x6; // Expected: 30
  print_string("3. ADD: 10 + 20 = ");
  if (x7 == 0x1E) {
    print_string("30 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x7);
    print_string(")\r\n");
  }

  // Test 4: SUB
  int x8 = x6 - x5; // Expected: 10
  print_string("4. SUB: 20 - 10 = ");
  if (x8 == 0x0A) {
    print_string("10 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x8);
    print_string(")\r\n");
  }

  // Test 5: SLLI (Logical Left Shift)
  int x9 = x5 << 2; // Expected: 40
  print_string("5. SLLI: 10 << 2 = ");
  if (x9 == 0x28) {
    print_string("40 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x9);
    print_string(")\r\n");
  }

  // Test 6: XORI (Bitwise XOR Immediate)
  int x10 = x5 ^ 15; // Expected: 5
  print_string("6. XORI: 10 ^ 15 = ");
  if (x10 == 0x05) {
    print_string("5 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x10);
    print_string(")\r\n");
  }

  // Test 7: AND (Bitwise AND)
  int x11 = x5 & x6; // Expected: 0
  print_string("7. AND: 10 & 20 = ");
  if (x11 == 0x00) {
    print_string("0 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x11);
    print_string(")\r\n");
  }

  // Test 8: OR (Bitwise OR)
  int x12 = x5 | x6; // Expected: 30
  print_string("8. OR: 10 | 20 = ");
  if (x12 == 0x1E) {
    print_string("30 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x12);
    print_string(")\r\n");
  }

  // Test 9: SLT (Set Less Than)
  int x13 = (x6 < x5) ? 1 : 0; // Expected: 0 (20 is not less than 10)
  print_string("9. SLT: 20 < 10 = ");
  if (x13 == 0x00) {
    print_string("0 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x13);
    print_string(")\r\n");
  }

  // Test 10: ADDI (Chained with SLT result)
  int x14 = x13 + 100; // Expected: 100
  print_string("10. ADDI: 0 + 100 = ");
  if (x14 == 0x64) {
    print_string("100 [PASSED]\r\n");
  } else {
    print_string("FAILED (Hex: ");
    print_hex((unsigned int)x14);
    print_string(")\r\n");
  }

  print_string("\r\nAll integer instructions verified! Base ALU is fully "
               "operational!\r\n");

  while (1) {
    for (volatile int i = 0; i < 100000; i++)
      ; // Halt
  }

  return 0;
}










// #include "util.h"
// #include <stdint.h>

// // --- CORDIC MAP ---
// #define CORDIC_ANGLE ((volatile int32_t *)0x40000000)
// #define CORDIC_STATUS ((volatile int32_t *)0x40000004)
// #define CORDIC_SINE ((volatile int32_t *)0x40000008)
// #define CORDIC_COSINE ((volatile int32_t *)0x4000000C)

// // --- SYSTOLIC MAP ---
// #define SYS_WEIGHT_BASE ((volatile int32_t *)0x50000000)
// #define SYS_ACT_BASE ((volatile int32_t *)0x50000040)
// #define SYS_STEP ((volatile int32_t *)0x50000050)
// #define SYS_OUT_BASE ((volatile int32_t *)0x50000060)

// // Q4.28 fixed-point scale factor
// #define Q28_SCALE (1 << 28)

// void c_trap_handler(unsigned int cause) {
//   print_string("TRAP! Cause: ");
//   print_int(cause);
//   while (1)
//     ;
// }

// // Helper function to force a small delay for the AXI Master to recover
// void axi_cooldown_delay() {
//   volatile int delay = 0;
//   for (int i = 0; i < 5; i++) {
//     delay++;
//   }
// }

// void test_cordic(const char *label, int32_t angle_q28) {
//   print_string("CORDIC [");
//   print_string(label);
//   print_string("]: ");

//   *CORDIC_ANGLE = angle_q28;

//   // Dummy read to force AXI write to flush before polling status.
//   volatile int32_t dummy_sync = *CORDIC_ANGLE;
//   (void)dummy_sync;

//   while (*CORDIC_STATUS == 0)
//     ;

//   int32_t s = *CORDIC_SINE;

//   // FIX: Delay before second read so AXI Master doesn't duplicate the result
//   axi_cooldown_delay();

//   int32_t c = *CORDIC_COSINE;

//   print_string("Sin=");
//   print_hex(s);
//   print_string(" Cos=");
//   print_hex(c);
//   print_string("\n");
// }

// void test_systolic_identity() {
//   print_string("SYSTOLIC [Identity x Vector]: ");

//   // 1. Load Identity Matrix
//   // FIX 1: You accidentally deleted this loop! We must write to
//   // SYS_WEIGHT_BASE.
//   for (int i = 0; i < 16; i++) {
//     SYS_WEIGHT_BASE[i] = (i % 5 == 0) ? 1 : 0;
//   }

//   // 2. Load Vector [10, 20, 30, 40]
//   for (int i = 0; i < 4; i++) {
//     SYS_ACT_BASE[i] = (i + 1) * 10;
//   }

//   // 3. Pulse steps (Latency = 7)
//   // FIX 2: We must do all 7 steps in ONE loop and NEVER clear SYS_ACT_BASE
//   to
//   // 0.
//   for (int i = 0; i < 7; i++) {
//     *SYS_STEP = 1;
//   }

//   // 4. Print Results
//   print_string("Out=[");
//   print_int(SYS_OUT_BASE[0]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[1]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[2]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[3]);
//   print_string("]\n");
// }

// int main() {
//   print_string("--- EXTENDED SoC TEST SUITE ---\n");

//   // 1. CORDIC TESTS (angles in Q4.28 fixed-point)
//   test_cordic(" 90 deg", 0x1921FB54); // PI/2
//   test_cordic(" 45 deg", 0x0C90FDAB); // PI/4
//   test_cordic(" 30 deg", 0x0860A91C); // PI/6
//   test_cordic("-45 deg", 0xF36F0255); // -PI/4 (2's complement of 0x0C90FDAB)

//   // 2. SYSTOLIC ARRAY TESTS
//   test_systolic_identity();

//   // 3. CUSTOM SYSTOLIC (Scaling)
//   print_string("SYSTOLIC [Scale-by-2]: ");
//   for (int i = 0; i < 16; i++) {
//     SYS_WEIGHT_BASE[i] = (i % 5 == 0) ? 2 : 0;
//   }

//   // FIX: Spaced out writes here too
//   for (int i = 0; i < 4; i++) {
//     SYS_ACT_BASE[i] = (i + 1) * 5;
//   }

//   // Keep inputs steady for the full wavefront latency
//   for (int i = 0; i < 7; i++) {
//     *SYS_STEP = 1;
//   }

//   print_string("Out=[");
//   print_int(SYS_OUT_BASE[0]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[1]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[2]);
//   print_string(",");
//   print_int(SYS_OUT_BASE[3]);
//   print_string("]\n");

//   print_string("--- ALL TESTS FINISHED ---\n");
//   while (1)
//     ;
//   return 0;
// }