//==============================================================================
// axi_data_if.sv -- AXI4 data bus, full 5-channel, single-beat only.
// top_module is the AXI master; our environment is the slave.
//==============================================================================
interface axi_data_if (input logic clk, input logic reset);

  // Read address / data
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic        rvalid;
  logic [1:0]  rresp;
  logic        rready;

  // Write address / data / response
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;

  clocking drv_cb @(posedge clk);
    default input #1step output #1step;
    input  araddr, arvalid, rready, awaddr, awvalid, wdata, wstrb, wvalid, bready;
    output arready, rdata, rvalid, rresp, awready, wready, bresp, bvalid;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input araddr, arvalid, arready, rdata, rvalid, rresp, rready,
          awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready;
  endclocking

  modport DRV (clocking drv_cb, input clk, reset);
  modport MON (clocking mon_cb, input clk, reset);

endinterface : axi_data_if
