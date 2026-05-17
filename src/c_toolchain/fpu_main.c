#include "util.h"

void c_trap_handler(unsigned int cause) {
  print_string("\r\n[TRAP]\r\n");
  while (1);
}

int main() {
  for (volatile int i = 0; i < 500000; i++); 

  print_string("\r\n--- STARTING RV32F FLOATING POINT TESTS ---\r\n");

  // Test 1: Basic Addition
  volatile float a = 5.25f;
  volatile float b = 3.5f;
  volatile float res = a + b; // Expected: 8.75
  
  print_string("Addition: 5.25 + 3.50 = ");
  unsigned int raw = *((volatile unsigned int*)&res);
  if (raw == 0x410C0000) {
       print_string("8.75 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }

  // Test 2: Multiplication
  res = a * b; // Expected: 18.375
  print_string("Multiplication: 5.25 * 3.50 = ");
  raw = *((volatile unsigned int*)&res);
  if (raw == 0x41930000) {
       print_string("18.375 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }
  
  // Test 3: Division
    res = b / 0.5f; // Expected: 7.0
  print_string("Division: 3.50 / 0.50 = ");
  raw = *((volatile unsigned int*)&res);
  if (raw == 0x40E00000) {
      print_string("7.0 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }

// Test 4: Division by zero
  res = b / 0.0f; // Expected: INF
  print_string("Division by zero: 3.50 / 0.00 = ");
  raw = *((volatile unsigned int*)&res);
  if (raw == 0x7F800000) {
      print_string("INF [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }

  // Test 5: Subtraction
  res = a - b; // Expected: 1.75
  print_string("Subtraction: 5.25 - 3.50 = ");
  raw = *((volatile unsigned int*)&res);
  if (raw == 0x3FE00000) {
      print_string("1.75 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }

  

    res = b-a; // Expected: 1.75
  print_string("Subtraction: 3.50 - 5.25 = ");
  raw = *((volatile unsigned int*)&res);
  if (raw == 0xBFE00000) {
      print_string("-1.75 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }


  // Test 6: FPU Comparisons
  print_string("Greater than: 5.25 > 3.50 = ");
  volatile int cmp = (a > b); // Expected: 1
  if (cmp == 1) {
      print_string("1 [PASSED]\r\n");
  } else {
      print_string("FAILED (Val: ");
      print_int(cmp);
      print_string(")\r\n");
  }

    print_string("Less than: 5.25 < 3.50 = ");
  volatile int cmp2 = (a < b); // Expected: 0
  if (cmp2 == 0) {
      print_string("0 [PASSED]\r\n");
  } else {
      print_string("FAILED (Val: ");
      print_int(cmp2);
      print_string(")\r\n");
  }


  // Test 7: Float Negation
  volatile float neg_a = -a; // Expected: -5.25
  print_string("Additive Inverse: -5.25 = ");
  raw = *((volatile unsigned int*)&neg_a);
  if (raw == 0xC0A80000) {
      print_string("5.25 [PASSED] (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  } else {
      print_string("FAILED (Hex: ");
      print_hex(raw);
      print_string(")\r\n");
  }

  print_string("\r\n--- FPU TEST COMPLETE ---\r\n");

  while(1) {
      // Halt
  }

  return 0;
}