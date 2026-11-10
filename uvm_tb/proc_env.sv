class proc_env extends uvm_env;
  `uvm_component_utils(proc_env)

  axi_instr_agent instr_agt;
  axi_data_agent  data_agt;
  irq_agent       irq_agt;

  proc_scoreboard sb;
  proc_golden_ref golden_ref;
  proc_coverage   cov;

  proc_pkg::proc_env_cfg  cfg;
  proc_pkg::proc_mem_model mem;   // shared backing store for both AXI responders
  proc_pkg::proc_mem_cfg   mem_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(proc_pkg::proc_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = proc_pkg::proc_env_cfg::type_id::create("cfg");
      `uvm_warning("PROC_ENV", "no env cfg found in config_db -- using defaults (no golden files)")
    end
    uvm_config_db#(proc_pkg::proc_env_cfg)::set(this, "*", "cfg", cfg);

    mem = proc_pkg::proc_mem_model::type_id::create("mem");
    mem.load_readmemh(cfg.instr_mem_file);
    mem.load_readmemh(cfg.dmem_init_file);
    uvm_config_db#(proc_pkg::proc_mem_model)::set(this, "instr_agt.rsp", "mem", mem);
    uvm_config_db#(proc_pkg::proc_mem_model)::set(this, "data_agt.rsp", "mem", mem);

    mem_cfg = proc_pkg::proc_mem_cfg::type_id::create("mem_cfg");
    uvm_config_db#(proc_pkg::proc_mem_cfg)::set(this, "instr_agt.rsp", "cfg", mem_cfg);
    uvm_config_db#(proc_pkg::proc_mem_cfg)::set(this, "data_agt.rsp", "cfg", mem_cfg);
    // Sequences reach the live responders' knobs through this same handle
    // (published so injection sequences can uvm_config_db::get it too).
    uvm_config_db#(proc_pkg::proc_mem_cfg)::set(null, "*", "mem_cfg", mem_cfg);

    instr_agt = axi_instr_agent::type_id::create("instr_agt", this);
    data_agt  = axi_data_agent::type_id::create("data_agt", this);
    irq_agt   = irq_agent::type_id::create("irq_agt", this);

    golden_ref = proc_golden_ref::type_id::create("golden_ref", this);
    sb  = proc_scoreboard::type_id::create("sb", this);
    cov = proc_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    data_agt.mon.ap.connect(golden_ref.data_imp);
    data_agt.mon.ap.connect(sb.raw_data_imp);
    irq_agt.drv.ap.connect(golden_ref.irq_imp);
    irq_agt.drv.ap.connect(cov.irq_imp);
    golden_ref.expected_ap.connect(sb.golden_imp);
    golden_ref.actual_ap.connect(sb.data_imp);
    golden_ref.expected_ap.connect(cov.golden_imp);
    instr_agt.mon.ap.connect(sb.instr_imp);
    data_agt.mon.ap.connect(cov.analysis_export);
    instr_agt.mon.ap.connect(cov.instr_imp);
  endfunction

endclass : proc_env

