/* platform.h -- THE ONLY FILE YOU EDIT PER PROJECT.
 * Macros only: it is also run through the preprocessor to generate the linker
 * script, so no C declarations and no U/UL suffixes on numbers.            */
#ifndef PLATFORM_H
#define PLATFORM_H

#ifdef PLAT_QEMU   /* golden-reference preset: qemu-system-riscv{32,64} -machine virt (all overridable with -D) */
  #ifndef PLAT_XLEN
  #define PLAT_XLEN          64
  #endif
  #define PLAT_CLK_HZ        10000000       /* nominal; QEMU timing is NOT cycle-accurate */
  #ifndef PLAT_UNIFIED
  #define PLAT_UNIFIED       1
  #endif
  #ifndef PLAT_ROM_BASE
  #define PLAT_ROM_BASE      0x80000000
  #endif
  #ifndef PLAT_ROM_SIZE
  #define PLAT_ROM_SIZE      0x00100000
  #endif
  #ifndef PLAT_RAM_BASE
  #define PLAT_RAM_BASE      0x80100000
  #endif
  #ifndef PLAT_RAM_SIZE
  #define PLAT_RAM_SIZE      0x00100000
  #endif
  #define PLAT_OUT_BACKEND   0
  #define PLAT_UART_BASE     0x10000000
  #define PLAT_UART_STRIDE   1
  #define PLAT_EXIT_ADDR     0x00100000     /* sifive_test device */
  #define PLAT_EXIT_PASS_VAL 0x5555
#else
  /* ================= YOUR PROJECT: EDIT THIS BLOCK ================= */
  #define PLAT_XLEN          64             /* 32 or 64                              */
  #define PLAT_CLK_HZ        50000000       /* core clock in Hz                      */

  #define PLAT_HAS_CSR       1              /* 0 = core has NO CSRs/Zicsr (no rdcycle, mtvec, wfi...) */
                                            /*     then you MUST use PLAT_CYCLE_SRC 1 below            */
  #define PLAT_HARVARD       0              /* 1 = separate instr/data memories: .text -> ROM(imem),   */
                                            /*     .rodata+.data -> RAM(dmem) (loads can't read imem)  */
  #define PLAT_UNIFIED       0              /* 1 = code+data share one memory (only if HARVARD 0)    */
  #define PLAT_ROM_BASE      0x00010000     /* reset vector / code / rodata          */
  #define PLAT_ROM_SIZE      0x00008000
  #define PLAT_RAM_BASE      0x00020000     /* data / bss / heap / stack             */
  #define PLAT_RAM_SIZE      0x00020000

  #define PLAT_OUT_BACKEND   0              /* 0 = 16550/16450-style UART            */
                                            /* 1 = sim-only MMIO "print char" port   */
  #define PLAT_UART_BASE     0x10000000
  #define PLAT_UART_STRIDE   4              /* byte spacing between UART registers   */
  /* #define PLAT_UART_DIVISOR 27 */        /* uncomment if the UART needs baud init */
  #define PLAT_SIMOUT_ADDR   0x10000000     /* backend 1: byte store = print char    */
  /* #define PLAT_EXIT_ADDR  0x10000008 */  /* optional: any store = end of test     */

  /* Cycle source: 0 = rdcycle CSR (default). 1 = MMIO 64-bit timer. */
  /* #define PLAT_CYCLE_SRC  1 */
  /* #define PLAT_TIMER_ADDR 0x02000000 */
  /* #define PLAT_TICK_HZ    10000000 */    /* only if the counter is not the core clock */
  /* ================================================================= */
#endif

/* ---- defaults for anything not set above ---- */
#ifndef PLAT_HAS_CSR
#define PLAT_HAS_CSR       1
#endif
#ifndef PLAT_HARVARD
#define PLAT_HARVARD       0
#endif
#ifndef PLAT_TICK_HZ
#define PLAT_TICK_HZ       PLAT_CLK_HZ
#endif
#ifndef PLAT_CYCLE_SRC
#define PLAT_CYCLE_SRC     0
#endif
#ifndef PLAT_UART_STRIDE
#define PLAT_UART_STRIDE   1
#endif
#ifndef PLAT_EXIT_PASS_VAL
#define PLAT_EXIT_PASS_VAL 1
#endif
#ifndef PLAT_STACK_SIZE
#define PLAT_STACK_SIZE    0x4000
#endif
#endif
