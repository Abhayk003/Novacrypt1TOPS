`timescale 1ns / 1ps
// ============================================================================
// tb_spi_burst.sv
// Multi-byte SPI receive: a single 32-bit read transfer. The behavioral slave
// streams 4 distinct bytes (DE AD BE EF) MSB-first across 32 SCLK cycles; the
// master assembles them into one 32-bit RX FIFO word.
//
// PASS = D-SRAM[0] == 0xDEADBEEF (all 4 bytes received, in order).
// ============================================================================
module tb_spi_burst;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi, spi_miso;
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
    .spi_miso_i(spi_miso), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq)
  );

  // behavioral slave: stream 32 bits MSB-first, update on falling spi_clk
  localparam [31:0] STREAM = 32'hDEADBEEF;
  reg [31:0] sh;
  wire cs0 = spi_csn[0];
  always @(negedge cs0) sh <= STREAM;
  assign spi_miso = (!cs0) ? sh[31] : 1'b0;
  always @(negedge spi_clk) if (!cs0) sh <= {sh[30:0], 1'b0};

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];
  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    while ((d0 !== STREAM) && cyc < 60000) begin @(posedge clk); cyc = cyc + 1; end
    if (d0 === STREAM) begin
      $display("================================================================");
      $display("SPI_BURST PASS");
      $display("  4-byte stream 0x%08h received as one 32-bit word", STREAM);
      $display("  D-SRAM[0] = 0x%08h", d0);
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("SPI_BURST FAIL  D-SRAM[0]=0x%08h (expect 0x%08h)", d0, STREAM);
      $display("================================================================");
    end
    $finish;
  end
endmodule