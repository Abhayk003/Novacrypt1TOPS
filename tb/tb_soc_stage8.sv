`timescale 1ns / 1ps
// Stage 8: GPIO test - set pin0 to output, drive it high, also read an input pin.
module tb_soc_stage8;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic uart_irq,i2c_irq,gpio_irq; logic [3:0] timer_irq;
  logic scl_o,scl_oen,sda_o,sda_oen;
  logic spi_clk,spi_mosi; logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;

  // drive a known pattern on an input pin (pin 5 high) to test input path
  assign gpio_in = 32'h0000_0020;   // pin5 = 1

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

  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    repeat (3000) @(posedge clk);
    $display("GPIO: out=%h dir=%h (pin0 out=%b dir=%b)",
             gpio_out, gpio_dir, gpio_out[0], gpio_dir[0]);
    if (gpio_out[0] === 1'b1 && gpio_dir[0] === 1'b1)
      $display("STAGE8 PASS: GPIO pin0 configured as output and driven high");
    else
      $display("STAGE8 FAIL: out[0]=%b dir[0]=%b", gpio_out[0], gpio_dir[0]);
    $finish;
  end
endmodule
