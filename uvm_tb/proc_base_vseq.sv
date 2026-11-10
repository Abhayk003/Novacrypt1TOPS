//==============================================================================
// proc_base_vseq.sv
//
// The DUT drives its own program counter autonomously from whatever
// program image was preloaded into the shared proc_mem_model -- there is
// no per-instruction "sequence" to send it. A virtual sequence here is
// therefore mostly about (a) which irq stimulus pattern runs concurrently
// and (b) how long to let the DUT run before the test's check_phase (the
// scoreboard) evaluates the golden-trace / final-DMEM comparison.
//==============================================================================
class proc_base_vseq extends uvm_sequence;
  `uvm_object_utils(proc_base_vseq)
  `uvm_declare_p_sequencer(proc_vseqr)

  proc_pkg::proc_env_cfg cfg;
  virtual clk_if vclk; // see top/tb_top.sv -- simple free-running clock probe

  // Override in derived directed sequences to select irq behavior.
  uvm_sequence #(proc_pkg::proc_irq_txn) irq_seq;

  function new(string name = "proc_base_vseq");
    super.new(name);
  endfunction

  task body();
    if (!uvm_config_db#(proc_pkg::proc_env_cfg)::get(null, "*", "cfg", cfg))
      `uvm_fatal("PROC_VSEQ", "env cfg not found")
    if (!uvm_config_db#(virtual clk_if)::get(null, "*", "vclk", vclk))
      `uvm_fatal("PROC_VSEQ", "clk_if not found")

    if (irq_seq == null) irq_seq = irq_idle_seq::type_id::create("irq_seq");

    fork
      irq_seq.start(p_sequencer.irq_sqr);
    join_none

    repeat (cfg.timeout_cycles) @(posedge vclk.clk);
    `uvm_info("PROC_VSEQ", $sformatf(
      "ran for the configured %0d-cycle timeout; handing off to scoreboard check_phase",
      cfg.timeout_cycles), UVM_LOW)
  endtask

endclass : proc_base_vseq
