// // ============================================================================
// // core_rtl.f -- RTL compile list for the blackbox UVM environment.
// //
// // DUT here is top_module ONLY (the CPU core in isolation), not soc_top --
// // see TEAM_BRIEF.md / proc_pkg.sv header. None of the vendor SoC
// // peripherals (AXI/APB fabric, GPIO, UART, PLIC, etc. from rtl.f) are
// // part of this DUT boundary and are deliberately NOT included here.
// // ============================================================================
// ../rtl/cpu/top_module.sv
// ../rtl/cpu/prefetch_buffer.sv
// ../rtl/cpu/prefetch_controller.sv
// ../rtl/cpu/if_id.sv
// ../rtl/cpu/registers.sv
// ../rtl/cpu/ex.sv
// ../rtl/cpu/mem_wb.sv
// ../rtl/cpu/hazard_unit.sv
// ../rtl/cpu/csr.sv
// ../rtl/cpu/wallace_mul_pipeline.sv
// ../rtl/cpu/rv32m_div_radix4.sv





// ============================================================================
// core_rtl.f -- RTL compile list for the blackbox UVM environment.
//
// DUT here is top_module ONLY (the CPU core in isolation), not soc_top.
// None of the vendor SoC peripherals are part of this DUT boundary.
//
// PATH CONVENTION: paths are relative to the uvm_tb/ directory, because the
// Makefile is invoked from inside uvm_tb/ (it uses `-f ./core_rtl.f -f ./tb.f`
// and finds golden at ../golden/). RTL therefore lives at ../rtl/cpu.
//
// +libext+.sv is REQUIRED so the -y search directory matches .sv files:
// top_module instantiates prefetch_controller, registers, ex, mem_wb,
// hazard_unit (which pull in csr, wallace_mul_pipeline, rv32m_div_radix4,
// prefetch_buffer, if_id, clint) -- all separate .sv files. Without
// +libext+.sv, -y resolves nothing and elaboration dies on unresolved modules.
// ============================================================================
+libext+.sv
-y ../rtl/cpu
../rtl/cpu/top_module.sv








