// // ============================================================================
// // tb.f -- UVM testbench compile list. Compile order matters:
// //   1. interfaces (plain top-level modules, referenced by virtual-interface
// //      handles inside proc_pkg.sv's classes -- must exist before the package)
// //   2. proc_pkg.sv        (pulls in every agent/monitor/responder/scoreboard/
// //                           env class via internal `include, in dependency order
// //                           -- see that file's own header comment)
// //   3. proc_test_pkg.sv   (sequences + tests, imports proc_pkg::*)
// //   4. tb_top.sv          (module, not a package -- instantiates DUT + interfaces,
// //                           imports both packages)
// //
// // +incdir+. lets every internal `include inside proc_pkg.sv / proc_test_pkg.sv
// // resolve by bare filename against this same directory.
// // ============================================================================
// +incdir+.

// clk_if.sv
// axi_instr_if.sv
// axi_data_if.sv
// irq_if.sv

// proc_pkg.sv
// proc_test_pkg.sv

// tb_top.sv




// ============================================================================
// tb.f -- UVM testbench compile list. Compile order matters:
//   1. interfaces  2. proc_pkg.sv  3. proc_test_pkg.sv  4. tb_top.sv
//
// PATH CONVENTION: relative to uvm_tb/ (the Makefile runs from here via
// `-f ./tb.f`). Bare filenames + `+incdir+.` so the internal `include lines
// inside proc_pkg.sv / proc_test_pkg.sv resolve against this directory.
// ============================================================================
+incdir+.

clk_if.sv
axi_instr_if.sv
axi_data_if.sv
irq_if.sv

proc_pkg.sv
proc_test_pkg.sv

tb_top.sv