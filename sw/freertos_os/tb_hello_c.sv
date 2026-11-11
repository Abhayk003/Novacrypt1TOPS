`timescale 1ns / 1ps
// ============================================================================
// tb_hello_c.sv - run the C firmware (boot stub in ROM -> crt0 in I-SRAM -> main).
// Decodes the UART TX line to capture the printed string, and also checks the
// D-SRAM sentinel main() writes (0x600DC0DE @ 0x20000).
//
// Load: bootrom.mem (the .boot stub) and program.mem (the I-SRAM image).
// PASS = D-SRAM[0] == 0x600DC0DE (main reached and ran) -- and you should see
// the greeting decoded on UART in the transcript.
// ============================================================================
module tb_hello_c;
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

  // UART TX decoder: divisor=1 -> 2 clk/bit -> 20 ns/bit at 100 MHz.
  localparam int BIT_NS = 20;
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
      else if (ch == 8'h0a) $write("\n");
    end
  end

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    while ((d0 !== 32'h600DC0DE) && cyc < 2_000_000) begin
      @(posedge clk); cyc = cyc + 1;
    end
    #(50*BIT_NS);                               // let the last chars flush
    $display("\n----");
    if (d0 === 32'h600DC0DE)
      $display("HELLO_C PASS: main() ran (D-SRAM[0]=0x%08h, greeting on UART above)", d0);
    else
      $display("HELLO_C FAIL: D-SRAM[0]=0x%08h (expected 0x600DC0DE)", d0);
    $finish;
  end
endmodule
