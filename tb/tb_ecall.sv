`timescale 1ns / 1ps
// ============================================================================
// tb_ecall.sv
// Verifies SYNCHRONOUS EXCEPTION support (ECALL) -- a feature added to the CPU
// (csr.sv/ex.sv) for this test; previously the trap logic handled interrupts
// only. ECALL traps to mtvec with mcause=11 (interrupt bit 0) and mepc = the
// ECALL PC. The handler checks mcause, advances mepc by 4, and mret returns.
//
// PASS = D-SRAM[0]==11 (mcause from ECALL) AND D-SRAM[1]==0x222 (clean return).
// ============================================================================
module tb_ecall;
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

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];
  wire [31:0] d1 = dut.gen_mem[2].i_sram.mem[1];
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    while (((d0 !== 32'd11) || (d1 !== 32'h222)) && cyc < 10000) begin
      @(posedge clk); cyc = cyc + 1;
    end
    if (d0 === 32'd11 && d1 === 32'h222) begin
      $display("================================================================");
      $display("ECALL PASS");
      $display("  ECALL trapped: mcause = %0d (=11, env-call M-mode), interrupt bit 0", d0);
      $display("  handler ran and mret returned past ECALL (D-SRAM[1]=0x%08h)", d1);
      $display("  -> synchronous exception entry + return verified");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("ECALL FAIL  mcause(d0)=%0d (want 11)  return(d1)=0x%08h (want 0x222)", d0, d1);
      $display("  (if d0=0: ECALL did not trap -> exception support not active)");
      $display("================================================================");
    end
    $finish;
  end
endmodule