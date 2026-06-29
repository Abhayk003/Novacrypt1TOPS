`timescale 1ns / 1ps
// ============================================================================
// soc_top.sv  -  RV32IM SoC top level (AXI4 fabric)
//
//   CPU I-master (burst AXI4, read-only) --+
//                                          +--> axi_xbar (full AXI4)
//   CPU D-master (single-beat AXI4) -------+        |
//                                                   +--> Boot ROM  (axi_to_mem + sram)
//                                                   +--> I-SRAM    (axi_to_mem + sram)
//                                                   +--> D-SRAM    (axi_to_mem + sram)
//                                                   +--> APB leg   (axi_err_slv placeholder)
//                                                        ^^^ replace with your custom
//                                                            axi2apb bridge + peripherals
//
// Dependencies: pulp-platform/axi, pulp-platform/common_cells
// ============================================================================

`include "axi/typedef.svh"
`include "apb/typedef.svh"
`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module soc_top (
    input  logic clk_i,
    input  logic rst_ni,     // ACTIVE-LOW (pulp convention). Invert your board reset.

    // UART pins
    input  logic uart_rx_i,
    output logic uart_tx_o,
    output logic uart_irq_o,

    // Timer interrupts (2 timers x {overflow, compare})
    output logic [3:0] timer_irq_o,

    // I2C pins (tristate-style: *_o drives, *_oen output-enable (active low), *_i samples)
    input  logic i2c_scl_i,
    output logic i2c_scl_o,
    output logic i2c_scl_oen_o,
    input  logic i2c_sda_i,
    output logic i2c_sda_o,
    output logic i2c_sda_oen_o,
    output logic i2c_irq_o,

    // SPI master pins (single-lane use: clk, cs, mosi=sdo0, miso=sdi0)
    output logic       spi_clk_o,
    output logic [3:0] spi_csn_o,
    output logic       spi_mosi_o,
    input  logic       spi_miso_i,
    output logic [1:0] spi_irq_o,

    // GPIO: 32 pins, each independently input or output
    input  logic [31:0] gpio_in_i,
    output logic [31:0] gpio_out_o,
    output logic [31:0] gpio_dir_o,    // 0 = input, 1 = output (drive enable)
    output logic        gpio_irq_o
);

  // --------------------------------------------------------------------------
  // Fabric parameters
  // --------------------------------------------------------------------------
  localparam int unsigned AxiAddrWidth  = 32;
  localparam int unsigned AxiDataWidth  = 32;
  localparam int unsigned AxiUserWidth  = 1;   // unused, min width
  localparam int unsigned NoMasters     = 2;   // CPU-I, CPU-D
  localparam int unsigned NoSlaves      = 4;   // ROM, ISRAM, DSRAM, APB
  localparam int unsigned AxiIdWidthSlv = 1;                          // CPU has no IDs
  localparam int unsigned AxiIdWidthMst = AxiIdWidthSlv + $clog2(NoMasters);

  // Slave port indices on the xbar
  localparam int unsigned SlvRom   = 0;
  localparam int unsigned SlvIsram = 1;
  localparam int unsigned SlvDsram = 2;
  localparam int unsigned SlvApb   = 3;

  // --------------------------------------------------------------------------
  // Memory map  (keep in sync with your linker script!)
  // --------------------------------------------------------------------------
  localparam logic [31:0] RomBase   = 32'h0000_0000;  localparam logic [31:0] RomSize   = 32'h0000_4000; // 16 KB
  localparam logic [31:0] IsramBase = 32'h0001_0000;  localparam logic [31:0] IsramSize = 32'h0001_0000; // 64 KB
  localparam logic [31:0] DsramBase = 32'h0002_0000;  localparam logic [31:0] DsramSize = 32'h0001_0000; // 64 KB
  localparam logic [31:0] ApbBase   = 32'h1000_0000;  localparam logic [31:0] ApbSize   = 32'h00C0_0000; // 12 MB (covers CLINT + 4MB PLIC)

  typedef axi_pkg::xbar_rule_32_t rule_t;
  localparam rule_t [NoSlaves-1:0] AddrMap = '{
    '{idx: 32'(SlvApb),   start_addr: ApbBase,   end_addr: ApbBase   + ApbSize  },
    '{idx: 32'(SlvDsram), start_addr: DsramBase, end_addr: DsramBase + DsramSize},
    '{idx: 32'(SlvIsram), start_addr: IsramBase, end_addr: IsramBase + IsramSize},
    '{idx: 32'(SlvRom),   start_addr: RomBase,   end_addr: RomBase   + RomSize  }
  };

  // --------------------------------------------------------------------------
  // AXI typedefs (struct flavor of the pulp library)
  // --------------------------------------------------------------------------
  typedef logic [AxiAddrWidth-1:0]   addr_t;
  typedef logic [AxiDataWidth-1:0]   data_t;
  typedef logic [AxiDataWidth/8-1:0] strb_t;
  typedef logic [AxiUserWidth-1:0]   user_t;
  typedef logic [AxiIdWidthSlv-1:0]  id_slv_t;
  typedef logic [AxiIdWidthMst-1:0]  id_mst_t;

  `AXI_TYPEDEF_ALL(slv, addr_t, id_slv_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(mst, addr_t, id_mst_t, data_t, strb_t, user_t)

  // APB struct types for peripherals that take struct ports (e.g. gpio_apb_wrap)
  `APB_TYPEDEF_REQ_T(apb_req_t, addr_t, data_t, strb_t)
  `APB_TYPEDEF_RESP_T(apb_resp_t, data_t)

  // reg_bus struct types for peripherals that take a register interface (plic_top)
  `REG_BUS_TYPEDEF_ALL(reg, addr_t, data_t, strb_t)

  slv_req_t  [NoMasters-1:0] cpu_req;
  slv_resp_t [NoMasters-1:0] cpu_resp;
  mst_req_t  [NoSlaves-1:0]  periph_req;
  mst_resp_t [NoSlaves-1:0]  periph_resp;

  // --------------------------------------------------------------------------
  // CPU
  // --------------------------------------------------------------------------
  // I-bus master signals
  logic [31:0] ARADDR_I;  logic [7:0] ARLEN_I;  logic [2:0] ARSIZE_I;
  logic [1:0]  ARBURST_I; logic ARVALID_I, ARREADY_I;
  logic [31:0] RDATA_I;   logic RVALID_I, RLAST_I, RREADY_I;
  logic [1:0]  RRESP_I;
  // D-bus master signals
  logic [31:0] ARADDR_D;  logic ARVALID_D, ARREADY_D;
  logic [31:0] RDATA_D;   logic RVALID_D, RREADY_D;
  logic [1:0]  RRESP_D;
  logic [31:0] AWADDR_D;  logic AWVALID_D, AWREADY_D;
  logic [31:0] WDATA_D;   logic [3:0] WSTRB_D; logic WVALID_D, WREADY_D;
  logic [1:0]  BRESP_D;   logic BVALID_D, BREADY_D;

  // CPU interrupt lines
  logic cpu_irq_timer, cpu_irq_software, cpu_irq_external;
  logic clint_mtip, clint_msip;
  logic plic_irq;
  assign cpu_irq_timer    = clint_mtip;   // from CLINT
  assign cpu_irq_software = clint_msip;   // from CLINT
  assign cpu_irq_external = plic_irq;     // from PLIC

  top_module cpu (
    .clk      (clk_i),
    .reset    (~rst_ni),   // CPU uses active-high reset

    .ARADDR_I, .ARLEN_I, .ARSIZE_I, .ARBURST_I, .ARVALID_I, .ARREADY_I,
    .RDATA_I,  .RVALID_I, .RLAST_I,  .RRESP_I,   .RREADY_I,

    .ARADDR_D, .ARVALID_D, .ARREADY_D,
    .RDATA_D,  .RVALID_D,  .RRESP_D,  .RREADY_D,
    .AWADDR_D, .AWVALID_D, .AWREADY_D,
    .WDATA_D,  .WSTRB_D,   .WVALID_D, .WREADY_D,
    .BRESP_D,  .BVALID_D,  .BREADY_D,
    .irq_timer_i    (cpu_irq_timer),
    .irq_software_i (cpu_irq_software),
    .irq_external_i (cpu_irq_external)
  );

  // ---- Map CPU I-port onto xbar slave port 0 (read-only master) ----
  always_comb begin
    cpu_req[0] = '0;
    // AR channel
    cpu_req[0].ar.id     = '0;
    cpu_req[0].ar.addr   = ARADDR_I;
    cpu_req[0].ar.len    = ARLEN_I;
    cpu_req[0].ar.size   = ARSIZE_I;
    cpu_req[0].ar.burst  = ARBURST_I;
    cpu_req[0].ar_valid  = ARVALID_I;
    cpu_req[0].r_ready   = RREADY_I;
    // AW/W/B tied off: instruction port never writes
  end
  assign ARREADY_I = cpu_resp[0].ar_ready;
  assign RDATA_I   = cpu_resp[0].r.data;
  assign RRESP_I   = cpu_resp[0].r.resp;
  assign RLAST_I   = cpu_resp[0].r.last;
  assign RVALID_I  = cpu_resp[0].r_valid;

  // ---- Map CPU D-port onto xbar slave port 1 (single-beat master) ----
  always_comb begin
    cpu_req[1] = '0;
    // AR channel (loads)
    cpu_req[1].ar.id     = '0;
    cpu_req[1].ar.addr   = ARADDR_D;
    cpu_req[1].ar.len    = 8'd0;                 // single beat
    cpu_req[1].ar.size   = 3'd2;                 // 4 bytes
    cpu_req[1].ar.burst  = axi_pkg::BURST_INCR;
    cpu_req[1].ar_valid  = ARVALID_D;
    cpu_req[1].r_ready   = RREADY_D;
    // AW channel (stores)
    cpu_req[1].aw.id     = '0;
    cpu_req[1].aw.addr   = AWADDR_D;
    cpu_req[1].aw.len    = 8'd0;
    cpu_req[1].aw.size   = 3'd2;
    cpu_req[1].aw.burst  = axi_pkg::BURST_INCR;
    cpu_req[1].aw_valid  = AWVALID_D;
    // W channel
    cpu_req[1].w.data    = WDATA_D;
    cpu_req[1].w.strb    = WSTRB_D;
    cpu_req[1].w.last    = 1'b1;                 // single beat => always last
    cpu_req[1].w_valid   = WVALID_D;
    cpu_req[1].b_ready   = BREADY_D;
  end
  assign ARREADY_D = cpu_resp[1].ar_ready;
  assign RDATA_D   = cpu_resp[1].r.data;
  assign RRESP_D   = cpu_resp[1].r.resp;
  assign RVALID_D  = cpu_resp[1].r_valid;
  assign AWREADY_D = cpu_resp[1].aw_ready;
  assign WREADY_D  = cpu_resp[1].w_ready;
  assign BRESP_D   = cpu_resp[1].b.resp;
  assign BVALID_D  = cpu_resp[1].b_valid;

  // --------------------------------------------------------------------------
  // AXI4 crossbar
  // --------------------------------------------------------------------------
  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         32'(NoMasters),
    NoMstPorts:         32'(NoSlaves),
    MaxMstTrans:        4,
    MaxSlvTrans:        4,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_AX,
    PipelineStages:     0,
    AxiIdWidthSlvPorts: 32'(AxiIdWidthSlv),
    AxiIdUsedSlvPorts:  32'(AxiIdWidthSlv),
    UniqueIds:          1'b0,
    AxiAddrWidth:       32'(AxiAddrWidth),
    AxiDataWidth:       32'(AxiDataWidth),
    NoAddrRules:        32'(NoSlaves)
  };

  axi_xbar #(
    .Cfg            (XbarCfg),
    .ATOPs          (1'b0),
    .slv_aw_chan_t  (slv_aw_chan_t),
    .mst_aw_chan_t  (mst_aw_chan_t),
    .w_chan_t       (slv_w_chan_t),
    .slv_b_chan_t   (slv_b_chan_t),
    .mst_b_chan_t   (mst_b_chan_t),
    .slv_ar_chan_t  (slv_ar_chan_t),
    .mst_ar_chan_t  (mst_ar_chan_t),
    .slv_r_chan_t   (slv_r_chan_t),
    .mst_r_chan_t   (mst_r_chan_t),
    .slv_req_t      (slv_req_t),
    .slv_resp_t     (slv_resp_t),
    .mst_req_t      (mst_req_t),
    .mst_resp_t     (mst_resp_t),
    .rule_t         (rule_t)
  ) i_xbar (
    .clk_i,
    .rst_ni,
    .test_i                (1'b0),
    .slv_ports_req_i       (cpu_req),
    .slv_ports_resp_o      (cpu_resp),
    .mst_ports_req_o       (periph_req),
    .mst_ports_resp_i      (periph_resp),
    .addr_map_i            (AddrMap),
    .en_default_mst_port_i ('0),
    .default_mst_port_i    ('0)
  );

  // --------------------------------------------------------------------------
  // Memory slaves: Boot ROM, I-SRAM, D-SRAM  (axi_to_mem + sram)
  // --------------------------------------------------------------------------
  // gen block parameters per slave
  localparam int unsigned MemWords [3] = '{4096, 16384, 16384}; // ROM 16KB, 64KB, 64KB

  for (genvar i = 0; i < 3; i++) begin : gen_mem
    logic        mem_req, mem_gnt, mem_we, mem_rvalid;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [3:0]  mem_strb;

    axi_to_mem #(
      .axi_req_t  (mst_req_t),
      .axi_resp_t (mst_resp_t),
      .AddrWidth  (AxiAddrWidth),
      .DataWidth  (AxiDataWidth),
      .IdWidth    (AxiIdWidthMst),
      .NumBanks   (1),
      .BufDepth   (1)
    ) i_axi_to_mem (
      .clk_i,
      .rst_ni,
      .busy_o       (/* open */),
      .axi_req_i    (periph_req [i]),
      .axi_resp_o   (periph_resp[i]),
      .mem_req_o    (mem_req),
      .mem_gnt_i    (mem_gnt),
      .mem_addr_o   (mem_addr),
      .mem_wdata_o  (mem_wdata),
      .mem_strb_o   (mem_strb),
      .mem_atop_o   (/* open */),
      .mem_we_o     (mem_we),
      .mem_rvalid_i (mem_rvalid),
      .mem_rdata_i  (mem_rdata)
    );

    sram #(
      .NumWords (MemWords[i]),
      .InitFile ((i == SlvRom)   ? "bootrom.mem" :
                 (i == SlvIsram) ? "program.mem" : "")
    ) i_sram (
      .clk_i,
      .rst_ni,
      .req_i    (mem_req),
      .gnt_o    (mem_gnt),
      .addr_i   (mem_addr),
      .wdata_i  (mem_wdata),
      .strb_i   (mem_strb),
      .we_i     (mem_we),
      .rvalid_o (mem_rvalid),
      .rdata_o  (mem_rdata)
    );
  end

  // --------------------------------------------------------------------------
  // APB leg: custom AXI->APB bridge + peripherals
  // --------------------------------------------------------------------------
  // APB slaves (each a 4 KB window inside the 1 MB ApbBase region):
  //   0: UART  @ 0x1000_0000
  //   1: Timer @ 0x1000_1000
  //   2: I2C   @ 0x1000_2000
  // Add more by extending NoApb, the apb_map, the response mux, and adding the
  // peripheral instance with .PSEL(apb_psel[n]).
  localparam int unsigned NoApb = 7;

  localparam logic [31:0] UartBase  = ApbBase + 32'h0000_0000;
  localparam logic [31:0] TimerBase = ApbBase + 32'h0000_1000;
  localparam logic [31:0] I2cBase   = ApbBase + 32'h0000_2000;
  localparam logic [31:0] SpiBase   = ApbBase + 32'h0000_3000;
  localparam logic [31:0] GpioBase  = ApbBase + 32'h0000_4000;
  localparam logic [31:0] ClintBase = ApbBase + 32'h0001_0000;  // 0x1001_0000 (64KB)
  localparam logic [31:0] PlicBase  = ApbBase + 32'h0040_0000;  // 0x1040_0000 (4MB-aligned)
  localparam logic [31:0] WinSize   = 32'h0000_1000; // 4 KB each
  localparam logic [31:0] ClintWin  = 32'h0001_0000; // 64 KB
  localparam logic [31:0] PlicWin   = 32'h0040_0000; // 4 MB (PLIC map is large)

  rule_t [NoApb-1:0] apb_map;
  assign apb_map[0] = '{idx: 32'd0, start_addr: UartBase,  end_addr: UartBase  + WinSize};
  assign apb_map[1] = '{idx: 32'd1, start_addr: TimerBase, end_addr: TimerBase + WinSize};
  assign apb_map[2] = '{idx: 32'd2, start_addr: I2cBase,   end_addr: I2cBase   + WinSize};
  assign apb_map[3] = '{idx: 32'd3, start_addr: SpiBase,   end_addr: SpiBase   + WinSize};
  assign apb_map[4] = '{idx: 32'd4, start_addr: GpioBase,  end_addr: GpioBase  + WinSize};
  assign apb_map[5] = '{idx: 32'd5, start_addr: ClintBase, end_addr: ClintBase + ClintWin};
  assign apb_map[6] = '{idx: 32'd6, start_addr: PlicBase,  end_addr: PlicBase  + PlicWin};

  // shared APB request signals + per-peripheral response, muxed back to bridge
  logic [31:0]      apb_paddr, apb_pwdata;
  logic             apb_pwrite, apb_penable;
  logic [3:0]       apb_pstrb;
  logic [NoApb-1:0] apb_psel;

  logic [31:0]      apb_prdata;          // muxed into the bridge
  logic             apb_pready;
  logic             apb_pslverr;

  logic [NoApb-1:0][31:0] p_prdata;      // per-peripheral
  logic [NoApb-1:0]       p_pready;
  logic [NoApb-1:0]       p_pslverr;

  // response mux: select the slave whose PSEL is active; default ready to avoid hang
  always_comb begin
    apb_prdata  = 32'b0;
    apb_pready  = 1'b1;
    apb_pslverr = 1'b0;
    for (int unsigned k = 0; k < NoApb; k++) begin
      if (apb_psel[k]) begin
        apb_prdata  = p_prdata[k];
        apb_pready  = p_pready[k];
        apb_pslverr = p_pslverr[k];
      end
    end
  end

  axi_to_apb_custom #(
    .NoApb      (NoApb),
    .AddrWidth  (AxiAddrWidth),
    .DataWidth  (AxiDataWidth),
    .axi_req_t  (mst_req_t),
    .axi_resp_t (mst_resp_t),
    .rule_t     (rule_t)
  ) i_axi2apb (
    .clk_i,
    .rst_ni,
    .axi_req_i  (periph_req [SlvApb]),
    .axi_resp_o (periph_resp[SlvApb]),
    .paddr_o    (apb_paddr),
    .pwdata_o   (apb_pwdata),
    .pwrite_o   (apb_pwrite),
    .pstrb_o    (apb_pstrb),
    .psel_o     (apb_psel),
    .penable_o  (apb_penable),
    .prdata_i   (apb_prdata),
    .pready_i   (apb_pready),
    .pslverr_i  (apb_pslverr),
    .addr_map_i (apb_map)
  );

  // --- APB peripheral 0: UART (apb_uart_sv, 16550-style) ---
  apb_uart_sv #(
    .APB_ADDR_WIDTH (12)
  ) i_uart (
    .CLK     (clk_i),
    .RSTN    (rst_ni),
    .PADDR   (apb_paddr[11:0]),
    .PWDATA  (apb_pwdata),
    .PWRITE  (apb_pwrite),
    .PSEL    (apb_psel[0]),
    .PENABLE (apb_penable),
    .PRDATA  (p_prdata[0]),
    .PREADY  (p_pready[0]),
    .PSLVERR (p_pslverr[0]),
    .rx_i    (uart_rx_i),
    .tx_o    (uart_tx_o),
    .event_o (uart_irq_o)
  );

  // --- APB peripheral 1: Timer (apb_timer, 2 timers) ---
  apb_timer #(
    .APB_ADDR_WIDTH (12),
    .TIMER_CNT      (2)
  ) i_timer (
    .HCLK    (clk_i),
    .HRESETn (rst_ni),
    .PADDR   (apb_paddr[11:0]),
    .PWDATA  (apb_pwdata),
    .PWRITE  (apb_pwrite),
    .PSEL    (apb_psel[1]),
    .PENABLE (apb_penable),
    .PRDATA  (p_prdata[1]),
    .PREADY  (p_pready[1]),
    .PSLVERR (p_pslverr[1]),
    .irq_o   (timer_irq_o)
  );

  // --- APB peripheral 2: I2C (apb_i2c) ---
  apb_i2c #(
    .APB_ADDR_WIDTH (12)
  ) i_i2c (
    .HCLK         (clk_i),
    .HRESETn      (rst_ni),
    .PADDR        (apb_paddr[11:0]),
    .PWDATA       (apb_pwdata),
    .PWRITE       (apb_pwrite),
    .PSEL         (apb_psel[2]),
    .PENABLE      (apb_penable),
    .PRDATA       (p_prdata[2]),
    .PREADY       (p_pready[2]),
    .PSLVERR      (p_pslverr[2]),
    .interrupt_o  (i2c_irq_o),
    .scl_pad_i    (i2c_scl_i),
    .scl_pad_o    (i2c_scl_o),
    .scl_padoen_o (i2c_scl_oen_o),
    .sda_pad_i    (i2c_sda_i),
    .sda_pad_o    (i2c_sda_o),
    .sda_padoen_o (i2c_sda_oen_o)
  );

  // --- APB peripheral 3: SPI master (apb_spi_master) ---
  apb_spi_master #(
    .BUFFER_DEPTH   (8),
    .APB_ADDR_WIDTH (12)
  ) i_spi (
    .HCLK     (clk_i),
    .HRESETn  (rst_ni),
    .PADDR    (apb_paddr[11:0]),
    .PWDATA   (apb_pwdata),
    .PWRITE   (apb_pwrite),
    .PSEL     (apb_psel[3]),
    .PENABLE  (apb_penable),
    .PRDATA   (p_prdata[3]),
    .PREADY   (p_pready[3]),
    .PSLVERR  (p_pslverr[3]),
    .events_o (spi_irq_o),
    .spi_clk  (spi_clk_o),
    .spi_csn0 (spi_csn_o[0]),
    .spi_csn1 (spi_csn_o[1]),
    .spi_csn2 (spi_csn_o[2]),
    .spi_csn3 (spi_csn_o[3]),
    .spi_mode (/* unused: quad-mode direction ctrl */),
    .spi_sdo0 (spi_mosi_o),
    .spi_sdo1 (/* quad */),
    .spi_sdo2 (/* quad */),
    .spi_sdo3 (/* quad */),
    .spi_sdi0 (spi_miso_i),
    .spi_sdi1 (spi_miso_i),   // standard (single-lane) RX samples sdi1, so MISO must drive it
    .spi_sdi2 (1'b0),
    .spi_sdi3 (1'b0)
  );

  // --- APB peripheral 4: GPIO (gpio_apb_wrap, 32 pins, struct APB port) ---
  // Pack the flat APB bus into the struct the wrapper expects.
  apb_req_t  gpio_apb_req;
  apb_resp_t gpio_apb_rsp;
  always_comb begin
    gpio_apb_req.paddr   = apb_paddr;
    gpio_apb_req.pprot   = '0;
    gpio_apb_req.psel    = apb_psel[4];
    gpio_apb_req.penable = apb_penable;
    gpio_apb_req.pwrite  = apb_pwrite;
    gpio_apb_req.pwdata  = apb_pwdata;
    gpio_apb_req.pstrb   = apb_pstrb;
  end
  assign p_prdata[4]  = gpio_apb_rsp.prdata;
  assign p_pready[4]  = gpio_apb_rsp.pready;
  assign p_pslverr[4] = gpio_apb_rsp.pslverr;

  gpio_apb_wrap #(
    .ADDR_WIDTH (AxiAddrWidth),
    .DATA_WIDTH (AxiDataWidth),
    .apb_req_t  (apb_req_t),
    .apb_rsp_t  (apb_resp_t)
  ) i_gpio (
    .clk_i,
    .rst_ni,
    .gpio_in                 (gpio_in_i),
    .gpio_out                (gpio_out_o),
    .gpio_tx_en_o            (gpio_dir_o),
    .gpio_in_sync_o          (/* open */),
    .global_interrupt_o      (gpio_irq_o),
    .pin_level_interrupts_o  (/* open */),
    .apb_req_i               (gpio_apb_req),
    .apb_rsp_o               (gpio_apb_rsp)
  );

  // --- APB peripheral 5: CLINT (timer + software interrupts) ---
  clint #(
    .APB_ADDR_WIDTH (16)
  ) i_clint (
    .clk_i,
    .rst_ni,
    .paddr_i    (apb_paddr[15:0]),
    .pwdata_i   (apb_pwdata),
    .pwrite_i   (apb_pwrite),
    .psel_i     (apb_psel[5]),
    .penable_i  (apb_penable),
    .prdata_o   (p_prdata[5]),
    .pready_o   (p_pready[5]),
    .pslverr_o  (p_pslverr[5]),
    .mtip_o     (clint_mtip),
    .msip_o     (clint_msip)
  );

  // --- APB peripheral 6: PLIC (pulp rv_plic plic_top via APB->reg_bus) ---
  // 30 sources (rv_plic default). We use sources 1..5:
  //   1=UART 2=Timer 3=I2C 4=SPI 5=GPIO. Source 0 is reserved by the PLIC.
  localparam int unsigned PLIC_N_SOURCE = 30;
  localparam int unsigned PLIC_N_TARGET = 2;

  logic [PLIC_N_SOURCE-1:0] plic_sources;
  always_comb begin
    plic_sources = '0;
    plic_sources[0] = uart_irq_o;     // source id 1
    plic_sources[1] = |timer_irq_o;   // source id 2
    plic_sources[2] = i2c_irq_o;      // source id 3
    plic_sources[3] = |spi_irq_o;     // source id 4
    plic_sources[4] = gpio_irq_o;     // source id 5
  end

  // flat APB (from bridge) -> REG_BUS interface -> struct reg_req/reg_rsp
  REG_BUS #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) plic_regbus (clk_i);

  apb_to_reg i_plic_apb2reg (
    .clk_i,
    .rst_ni,
    .penable_i (apb_penable),
    .pwrite_i  (apb_pwrite),
    .paddr_i   (32'h0C00_0000 | {10'b0, apb_paddr[21:0]}),
    .psel_i    (apb_psel[6]),
    .pwdata_i  (apb_pwdata),
    .prdata_o  (p_prdata[6]),
    .pready_o  (p_pready[6]),
    .pslverr_o (p_pslverr[6]),
    .reg_o     (plic_regbus)
  );

  reg_req_t plic_reg_req;
  reg_rsp_t plic_reg_rsp;
  `REG_BUS_ASSIGN_TO_REQ(plic_reg_req, plic_regbus)
  `REG_BUS_ASSIGN_FROM_RSP(plic_regbus, plic_reg_rsp)

  logic [PLIC_N_TARGET-1:0] plic_eip;
  plic_top #(
    .N_SOURCE  (PLIC_N_SOURCE),
    .N_TARGET  (PLIC_N_TARGET),
    .MAX_PRIO  (7),
    .reg_req_t (reg_req_t),
    .reg_rsp_t (reg_rsp_t)
  ) i_plic (
    .clk_i,
    .rst_ni,
    .req_i          (plic_reg_req),
    .resp_o         (plic_reg_rsp),
    .le_i           ('1),               // edge-sensitive: latch pulse IRQs as pending
    .irq_sources_i  (plic_sources),
    .eip_targets_o  (plic_eip)
  );

  assign plic_irq = plic_eip[0];        // target 0 drives the core external int

endmodule
