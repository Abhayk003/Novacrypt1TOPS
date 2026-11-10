//==============================================================================
// proc_test_pkg.sv -- sequences + tests, compiled after proc_pkg.
//==============================================================================
package proc_test_pkg;

  import uvm_pkg::*;
  import proc_pkg::*;
  `include "uvm_macros.svh"

  `include "irq_seqs.sv"
  `include "mem_inject_seqs.sv"
  `include "proc_vseqr.sv"
  `include "proc_base_vseq.sv"
  `include "proc_directed_vseqs.sv"

  `include "proc_base_test.sv"
  `include "proc_directed_tests.sv"

endpackage : proc_test_pkg
