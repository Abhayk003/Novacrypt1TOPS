# Firmware bring-up (Stage 0): C toolchain -> hello over UART

This is the enabler for FreeRTOS: get C compiling, linking, and running on the
SoC before any RTOS code. Memory layout (Option C):
  Boot ROM  0x00000000 16KB  -> .boot stub (jumps to I-SRAM)   [bootrom.mem]
  I-SRAM    0x00010000 64KB  -> .text/.rodata + .data init img [program.mem]
  D-SRAM    0x00020000 64KB  -> .data (run)/.bss/heap/stack     [no init file]
Reset PC = 0x0, so the ROM boot stub runs first and jumps to _start in I-SRAM.

## Files
  link.ld     linker script (the memory map above)
  boot.S      reset vector @ 0x0: jump to _start
  crt0.S      _start: set sp, zero .bss, copy .data (I-SRAM->D-SRAM), set mtvec, call main
  uart.c/.h   minimal UART driver (THR/LSR polling)
  main.c      hello-world: prints greeting, writes 0x600DC0DE to D-SRAM[0]
  elf2mem.py  objcopy-binary -> .mem (8 hex/word/line)
  Makefile    builds bootrom.mem + program.mem
  (tb_hello_c.sv is in the repo tb/ folder)

## 1. Install the toolchain (Windows)
xPack prebuilt GCC (no build needed):
  https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
Download the win32-x64 zip, extract to C:\riscv\, add its bin\ to PATH.
Verify:  riscv-none-elf-gcc --version
(Prefix is riscv-none-elf- for xPack. If yours is riscv32-unknown-elf-, set
 PREFIX=riscv32-unknown-elf- when calling make.)

## 2. Build  (PowerShell, in this fw/ folder)
If you have GNU make:
    make
If not, run the steps manually (PowerShell):
    $A = "-march=rv32im -mabi=ilp32 -mno-relax"
    $CF = "$A -Os -ffreestanding -nostdlib -nostartfiles -Wall -ffunction-sections -fdata-sections"
    riscv-none-elf-gcc $CF.Split(' ') -c boot.S -o boot.o
    riscv-none-elf-gcc $CF.Split(' ') -c crt0.S -o crt0.o
    riscv-none-elf-gcc $CF.Split(' ') -c uart.c -o uart.o
    riscv-none-elf-gcc $CF.Split(' ') -c main.c -o main.o
    riscv-none-elf-gcc $A.Split(' ') -nostdlib -nostartfiles -T link.ld -Wl,--gc-sections `
        boot.o crt0.o uart.o main.o -o fw.elf
    riscv-none-elf-objcopy -O binary --only-section=.boot fw.elf boot.bin
    riscv-none-elf-objcopy -O binary -j .text -j .rodata -j .srodata -j .data -j .sdata fw.elf isram.bin
    python elf2mem.py boot.bin bootrom.mem
    python elf2mem.py isram.bin program.mem
Also useful:  riscv-none-elf-objdump -d -S fw.elf > fw.lst   (read the disassembly)

## 3. Run in Verilator (in the repo root, with bootrom.mem + program.mem copied there)
    copy fw\bootrom.mem .
    copy fw\program.mem .
    verilator --binary --timing [the usual -Wno flags] -f rtl.f \
        --top-module tb_hello_c tb/tb_hello_c.sv
    obj_dir\Vtb_hello_c
Expect the greeting decoded on the UART line, then:
    HELLO_C PASS: main() ran (D-SRAM[0]=0x600DC0DE ...)

## 4. Run in Vivado XSim
Add tb_hello_c.sv (top) + bootrom.mem AND program.mem to sim_1; define XSIM; run -all.

## Gotchas
- MUST use -march=rv32im (NOT rv32imc): the core has no compressed instructions.
- -mno-relax avoids linker relaxation that assumes a global pointer setup we don't do.
- If main() prints garbage: the UART divisor in uart_init() must match tb BIT_NS
  (divisor=1 -> 2 clk/bit -> 20 ns/bit, matching tb_hello_c BIT_NS=20).
- If nothing runs: check the boot stub jumped correctly -- objdump fw.elf, confirm
  _boot @ 0x0 and _start @ 0x10000.

## Next (FreeRTOS)
Once HELLO_C PASS: add the FreeRTOS RISC-V port (portASM.S/port.c), a
FreeRTOSConfig.h pointing at the CLINT (mtime@0x1001BFF8, mtimecmp@0x10014000,
msip@0x10010000), a real trap_entry that routes timer+software interrupts to the
kernel, and two blinky tasks. The verified CLINT/exception work plugs in here.
