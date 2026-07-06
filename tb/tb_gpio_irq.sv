`timescale 1ns / 1ps
// ============================================================================
// tb_gpio_irq.sv
// Verifies a GPIO interrupt propagating through the PLIC to the core -- a
// NON-timer PLIC source (every other interrupt test uses the timer), and the
// GPIO rising-edge interrupt logic, both previously untested.
//
// Program (bootrom_gpio_irq.mem):
//   - enable GPIO rising-edge interrupt on pin 0 (INTRPT_RISE_EN @ 0x380)
//   - configure PLIC for GPIO (source index 4): priority, enable, threshold
//   - enable mie.MEIE then mstatus.MIE (last), spin.
// The TB drives gpio_in[0] from 0 -> 1, creating a rising edge. That fires the
// GPIO interrupt -> PLIC -> external interrupt -> handler claims, clears the
// GPIO status, completes, sets a done flag, mret. Program then writes 0x123.
//
// PASS = D-SRAM[2] == 0x123  (GPIO edge -> PLIC -> trap -> claim/clear/complete).
// ============================================================================
module tb_gpio_irq;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0]  spi_csn;
  logic [1:0]  spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;

  logic gpio0 = 1'b0;            // the input pin we toggle
  assign gpio_in = {31'b0, gpio0};

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

  logic saw_gpio_irq = 0, saw_ext = 0;
  always @(posedge clk) if (rst_n) begin
    if (gpio_irq)            saw_gpio_irq <= 1;
    if (dut.cpu_irq_external) saw_ext     <= 1;
  end

  integer cyc = 0;
  wire [31:0] d2 = dut.gen_mem[2].i_sram.mem[2];

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    // let the program arm GPIO + PLIC + interrupts
    repeat (400) @(posedge clk);
    // create the rising edge on GPIO pin 0
    gpio0 = 1'b1;

    while ((d2 !== 32'h00000123) && cyc < 20000) begin
      @(posedge clk); cyc = cyc + 1;
    end

    if (d2 === 32'h00000123) begin
      $display("================================================================");
      $display("GPIO_IRQ PASS");
      $display("  GPIO rising edge -> gpio_irq seen   : %b", saw_gpio_irq);
      $display("  -> PLIC external interrupt seen     : %b", saw_ext);
      $display("  handler claimed/cleared/completed   : D-SRAM[2]=0x%08h", d2);
      $display("  (non-timer PLIC source + GPIO IRQ logic verified)");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("GPIO_IRQ FAIL");
      $display("  D-SRAM[2]=0x%08h (expect 0x123)  gpio_irq=%b ext=%b",
               d2, saw_gpio_irq, saw_ext);
      $display("  (check INTRPT_RISE_EN, PLIC src4 offsets, edge mode)");
      $display("================================================================");
    end
    $finish;
  end
endmodule