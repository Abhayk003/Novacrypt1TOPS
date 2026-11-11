/* crt0.S -- generic RV32/RV64 bare-metal startup */
#include "platform.h"
    .section .init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop
    la   sp, _stack_top
#if PLAT_HAS_CSR
    la   t0, trap_entry
    csrw mtvec, t0
    li   t0, 0x2000              /* mstatus.FS = Initial (ignored if no FPU) */
    csrs mstatus, t0
#endif

    la   t0, _bss_start          /* zero .bss */
    la   t1, _bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:  la   t0, _data_lma           /* copy .data if load addr != run addr */
    la   t1, _data_start
    la   t2, _data_end
    beq  t0, t1, 4f
3:  bgeu t1, t2, 4f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    3b
4:  call plat_early_init         /* weak hook: enable caches etc. */
    call plat_banner
    li   a0, 0
    li   a1, 0
    call main
    call plat_exit               /* a0 = main's return value */
5:  j    5b

#if PLAT_HAS_CSR
    .align 2
trap_entry:                      /* any trap = report and stop */
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call plat_trap
6:  j    6b
#endif