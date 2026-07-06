`timescale 1ns / 1ps
// ============================================================================
// tb_spi_rx.sv
// Verifies the SPI RECEIVE path (Stage 6 only checked transmit: clock/CS/MOSI).
//
// A behavioral SPI slave drives a known byte (0xC3) onto spi_miso_i, MSB-first.
// The master is configured for an 8-bit READ transfer; it asserts CS0, clocks
// 8 SCLK cycles, and samples MISO on the RISING edge (mode-0). The program then
// reads the RX FIFO and stores it to D-SRAM[0].
//
// PASS = D-SRAM[0] low byte == 0xC3  (the byte the slave shifted in).
// ============================================================================
module tb_spi_rx;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen;
  logic        spi_clk, spi_mosi, spi_miso;
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

  // ---- Behavioral SPI slave on CS0 ----
  // Presents SLAVE_BYTE MSB-first. New bit driven on the FALLING edge of spi_clk
  // so it is stable when the master samples on the rising edge (mode 0).
  localparam logic [7:0] SLAVE_BYTE = 8'hC3;
  logic [7:0] sh;
  logic       cs0;
  assign cs0 = spi_csn[0];

  // load shift reg when CS asserts; preload MSB onto MISO
  always @(negedge cs0) begin
    sh = SLAVE_BYTE;
  end
  // drive current MSB; advance on falling edge of sclk while selected
  assign spi_miso = (!cs0) ? sh[7] : 1'b0;
  always @(negedge spi_clk) begin
    if (!cs0) sh = {sh[6:0], 1'b0};   // shift out next bit MSB-first
  end

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    while ((d0[7:0] !== SLAVE_BYTE) && cyc < 40000) begin
      @(posedge clk); cyc = cyc + 1;
    end
    if (d0[7:0] === SLAVE_BYTE) begin
      $display("================================================================");
      $display("SPI_RX PASS");
      $display("  byte driven on MISO    : 0x%02h", SLAVE_BYTE);
      $display("  RX FIFO -> D-SRAM[0]   : 0x%08h  (low byte 0x%02h)", d0, d0[7:0]);
      $display("  -> CS asserted, 8 SCLK clocks, MISO sampled, RXFIFO read OK");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("SPI_RX FAIL");
      $display("  expected low byte 0x%02h, D-SRAM[0] = 0x%08h", SLAVE_BYTE, d0);
      $display("  (check data_len in SPILEN, STATUS spi_rd|csreg, MISO edge)");
      $display("================================================================");
    end
    $finish;
  end
endmodule