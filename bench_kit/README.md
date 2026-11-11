# bench_kit — Dhrystone + CoreMark on any RISC-V project

You edit **one block in `platform.h`** (clock, memory map, UART/print port, cycle source).
Everything else (startup, linker script, libc subset, CoreMark port patching, result validation,
score computation) is generic RV32/RV64. Needs: `riscv*-gcc` (any, bare-metal), GNU make >= 3.82, python3, git.

## Workflow
```bash
make fetch                                                # clone CoreMark + Dhrystone once

# 1) GOLDEN RUN on QEMU first -> proves toolchain + software are right before blaming your RTL
make PLAT_DEFS=-DPLAT_QEMU qemu-coremark  report-coremark
make PLAT_DEFS=-DPLAT_QEMU qemu-dhrystone report-dhrystone

# 2) your project: edit the marked block in platform.h, then
make clean && make coremark dhrystone                     # -> build/*.elf .bin .hex .dump .info
#    load build/*.bin|.hex into your ROM with your own flow (hex2mif etc.), run sim/FPGA,
#    save the UART text to logs/coremark.log / logs/dhrystone.log, then:
make report-coremark report-dhrystone                     # validates + scores + records
```
Useful overrides: `ARCH=rv32imc_zicsr_zifencei ABI=ilp32 PREFIX=riscv32-unknown-elf-`,
`CORE_ITER=...`, `DHRY_RUNS=...`, `OPT=-O3`. (`_zicsr` is mandatory with binutils >= 2.38.)

## What "valid" means (enforced by `scripts/parse_results.py`, exit code 1 on failure)
* **CoreMark:** seedcrc/crclist/crcmatrix/crcstate = `e9f5/e714/1fd7/8e3a`; >= 10 s for an *official* score.
  Short RTL runs still give a trustworthy **CoreMark/MHz** (computed from raw cycles) but are flagged non-official.
* **Dhrystone:** every "should be" value matches (incl. `Arr_2_Glob[8][7] = runs+10`); DMIPS = Dhrystones/s / 1757.
  Ignore Dhrystone's own "Microseconds / Dhrystones per Second" lines (timer is cycles, not seconds) — the parser recomputes from exact cycles.
* Log must contain the `[BENCH]` banner and `[BENCH] done` (catches hangs, traps, truncated UART capture).
* Recorded to `results/<bench>.json` (+ `results/summary.md`) with compiler version and flags from `build/<bench>.info`.

## Making it official on hardware
CoreMark needs >= 10 s: `CORE_ITER ~= 11 * (CoreMark/MHz * clk_MHz)`; Dhrystone needs >= 2 s.
CoreMark's tick counter is 32-bit: at clocks above ~400 MHz it wraps within a 10 s run — use
`PLAT_CYCLE_SRC 1` with a slower MMIO timer and set `PLAT_TICK_HZ` (the parser rescales).

## Bring-up ladder (symptom -> cause)
| Log shows | Cause |
|---|---|
| nothing / "No banner" | reset vector != `PLAT_ROM_BASE`, ROM image not loaded, UART map/stride wrong, TB UART capture missing |
| `[BENCH] TRAP mcause=..` | illegal instr (check `-march` vs core), misaligned/bad address, `rdcycle` not implemented (mcause=2) |
| banner, then hang | cycle CSR stuck, stack/RAM region wrong, UART TX-ready bit never set |
| CRC / value mismatch | real core bug (software already passed on QEMU) — diff the trace vs `qemu -d in_asm` / spike |

## Simulation tips
* A real UART at 115200 baud on 50 MHz costs ~434 cycles/bit — slow in RTL sim. Use `PLAT_OUT_BACKEND 1`
  (1-byte MMIO print port) with 3 lines in your testbench, and the real UART only on FPGA:
```systemverilog
// bus write strobe/addr/data names are yours
integer logf; initial logf = $fopen("logs/coremark.log","w");
always @(posedge clk) if (wr_en && wr_addr==32'h1000_0000) begin $write("%c",wr_data[7:0]); $fwrite(logf,"%c",wr_data[7:0]); $fflush(logf); end
always @(posedge clk) if (wr_en && wr_addr==32'h1000_0008) begin $display("EXIT code=%0d",wr_data); $finish; end  // PLAT_EXIT_ADDR
```
* Core without `rdcycle`? Add a free-running counter CSR/MMIO, or (last resort) have the TB timestamp the
  start/end prints and use cycles = delta_time / clock_period.
* QEMU cycle counts are **not** performance data (they vary run to run); use QEMU for correctness only.
* Need cache/MPU/CSR setup before `main`? Define `void plat_early_init(void)` in your own file (weak default is empty).
* ROM footprint measured: CoreMark ~12.8 KB, Dhrystone ~5.4 KB code (-O2).

## Custom RV32IM core in VCS (no CSRs, separate imem/dmem) -- the short version
```bash
make fetch
# edit platform.h: PLAT_XLEN 32, PLAT_HAS_CSR 0, PLAT_HARVARD 1 (if imem/dmem are separate),
# ROM_* = imem, RAM_* = dmem as your core's LOAD/STORE address decode sees it,
# PLAT_OUT_BACKEND 1 + PLAT_SIMOUT_ADDR, PLAT_EXIT_ADDR, PLAT_CYCLE_SRC 1 + PLAT_TIMER_ADDR
make clean
make ARCH=rv32im ABI=ilp32 CORE_ITER=10 DHRY_RUNS=500 coremark dhrystone
make ARCH=rv32im ABI=ilp32 images-dhrystone images-coremark
#   -> build/dhrystone.imem.hex (+ .dmem.hex when HARVARD)   [$readmemh format, 1 word/line]
```
Copy the `.imem.hex` over your `imem.hex` (and `.dmem.hex` over your dmem init file), run your VCS testbench,
write the print-port bytes to `logs/<bench>.log`, then `make report-dhrystone`. Footprint (rv32im -O2):
CoreMark ~20 KB imem + ~2.6 KB dmem image, Dhrystone ~13.6 KB imem (soft-float helpers for its final printout; not in the timed loop) + ~2.2 KB dmem image, plus ~10 KB bss (Arr_2_Glob); stack defaults to 16 KB
(`-DPLAT_STACK_SIZE=0x2000` via PLAT_DEFS to shrink). dmem base must be aligned to the dmem size so its
low address bits index `$readmemh` entry 0 at `PLAT_RAM_BASE`.
Tested here on QEMU rv32: no-CSR + MMIO timer + split memories + RV32IM -> both benchmarks validate.
