//==============================================================================
// axi_instr_if.sv -- AXI4 instruction bus (AR + R channel only).
// top_module is the AXI master on this bus; our environment is the slave.
//==============================================================================
interface axi_instr_if (input logic clk, input logic reset);

  logic [31:0] araddr;
  logic [7:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;
  logic        arvalid;
  logic        arready;

  logic [31:0] rdata;
  logic        rvalid;
  logic        rlast;
  logic [1:0]  rresp;
  logic        rready;

  clocking drv_cb @(posedge clk);
    default input #1step output #1step;
    input  araddr, arlen, arsize, arburst, arvalid, rready;
    output arready, rdata, rvalid, rlast, rresp;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input araddr, arlen, arsize, arburst, arvalid, arready,
          rdata, rvalid, rlast, rresp, rready;
  endclocking

  modport DRV (clocking drv_cb, input clk, reset);
  modport MON (clocking mon_cb, input clk, reset);

endinterface : axi_instr_if
