`timescale 1ns / 1ps
// ============================================================================
// tb_clint.sv
// Verifies BOTH CLINT interrupt sources through the core's trap logic:
//   (1) TIMER  : mtime >= mtimecmp -> mtip -> machine timer interrupt (mcause 7)
//   (2) SOFTWARE: msip -> machine software interrupt (mcause 3)
//
// Program (bootrom_clint.mem) flow:
//   - set mtvec, program mtimecmp=100, enable MTIE+MIE, spin.
//   - CLINT timer fires -> handler sees mcause=7, writes 0x111 to D-SRAM[0],
//     disables the timer, clears MTIE, sets timer-done flag, MRET.
//   - main then enables MSIE and writes msip=1 (software interrupt request).
//   - software int fires -> handler sees mcause=3, writes 0x222 to D-SRAM[1],
//     clears msip, sets sw-done flag, MRET.
//   - main writes 0x123 to D-SRAM[2] once BOTH happened, then halts.
//
// PASS = D-SRAM[0]=0x111 AND [1]=0x222 AND [2]=0x123
//        (timer int, software int, and clean return from both).
// ============================================================================
module tb_clint;

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

  // convenience monitors (PASS criterion is the D-SRAM markers)
  logic saw_mtip = 0, saw_msip = 0;
  always @(posedge clk) if (rst_n) begin
    if (dut.clint_mtip) saw_mtip <= 1;
    if (dut.clint_msip) saw_msip <= 1;
  end

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];
  wire [31:0] d1 = dut.gen_mem[2].i_sram.mem[1];
  wire [31:0] d2 = dut.gen_mem[2].i_sram.mem[2];

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    while ((d2 !== 32'h00000123) && cyc < 30000) begin
      @(posedge clk); cyc = cyc + 1;
    end

    if (d0 === 32'h00000111 && d1 === 32'h00000222 && d2 === 32'h00000123) begin
      $display("================================================================");
      $display("CLINT PASS");
      $display("  timer interrupt    (mcause 7): marker 0x%08h  (mtip seen=%b)", d0, saw_mtip);
      $display("  software interrupt (mcause 3): marker 0x%08h  (msip seen=%b)", d1, saw_msip);
      $display("  both handled + returned      : marker 0x%08h", d2);
      $display("  completed in %0d cycles", cyc);
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("CLINT FAIL");
      $display("  D-SRAM[0] timer = 0x%08h (want 0x111)  mtip_seen=%b", d0, saw_mtip);
      $display("  D-SRAM[1] sw    = 0x%08h (want 0x222)  msip_seen=%b", d1, saw_msip);
      $display("  D-SRAM[2] done  = 0x%08h (want 0x123)", d2);
      $display("================================================================");
    end
    $finish;
  end
endmodule
