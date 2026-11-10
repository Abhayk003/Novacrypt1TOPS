class axi_instr_agent extends uvm_agent;
  `uvm_component_utils(axi_instr_agent)

  axi_instr_responder rsp;
  axi_instr_monitor    mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rsp = axi_instr_responder::type_id::create("rsp", this);
    mon = axi_instr_monitor::type_id::create("mon", this);
  endfunction

endclass : axi_instr_agent
