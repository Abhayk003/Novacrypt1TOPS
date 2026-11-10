//==============================================================================
// proc_pkg.sv
//
// Shared package for the Novacrypt1TOPS blackbox UVM environment.
//
// SCOPE NOTE: this environment is strictly blackbox. The only DUT-visible
// signals are top_module's ports: clk, reset, the AXI4 instruction bus
// (AR+R, fixed 4-beat INCR bursts), the AXI4 data bus (full AR/R/AW/W/B,
// single-beat), and the three interrupt inputs. There is no `bind`, no
// internal probe, no retirement/CSR visibility of any kind. Every class in
// this package is built around that constraint.
//==============================================================================
package proc_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Live Python reference-model DPI bridge.
  import "DPI-C" function int golden_init(input string instr_file, input string dmem_file);
  import "DPI-C" function int golden_irq(input int line, input int value);
  import "DPI-C" function string golden_step();
  import "DPI-C" function int golden_dump_dmem(input string path);
  import "DPI-C" function void golden_stop();

  //---------------------------------------------------------------------
  // Global parameters (from rtl/README.md memory map, top_module-local
  // subset only -- CLINT/PLIC live in soc_top, not in the isolated core).
  //---------------------------------------------------------------------
  parameter int unsigned BOOT_ROM_BASE = 32'h0000_0000;
  parameter int unsigned BOOT_ROM_LIMIT = 32'h0000_3FFF;
  parameter int unsigned IMEM_BASE      = 32'h0001_0000;
  parameter int unsigned IMEM_LIMIT     = 32'h0001_FFFF;
  parameter int unsigned DMEM_BASE      = 32'h0002_0000;
  parameter int unsigned DMEM_LIMIT     = 32'h0002_FFFF;

  parameter int unsigned INSTR_BURST_LEN = 4; // beats per fetch burst (fixed by prefetch_controller)

  typedef enum bit [1:0] { AXI_OKAY = 2'b00, AXI_EXOKAY = 2'b01,
                            AXI_SLVERR = 2'b10, AXI_DECERR = 2'b11 } axi_resp_e;

  //---------------------------------------------------------------------
  // proc_mem_cfg: shared knob object for a reactive AXI slave BFM.
  // Handed to the responder via config_db and mutated directly by
  // injection sequences (it is a plain uvm_object, not randomized inline
  // by the responder -- sequences set fields, the responder reads them
  // each transaction).
  //---------------------------------------------------------------------
  class proc_mem_cfg extends uvm_object;
    `uvm_object_utils(proc_mem_cfg)

    int unsigned min_latency_cycles = 0;
    int unsigned max_latency_cycles = 2;

    // Percent (0-100) chance a given beat/transaction gets SLVERR instead
    // of OKAY. Kept separate for read vs write so directed error tests can
    // target one channel only.
    int unsigned read_err_pct  = 0;
    int unsigned write_err_pct = 0;

    // Percent chance ARREADY/AWREADY/WREADY is deasserted for one extra
    // cycle beyond the minimum -- crude backpressure injection independent
    // of the latency knobs above.
    int unsigned backpressure_pct = 0;

    function new(string name = "proc_mem_cfg");
      super.new(name);
    endfunction
  endclass

  //---------------------------------------------------------------------
  // proc_instr_txn: one instruction-bus burst read, address-request side
  // paired with the beat data actually returned. Built by the instruction
  // monitor from AR+R channel activity.
  //---------------------------------------------------------------------
  class proc_instr_txn extends uvm_sequence_item;
    rand bit [31:0] araddr;
    bit [7:0]       arlen;
    bit [2:0]       arsize;
    bit [1:0]       arburst;

    bit [31:0]      rdata[$];   // one entry per beat, in order
    axi_resp_e      rresp[$];

    time            ar_time;
    time            rlast_time;

    `uvm_object_utils_begin(proc_instr_txn)
      `uvm_field_int(araddr, UVM_ALL_ON)
      `uvm_field_int(arlen, UVM_ALL_ON)
      `uvm_field_int(arsize, UVM_ALL_ON)
      `uvm_field_int(arburst, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "proc_instr_txn");
      super.new(name);
    endfunction

    function string convert2str();
      string s;
      s = $sformatf("INSTR_RD addr=%08h len=%0d beats=%0d", araddr, arlen, rdata.size());
      return s;
    endfunction
  endclass

  //---------------------------------------------------------------------
  // proc_data_txn: one data-bus transaction, either a single-beat read
  // or a single-beat write, exactly as top_module issues them (no
  // bursting on the data side).
  //---------------------------------------------------------------------
  typedef enum bit { DATA_READ = 1'b0, DATA_WRITE = 1'b1 } data_dir_e;

  class proc_data_txn extends uvm_sequence_item;
    rand data_dir_e dir;
    rand bit [31:0] addr;
    bit [31:0]      wdata;   // valid for DATA_WRITE
    bit [3:0]       wstrb;   // valid for DATA_WRITE
    bit [31:0]      rdata;   // valid for DATA_READ
    axi_resp_e      resp;
    time            issue_time;
    time            complete_time;

    `uvm_object_utils_begin(proc_data_txn)
      `uvm_field_enum(data_dir_e, dir, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(wdata, UVM_ALL_ON)
      `uvm_field_int(wstrb, UVM_ALL_ON)
      `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "proc_data_txn");
      super.new(name);
    endfunction

    function string convert2str();
      if (dir == DATA_WRITE)
        return $sformatf("DATA_WR addr=%08h data=%08h strb=%01h", addr, wdata, wstrb);
      else
        return $sformatf("DATA_RD addr=%08h data=%08h", addr, rdata);
    endfunction
  endclass

  //---------------------------------------------------------------------
  // proc_irq_txn: a single stimulus edit to one of the three interrupt
  // lines, driven by the (active) irq agent.
  //---------------------------------------------------------------------
  typedef enum bit [1:0] { IRQ_TIMER = 0, IRQ_SOFTWARE = 1, IRQ_EXTERNAL = 2 } irq_line_e;

  class proc_irq_txn extends uvm_sequence_item;
    rand irq_line_e line;
    rand bit        value;
    rand int unsigned hold_cycles;

    // Atomic update is used for simultaneous-interrupt/priority tests.
    // levels[0]=timer, levels[1]=software, levels[2]=external.
    bit atomic_levels;
    bit [2:0] levels;

    `uvm_object_utils_begin(proc_irq_txn)
      `uvm_field_enum(irq_line_e, line, UVM_ALL_ON)
      `uvm_field_int(value, UVM_ALL_ON)
      `uvm_field_int(hold_cycles, UVM_ALL_ON)
      `uvm_field_int(atomic_levels, UVM_ALL_ON)
      `uvm_field_int(levels, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_hold { hold_cycles inside {[1:50]}; }

    function new(string name = "proc_irq_txn");
      super.new(name);
    endfunction
  endclass

  //---------------------------------------------------------------------
  // proc_golden_txn: one expected architectural data-bus event returned by
  // the live Python reference model.
  //---------------------------------------------------------------------
  class proc_golden_txn extends uvm_sequence_item;
    data_dir_e  dir;
    bit [31:0]  pc;
    bit [6:0]   opcode;
    bit [2:0]   funct3;
    bit [6:0]   funct7;
    bit [31:0]  addr;
    bit [31:0]  data;
    bit [3:0]   strb;
    bit [31:0]  rdata;
    bit         has_rdata;

    `uvm_object_utils_begin(proc_golden_txn)
      `uvm_field_enum(data_dir_e, dir, UVM_ALL_ON)
      `uvm_field_int(pc, UVM_ALL_ON)
      `uvm_field_int(opcode, UVM_ALL_ON)
	`uvm_field_int(funct3, UVM_ALL_ON)
	`uvm_field_int(funct7, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(strb, UVM_ALL_ON)
      `uvm_field_int(rdata, UVM_ALL_ON)
      `uvm_field_int(has_rdata, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "proc_golden_txn");
      super.new(name);
    endfunction
  endclass

  //---------------------------------------------------------------------
  // proc_env_cfg: top-level env configuration. The legacy offline filenames
  // remain only for compatibility with older runs; live checking does not use them.
  // The instruction/data image paths remain the source for UVM memory loading.
  //---------------------------------------------------------------------
  class proc_env_cfg extends uvm_object;
    `uvm_object_utils(proc_env_cfg)

    string instr_mem_file   = "";  // $readmemh image for boot rom + IMEM
    string dmem_init_file   = "";  // $readmemh image for initial DMEM content
    string bus_trace_file   = "";  // legacy offline trace (unused by live scoreboard)
    string dmem_final_file  = "";  // legacy final dump (unused by live scoreboard)
    string pc_trace_file    = "";  // legacy coverage artifact (optional)
    string prog_name         = "";

    bit    check_final_dmem  = 1;
    bit    check_bus_trace   = 1;
    int unsigned timeout_cycles = 200_000;

    function new(string name = "proc_env_cfg");
      super.new(name);
    endfunction
  endclass

  //---------------------------------------------------------------------
  // Custom analysis_imp declarations (must be package/compilation-unit
  // scope, ahead of the classes that use them) so proc_scoreboard can
  // expose two independently-typed analysis exports.
  //---------------------------------------------------------------------
  `uvm_analysis_imp_decl(_data)
  `uvm_analysis_imp_decl(_instr)
  `uvm_analysis_imp_decl(_irq)
  `uvm_analysis_imp_decl(_golden)
  `uvm_analysis_imp_decl(_raw_data)

  //---------------------------------------------------------------------
  // Component/class bodies, split into separate files for readability.
  // All of them live inside this package (none declare their own
  // package block), so include order here IS the elaboration order --
  // memory model and shared objects first, then agents, then env-level
  // scoreboard/coverage/env, matching each file's dependencies.
  //---------------------------------------------------------------------
  `include "proc_mem_model.sv"

  `include "axi_instr_monitor.sv"
  `include "axi_instr_responder.sv"
  `include "axi_instr_agent.sv"

  `include "axi_data_monitor.sv"
  `include "axi_data_responder.sv"
  `include "axi_data_agent.sv"

  `include "irq_driver.sv"
  `include "irq_agent.sv"

  `include "proc_golden_ref.sv"
  `include "proc_scoreboard.sv"
  `include "proc_coverage.sv"
  `include "proc_env.sv"

endpackage : proc_pkg

