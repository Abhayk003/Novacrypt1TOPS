//==============================================================================
// proc_golden_ref.sv
//
// Live reference-model adapter. The Python ISS is a separate process; this
// UVM component is the only place that knows how to talk to it.
//
// Data flow:
//   irq_driver.ap  --> write_irq() --> Python ISS live IRQ state
//   data_monitor.ap --> write_data() --> Python ISS steps to next data event
//                                            |
//                                            v
//                                   expected_ap --> scoreboard
//==============================================================================


class proc_golden_ref extends uvm_component;
  `uvm_component_utils(proc_golden_ref)

  proc_pkg::proc_env_cfg cfg;

  uvm_analysis_imp_data #(proc_pkg::proc_data_txn, proc_golden_ref) data_imp;
  uvm_analysis_imp_irq  #(proc_pkg::proc_irq_txn,  proc_golden_ref) irq_imp;

  uvm_analysis_port #(proc_pkg::proc_golden_txn) expected_ap;
  uvm_analysis_port #(proc_pkg::proc_data_txn) actual_ap;

  bit initialized;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    data_imp    = new("data_imp", this);
    irq_imp     = new("irq_imp", this);
    expected_ap = new("expected_ap", this);
    actual_ap   = new("actual_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(proc_pkg::proc_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("GOLDEN_REF", "env cfg not set")

    if (!golden_init(cfg.instr_mem_file, cfg.dmem_init_file)) begin
      `uvm_fatal("GOLDEN_REF",
        $sformatf("could not initialize live Python golden model; instr=%s dmem=%s",
                  cfg.instr_mem_file, cfg.dmem_init_file))
    end
    initialized = 1;
  endfunction

  // The IRQ driver publishes the transaction at the same point it applies the
  // corresponding level to the DUT. The Python model therefore receives the
  // same logical input event instead of generating an independent IRQ stream.
  function void write_irq(proc_pkg::proc_irq_txn txn);
    bit ok;
    if (!initialized) return;
    if (txn.atomic_levels) begin
      // All three updates are sent back-to-back before the ISS can step,
      // so Python observes one simultaneous pending-state combination.
      ok = golden_irq(int'(proc_pkg::IRQ_TIMER), txn.levels[0]);
      if (!ok) `uvm_error("GOLDEN_REF", "failed to forward timer IRQ level")
      ok = golden_irq(int'(proc_pkg::IRQ_SOFTWARE), txn.levels[1]);
      if (!ok) `uvm_error("GOLDEN_REF", "failed to forward software IRQ level")
      ok = golden_irq(int'(proc_pkg::IRQ_EXTERNAL), txn.levels[2]);
      if (!ok) `uvm_error("GOLDEN_REF", "failed to forward external IRQ level")
    end
    else begin
      ok = golden_irq(int'(txn.line), txn.value);
      if (!ok) `uvm_error("GOLDEN_REF", $sformatf(
        "failed to forward IRQ event line=%0d value=%0b", txn.line, txn.value))
    end
  endfunction

  // The DUT's data-bus monitor is our architectural synchronization boundary.
  // The Python ISS executes one retired instruction at a time until its next
  // memory operation, then returns the expected AXI-visible event.
  function void write_data(proc_pkg::proc_data_txn txn);
    string line;
    proc_pkg::proc_golden_txn exp;
    int n;
    int pc, addr, data, strb, rdata, opcode, funct3, funct7;
    string tag;

    if (!initialized) return;

    line = golden_step();
    if (line.len() == 0) begin
      `uvm_error("GOLDEN_REF", "Python golden model returned an empty response")
      return;
    end
    if (line.substr(0, 3) == "ERR,") begin
      `uvm_error("GOLDEN_REF", $sformatf("Python golden model error: %s", line))
      return;
    end

    exp = proc_pkg::proc_golden_txn::type_id::create("golden_exp");
    n = $sscanf(line, "%s %h %h %h %h %h %h %h", tag, pc, opcode, funct3, funct7, addr, data, strb);
    if (n == 8 && tag == "W") begin
      exp.dir  = proc_pkg::DATA_WRITE;
      exp.pc   = pc;
      exp.opcode  = opcode;
	exp.funct3  = funct3;
	exp.funct7  = funct7;
      exp.addr = addr;
      exp.data = data;
      exp.strb = strb;
      exp.has_rdata = 0;
      expected_ap.write(exp);
      actual_ap.write(txn);
      return;
    end

    n = $sscanf(line, "%s %h %h %h %h %h %h", tag, pc, opcode, funct3, funct7, addr, rdata);
    if (n == 7 && tag == "R") begin
      exp.dir  = proc_pkg::DATA_READ;
      exp.pc   = pc;
      exp.opcode  = opcode;
	exp.funct3  = funct3;
	exp.funct7  = funct7; 
      exp.addr = addr;
      exp.rdata = rdata;
      exp.has_rdata = 1;
      expected_ap.write(exp);
      actual_ap.write(txn);
      return;
    end

    `uvm_error("GOLDEN_REF", $sformatf("unparseable golden event: %s", line))
  endfunction


endclass : proc_golden_ref

