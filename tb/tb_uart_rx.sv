`timescale 1ns / 1ps
// ============================================================================
// tb_uart_rx.sv
// Verifies UART RECEIVE (the Stage-4 test only covered transmit).
//
// The TB drives a properly-timed UART frame on uart_rx_i:
//   start bit (0), 8 data bits LSB-first, stop bit (1), at the configured baud.
// The program (bootrom_uart_rx.mem) sets the baud divisor to 9 (=> 10 core
// clocks per bit at 100 MHz = 100 ns/bit), polls LSR bit0 (data-ready), reads
// the received byte from RBR, and stores it to D-SRAM[0].
//
// PASS = D-SRAM[0] holds the byte the TB transmitted (0x5A).
// ============================================================================
module tb_uart_rx;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                       // 100 MHz, 10 ns period

  // bit period MUST match the program's divisor: (div+1) core clocks.
  // div=9 -> 10 clocks/bit -> 100 ns/bit.
  localparam int BIT_NS = 100;
  localparam logic [7:0] TX_BYTE0 = 8'h5A;
  localparam logic [7:0] TX_BYTE1 = 8'h3C;

  logic        uart_rx;                       // TB drives this into the DUT
  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0]  spi_csn;
  logic [1:0]  spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;
  assign gpio_in = 32'h0;

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(uart_rx), .uart_tx_o(), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq)
  );

  // serial transmit task: drive one 8N1 frame, LSB first
  task send_uart_byte(input [7:0] b);
    integer i;
    begin
      uart_rx = 1'b0;             #(BIT_NS);   // start bit
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx = b[i];          #(BIT_NS);    // data bits, LSB first
      end
      uart_rx = 1'b1;             #(BIT_NS);   // stop bit
      #(2*BIT_NS);                             // idle gap
    end
  endtask

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];
  wire [31:0] d1 = dut.gen_mem[2].i_sram.mem[1];

  initial begin
    uart_rx = 1'b1;                            // idle line is high
    repeat (10) @(posedge clk);
    rst_n = 1;

    // let the program configure the UART baud/format before we send.
    repeat (300) @(posedge clk);

    // drive two distinct bytes into the UART receiver
    send_uart_byte(TX_BYTE0);
    send_uart_byte(TX_BYTE1);

    while ((d1 !== {24'h0, TX_BYTE1}) && cyc < 60000) begin
      @(posedge clk); cyc = cyc + 1;
    end

    if (d0 === {24'h0, TX_BYTE0} && d1 === {24'h0, TX_BYTE1}) begin
      $display("================================================================");
      $display("UART_RX PASS");
      $display("  bytes sent on uart_rx_i : 0x%02h, 0x%02h", TX_BYTE0, TX_BYTE1);
      $display("  bytes read from RBR     : 0x%08h, 0x%08h (D-SRAM[0],[1])", d0, d1);
      $display("  -> framing, data-ready polling, RBR read, FIFO ordering OK");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("UART_RX FAIL");
      $display("  expected 0x%02h,0x%02h  got D-SRAM[0]=0x%08h [1]=0x%08h",
               TX_BYTE0, TX_BYTE1, d0, d1);
      $display("================================================================");
    end
    $finish;
  end
endmodule