//==============================================================================
// mem_inject_seqs.sv
//
// The AXI slave responders are reactive BFMs (see axi_instr_responder /
// axi_data_responder), not classic uvm_driver-behind-a-sequencer
// components -- there's no "next AXI response transaction" to randomize
// and send, the DUT alone decides when it issues AR/AW/W. Error/latency/
// backpressure injection is therefore done by mutating the *shared*
// proc_mem_cfg object those responders read every transaction, rather
// than by sequence items. This class is a thin, restartable wrapper
// around that so virtual sequences/tests can call it like a sequence.
//==============================================================================
class mem_inject_cfg_helper extends uvm_object;
  `uvm_object_utils(mem_inject_cfg_helper)

  proc_pkg::proc_mem_cfg cfg;

  function new(string name = "mem_inject_cfg_helper");
    super.new(name);
  endfunction

  function void resolve_cfg();
    if (cfg == null) begin
      if (!uvm_config_db#(proc_pkg::proc_mem_cfg)::get(null, "*", "mem_cfg", cfg))
        `uvm_fatal("MEM_INJECT", "shared proc_mem_cfg not found in config_db")
    end
  endfunction

  // Directed backpressure: hold ARREADY/AWREADY/WREADY off ~50% of the
  // time, no errors.
  function void apply_backpressure(int unsigned pct = 50);
    resolve_cfg();
    cfg.backpressure_pct = pct;
  endfunction

  // Directed SLVERR injection on reads, writes, or both.
  function void apply_slverr(int unsigned read_pct = 0, int unsigned write_pct = 0);
    resolve_cfg();
    cfg.read_err_pct  = read_pct;
    cfg.write_err_pct = write_pct;
  endfunction

  function void apply_latency(int unsigned min_c, int unsigned max_c);
    resolve_cfg();
    cfg.min_latency_cycles = min_c;
    cfg.max_latency_cycles = max_c;
  endfunction

  // Back to a clean, always-OKAY, zero-extra-latency slave.
  function void clear();
    resolve_cfg();
    cfg.min_latency_cycles = 0;
    cfg.max_latency_cycles = 2;
    cfg.read_err_pct       = 0;
    cfg.write_err_pct      = 0;
    cfg.backpressure_pct   = 0;
  endfunction

endclass : mem_inject_cfg_helper
