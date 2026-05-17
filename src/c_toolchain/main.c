#include "util.h"
#include <stdint.h>

// --- CORDIC MAP ---
#define CORDIC_ANGLE ((volatile int32_t *)0x40000000)
#define CORDIC_STATUS ((volatile int32_t *)0x40000004)
#define CORDIC_SINE ((volatile int32_t *)0x40000008)
#define CORDIC_COSINE ((volatile int32_t *)0x4000000C)

// --- SYSTOLIC MAP ---
#define SYS_WEIGHT_BASE ((volatile int32_t *)0x50000000)
#define SYS_ACT_BASE ((volatile int32_t *)0x50000040)
#define SYS_STEP ((volatile int32_t *)0x50000050)
#define SYS_OUT_BASE ((volatile int32_t *)0x50000060)

// Q4.28 fixed-point scale factor
#define Q28_SCALE (1 << 28)

void c_trap_handler(unsigned int cause) {
  print_string("TRAP! Cause: ");
  print_int(cause);
  while (1)
    ;
}

// Helper function to force a small delay for the AXI Master to recover
void axi_cooldown_delay() {
  volatile int delay = 0;
  for (int i = 0; i < 5; i++) {
    delay++;
  }
}

void test_cordic(const char *label, int32_t angle_q28) {
  print_string("CORDIC [");
  print_string(label);
  print_string("]: ");

  *CORDIC_ANGLE = angle_q28;

  // Dummy read to force AXI write to flush before polling status.
  volatile int32_t dummy_sync = *CORDIC_ANGLE;
  (void)dummy_sync;

  while (*CORDIC_STATUS == 0)
    ;

  int32_t s = *CORDIC_SINE;

  // FIX: Delay before second read so AXI Master doesn't duplicate the result
  axi_cooldown_delay();

  int32_t c = *CORDIC_COSINE;

  print_string("Sin=");
  print_hex(s);
  print_string(" Cos=");
  print_hex(c);
  print_string("\n");
}

void test_systolic_identity() {
  print_string("SYSTOLIC [Identity x Vector]: ");

  // 1. Load Identity Matrix
  // FIX 1: You accidentally deleted this loop! We must write to
  // SYS_WEIGHT_BASE.
  for (int i = 0; i < 16; i++) {
    SYS_WEIGHT_BASE[i] = (i % 5 == 0) ? 1 : 0;
  }

  // 2. Load Vector [10, 20, 30, 40]
  for (int i = 0; i < 4; i++) {
    SYS_ACT_BASE[i] = (i + 1) * 10;
  }

  // 3. Pulse steps and print intermediate results (Latency = 7)
  for (int i = 0; i < 7; i++) {
    *SYS_STEP = 1;
    print_string("  Step ");
    print_int(i);
    print_string(": [");
    print_hex(SYS_OUT_BASE[0]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[1]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[2]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[3]);
    print_string("]\n");
  }
}

int main() {
  print_string("--- EXTENDED SoC TEST SUITE ---\n");

  // 1. CORDIC TESTS (angles in Q4.28 fixed-point)
  test_cordic(" 90 deg", 0x1921FB54); // PI/2
  test_cordic(" 45 deg", 0x0C90FDAB); // PI/4
  test_cordic(" 30 deg", 0x0860A91C); // PI/6
  test_cordic("-45 deg", 0xF36F0255); // -PI/4 (2's complement of 0x0C90FDAB)

  // 2. SYSTOLIC ARRAY TESTS
  test_systolic_identity();

  // --- PIPELINE FLUSH ---
  // To avoid old activations/partial sums bleeding into the next test,
  // we must flush the systolic array pipeline with 0s.
  for (int i = 0; i < 4; i++) {
    SYS_ACT_BASE[i] = 0;
  }
  for (int i = 0; i < 7; i++) {
    *SYS_STEP = 1;
  }

  // 3. CUSTOM SYSTOLIC (Scaling)
  print_string("SYSTOLIC [Scale-by-2]:\n");
  for (int i = 0; i < 16; i++) {
    SYS_WEIGHT_BASE[i] = (i % 5 == 0) ? 2 : 0;
  }

  // FIX: Spaced out writes here too
  for (int i = 0; i < 4; i++) {
    SYS_ACT_BASE[i] = (i + 1) * 5;
  }

  // Keep inputs steady for the full wavefront latency and print step-by-step
  for (int i = 0; i < 7; i++) {
    *SYS_STEP = 1;
    print_string("  Step ");
    print_int(i);
    print_string(": [");
    print_hex(SYS_OUT_BASE[0]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[1]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[2]);
    print_string(", ");
    print_hex(SYS_OUT_BASE[3]);
    print_string("]\n");
  }

  print_string("--- ALL TESTS FINISHED ---\n");
  while (1)
    ;
  return 0;
}