`timescale 1ns / 1ps
// ============================================================================
// tb_freertos.sv - run the FreeRTOS blinky firmware and decode UART TX.
// Loads bootrom.mem (boot stub) + program.mem (I-SRAM image, the FreeRTOS build).
// Prints every UART character so you see: "FreeRTOS blinky start" then A/B/A/B...
// A and B alternating = the scheduler is running with context switches. 
// UART: divisor=16 -> 17 clk/bit -> 170 ns/bit at 100 MHz (matches uart_init(16)).
// ============================================================================
module tb_freertos;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                       // 100 MHz

  logic        uart_tx, uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0]  spi_csn;
  logic [1:0]  spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;
  assign gpio_in = 32'h0;

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq)
  );

  // UART TX decoder: 170 ns/bit. Prints each received character.
  localparam int BIT_NS = 170;
  initial begin : rx_decode
    byte ch;
    integer i;
    forever begin
      @(negedge uart_tx);                      // start bit
      #(BIT_NS + BIT_NS/2);                     // center of bit0
      ch = 0;
      for (i = 0; i < 8; i++) begin
        ch[i] = uart_tx;
        #(BIT_NS);
      end
      if (ch >= 8'h20 && ch < 8'h7f) $write("%c", ch);
      else if (ch == 8'h0a)          $write("\n");
    end
  end

  // End-of-sim (FreeRTOS runs forever; stop after enough time to see A/B).
  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1;
    #4_000_000;                                // 4 ms of sim time
    $display("\n---- [tb_freertos done] ----");
    $finish;
  end
endmodule
