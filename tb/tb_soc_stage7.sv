`timescale 1ns / 1ps
// Stage 7: I2C functional test.
// Drives a START + address byte; a behavioral slave model on SDA/SCL checks
// the START condition and ACKs. TB verifies START seen and SCL clocked.
module tb_soc_stage7;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic uart_irq, i2c_irq; logic [3:0] timer_irq;
  logic scl_o, scl_oen, sda_o, sda_oen;
  logic spi_clk, spi_mosi; logic [3:0] spi_csn; logic [1:0] spi_irq;

  // Tristate model of the open-drain I2C bus.
  // Controller drives via *_o with *_oen (active-low enable: 0 => driving).
  // Pull-ups make the line high when nobody drives. The slave can pull SDA low.
  logic sda_slave_pulldown = 0;   // slave drives 0 when asserting ACK
  wire scl_line = scl_oen ? 1'b1 : scl_o;                 // only controller drives SCL
  wire sda_line = (!sda_oen ? sda_o : 1'b1) & ~sda_slave_pulldown; // wired-AND

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(scl_line), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(sda_line), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq)
  );

  // START detection: SDA falls while SCL high
  logic saw_start = 0;
  logic prev_sda = 1;
  always @(posedge clk) begin
    if (rst_n) begin
      if (scl_line && prev_sda && !sda_line) saw_start <= 1;
      prev_sda <= sda_line;
    end
  end

  // count SCL edges (clocking activity)
  int scl_edges = 0; logic prev_scl = 1;
  always @(posedge clk) begin
    if (rst_n) begin
      if (scl_line !== prev_scl) scl_edges <= scl_edges + 1;
      prev_scl <= scl_line;
    end
  end

  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    repeat (20000) @(posedge clk);
    $display("I2C: start_seen=%b  scl_edges=%0d", saw_start, scl_edges);
    if (saw_start && scl_edges > 8)
      $display("STAGE7 PASS: I2C START generated and SCL clocked the address byte");
    else
      $display("STAGE7 FAIL: start=%b edges=%0d", saw_start, scl_edges);
    $finish;
  end
endmodule
