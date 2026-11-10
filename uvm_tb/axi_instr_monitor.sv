// //==============================================================================
// // axi_instr_monitor.sv -- passive monitor for the instruction AXI bus.
// // Assembles one proc_instr_txn per AR request (all INSTR_BURST_LEN beats
// // collected under RLAST), and publishes it for the scoreboard/coverage.
// //==============================================================================
// class axi_instr_monitor extends uvm_monitor;
//   `uvm_component_utils(axi_instr_monitor)

//   virtual axi_instr_if.MON vif;
//   uvm_analysis_port #(proc_pkg::proc_instr_txn) ap;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//     ap = new("ap", this);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     if (!uvm_config_db#(virtual axi_instr_if.MON)::get(this, "", "vif", vif))
//       `uvm_fatal("AXI_INSTR_MON", "virtual interface not set")
//   endfunction

//   task run_phase(uvm_phase phase);
//     fork
//       collect_bursts();
//     join
//   endtask

//   // One thread per in-flight AR handshake is unnecessary here: the
//   // instruction bus never has more than one outstanding burst (the DUT's
//   // prefetch_controller is strictly IDLE->FETCH->[FLUSH]->IDLE, one AR at
//   // a time), so a single sequential collector is sufficient and simpler
//   // than a scoreboard that has to reorder concurrent bursts.
//   task collect_bursts();
//     forever begin
//       proc_pkg::proc_instr_txn txn;
//       @(vif.mon_cb);
//       if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
//         txn = proc_pkg::proc_instr_txn::type_id::create("instr_txn");
//         txn.araddr  = vif.mon_cb.araddr;
//         txn.arlen   = vif.mon_cb.arlen;
//         txn.arsize  = vif.mon_cb.arsize;
//         txn.arburst = vif.mon_cb.arburst;
//         txn.ar_time = $time;
//         collect_r_beats(txn);
//         ap.write(txn);
//       end
//     end
//   endtask

//   task collect_r_beats(proc_pkg::proc_instr_txn txn);
//     bit done;
//     done = 0;
//     while (!done) begin
//       @(vif.mon_cb);
//       if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
//         txn.rdata.push_back(vif.mon_cb.rdata);
//         txn.rresp.push_back(proc_pkg::axi_resp_e'(vif.mon_cb.rresp));
//         if (vif.mon_cb.rlast) begin
//           txn.rlast_time = $time;
//           done = 1;
//         end
//       end
//     end
//   endtask

// endclass : axi_instr_monitor




//==============================================================================
// axi_instr_monitor.sv -- passive monitor for the instruction AXI bus.
// Assembles one proc_instr_txn per AR request (all INSTR_BURST_LEN beats
// collected under RLAST), and publishes it for the scoreboard/coverage.
//==============================================================================
class axi_instr_monitor extends uvm_monitor;
  `uvm_component_utils(axi_instr_monitor)

  virtual axi_instr_if.MON vif;
  uvm_analysis_port #(proc_pkg::proc_instr_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_instr_if.MON)::get(this, "", "vif", vif))
      `uvm_fatal("AXI_INSTR_MON", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    `uvm_info("INSTR_MON", "Instruction monitor run_phase started", UVM_LOW) 
    fork
      collect_bursts();
    join
  endtask

  // One thread per in-flight AR handshake is unnecessary here: the
  // instruction bus never has more than one outstanding burst (the DUT's
  // prefetch_controller is strictly IDLE->FETCH->[FLUSH]->IDLE, one AR at
  // a time), so a single sequential collector is sufficient and simpler
  // than a scoreboard that has to reorder concurrent bursts.
  task collect_bursts();
    forever begin
      proc_pkg::proc_instr_txn txn;
      // FIX: capture the AR attributes when ARVALID is asserted (AXI holds them
      // stable until ARREADY), then wait for the handshake to complete. Gating
      // the capture on (arvalid && arready) risked latching a skewed/reset value
      // under the responder's registered-ready + #1step monitor timing (same
      // root cause fixed on the data bus).
      @(vif.mon_cb);
      if (vif.mon_cb.arvalid) begin
      //`uvm_info("INSTR_MON",
      //      $sformatf("ARVALID: addr=%08h len=%0d ready=%0b",
      //                vif.mon_cb.araddr,
      //                vif.mon_cb.arlen,
      //                vif.mon_cb.arready),
      //      UVM_LOW)
        txn = proc_pkg::proc_instr_txn::type_id::create("instr_txn");
        txn.araddr  = vif.mon_cb.araddr;
        txn.arlen   = vif.mon_cb.arlen;
        txn.arsize  = vif.mon_cb.arsize;
        txn.arburst = vif.mon_cb.arburst;
        txn.ar_time = $time;
        // Wait for the AR handshake to actually complete before collecting beats.
        while (!(vif.mon_cb.arvalid && vif.mon_cb.arready)) @(vif.mon_cb);
        collect_r_beats(txn);
        //`uvm_info("INSTR_MON",
        //  $sformatf("PUBLISHING INSTR TXN: addr=%08h len=%0d beats=%0d",
        //            txn.araddr,
        //            txn.arlen,
        //            txn.rdata.size()),
        //  UVM_LOW)
        ap.write(txn);
      end
    end
  endtask

  task collect_r_beats(proc_pkg::proc_instr_txn txn);
    bit done;
    done = 0;
    while (!done) begin
      @(vif.mon_cb);
      if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
        txn.rdata.push_back(vif.mon_cb.rdata);
        txn.rresp.push_back(proc_pkg::axi_resp_e'(vif.mon_cb.rresp));
        if (vif.mon_cb.rlast) begin
          txn.rlast_time = $time;
          done = 1;
        end
      end
    end
  endtask

endclass : axi_instr_monitor
