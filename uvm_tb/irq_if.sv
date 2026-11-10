//==============================================================================
// irq_if.sv -- the three level-active-high interrupt inputs into top_module.
//==============================================================================
interface irq_if (input logic clk, input logic reset);

  logic irq_timer;
  logic irq_software;
  logic irq_external;

  clocking drv_cb @(posedge clk);
    default output #1step;
    output irq_timer, irq_software, irq_external;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input irq_timer, irq_software, irq_external;
  endclocking

  modport DRV (clocking drv_cb, input clk, reset);
  modport MON (clocking mon_cb, input clk, reset);

endinterface : irq_if
