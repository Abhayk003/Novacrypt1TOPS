class axi_data_agent extends uvm_agent;
  `uvm_component_utils(axi_data_agent)

  axi_data_responder rsp;
  axi_data_monitor    mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rsp = axi_data_responder::type_id::create("rsp", this);
    mon = axi_data_monitor::type_id::create("mon", this);
  endfunction

endclass : axi_data_agent
