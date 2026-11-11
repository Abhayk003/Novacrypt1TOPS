`timescale 1ns / 1ps
// ============================================================================
// tb_plic_os.sv - PLIC peripheral interrupt integrated with FreeRTOS.
// Requires the rebuilt firmware (main.c + irq_ext.c): tasks A/B (timer-driven)
// plus task G woken by GPIO pin-0 rising edge -> PLIC ID 5 -> mcause 0x8000000B
// -> freertos_risc_v_application_interrupt_handler -> vTaskNotifyGiveFromISR.
// The TB pulses gpio_in[0] three times mid-run.
// PASS = at least 2 G's AND at least one A or B AFTER the first G
//        (external interrupts serviced; timer scheduling undisturbed).
// ============================================================================
module tb_plic_os;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic uart_tx, uart_irq, i2c_irq, gpio_irq;
  logic [3:0] timer_irq;
  logic scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;

  soc_top dut (.clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen), .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq));

  // ---- UART decode + counters ------------------------------------------------
  localparam int BIT_NS = 170;
  integer nA = 0, nB = 0, nG = 0, ab_after_g = 0;
  initial begin : rx
    byte ch; integer i;
    forever begin
      @(negedge uart_tx); #(BIT_NS + BIT_NS/2); ch = 0;
      for (i = 0; i < 8; i++) begin ch[i] = uart_tx; #(BIT_NS); end
      if (ch == "A") begin nA++; if (nG > 0) ab_after_g++; end
      if (ch == "B") begin nB++; if (nG > 0) ab_after_g++; end
      if (ch == "G") nG++;
      if (ch >= 8'h20 && ch < 8'h7f) $write("%c", ch);
      else if (ch == 8'h0a) $write("\n");
    end
  end

  // ---- GPIO pin-0 pulses after the scheduler is up ----------------------------
  initial begin
    gpio_in = '0;
    #1_500_000;                       // 1.5 ms: greeting done, A/B flowing
    repeat (3) begin
      gpio_in[0] = 1'b1; #2_000;      // 2 us high (plenty for the sync stage)
      gpio_in[0] = 1'b0; #400_000;    // 400 us between pulses
    end
  end

  // ---- run + verdict -----------------------------------------------------------
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    #4_000_000;                       // 4 ms total
    $display("\n[census] A=%0d B=%0d G=%0d A/B-after-first-G=%0d", nA, nB, nG, ab_after_g);
    if (nG >= 2 && ab_after_g > 0 && nA > 0 && nB > 0)
      $display("PLIC_OS PASS: GPIO->PLIC interrupts wake task G; timer scheduling undisturbed");
    else
      $display("PLIC_OS FAIL (needs the rebuilt firmware with irq_ext.c + G task)");
    $finish;
  end
endmodule
