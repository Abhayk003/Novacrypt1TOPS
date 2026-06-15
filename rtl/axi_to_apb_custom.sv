`timescale 1ns / 1ps
// ============================================================================
// axi_to_apb_custom.sv  -  hand-written AXI4 -> APB4 bridge
//
//  * Slave side: full-AXI request/response STRUCTS (same types the xbar emits),
//    so it plugs straight into the SlvApb port of soc_top.
//  * Master side: FLAT APB4 signals, with one PSEL bit per peripheral decoded
//    from an address map.
//  * Single-beat by design (len==0). This SoC never routes the burst I-bus into
//    APB space (address map forbids it), and the D-bus is single-beat. If a
//    multi-beat AXI request ever arrives, it is answered with SLVERR rather than
//    silently mis-handled.
//  * Read/write arbitration: writes take priority; the other channel stalls.
//
//  APB transfer FSM:  IDLE -> SETUP (psel,!penable) -> ACCESS (psel,penable,
//  wait pready) -> back to IDLE. PSLVERR maps to AXI SLVERR.
// ============================================================================
module axi_to_apb_custom #(
    parameter int unsigned NoApb     = 5,           // number of APB peripherals
    parameter int unsigned AddrWidth = 32,
    parameter int unsigned DataWidth = 32,
    parameter type axi_req_t  = logic,
    parameter type axi_resp_t = logic,
    parameter type rule_t     = logic              // axi_pkg::xbar_rule_32_t
)(
    input  logic                       clk_i,
    input  logic                       rst_ni,

    // ---- AXI4 slave port (struct) ----
    input  axi_req_t                   axi_req_i,
    output axi_resp_t                  axi_resp_o,

    // ---- APB4 master port (flat) ----
    output logic [AddrWidth-1:0]       paddr_o,
    output logic [DataWidth-1:0]       pwdata_o,
    output logic                       pwrite_o,
    output logic [DataWidth/8-1:0]     pstrb_o,
    output logic [NoApb-1:0]           psel_o,      // one-hot per peripheral
    output logic                       penable_o,
    input  logic [DataWidth-1:0]       prdata_i,
    input  logic                       pready_i,
    input  logic                       pslverr_i,

    // ---- address map for PSEL decode ----
    input  rule_t [NoApb-1:0]          addr_map_i
);

  typedef enum logic [1:0] {IDLE, SETUP, ACCESS, RESP} state_e;
  state_e state_q, state_d;

  logic                  is_write_q, is_write_d;
  logic [AddrWidth-1:0]  addr_q,     addr_d;
  logic [DataWidth-1:0]  wdata_q,    wdata_d;
  logic [DataWidth/8-1:0]strb_q,     strb_d;
  logic [DataWidth-1:0]  rdata_q,    rdata_d;
  logic                  err_q,      err_d;
  logic                  bad_burst_q,bad_burst_d;  // multi-beat -> SLVERR

  // captured transaction ID (must be echoed in B/R so the xbar can route back)
  localparam int unsigned IdWidth = $bits(axi_req_i.aw.id);
  logic [IdWidth-1:0]    id_q, id_d;
  logic                  size_byte_q, size_byte_d;  // 1 = byte-sized read

  // ---- PSEL address decode (combinational, only meaningful in SETUP/ACCESS) ----
  logic [NoApb-1:0] psel_dec;
  always_comb begin
    psel_dec = '0;
    for (int unsigned k = 0; k < NoApb; k++) begin
      if (addr_q >= addr_map_i[k].start_addr && addr_q < addr_map_i[k].end_addr)
        psel_dec[k] = 1'b1;
    end
  end

  // ---- AXI handshake defaults ----
  always_comb begin
    // response struct fully driven
    axi_resp_o            = '0;
    axi_resp_o.r.id       = id_q;
    axi_resp_o.r.data     = rdata_q;
    axi_resp_o.r.resp     = (err_q || bad_burst_q) ? axi_pkg::RESP_SLVERR
                                                   : axi_pkg::RESP_OKAY;
    axi_resp_o.r.last     = 1'b1;
    axi_resp_o.b.id       = id_q;
    axi_resp_o.b.resp     = (err_q || bad_burst_q) ? axi_pkg::RESP_SLVERR
                                                   : axi_pkg::RESP_OKAY;
    axi_resp_o.aw_ready   = 1'b0;
    axi_resp_o.w_ready    = 1'b0;
    axi_resp_o.ar_ready   = 1'b0;
    axi_resp_o.r_valid    = 1'b0;
    axi_resp_o.b_valid    = 1'b0;

    state_d     = state_q;
    is_write_d  = is_write_q;
    addr_d      = addr_q;
    wdata_d     = wdata_q;
    strb_d      = strb_q;
    rdata_d     = rdata_q;
    err_d       = err_q;
    bad_burst_d = bad_burst_q;
    id_d        = id_q;
    size_byte_d = size_byte_q;

    unique case (state_q)
      // ---------------------------------------------------------------
      IDLE: begin
        if (axi_req_i.aw_valid && axi_req_i.w_valid) begin
          // accept write address + data together
          axi_resp_o.aw_ready = 1'b1;
          axi_resp_o.w_ready  = 1'b1;
          is_write_d  = 1'b1;
          addr_d      = axi_req_i.aw.addr;
          wdata_d     = axi_req_i.w.data;
          strb_d      = axi_req_i.w.strb;
          id_d        = axi_req_i.aw.id;
          bad_burst_d = (axi_req_i.aw.len != 8'd0);
          state_d     = SETUP;
        end else if (axi_req_i.ar_valid) begin
          axi_resp_o.ar_ready = 1'b1;
          is_write_d  = 1'b0;
          addr_d      = axi_req_i.ar.addr;
          id_d        = axi_req_i.ar.id;
          size_byte_d = (axi_req_i.ar.size == 3'd0);
          bad_burst_d = (axi_req_i.ar.len != 8'd0);
          state_d     = SETUP;
        end
      end
      // ---------------------------------------------------------------
      SETUP: begin
        // PSEL asserted, PENABLE low for one cycle (APB setup phase)
        if (bad_burst_q) begin
          // multi-beat burst: skip APB access, go straight to error response
          err_d   = 1'b1;
          state_d = RESP;
        end else if (psel_dec == '0) begin
          // address decoded to no peripheral: SLVERR instead of hanging on PREADY
          err_d   = 1'b1;
          state_d = RESP;
        end else begin
          state_d = ACCESS;
        end
      end
      // ---------------------------------------------------------------
      ACCESS: begin
        // PSEL + PENABLE high, wait for PREADY
        if (pready_i) begin
          err_d   = pslverr_i;
          // Lane placement: APB peripherals return data in PRDATA[7:0]. This
          // CPU extracts byte loads from the lane selected by addr[1:0]. Build
          // rdata explicitly so the low byte also lands in that lane. Written
          // as plain if/else (not unique case) for 4-state simulator robustness.
          if (addr_q[1:0] == 2'b00)
            rdata_d = prdata_i;
          else if (addr_q[1:0] == 2'b01)
            rdata_d = {prdata_i[31:16], prdata_i[7:0], prdata_i[7:0]};
          else if (addr_q[1:0] == 2'b10)
            rdata_d = {prdata_i[31:24], prdata_i[7:0], prdata_i[15:0]};
          else
            rdata_d = {prdata_i[7:0], prdata_i[23:0]};
          state_d = RESP;
        end
      end
      // ---------------------------------------------------------------
      RESP: begin
        if (is_write_q) begin
          axi_resp_o.b_valid = 1'b1;
          if (axi_req_i.b_ready) state_d = IDLE;
        end else begin
          axi_resp_o.r_valid = 1'b1;
          if (axi_req_i.r_ready) state_d = IDLE;
        end
      end
      default: state_d = IDLE;
    endcase
  end

  // ---- APB outputs ----
  // Byte-lane adaptation: this SoC's CPU positions sub-word data by byte lane
  // (addr[1:0]), but APB peripherals use PWDATA[7:0]/PRDATA[7:0]. On writes,
  // funnel the active strobe lane down to PWDATA[7:0]. On reads, the captured
  // prdata is replicated across all lanes (see rdata_d below) so a byte/half
  // load from any lane sees the value.
  logic [DataWidth-1:0] wdata_lane;
  always_comb begin
    unique case (strb_q)
      4'b0010: wdata_lane = {4{wdata_q[15: 8]}};
      4'b0100: wdata_lane = {4{wdata_q[23:16]}};
      4'b1000: wdata_lane = {4{wdata_q[31:24]}};
      4'b0011: wdata_lane = {2{wdata_q[15: 0]}};
      4'b1100: wdata_lane = {2{wdata_q[31:16]}};
      default: wdata_lane = wdata_q;            // lane0 / full word
    endcase
  end

  always_comb begin
    paddr_o   = addr_q;
    pwdata_o  = wdata_lane;
    pwrite_o  = is_write_q;
    pstrb_o   = strb_q;
    psel_o    = (state_q == SETUP || state_q == ACCESS) ? psel_dec : '0;
    penable_o = (state_q == ACCESS);
  end

  // ---- state ----
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= IDLE;
      is_write_q  <= 1'b0;
      addr_q      <= '0;
      wdata_q     <= '0;
      strb_q      <= '0;
      rdata_q     <= '0;
      err_q       <= 1'b0;
      bad_burst_q <= 1'b0;
      id_q        <= '0;
      size_byte_q <= 1'b0;
    end else begin
      state_q     <= state_d;
      is_write_q  <= is_write_d;
      addr_q      <= addr_d;
      wdata_q     <= wdata_d;
      strb_q      <= strb_d;
      rdata_q     <= rdata_d;
      err_q       <= err_d;
      bad_burst_q <= bad_burst_d;
      id_q        <= id_d;
      size_byte_q <= size_byte_d;
    end
  end

endmodule
