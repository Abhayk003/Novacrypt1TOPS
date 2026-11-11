/* platform.c -- output, cycle counter, exit; driven entirely by platform.h */
#include <stdint.h>
#include "platform.h"

int  printf(const char *fmt, ...);
void plat_putc(char c);
void plat_exit(int code);

/* ---------------- character output ---------------- */
#if PLAT_OUT_BACKEND == 0
#define UREG(n) (*(volatile uint8_t *)((uintptr_t)PLAT_UART_BASE + (uintptr_t)(n) * PLAT_UART_STRIDE))
void plat_putc(char c) { while (!(UREG(5) & 0x20)) { } UREG(0) = (uint8_t)c; }
static void out_init(void)
{
#ifdef PLAT_UART_DIVISOR
    UREG(3) = 0x80; UREG(0) = PLAT_UART_DIVISOR & 0xff; UREG(1) = (PLAT_UART_DIVISOR >> 8) & 0xff;
    UREG(3) = 0x03; UREG(2) = 0x07;
#endif
}
#else
void plat_putc(char c) { *(volatile uint8_t *)(uintptr_t)PLAT_SIMOUT_ADDR = (uint8_t)c; }
static void out_init(void) { }
#endif

/* ---------------- cycle / tick counter (64-bit, tear-free) ---------------- */
uint64_t plat_cycles(void)
{
#if PLAT_CYCLE_SRC == 1
 #if PLAT_XLEN == 64
    return *(volatile uint64_t *)(uintptr_t)PLAT_TIMER_ADDR;
 #else
    volatile uint32_t *t = (volatile uint32_t *)(uintptr_t)PLAT_TIMER_ADDR;
    uint32_t hi, lo, hi2;
    do { hi = t[1]; lo = t[0]; hi2 = t[1]; } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
 #endif
#elif !PLAT_HAS_CSR
 #error "PLAT_HAS_CSR=0: set PLAT_CYCLE_SRC 1 and PLAT_TIMER_ADDR (an MMIO counter your testbench/core provides)"
#elif PLAT_XLEN == 64
    uint64_t c; __asm__ volatile ("rdcycle %0" : "=r"(c)); return c;
#else
    uint32_t hi, lo, hi2;
    do {
        __asm__ volatile ("rdcycleh %0" : "=r"(hi));
        __asm__ volatile ("rdcycle  %0" : "=r"(lo));
        __asm__ volatile ("rdcycleh %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
#endif
}

/* ---------------- lifecycle ---------------- */
__attribute__((weak)) void plat_early_init(void) { }   /* override for cache enable etc. */

void plat_banner(void)
{
    out_init();
    printf("\n[BENCH] clk_hz=%lu tick_hz=%lu xlen=%d\n",
           (unsigned long)PLAT_CLK_HZ, (unsigned long)PLAT_TICK_HZ, PLAT_XLEN);
}

void plat_exit(int code)
{
    printf("[BENCH] done exit=%d\n", code);
#ifdef PLAT_EXIT_ADDR
    *(volatile uint32_t *)(uintptr_t)PLAT_EXIT_ADDR =
        code ? (((uint32_t)code << 16) | 0x3333u) : (uint32_t)PLAT_EXIT_PASS_VAL;
#endif
    for (;;) { }                                   /* no wfi: custom cores may not implement it */
}

#if PLAT_HAS_CSR
void plat_trap(unsigned long cause, unsigned long epc, unsigned long tval)
{
    printf("[BENCH] TRAP mcause=%lx mepc=%lx mtval=%lx\n", cause, epc, tval);
    plat_exit(255);
}
#endif

/* ---------------- Dhrystone timing shim (built with -DTIME) ----------------
 * Dhrystone calls time() before and after its loop; we return raw cycles and
 * print the delta, so the score is computed from exact cycles by the parser.  */
long time(long *t)
{
    static int n; static uint64_t b;
    uint64_t c = plat_cycles();
    if (n++ == 0) b = c;
    else printf("[BENCH] dhry_cycles=%llu\n", (unsigned long long)(c - b));
    if (t) *t = (long)c;
    return (long)c;
}
