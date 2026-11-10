// //==============================================================================
// // axi_data_monitor.sv -- passive monitor for the data AXI bus.
// // The DUT (top_module) only ever has one outstanding read OR one
// // outstanding write in flight at a time (dmem_stall / store_stall gate
// // the pipeline until the prior access completes), but read and write can
// // overlap each other (independent channels), so this monitor runs one
// // collector per direction concurrently.
// //==============================================================================
// class axi_data_monitor extends uvm_monitor;
//   `uvm_component_utils(axi_data_monitor)

//   virtual axi_data_if.MON vif;
//   uvm_analysis_port #(proc_pkg::proc_data_txn) ap;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//     ap = new("ap", this);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     if (!uvm_config_db#(virtual axi_data_if.MON)::get(this, "", "vif", vif))
//       `uvm_fatal("AXI_DATA_MON", "virtual interface not set")
//   endfunction

//   task run_phase(uvm_phase phase);
//     fork
//       collect_reads();
//       collect_writes();
//     join
//   endtask

//   task collect_reads();
//     forever begin
//       proc_pkg::proc_data_txn txn;
//       @(vif.mon_cb);
//       if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
//         txn = proc_pkg::proc_data_txn::type_id::create("data_rd_txn");
//         txn.dir        = proc_pkg::DATA_READ;
//         txn.addr       = vif.mon_cb.araddr;
//         txn.issue_time = $time;
//         do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
//         txn.rdata         = vif.mon_cb.rdata;
//         txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.rresp);
//         txn.complete_time = $time;
//         ap.write(txn);
//       end
//     end
//   endtask

//   task collect_writes();
//     bit [31:0] aw_addr;
//     bit        aw_seen, w_seen;
//     bit [31:0] w_data;
//     bit [3:0]  w_strb;

//     forever begin
//       proc_pkg::proc_data_txn txn;
//       aw_seen = 0; w_seen = 0;

//       // AW and W can complete in either order (independent channels);
//       // wait until both have handshaken at least once.
//       while (!(aw_seen && w_seen)) begin
//         @(vif.mon_cb);
//         if (!aw_seen && vif.mon_cb.awvalid && vif.mon_cb.awready) begin
//           aw_addr = vif.mon_cb.awaddr;
//           aw_seen = 1;
//         end
//         if (!w_seen && vif.mon_cb.wvalid && vif.mon_cb.wready) begin
//           w_data = vif.mon_cb.wdata;
//           w_strb = vif.mon_cb.wstrb;
//           w_seen = 1;
//         end
//       end

//       txn = proc_pkg::proc_data_txn::type_id::create("data_wr_txn");
//       txn.dir        = proc_pkg::DATA_WRITE;
//       txn.addr       = aw_addr;
//       txn.wdata      = w_data;
//       txn.wstrb      = w_strb;
//       txn.issue_time = $time;

//       // Response phase.
//       do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
//       txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.bresp);
//       txn.complete_time = $time;
//       ap.write(txn);
//     end
//   endtask

// endclass : axi_data_monitor






// //==============================================================================
// // axi_data_monitor.sv -- passive monitor for the data AXI bus.
// // The DUT (top_module) only ever has one outstanding read OR one
// // outstanding write in flight at a time (dmem_stall / store_stall gate
// // the pipeline until the prior access completes), but read and write can
// // overlap each other (independent channels), so this monitor runs one
// // collector per direction concurrently.
// //==============================================================================
// class axi_data_monitor extends uvm_monitor;
//   `uvm_component_utils(axi_data_monitor)

//   virtual axi_data_if.MON vif;
//   uvm_analysis_port #(proc_pkg::proc_data_txn) ap;

//   function new(string name, uvm_component parent);
//     super.new(name, parent);
//     ap = new("ap", this);
//   endfunction

//   function void build_phase(uvm_phase phase);
//     super.build_phase(phase);
//     if (!uvm_config_db#(virtual axi_data_if.MON)::get(this, "", "vif", vif))
//       `uvm_fatal("AXI_DATA_MON", "virtual interface not set")
//   endfunction

//   task run_phase(uvm_phase phase);
//     fork
//       collect_reads();
//       collect_writes();
//     join
//   endtask

//   task collect_reads();
//     forever begin
//       proc_pkg::proc_data_txn txn;
//       @(vif.mon_cb);
//       if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
//         txn = proc_pkg::proc_data_txn::type_id::create("data_rd_txn");
//         txn.dir        = proc_pkg::DATA_READ;
//         txn.addr       = vif.mon_cb.araddr;
//         txn.issue_time = $time;
//         do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
//         txn.rdata         = vif.mon_cb.rdata;
//         txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.rresp);
//         txn.complete_time = $time;
//         ap.write(txn);
//       end
//     end
//   endtask

//   task collect_writes();
//     bit [31:0] aw_addr;
//     bit        aw_seen, w_seen;
//     bit [31:0] w_data;
//     bit [3:0]  w_strb;

//     forever begin
//       proc_pkg::proc_data_txn txn;
//       aw_seen = 0; w_seen = 0;

//       // AW and W can complete in either order (independent channels);
//       // wait until both have handshaken at least once.
//       while (!(aw_seen && w_seen)) begin
//         @(vif.mon_cb);
//         if (!aw_seen && vif.mon_cb.awvalid && vif.mon_cb.awready) begin
//           aw_addr = vif.mon_cb.awaddr;
//           aw_seen = 1;
//         end
//         if (!w_seen && vif.mon_cb.wvalid && vif.mon_cb.wready) begin
//           w_data = vif.mon_cb.wdata;
//           w_strb = vif.mon_cb.wstrb;
//           w_seen = 1;
//         end
//       end

//       txn = proc_pkg::proc_data_txn::type_id::create("data_wr_txn");
//       txn.dir        = proc_pkg::DATA_WRITE;
//       txn.addr       = aw_addr;
//       txn.wdata      = w_data;
//       txn.wstrb      = w_strb;
//       txn.issue_time = $time;

//       // Response phase.
//       do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
//       txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.bresp);
//       txn.complete_time = $time;
//       ap.write(txn);
//     end
//   endtask

// endclass : axi_data_monitor






//==============================================================================
// axi_data_monitor.sv -- passive monitor for the data AXI bus.
// The DUT (top_module) only ever has one outstanding read OR one
// outstanding write in flight at a time (dmem_stall / store_stall gate
// the pipeline until the prior access completes), but read and write can
// overlap each other (independent channels), so this monitor runs one
// collector per direction concurrently.
//==============================================================================
class axi_data_monitor extends uvm_monitor;
  `uvm_component_utils(axi_data_monitor)

  virtual axi_data_if.MON vif;
  uvm_analysis_port #(proc_pkg::proc_data_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_data_if.MON)::get(this, "", "vif", vif))
      `uvm_fatal("AXI_DATA_MON", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      collect_reads();
      collect_writes();
    join
  endtask

  task collect_reads();
    forever begin
      proc_pkg::proc_data_txn txn;
      // FIX: capture ARADDR when ARVALID is first asserted (AXI holds it stable
      // from ARVALID until ARREADY), not gated on (arvalid && arready). Same
      // rationale as the write path -- gating the address capture on READY made
      // the sampled value sensitive to the exact cycle READY appears under the
      // responder's registered-ready + monitor #1step timing, which could latch
      // the reset-value address. Wait for ARVALID, latch the address, then
      // require the arready handshake to consider the request accepted.
      @(vif.mon_cb);
      if (vif.mon_cb.arvalid) begin
        txn = proc_pkg::proc_data_txn::type_id::create("data_rd_txn");
        txn.dir        = proc_pkg::DATA_READ;
        txn.addr       = vif.mon_cb.araddr;   // stable while ARVALID high
        txn.issue_time = $time;
        // Wait for the AR handshake to actually complete.
        while (!(vif.mon_cb.arvalid && vif.mon_cb.arready)) @(vif.mon_cb);
        // Then wait for the read-data beat.
        do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
        txn.rdata         = vif.mon_cb.rdata;
        txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.rresp);
        txn.complete_time = $time;
        ap.write(txn);
      end
    end
  endtask

  task collect_writes();
    bit [31:0] aw_addr;
    bit        aw_seen, w_seen;
    bit [31:0] w_data;
    bit [3:0]  w_strb;

    forever begin
      proc_pkg::proc_data_txn txn;
      aw_seen = 0; w_seen = 0;

      // AW and W can complete in either order (independent channels);
      // wait until both have handshaken at least once.
      //
      // FIX: capture AWADDR/WDATA on the cycle the *VALID* is asserted, not on
      // (valid && ready). Per AXI, a master must hold AWADDR stable from the
      // cycle AWVALID is asserted until AWREADY completes the handshake, so the
      // address/data are already valid at VALID time. Gating the *capture* on
      // (valid && ready) made the sampled value depend on the exact cycle READY
      // appears -- which, with the responder driving AWREADY registered (one
      // cycle late) and the monitor clocking block's #1step input skew, could
      // sample AWADDR before the DUT had driven it (yielding the reset value 0)
      // even though the DUT holds the correct address stable. We still require
      // the ready handshake to mark the transfer *complete* (aw_done/w_done),
      // but we latch the payload as soon as VALID is seen.
      begin
        bit aw_done, w_done;
        aw_done = 0; w_done = 0;
        while (!(aw_done && w_done)) begin
          @(vif.mon_cb);
          // Latch payload as soon as VALID is observed (address/data are stable
          // from this cycle per AXI), independent of when READY arrives.
          if (!aw_seen && vif.mon_cb.awvalid) begin
            aw_addr = vif.mon_cb.awaddr;
            aw_seen = 1;
          end
          if (!w_seen && vif.mon_cb.wvalid) begin
            w_data = vif.mon_cb.wdata;
            w_strb = vif.mon_cb.wstrb;
            w_seen = 1;
          end
          // Mark the channel done only on the actual valid&&ready transfer.
          if (!aw_done && vif.mon_cb.awvalid && vif.mon_cb.awready) aw_done = 1;
          if (!w_done  && vif.mon_cb.wvalid  && vif.mon_cb.wready)  w_done  = 1;
        end
      end

      txn = proc_pkg::proc_data_txn::type_id::create("data_wr_txn");
      txn.dir        = proc_pkg::DATA_WRITE;
      txn.addr       = aw_addr;
      txn.wdata      = w_data;
      txn.wstrb      = w_strb;
      txn.issue_time = $time;
      // TEMP DEBUG: what the MONITOR captured via mon_cb (compare to [PROBE-AW])
      `uvm_info("MON_CAP", $sformatf("captured WRITE addr=%08h data=%08h strb=%01h @%0t",
                aw_addr, w_data, w_strb, $time), UVM_LOW)

      // Response phase.
      do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
      txn.resp          = proc_pkg::axi_resp_e'(vif.mon_cb.bresp);
      txn.complete_time = $time;
      ap.write(txn);
    end
  endtask

endclass : axi_data_monitor