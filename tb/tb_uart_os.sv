`timescale 1ns / 1ps
// ============================================================================
// tb_uart_os.sv - UART RX interrupt integrated with FreeRTOS.
// Requires the extended firmware (main.c + irq_ext.c) with task U (UART echo).
// Chain: byte on uart_rx_i -> apb_uart RX FIFO -> uart_irq -> PLIC source 1 ->
//        mcause 0x8000000B -> application interrupt handler -> read RBR (clears
//        the UART int) -> vTaskNotifyGiveFromISR(xUartTaskHandle) -> task U
//        echoes "[U:x]".
// The TB drives two bytes into the receiver mid-run and checks both echoes
// appear, while A/B keep flowing.
// PASS = both echoed bytes seen in the TX stream AND A/B still running.
// firmware uart_init(16) => divisor 16 => 17 core clocks/bit => 170 ns/bit.
// ============================================================================
module tb_uart_os;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                            // 100 MHz
  logic uart_tx, uart_rx, uart_irq, i2c_irq, gpio_irq;
  logic [3:0] timer_irq;
  logic scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir; assign gpio_in = '0;

  soc_top dut (.clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(uart_rx), .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen), .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq));

  localparam int BIT_NS = 170;                     // 170 ns/bit (divisor 16)

  // ---- TX decode: print chars, and remember echoed payload bytes -----------
  integer nA = 0, nB = 0;
  integer got_X = 0, got_Y = 0, ab_after_rx = 0, rx_done = 0;
  localparam byte TX_X = "X", TX_Y = "Y";
  initial begin : rx_decode
    byte ch; integer i;
    forever begin
      @(negedge uart_tx); #(BIT_NS + BIT_NS/2); ch = 0;
      for (i = 0; i < 8; i++) begin ch[i] = uart_tx; #(BIT_NS); end
      if (ch == "A") begin nA++; if (rx_done) ab_after_rx++; end
      if (ch == "B") begin nB++; if (rx_done) ab_after_rx++; end
      if (ch == TX_X) got_X++;
      if (ch == TX_Y) got_Y++;
      if (ch >= 8'h20 && ch < 8'h7f) $write("%c", ch);
      else if (ch == 8'h0a) $write("\n");
    end
  end

  // ---- drive a framed byte into the UART receiver --------------------------
  task send_uart_byte(input byte b);
    integer i;
    begin
      uart_rx = 1'b0; #(BIT_NS);                   // start bit
      for (i = 0; i < 8; i++) begin uart_rx = b[i]; #(BIT_NS); end
      uart_rx = 1'b1; #(BIT_NS);                   // stop bit
      #(4*BIT_NS);                                 // inter-byte idle
    end
  endtask

  // ---- stimulus: send two bytes once the scheduler is running --------------
  initial begin
    uart_rx = 1'b1;                                // idle high
    #1_800_000;                                    // 1.8 ms: A/B flowing
    send_uart_byte(TX_X);
    #300_000;
    send_uart_byte(TX_Y);
    rx_done = 1;
  end

  // ---- run + verdict --------------------------------------------------------
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    #4_000_000;                                    // 4 ms
    $display("\n[census] A=%0d B=%0d  echoedX=%0d echoedY=%0d  A/B-after-rx=%0d",
             nA, nB, got_X, got_Y, ab_after_rx);
    if (got_X > 0 && got_Y > 0 && ab_after_rx > 0 && nA > 0 && nB > 0)
      $display("UART_OS PASS: UART RX interrupts wake the echo task; timer scheduling undisturbed");
    else
      $display("UART_OS FAIL (needs rebuilt firmware with irq_ext.c UART source + task U)");
    $finish;
  end
endmodule