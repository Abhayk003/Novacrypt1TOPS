// //==============================================================================
// // proc_base_test.sv
// //
// // All golden-artifact filenames are plusarg-driven so the same compiled
// // test can be pointed at any program image without a recompile:
// //   +PROG_NAME=<name>              (used to build default filenames below)
// //   +INSTR_MEM_FILE=<path>         (overrides)
// //   +DMEM_INIT_FILE=<path>
// //   +BUS_TRACE_FILE=<path>
// //   +DMEM_FINAL_FILE=<path>
// //   +PC_TRACE_FILE=<path>
// //   +TIMEOUT_CYCLES=<n>
// //==============================================================================
// class proc_base_test extends uvm_test;
//   `uvm_component_utils(proc_base_test)

//   proc_env env;
//   proc_vseqr vseqr; // convenience handle; env doesn't own the virtual sequencer,
//                      // tb_top does, so tests fetch it back out of config_db.

//   proc_pkg::proc_env_cfg cfg;

//   // Override in a directed test subclass to select which virtual sequence
//   // class runs by default.
//   string default_vseq_type = "proc_base_vseq";

//   function new(string name = "proc_base_test", uvm_component parent = null);
//     super.new(name, parent);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     string prog_name;
//     super.build_phase(phase);

//     cfg = proc_pkg::proc_env_cfg::type_id::create("cfg");

//     if (!$value$plusargs("PROG_NAME=%s", prog_name)) prog_name = "smoke";

//     cfg.instr_mem_file  = get_plusarg_or_default("INSTR_MEM_FILE",
//                              {"../golden/out/", prog_name, ".instr.mem"});
//     cfg.dmem_init_file  = get_plusarg_or_default("DMEM_INIT_FILE",
//                              {"../golden/out/", prog_name, ".dmem_init.mem"});
//     cfg.bus_trace_file  = get_plusarg_or_default("BUS_TRACE_FILE",
//                              {"../golden/out/", prog_name, ".bus_trace.txt"});
//     cfg.dmem_final_file = get_plusarg_or_default("DMEM_FINAL_FILE",
//                              {"../golden/out/", prog_name, ".dmem_final.mem"});
//     cfg.pc_trace_file   = get_plusarg_or_default("PC_TRACE_FILE",
//                              {"../golden/out/", prog_name, ".pc_trace.txt"});

//     void'($value$plusargs("TIMEOUT_CYCLES=%d", cfg.timeout_cycles));
//     if (cfg.timeout_cycles == 0) cfg.timeout_cycles = 200_000;

//     uvm_config_db#(proc_pkg::proc_env_cfg)::set(this, "*", "cfg", cfg);
//     uvm_config_db#(proc_pkg::proc_env_cfg)::set(null, "*", "cfg", cfg);

//     env = proc_env::type_id::create("env", this);
//   endfunction

//   // vseqr (created by tb_top before run_test()) needs its irq_sqr handle
//   // pointed at the real irq sequencer, which doesn't exist until env's
//   // build_phase runs -- must happen here (connect_phase, after build,
//   // before run_phase's vseq.start()), not in tb_top.
//   function void connect_phase(uvm_phase phase);
//     super.connect_phase(phase);
//     if (!uvm_config_db#(proc_vseqr)::get(this, "", "vseqr", vseqr))
//       `uvm_fatal("PROC_TEST", "virtual sequencer not published by tb_top")
//     vseqr.irq_sqr = env.irq_agt.sqr;
//   endfunction

//   function string get_plusarg_or_default(string key, string dflt);
//     string val;
//     if ($value$plusargs({key, "=%s"}, val)) return val;
//     return dflt;
//   endfunction

//   task run_phase(uvm_phase phase);
//     proc_base_vseq vseq;
//     uvm_object obj;
//     uvm_factory factory = uvm_factory::get();

//     phase.raise_objection(this);

//     if (!uvm_config_db#(proc_vseqr)::get(this, "", "vseqr", vseqr))
//       `uvm_fatal("PROC_TEST", "virtual sequencer not published by tb_top")

//     obj = factory.create_object_by_name(default_vseq_type, get_full_name(), "vseq");
//     if (!$cast(vseq, obj))
//       `uvm_fatal("PROC_TEST", $sformatf("%s is not a proc_base_vseq", default_vseq_type))

//     vseq.start(vseqr);

//     phase.drop_objection(this);
//   endtask

// endclass : proc_base_test



//==============================================================================
// proc_base_test.sv
//
// All golden-artifact filenames are plusarg-driven so the same compiled
// test can be pointed at any program image without a recompile:
//   +PROG_NAME=<name>              (used to build default filenames below)
//   +INSTR_MEM_FILE=<path>         (overrides)
//   +DMEM_INIT_FILE=<path>
//   +BUS_TRACE_FILE=<path>
//   +DMEM_FINAL_FILE=<path>
//   +PC_TRACE_FILE=<path>
//   +TIMEOUT_CYCLES=<n>
//==============================================================================
class proc_base_test extends uvm_test;
  `uvm_component_utils(proc_base_test)

  proc_env env;
  proc_vseqr vseqr; // convenience handle; env doesn't own the virtual sequencer,
                     // tb_top does, so tests fetch it back out of config_db.

  proc_pkg::proc_env_cfg cfg;

  // Override in a directed test subclass to select which virtual sequence
  // class runs by default.
  string default_vseq_type = "proc_base_vseq";

  function new(string name = "proc_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string prog_name;
    super.build_phase(phase);

    cfg = proc_pkg::proc_env_cfg::type_id::create("cfg");

    if (!$value$plusargs("PROG_NAME=%s", prog_name)) prog_name = "smoke";

    cfg.prog_name       = prog_name;
    cfg.instr_mem_file  = get_plusarg_or_default("INSTR_MEM_FILE",
                             {"../golden/out/", prog_name, ".instr.mem"});
    cfg.dmem_init_file  = get_plusarg_or_default("DMEM_INIT_FILE",
                             {"../golden/out/", prog_name, ".dmem_init.mem"});
    // These are retained as optional legacy knobs for compatibility, but the
    // live scoreboard does not consume bus_trace/dmem_final artifacts.
    cfg.bus_trace_file  = get_plusarg_or_default("BUS_TRACE_FILE", "");
    cfg.dmem_final_file = get_plusarg_or_default("DMEM_FINAL_FILE", "");
    cfg.pc_trace_file   = get_plusarg_or_default("PC_TRACE_FILE",
                             {"../golden/out/", prog_name, ".pc_trace.txt"});

    // FIX: $value$plusargs leaves the target untouched when the plusarg is
    // absent, so cfg.timeout_cycles keeps its non-zero class default (200_000)
    // and the original `if (== 0)` guard was dead code. Read into a temp and
    // override only when the plusarg is actually supplied with a non-zero value,
    // so a stray `+TIMEOUT_CYCLES=0` can't silently disable the timeout.
    begin
      int unsigned tmo;
      if ($value$plusargs("TIMEOUT_CYCLES=%d", tmo) && tmo != 0)
        cfg.timeout_cycles = tmo;
    end

    uvm_config_db#(proc_pkg::proc_env_cfg)::set(this, "*", "cfg", cfg);
    uvm_config_db#(proc_pkg::proc_env_cfg)::set(null, "*", "cfg", cfg);

    env = proc_env::type_id::create("env", this);
  endfunction

  // vseqr (created by tb_top before run_test()) needs its irq_sqr handle
  // pointed at the real irq sequencer, which doesn't exist until env's
  // build_phase runs -- must happen here (connect_phase, after build,
  // before run_phase's vseq.start()), not in tb_top.
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (!uvm_config_db#(proc_vseqr)::get(this, "", "vseqr", vseqr))
      `uvm_fatal("PROC_TEST", "virtual sequencer not published by tb_top")
    vseqr.irq_sqr = env.irq_agt.sqr;
  endfunction

  function string get_plusarg_or_default(string key, string dflt);
    string val;
    if ($value$plusargs({key, "=%s"}, val)) return val;
    return dflt;
  endfunction

  task run_phase(uvm_phase phase);
    proc_base_vseq vseq;
    uvm_object obj;
    uvm_factory factory = uvm_factory::get();

    phase.raise_objection(this);

    if (!uvm_config_db#(proc_vseqr)::get(this, "", "vseqr", vseqr))
      `uvm_fatal("PROC_TEST", "virtual sequencer not published by tb_top")

    obj = factory.create_object_by_name(default_vseq_type, get_full_name(), "vseq");
    if (!$cast(vseq, obj))
      `uvm_fatal("PROC_TEST", $sformatf("%s is not a proc_base_vseq", default_vseq_type))

    vseq.start(vseqr);

    phase.drop_objection(this);
  endtask

endclass : proc_base_test