# RV32IM SoC (AXI + APB)

A small RISC-V (RV32IM) system-on-chip: a 3-stage AXI4-master core, an AXI
crossbar to on-chip memories, a custom AXI4->APB4 bridge, five APB peripherals,
and a CLINT + PLIC interrupt subsystem. Verified in Verilator and Vivado XSim.

## Architecture
    CPU (RV32IM, AXI4 master)
      |
    axi_xbar ---- Boot ROM (axi_to_mem)
      |      ---- I-SRAM   (axi_to_mem)
      |      ---- D-SRAM   (axi_to_mem)
      |
      +--------- axi_to_apb_custom (AXI4 -> APB4 bridge)
                    |
              APB slaves (psel 0..6):
                0 UART   1 Timer  2 I2C  3 SPI  4 GPIO
                5 CLINT  6 PLIC (pulp rv_plic)

## Memory map
    0x0000_0000  Boot ROM   (16 KB)
    0x0001_0000  I-SRAM     (64 KB)
    0x0002_0000  D-SRAM     (64 KB)
    0x1000_0000  APB region (12 MB window routed by the xbar)
      0x1000_0000 UART   0x1000_1000 Timer  0x1000_2000 I2C
      0x1000_3000 SPI    0x1000_4000 GPIO
      0x1001_0000 CLINT  (msip@0x0, mtimecmp@0x4000, mtime@0xBFF8)
      0x1040_0000 PLIC   (4 MB, pulp rv_plic; 4MB-aligned base required)

## Layout
    rtl/         our RTL (soc_top, sram, axi_to_apb_custom, cpu/*, clint)
    vendor/      ONLY the IP files this design actually uses (see VENDOR_MANIFEST.txt)
    tb/          testbenches
    sw/          hand-assembled test programs (.mem)
    doc/         notes
    rtl.f        compile-order file list

## Build & run (Verilator)
    cp sw/bootrom_clint.mem bootrom.mem && cp bootrom.mem program.mem
    verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-MULTIDRIVEN \
      -Wno-BLKANDNBLK -Wno-CASEINCOMPLETE -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSED \
      -Wno-SELRANGE -Wno-IMPLICIT -Wno-LATCH -Wno-GENUNNAMED -Wno-ASCRANGE -Wno-PINMISSING \
      -Wno-TIMESCALEMOD -j 2 -f rtl.f --top-module tb_clint tb/tb_clint.sv
    ./obj_dir/Vtb_clint        # -> CLINT PASS

Other tops: tb_rv_plic, tb_soc_stage2/4/5/6/7/8 (copy the matching sw/*.mem first).

## Vivado
Add rtl/, vendor/, and one tb/ file as sources; set the four include dirs
(vendor/{axi,common_cells,apb,register_interface}/include); define the XSIM macro;
copy the test .mem to sim_1 as bootrom.mem AND program.mem; `run -all`.

## Integration gotchas (learned the hard way - keep these in mind)
- SPI needs BOTH apb_spi_master and axi_spi_master (the former's submodule files
  are symlinks into the latter; here they are vendored as real files).
- GPIO/PLIC use a reg_bus: APB -> apb_to_reg -> REG_BUS -> struct reg_req/rsp.
- plic_regmap.sv's module is `plic_regs` (filename != module) - list explicitly.
- rv_plic regmap hardcodes PLIC base 0x0C00_0000; soc_top ORs that into the
  reg-bus address. PLIC sources are 1-based with an internal shift:
  Timer (irq_sources_i[1]) -> PRIO offset 0x8, IE0 bit2 (0x4), claim id 2.
  le_i = edge so pulse IRQs latch.
- Enable mstatus.MIE LAST when arming interrupts (after the source + per-source
  enable), so the trap is taken at a clean boundary, not mid-setup.

## IP provenance / licenses
All vendor/ files are from pulp-platform (and lowRISC prims via register_interface),
under their original licenses (Solderpad/Apache) - see vendor/<ip>/LICENSE and the
SPDX headers kept in each file. Upstream:
  axi, common_cells, apb, apb_uart_sv, apb_timer, apb_i2c, apb_spi_master,
  axi_spi_master, gpio, register_interface, tech_cells_generic, rv_plic
  -> github.com/pulp-platform/<name>
This repo vendors only the subset required to build; full repos are upstream.
