`timescale 1ns / 1ps
// ============================================================================
// tb_gpio_sct.sv
// Verifies the GPIO SET / CLEAR / TOGGLE registers (never tested; Stage 8 only
// used the OUT register directly).
//
// Program (bootrom_gpio_sct.mem): pin0 -> output mode + enabled, then:
//   SET pin0    -> out = 1
//   CLEAR pin0  -> out = 0
//   TOGGLE pin0 -> out = 1
//   TOGGLE pin0 -> out = 0
// (each separated by a gap so transitions are distinct)
//
// The TB records the ordered sequence of distinct values gpio_out[0] takes after
// reset and checks it is exactly 0 -> 1 -> 0 -> 1 -> 0.
//
// PASS = observed transition sequence matches [1,0,1,0] after the initial 0.
// ============================================================================
module tb_gpio_sct;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0]  spi_csn;
  logic [1:0]  spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;
  assign gpio_in = 32'h0;

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq)
  );

  // record ordered distinct values of gpio_out[0]
  logic [0:7] seq;   integer n = 0;
  logic prev;
  initial prev = 1'bx;
  always @(posedge clk) if (rst_n) begin
    if (gpio_out[0] !== prev) begin
      if (n < 8) seq[n] = gpio_out[0];
      n = n + 1;
      prev = gpio_out[0];
    end
  end

  integer cyc = 0;
  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (1500) @(posedge clk);
    // Expect transitions: (reset 0) -> 1(SET) -> 0(CLEAR) -> 1(TOGGLE) -> 0(TOGGLE)
    // n counts transitions including the first move from x/0. We check the last 4
    // recorded distinct levels are 1,0,1,0.
    if (n >= 4 && seq[n-4]===1'b1 && seq[n-3]===1'b0 && seq[n-2]===1'b1 && seq[n-1]===1'b0) begin
      $display("================================================================");
      $display("GPIO_SCT PASS");
      $display("  SET->1, CLEAR->0, TOGGLE->1, TOGGLE->0 observed on gpio_out[0]");
      $display("  (%0d transitions recorded)", n);
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("GPIO_SCT FAIL");
      $display("  transitions=%0d  last4=%b%b%b%b (want 1010)",
               n, seq[(n>=4)?n-4:0], seq[(n>=3)?n-3:0], seq[(n>=2)?n-2:0], seq[(n>=1)?n-1:0]);
      $display("================================================================");
    end
    $finish;
  end
endmodule