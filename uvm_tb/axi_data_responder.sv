//==============================================================================
// axi_data_responder.sv
//
// Reactive AXI4 slave for the data bus. Same rationale as
// axi_instr_responder: no meaningful "sequence" to generate here, the DUT
// alone decides addresses/data. Runs the read side and the write side as
// two independent fork branches since AW/W and AR/R are logically
// separate channel pairs (the DUT itself only ever has one op in flight
// at a time via dmem_stall/store_stall, but this responder doesn't rely
// on that -- it just serves whichever channel is active).
//==============================================================================
class axi_data_responder extends uvm_component;
  `uvm_component_utils(axi_data_responder)

  virtual axi_data_if.DRV   vif;
  proc_pkg::proc_mem_model  mem;
  proc_pkg::proc_mem_cfg    cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_data_if.DRV)::get(this, "", "vif", vif))
      `uvm_fatal("AXI_DATA_RSP", "virtual interface not set")
    if (!uvm_config_db#(proc_pkg::proc_mem_model)::get(this, "", "mem", mem))
      `uvm_fatal("AXI_DATA_RSP", "shared memory model not set")
    if (!uvm_config_db#(proc_pkg::proc_mem_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("AXI_DATA_RSP", "mem cfg not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.arready <= 1'b0;
    vif.drv_cb.rvalid  <= 1'b0;
    vif.drv_cb.rresp   <= proc_pkg::AXI_OKAY;
    vif.drv_cb.rdata   <= '0;
    vif.drv_cb.awready <= 1'b0;
    vif.drv_cb.wready  <= 1'b0;
    vif.drv_cb.bvalid  <= 1'b0;
    vif.drv_cb.bresp   <= proc_pkg::AXI_OKAY;

    @(negedge vif.reset);
    fork
      forever serve_read();
      forever serve_write();
    join
  endtask

  task serve_read();
    int unsigned lat;
    bit [31:0] addr;
    bit        inject_err;

    do @(vif.drv_cb); while (!vif.drv_cb.arvalid);
    lat = $urandom_range(cfg.min_latency_cycles, cfg.max_latency_cycles);
    repeat (lat) @(vif.drv_cb);

    addr = vif.drv_cb.araddr;
    vif.drv_cb.arready <= 1'b1;
    @(vif.drv_cb);
    vif.drv_cb.arready <= 1'b0;

    inject_err = (cfg.read_err_pct > 0) && ($urandom_range(0, 99) < cfg.read_err_pct);
    if (cfg.backpressure_pct > 0 && $urandom_range(0, 99) < cfg.backpressure_pct)
      @(vif.drv_cb);

    vif.drv_cb.rdata  <= mem.read_word(addr);
    vif.drv_cb.rresp  <= inject_err ? proc_pkg::AXI_SLVERR : proc_pkg::AXI_OKAY;
    vif.drv_cb.rvalid <= 1'b1;
    do @(vif.drv_cb); while (!vif.drv_cb.rready);
    vif.drv_cb.rvalid <= 1'b0;
  endtask

  task serve_write();
    bit aw_seen, w_seen;
    bit [31:0] aw_addr, w_data;
    bit [3:0]  w_strb;
    bit inject_err;
    int unsigned lat;

    aw_seen = 0; w_seen = 0;
    while (!(aw_seen && w_seen)) begin
      @(vif.drv_cb);
      if (!aw_seen && vif.drv_cb.awvalid) begin
        vif.drv_cb.awready <= 1'b1;
        aw_addr = vif.drv_cb.awaddr;
        aw_seen = 1;
      end
      else vif.drv_cb.awready <= 1'b0;

      if (!w_seen && vif.drv_cb.wvalid) begin
        vif.drv_cb.wready <= 1'b1;
        w_data = vif.drv_cb.wdata;
        w_strb = vif.drv_cb.wstrb;
        w_seen = 1;
      end
      else vif.drv_cb.wready <= 1'b0;
    end
    @(vif.drv_cb);
    vif.drv_cb.awready <= 1'b0;
    vif.drv_cb.wready  <= 1'b0;

    mem.write_word(aw_addr, w_data, w_strb);

    lat = $urandom_range(cfg.min_latency_cycles, cfg.max_latency_cycles);
    repeat (lat) @(vif.drv_cb);

    inject_err = (cfg.write_err_pct > 0) && ($urandom_range(0, 99) < cfg.write_err_pct);
    vif.drv_cb.bresp  <= inject_err ? proc_pkg::AXI_SLVERR : proc_pkg::AXI_OKAY;
    vif.drv_cb.bvalid <= 1'b1;
    do @(vif.drv_cb); while (!vif.drv_cb.bready);
    vif.drv_cb.bvalid <= 1'b0;
  endtask

endclass : axi_data_responder
