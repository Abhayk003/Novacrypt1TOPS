/* link.ld - RV32IM SoC memory map (Option C: code in I-SRAM, ROM = reset vector)
 * Boot ROM   0x00000000  16 KB  -> tiny boot stub (jumps to I-SRAM)
 * I-SRAM     0x00010000  64 KB  -> .text/.rodata (firmware runs here)
 * D-SRAM     0x00020000  64 KB  -> .data/.bss/heap/stack
 */
OUTPUT_ARCH("riscv")
ENTRY(_boot)

MEMORY
{
  ROM   (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
  ISRAM (rx)  : ORIGIN = 0x00010000, LENGTH = 64K
  DSRAM (rw)  : ORIGIN = 0x00020000, LENGTH = 64K
}

/* top of stack = top of D-SRAM */
_stack_top = ORIGIN(DSRAM) + LENGTH(DSRAM);
_stack_size = 4K;

SECTIONS
{
  /* reset vector / boot stub in ROM at 0x0 */
  .boot : { KEEP(*(.boot)) } > ROM

  /* firmware code + read-only data in I-SRAM */
  .text : {
    *(.text.startup)        /* crt0 _start lands first */
    *(.text*)
    *(.rodata*)
    *(.srodata*)
    . = ALIGN(4);
  } > ISRAM

  /* initialized data: RUNS in D-SRAM (VMA) but its init image is LOADED in
   * I-SRAM (LMA), appended after .text. crt0 copies LMA->VMA at boot. This is
   * required because D-SRAM has no $readmemh init file; only I-SRAM (program.mem)
   * and ROM (bootrom.mem) are preloaded. */
  .data : AT (ADDR(.text) + SIZEOF(.text)) {
    . = ALIGN(4);
    _data_start = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    _data_end = .;
  } > DSRAM
  _data_lma = LOADADDR(.data);

  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DSRAM

  _heap_start = .;
  _heap_end   = _stack_top - _stack_size;

  /DISCARD/ : { *(.comment) *(.eh_frame) *(.riscv.attributes) }
}
