/* crt0.S - C runtime startup for FreeRTOS. Linked first in .text (I-SRAM).
 * Sets sp, zeroes .bss, copies .data, calls main(). mtvec is set inside main()
 * to freertos_risc_v_trap_handler before the scheduler starts. */
  .section .text.startup, "ax"
  .global _start
_start:
  la    sp, _stack_top

  /* zero .bss */
  la    a0, _bss_start
  la    a1, _bss_end
1:
  bgeu  a0, a1, 2f
  sw    zero, 0(a0)
  addi  a0, a0, 4
  j     1b
2:
  /* copy .data from LMA (I-SRAM) to VMA (D-SRAM) */
  la    a0, _data_lma
  la    a1, _data_start
  la    a2, _data_end
3:
  bgeu  a1, a2, 4f
  lw    t0, 0(a0)
  sw    t0, 0(a1)
  addi  a0, a0, 4
  addi  a1, a1, 4
  j     3b
4:
  call  main
5:
  j     5b
