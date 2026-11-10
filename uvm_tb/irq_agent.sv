class irq_sequencer extends uvm_sequencer #(proc_pkg::proc_irq_txn);
  `uvm_component_utils(irq_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : irq_sequencer

class irq_agent extends uvm_agent;
  `uvm_component_utils(irq_agent)

  irq_sequencer sqr;
  irq_driver    drv;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = irq_sequencer::type_id::create("sqr", this);
    drv = irq_driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : irq_agent
