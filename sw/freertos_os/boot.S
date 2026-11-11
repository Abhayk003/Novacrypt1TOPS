/* boot.S - reset vector in Boot ROM at 0x0. Jumps to firmware in I-SRAM. */
  .section .boot, "ax"
  .global _boot
_boot:
  lui   t0, %hi(_start)
  addi  t0, t0, %lo(_start)
  jr    t0
