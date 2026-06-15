`timescale 1ns / 1ps
// Stage 6: SPI master smoke test - configure + kick a cmd transfer, observe
// CS assertion and SPI clock toggling + MOSI activity.
module tb_soc_stage6;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic uart_irq, i2c_irq; logic [3:0] timer_irq;
  logic i2c_scl_o,i2c_scl_oen,i2c_sda_o,i2c_sda_oen;
  logic spi_clk, spi_mosi; logic [3:0] spi_csn; logic [1:0] spi_irq;
  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(i2c_scl_o), .i2c_scl_oen_o(i2c_scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(i2c_sda_o), .i2c_sda_oen_o(i2c_sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq)
  );
  int sclk_edges = 0; logic prev_sclk = 0;
  logic saw_cs_low = 0; logic saw_mosi_activity = 0; logic prev_mosi = 0;
  always @(posedge clk) begin
    if (rst_n) begin
      if (spi_clk !== prev_sclk) sclk_edges <= sclk_edges + 1;
      prev_sclk <= spi_clk;
      if (spi_csn[0] == 1'b0) saw_cs_low <= 1;
      if (spi_mosi !== prev_mosi) saw_mosi_activity <= 1;
      prev_mosi <= spi_mosi;
    end
  end
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    repeat (4000) @(posedge clk);
    $display("SPI: sclk_edges=%0d  cs0_asserted=%b  mosi_activity=%b",
             sclk_edges, saw_cs_low, saw_mosi_activity);
    if (sclk_edges > 4 && saw_cs_low)
      $display("STAGE6 PASS: SPI transfer occurred (clock toggled, CS asserted)");
    else
      $display("STAGE6 FAIL: no SPI transfer observed");
    $finish;
  end
endmodule
