`timescale 1ns / 1ps
// Stage 4: UART "Hi" test against the current 3-peripheral soc_top.
module tb_soc_stage4;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                 // 100 MHz, 10 ns

  logic uart_tx, uart_irq, i2c_irq;
  logic [3:0] timer_irq;
  logic i2c_scl_o, i2c_scl_oen, i2c_sda_o, i2c_sda_oen;

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(i2c_scl_o), .i2c_scl_oen_o(i2c_scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(i2c_sda_o), .i2c_sda_oen_o(i2c_sda_oen),
    .i2c_irq_o(i2c_irq)
  );

  // div=1 -> 2 core clocks/bit -> 20 ns/bit at 100 MHz
  localparam int BIT_NS = 20;
  byte unsigned rxbuf [0:7];
  int rxn = 0;

  // serial decoder: idle-high; lock to start bit; sample bit centers, LSB first
  task automatic uart_rx_byte(output byte unsigned b);
    b = 0;
    wait (uart_tx === 1'b1);
    @(negedge uart_tx);                 // start bit edge
    #(2*BIT_NS + BIT_NS/2);             // skip start bit, align to bit0 center
    for (int i = 0; i < 8; i++) begin
      b[i] = uart_tx;
      #(BIT_NS);
    end
  endtask

  initial begin
    byte unsigned c;
    repeat (10) @(posedge clk);
    rst_n = 1;
    for (int k = 0; k < 2; k++) begin
      uart_rx_byte(c);
      rxbuf[rxn++] = c;
      $display("UART RX byte %0d = 0x%02h ('%c')", k, c, c);
    end
    if (rxbuf[0] == "H" && rxbuf[1] == "i")
      $display("STAGE4 PASS: received \"Hi\" over UART");
    else
      $display("STAGE4 FAIL: got 0x%02h 0x%02h", rxbuf[0], rxbuf[1]);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("STAGE4 TIMEOUT - no/short UART output");
    $finish;
  end
endmodule
