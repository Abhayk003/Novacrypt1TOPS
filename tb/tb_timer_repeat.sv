`timescale 1ns / 1ps
// ============================================================================
// tb_timer_repeat.sv
// Verifies the Timer auto-reloads and REPEATS (Stage 5 only checked a single
// compare IRQ). Program sets CMP=15 and enables the timer; the counter should
// hit 15, fire the compare IRQ, auto-reload to 0, and fire again, repeatedly.
//
// The TB counts compare-IRQ pulses on timer_irq. PASS = at least 3 pulses
// (proves the timer did not stop after the first match).
// ============================================================================
module tb_timer_repeat;
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

  // count rising edges of the compare IRQ (timer_irq[?] -- use the OR of the bits)
  wire tirq = |timer_irq;
  logic tprev = 0;
  integer pulses = 0;
  always @(posedge clk) if (rst_n) begin
    if (tirq && !tprev) pulses = pulses + 1;
    tprev <= tirq;
  end

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (2000) @(posedge clk);     // enough for many CMP=15 cycles
    if (pulses >= 3) begin
      $display("================================================================");
      $display("TIMER_REPEAT PASS");
      $display("  compare IRQ fired %0d times -> timer auto-reloads and repeats", pulses);
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("TIMER_REPEAT FAIL");
      $display("  only %0d compare-IRQ pulse(s) seen (expected >= 3)", pulses);
      $display("  -> timer may not be reloading/repeating after the first match");
      $display("================================================================");
    end
    $finish;
  end
endmodule