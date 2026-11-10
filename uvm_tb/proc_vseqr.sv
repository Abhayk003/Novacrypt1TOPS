class proc_vseqr extends uvm_sequencer;
  `uvm_component_utils(proc_vseqr)

  irq_sequencer irq_sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : proc_vseqr
