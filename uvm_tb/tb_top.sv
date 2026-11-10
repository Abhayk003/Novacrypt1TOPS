//==============================================================================
// tb_top.sv -- top-level testbench module.
//
// Instantiates: clock/reset generation, the four verification interfaces
// (axi_instr_if, axi_data_if, irq_if, clk_if), the DUT (top_module) wired
// port-for-port to those interfaces (no `bind`, ports only -- this
// environment is strictly blackbox per TEAM_BRIEF.md), and the UVM
// virtual sequencer whose handle every test fetches back out of
// config_db under key "vseqr".
//==============================================================================
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import proc_pkg::*;
  import proc_test_pkg::*;

  //---------------------------------------------------------------
  // Clock / reset generation
  //---------------------------------------------------------------
  logic clk;
  logic reset;

  initial clk = 1'b0;
  always #5 clk = ~clk;   // 100 MHz

  initial begin
    reset = 1'b1;
    repeat (10) @(posedge clk);
    reset = 1'b0;
  end

  //---------------------------------------------------------------
  // Verification interfaces
  //---------------------------------------------------------------
  axi_instr_if instr_if (.clk(clk), .reset(reset));
  axi_data_if  data_if  (.clk(clk), .reset(reset));
  irq_if       irq_vif  (.clk(clk), .reset(reset));
  clk_if       clk_vif  (.clk(clk));

  //---------------------------------------------------------------
  // DUT -- top_module, port-for-port, no internal binding of any kind.
  //---------------------------------------------------------------
  top_module dut (
    .clk   (clk),
    .reset (reset),

    // AXI4 instruction bus (AR + R only)
    .ARADDR_I  (instr_if.araddr),
    .ARLEN_I   (instr_if.arlen),
    .ARSIZE_I  (instr_if.arsize),
    .ARBURST_I (instr_if.arburst),
    .ARVALID_I (instr_if.arvalid),
    .ARREADY_I (instr_if.arready),
    .RDATA_I   (instr_if.rdata),
    .RVALID_I  (instr_if.rvalid),
    .RLAST_I   (instr_if.rlast),
    .RRESP_I   (instr_if.rresp),
    .RREADY_I  (instr_if.rready),

    // AXI4 data bus (full AR/R/AW/W/B)
    .ARADDR_D  (data_if.araddr),
    .ARVALID_D (data_if.arvalid),
    .ARREADY_D (data_if.arready),
    .RDATA_D   (data_if.rdata),
    .RVALID_D  (data_if.rvalid),
    .RRESP_D   (data_if.rresp),
    .RREADY_D  (data_if.rready),
    .AWADDR_D  (data_if.awaddr),
    .AWVALID_D (data_if.awvalid),
    .AWREADY_D (data_if.awready),
    .WDATA_D   (data_if.wdata),
    .WSTRB_D   (data_if.wstrb),
    .WVALID_D  (data_if.wvalid),
    .WREADY_D  (data_if.wready),
    .BRESP_D   (data_if.bresp),
    .BVALID_D  (data_if.bvalid),
    .BREADY_D  (data_if.bready),

    // Interrupts
    .irq_timer_i    (irq_vif.irq_timer),
    .irq_software_i (irq_vif.irq_software),
    .irq_external_i (irq_vif.irq_external)
  );

  //---------------------------------------------------------------
  // UVM wiring: publish virtual interfaces + virtual sequencer before
  // run_test() so build_phase on every component/test can fetch them.
  //---------------------------------------------------------------
  proc_vseqr vseqr;

  initial begin
    uvm_config_db#(virtual axi_instr_if.DRV)::set(null, "*", "vif", instr_if.DRV);
    uvm_config_db#(virtual axi_instr_if.MON)::set(null, "*", "vif", instr_if.MON);
    uvm_config_db#(virtual axi_data_if.DRV)::set(null, "*", "vif", data_if.DRV);
    uvm_config_db#(virtual axi_data_if.MON)::set(null, "*", "vif", data_if.MON);
    uvm_config_db#(virtual irq_if.DRV)::set(null, "*", "vif", irq_vif.DRV);
    uvm_config_db#(virtual clk_if)::set(null, "*", "vclk", clk_vif);

    vseqr = proc_vseqr::type_id::create("vseqr", null);
    // vseqr.irq_sqr can't be wired here -- irq_agt.sqr doesn't exist until
    // env's build_phase runs, which happens later, inside run_test() below.
    // proc_base_test.connect_phase() does that assignment once env exists.
    uvm_config_db#(proc_vseqr)::set(null, "*", "vseqr", vseqr);

    run_test();
  end

  //---------------------------------------------------------------
  // Simple wall-clock watchdog independent of the virtual sequence's own
  // timeout_cycles -- catches a hang where UVM itself never raises/drops
  // an objection (e.g. a build_phase config_db miss that `uvm_fatal`
  // didn't actually kill the process for, under some simulators' -all
  // error settings). VCS_TIMEOUT_CYCLES plusarg overrides the default.
  //---------------------------------------------------------------
  initial begin
    int unsigned watchdog_cycles;
    if (!$value$plusargs("VCS_TIMEOUT_CYCLES=%d", watchdog_cycles))
      watchdog_cycles = 500_000;
    repeat (watchdog_cycles) @(posedge clk);
    `uvm_fatal("TB_TOP", $sformatf(
      "wall-clock watchdog (%0d cycles) expired -- simulation hung", watchdog_cycles))
  end

  //---------------------------------------------------------------
  // Optional waveform dump for local debugging -- NOT used by the
  // regular regression/coverage flow (opt-in only, off by default).
  //
  //   simv +UVM_TESTNAME=... +PROG_NAME=... +DUMP_VCD=1 [+DUMP_CYCLES=<n>]
  //
  // Dumps only tb_top.dut (the DUT's internal hierarchy) -- deliberately
  // excludes the UVM class-based TB code, both to keep the file small and
  // because this is purely a local signal-level debug aid, independent of
  // the environment's blackbox monitoring architecture.
  //---------------------------------------------------------------
  initial begin
    int unsigned dump_en;
    int unsigned dump_cycles;
    if ($value$plusargs("DUMP_VCD=%d", dump_en) && dump_en) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top.dut);
      if (!$value$plusargs("DUMP_CYCLES=%d", dump_cycles))
        dump_cycles = 2000;
      repeat (dump_cycles) @(posedge clk);
      $dumpoff;
    end
  end

  //---------------------------------------------------------------
  // Optional cycle-by-cycle signal trace for local debugging, printed
  // directly to the log -- no waveform viewer / X11 display required.
  //
  //   simv +UVM_TESTNAME=... +PROG_NAME=... +DEBUG_TRACE=1 [+DEBUG_CYCLES=<n>]
  //---------------------------------------------------------------
  initial begin
    int unsigned trace_en;
    int unsigned trace_cycles;
    int unsigned i;
    if ($value$plusargs("DEBUG_TRACE=%d", trace_en) && trace_en) begin
      if (!$value$plusargs("DEBUG_CYCLES=%d", trace_cycles))
        trace_cycles = 60;
      @(negedge reset);
      for (i = 0; i < trace_cycles; i++) begin
        @(posedge clk);
        #1; // let combinational logic settle post-edge before sampling
        $display("[TRACE] cyc=%0d rs1=%0d rd_ex=%0d ex_regwrite=%b forwardA=%b op1=%h ex_forward=%h mem_addr=%h mem_write=%b reg_waddr=%0d reg_wdata=%h reg_we=%b awvalid=%b awready=%b wvalid=%b wready=%b bvalid=%b bready=%b",
          i,
          dut.execute_stage.rs1,
          dut.ex_memwb_r.rd_ex,
          dut.ex_memwb_r.reg_write,
          dut.forwardA,
          dut.execute_stage.op1,
          dut.execute_stage.ex_forward,
          dut.mem_address,
          dut.mem_write,
          dut.reg_waddr,
          dut.reg_wdata,
          dut.reg_we,
          data_if.awvalid, data_if.awready,
          data_if.wvalid,  data_if.wready,
          data_if.bvalid,  data_if.bready);
      end
    end
  end

endmodule : tb_top