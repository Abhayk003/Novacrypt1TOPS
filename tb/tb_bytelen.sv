`timescale 1ns / 1ps
// ============================================================================
// tb_bytelane.sv
// Sub-word write coverage: sb to each of the 4 byte lanes and sh to each of the
// 2 halfword lanes, then read back the assembled word. This exercises the CPU
// WSTRB generation and the bridge/SRAM byte-lane handling -- the area that
// produced a real XSim-only bug earlier in the project.
//
// Program (bootrom_bytelane.mem):
//   sb 0xAA,0xBB,0xCC,0xDD -> base+0,+1,+2,+3 ; lw -> dmem[1] (expect 0xDDCCBBAA)
//   sh 0x1234 -> base+8, sh 0x5678 -> base+10 ; lw -> dmem[3] (expect 0x56781234)
//
// PASS = D-SRAM[1] == 0xDDCCBBAA AND D-SRAM[3] == 0x56781234.
// ============================================================================
module tb_bytelen;
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
  wire [31:0] byte_res = dut.gen_mem[2].i_sram.mem[1];
  wire [31:0] half_res = dut.gen_mem[2].i_sram.mem[3];

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    while (((byte_res !== 32'hDDCCBBAA) || (half_res !== 32'h56781234)) && cyc < 8000) begin
      @(posedge clk); cyc = cyc + 1;
    end
    if (byte_res === 32'hDDCCBBAA && half_res === 32'h56781234) begin
      $display("================================================================");
      $display("BYTELANE PASS");
      $display("  sb to lanes 0..3 -> word = 0x%08h (expect DDCCBBAA)", byte_res);
      $display("  sh to halves 0,1 -> word = 0x%08h (expect 56781234)", half_res);
      $display("  -> per-lane WSTRB + byte-lane write path verified");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("BYTELANE FAIL");
      $display("  byte word = 0x%08h (expect DDCCBBAA)", byte_res);
      $display("  half word = 0x%08h (expect 56781234)", half_res);
      $display("  -> a lane is wrong: check store_wstrb vs addr[1:0] and SRAM byte-enables");
      $display("================================================================");
    end
    $finish;
  end
endmodule