#include "util.h"
#include <stdint.h>

// --- CORDIC MAP ---
#define CORDIC_ANGLE ((volatile int32_t *)0x40000000)
#define CORDIC_STATUS ((volatile int32_t *)0x40000004)
#define CORDIC_SINE ((volatile int32_t *)0x40000008)
#define CORDIC_COSINE ((volatile int32_t *)0x4000000C)

#define Q28_SCALE (1 << 28)

void c_trap_handler(unsigned int cause) {
  print_string("\r\n[TRAP]\r\n");
  while (1);
}

// Helper function to force a small delay for the AXI Master to recover
void axi_cooldown_delay(void) {
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

int main() {
  for (volatile int i = 0; i < 500000; i++); 

  print_string("--- CORDIC STANDALONE TEST ---\n");

  // CORDIC TESTS (angles in Q4.28 fixed-point)
  test_cordic(" 90 deg", 0x1921FB54); // PI/2
  test_cordic(" 45 deg", 0x0C90FDAB); // PI/4
  test_cordic(" 30 deg", 0x0860A91C); // PI/6
  test_cordic("-45 deg", 0xF36F0255); // -PI/4 (2's complement of 0x0C90FDAB)

  print_string("--- TEST COMPLETE ---\n");
  while(1);
  return 0;
}