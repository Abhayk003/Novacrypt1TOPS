`timescale 1ns / 1ps
// ============================================================================
// clint.sv - Core Local Interruptor (single hart, RV32)
//
// APB-mapped. Standard RISC-V CLINT layout (relative to base):
//   0x0000  msip      (bit0 = software interrupt pending/request)
//   0x4000  mtimecmp  low  32 bits
//   0x4004  mtimecmp  high 32 bits
//   0xBFF8  mtime     low  32 bits
//   0xBFFC  mtime     high 32 bits
//
// Outputs:
//   mtip_o = (mtime >= mtimecmp)     -> machine timer interrupt
//   msip_o = msip[0]                 -> machine software interrupt
//
// mtime free-runs every clock (1 tick/cycle here; scale in SW via mtimecmp).
// ============================================================================
module clint #(
    parameter int unsigned APB_ADDR_WIDTH = 16
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    input  logic [APB_ADDR_WIDTH-1:0] paddr_i,
    input  logic [31:0]               pwdata_i,
    input  logic                      pwrite_i,
    input  logic                      psel_i,
    input  logic                      penable_i,
    output logic [31:0]               prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,

    output logic                      mtip_o,
    output logic                      msip_o
);

  localparam logic [APB_ADDR_WIDTH-1:0] MSIP     = 16'h0000;
  localparam logic [APB_ADDR_WIDTH-1:0] MTIMECMPL= 16'h4000;
  localparam logic [APB_ADDR_WIDTH-1:0] MTIMECMPH= 16'h4004;
  localparam logic [APB_ADDR_WIDTH-1:0] MTIMEL   = 16'hBFF8;
  localparam logic [APB_ADDR_WIDTH-1:0] MTIMEH   = 16'hBFFC;

  logic [63:0] mtime_q;
  logic [63:0] mtimecmp_q;
  logic        msip_q;

  wire do_write = psel_i && penable_i &&  pwrite_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime_q    <= 64'd0;
      mtimecmp_q <= 64'hFFFF_FFFF_FFFF_FFFF; // no timer int until programmed
      msip_q     <= 1'b0;
      pready_o   <= 1'b0;
      pslverr_o  <= 1'b0;
    end else begin
      mtime_q   <= mtime_q + 64'd1;   // free-running tick
      pready_o  <= 1'b0;
      pslverr_o <= 1'b0;

      if (psel_i && penable_i && !pready_o) begin
        pready_o <= 1'b1;
        if (pwrite_i) begin
          case (paddr_i)
            MSIP     : msip_q            <= pwdata_i[0];
            MTIMECMPL: mtimecmp_q[31:0]  <= pwdata_i;
            MTIMECMPH: mtimecmp_q[63:32] <= pwdata_i;
            MTIMEL   : mtime_q[31:0]     <= pwdata_i;
            MTIMEH   : mtime_q[63:32]    <= pwdata_i;
            default  : ;
          endcase
        end
      end
    end
  end

  always_comb begin
    case (paddr_i)
      MSIP     : prdata_o = {31'b0, msip_q};
      MTIMECMPL: prdata_o = mtimecmp_q[31:0];
      MTIMECMPH: prdata_o = mtimecmp_q[63:32];
      MTIMEL   : prdata_o = mtime_q[31:0];
      MTIMEH   : prdata_o = mtime_q[63:32];
      default  : prdata_o = 32'b0;
    endcase
  end

  assign mtip_o = (mtime_q >= mtimecmp_q);
  assign msip_o = msip_q;

endmodule
