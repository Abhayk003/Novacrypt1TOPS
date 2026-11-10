// //==============================================================================
// // axi_instr_responder.sv
// //
// // Reactive AXI4 slave for the instruction bus. Not a classic uvm_driver
// // pulled by a sequencer -- there is no "instruction fetch sequence" to
// // author, the DUT alone decides when/where to fetch. Instead this
// // component watches AR, accepts it (after an optional injected latency),
// // and streams back INSTR_BURST_LEN beats of RDATA sourced from the shared
// // proc_mem_model, honoring cfg knobs (error injection / backpressure) that
// // injection sequences mutate live via the shared proc_mem_cfg handle.
// //==============================================================================
// class axi_instr_responder extends uvm_component;
//   `uvm_component_utils(axi_instr_responder)

//   virtual axi_instr_if.DRV     vif;
//   proc_pkg::proc_mem_model     mem;
//   proc_pkg::proc_mem_cfg       cfg;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     if (!uvm_config_db#(virtual axi_instr_if.DRV)::get(this, "", "vif", vif))
//       `uvm_fatal("AXI_INSTR_RSP", "virtual interface not set")
//     if (!uvm_config_db#(proc_pkg::proc_mem_model)::get(this, "", "mem", mem))
//       `uvm_fatal("AXI_INSTR_RSP", "shared memory model not set")
//     if (!uvm_config_db#(proc_pkg::proc_mem_cfg)::get(this, "", "cfg", cfg))
//       `uvm_fatal("AXI_INSTR_RSP", "mem cfg not set")
//   endfunction

//   task run_phase(uvm_phase phase);
//     vif.drv_cb.arready <= 1'b0;
//     vif.drv_cb.rvalid  <= 1'b0;
//     vif.drv_cb.rlast   <= 1'b0;
//     vif.drv_cb.rdata   <= '0;
//     vif.drv_cb.rresp   <= proc_pkg::AXI_OKAY;

//     @(negedge vif.reset);
//     forever begin
//       accept_ar_and_burst();
//     end
//   endtask

//   task accept_ar_and_burst();
//     int unsigned lat;
//     bit [31:0] base_addr;
//     int unsigned nbeats;
//     int i;

//     // Wait for AR
//     do @(vif.drv_cb); while (!vif.drv_cb.arvalid);

//     // Optional accept latency before asserting ARREADY.
//     lat = $urandom_range(cfg.min_latency_cycles, cfg.max_latency_cycles);
//     repeat (lat) @(vif.drv_cb);

//     base_addr = vif.drv_cb.araddr;
//     nbeats    = vif.drv_cb.arlen + 1;

//     vif.drv_cb.arready <= 1'b1;
//     @(vif.drv_cb);
//     vif.drv_cb.arready <= 1'b0;

//     for (i = 0; i < nbeats; i++) begin
//       bit inject_err;
//       // Optional inter-beat backpressure: hold rvalid low a cycle longer.
//       if (cfg.backpressure_pct > 0 && $urandom_range(0, 99) < cfg.backpressure_pct)
//         @(vif.drv_cb);

//       inject_err = (cfg.read_err_pct > 0) && ($urandom_range(0, 99) < cfg.read_err_pct);

//       vif.drv_cb.rdata  <= mem.read_word(base_addr + i * 4);
//       vif.drv_cb.rresp  <= inject_err ? proc_pkg::AXI_SLVERR : proc_pkg::AXI_OKAY;
//       vif.drv_cb.rvalid <= 1'b1;
//       vif.drv_cb.rlast  <= (i == nbeats - 1);

//       // Hold rvalid until the master asserts rready (top-level RREADY is
//       // effectively tied high by prefetch_controller outside of reset/
//       // FLUSH edge cases, but don't assume it -- honor real handshaking).
//       do @(vif.drv_cb); while (!vif.drv_cb.rready);
//     end

//     vif.drv_cb.rvalid <= 1'b0;
//     vif.drv_cb.rlast  <= 1'b0;
//   endtask

// endclass : axi_instr_responder







// //==============================================================================
// // axi_instr_responder.sv
// //
// // Reactive AXI4 slave for the instruction bus. Not a classic uvm_driver
// // pulled by a sequencer -- there is no "instruction fetch sequence" to
// // author, the DUT alone decides when/where to fetch. Instead this
// // component watches AR, accepts it (after an optional injected latency),
// // and streams back INSTR_BURST_LEN beats of RDATA sourced from the shared
// // proc_mem_model, honoring cfg knobs (error injection / backpressure) that
// // injection sequences mutate live via the shared proc_mem_cfg handle.
// //==============================================================================
// class axi_instr_responder extends uvm_component;
//   `uvm_component_utils(axi_instr_responder)

//   virtual axi_instr_if.DRV     vif;
//   proc_pkg::proc_mem_model     mem;
//   proc_pkg::proc_mem_cfg       cfg;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     if (!uvm_config_db#(virtual axi_instr_if.DRV)::get(this, "", "vif", vif))
//       `uvm_fatal("AXI_INSTR_RSP", "virtual interface not set")
//     if (!uvm_config_db#(proc_pkg::proc_mem_model)::get(this, "", "mem", mem))
//       `uvm_fatal("AXI_INSTR_RSP", "shared memory model not set")
//     if (!uvm_config_db#(proc_pkg::proc_mem_cfg)::get(this, "", "cfg", cfg))
//       `uvm_fatal("AXI_INSTR_RSP", "mem cfg not set")
//   endfunction

//   task run_phase(uvm_phase phase);
//     vif.drv_cb.arready <= 1'b0;
//     vif.drv_cb.rvalid  <= 1'b0;
//     vif.drv_cb.rlast   <= 1'b0;
//     vif.drv_cb.rdata   <= '0;
//     vif.drv_cb.rresp   <= proc_pkg::AXI_OKAY;

//     @(negedge vif.reset);
//     forever begin
//       accept_ar_and_burst();
//     end
//   endtask

//   task accept_ar_and_burst();
//     int unsigned lat;
//     bit [31:0] base_addr;
//     int unsigned nbeats;
//     int i;

//     // Wait for AR
//     do @(vif.drv_cb); while (!vif.drv_cb.arvalid);

//     // Optional accept latency before asserting ARREADY.
//     lat = $urandom_range(cfg.min_latency_cycles, cfg.max_latency_cycles);
//     repeat (lat) @(vif.drv_cb);

//     base_addr = vif.drv_cb.araddr;
//     nbeats    = vif.drv_cb.arlen + 1;

//     vif.drv_cb.arready <= 1'b1;
//     @(vif.drv_cb);
//     vif.drv_cb.arready <= 1'b0;

//     for (i = 0; i < nbeats; i++) begin
//       bit inject_err;
//       // Optional inter-beat backpressure: hold rvalid low a cycle longer.
//       if (cfg.backpressure_pct > 0 && $urandom_range(0, 99) < cfg.backpressure_pct)
//         @(vif.drv_cb);

//       inject_err = (cfg.read_err_pct > 0) && ($urandom_range(0, 99) < cfg.read_err_pct);

//       vif.drv_cb.rdata  <= mem.read_word(base_addr + i * 4);
//       vif.drv_cb.rresp  <= inject_err ? proc_pkg::AXI_SLVERR : proc_pkg::AXI_OKAY;
//       vif.drv_cb.rvalid <= 1'b1;
//       vif.drv_cb.rlast  <= (i == nbeats - 1);

//       // Hold rvalid until the master asserts rready (top-level RREADY is
//       // effectively tied high by prefetch_controller outside of reset/
//       // FLUSH edge cases, but don't assume it -- honor real handshaking).
//       do @(vif.drv_cb); while (!vif.drv_cb.rready);
//     end

//     vif.drv_cb.rvalid <= 1'b0;
//     vif.drv_cb.rlast  <= 1'b0;
//   endtask

// endclass : axi_instr_responder








//==============================================================================
// axi_instr_responder.sv
//
// Reactive AXI4 slave for the instruction bus. Not a classic uvm_driver
// pulled by a sequencer -- there is no "instruction fetch sequence" to
// author, the DUT alone decides when/where to fetch. Instead this
// component watches AR, accepts it (after an optional injected latency),
// and streams back INSTR_BURST_LEN beats of RDATA sourced from the shared
// proc_mem_model, honoring cfg knobs (error injection / backpressure) that
// injection sequences mutate live via the shared proc_mem_cfg handle.
//==============================================================================
class axi_instr_responder extends uvm_component;
  `uvm_component_utils(axi_instr_responder)

  virtual axi_instr_if.DRV     vif;
  proc_pkg::proc_mem_model     mem;
  proc_pkg::proc_mem_cfg       cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_instr_if.DRV)::get(this, "", "vif", vif))
      `uvm_fatal("AXI_INSTR_RSP", "virtual interface not set")
    if (!uvm_config_db#(proc_pkg::proc_mem_model)::get(this, "", "mem", mem))
      `uvm_fatal("AXI_INSTR_RSP", "shared memory model not set")
    if (!uvm_config_db#(proc_pkg::proc_mem_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_INSTR_RSP", "mem cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.arready <= 1'b0;
    vif.drv_cb.rvalid  <= 1'b0;
    vif.drv_cb.rlast   <= 1'b0;
    vif.drv_cb.rdata   <= '0;
    vif.drv_cb.rresp   <= proc_pkg::AXI_OKAY;

    @(negedge vif.reset);
    forever begin
      accept_ar_and_burst();
    end
  endtask

  task accept_ar_and_burst();
    int unsigned lat;
    bit [31:0] base_addr;
    int unsigned nbeats;
    int i;

    // Wait for AR
    do @(vif.drv_cb); while (!vif.drv_cb.arvalid);

    // Optional accept latency before asserting ARREADY.
    lat = $urandom_range(cfg.min_latency_cycles, cfg.max_latency_cycles);
    repeat (lat) @(vif.drv_cb);

    base_addr = vif.drv_cb.araddr;
    nbeats    = vif.drv_cb.arlen + 1;

    vif.drv_cb.arready <= 1'b1;
    @(vif.drv_cb);
    vif.drv_cb.arready <= 1'b0;

    for (i = 0; i < nbeats; i++) begin
      bit inject_err;
      // Optional inter-beat backpressure: drop rvalid for a cycle BEFORE this
      // beat (a real gap in the stream), then present the beat.
      if (cfg.backpressure_pct > 0 && $urandom_range(0, 99) < cfg.backpressure_pct) begin
        vif.drv_cb.rvalid <= 1'b0;
        vif.drv_cb.rlast  <= 1'b0;
        @(vif.drv_cb);
      end

      inject_err = (cfg.read_err_pct > 0) && ($urandom_range(0, 99) < cfg.read_err_pct);

      // Present this beat and assert rvalid.
      vif.drv_cb.rdata  <= mem.read_word(base_addr + i * 4);
      vif.drv_cb.rresp  <= inject_err ? proc_pkg::AXI_SLVERR : proc_pkg::AXI_OKAY;
      vif.drv_cb.rvalid <= 1'b1;
      vif.drv_cb.rlast  <= (i == nbeats - 1);

      // FIX: transfer EXACTLY ONE beat per rvalid&&rready handshake. Advance to
      // the edge where this beat is live, then, if rready is not yet high, keep
      // rvalid asserted and wait for it. The previous "do @(); while(!rready)"
      // combined with rvalid being driven via a nonblocking clocking-block
      // assignment left rvalid asserted with the SAME rdata for two cycles per
      // beat; since prefetch_controller holds RREADY high, the DUT accepted
      // (pushed) each instruction word TWICE, re-executing adds/addis and
      // corrupting results on longer programs (e.g. axi_burst_boundary computed
      // 0x00039add instead of 0x0000ffff). Deasserting rvalid immediately after
      // the accepted transfer guarantees one push per beat.
      @(vif.drv_cb);
      while (!vif.drv_cb.rready) @(vif.drv_cb);
      // Beat accepted this cycle; drop rvalid so the same word is not re-sampled
      // on the following cycle before the next beat's rdata is presented.
      vif.drv_cb.rvalid <= 1'b0;
    end

    vif.drv_cb.rvalid <= 1'b0;
    vif.drv_cb.rlast  <= 1'b0;
  endtask

endclass : axi_instr_responder