`timescale 1ns / 1ps
// Diagnostic for the "greeting then silence" hang. Reports:
//  - whether uart_irq_o asserts before any RX byte (spurious)
//  - count of external-interrupt traps (storm detection)
//  - where the PC is stuck
module tb_uart_diag;
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
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
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir), .gpio_irq_o(gpio_irq));
  localparam int BIT_NS = 170;
  initial begin : rx
    byte ch; integer i;
    forever begin @(negedge uart_tx); #(BIT_NS+BIT_NS/2); ch=0;
      for(i=0;i<8;i++) begin ch[i]=uart_tx; #(BIT_NS); end
      if (ch>=8'h20&&ch<8'h7f) $write("%c",ch); else if(ch==8'h0a) $write("\n"); end
  end
  wire [31:0] expc = dut.cpu.ifid_ex_r.pc;
  wire trap = dut.cpu.trap_taken;
  wire [31:0] mcause = dut.cpu.execute_stage.csr_block.mcause_q;
  reg td=0, samp=0; integer next=0, ext=0, uirq_early=0;
  reg [31:0] lastpc=0;
  always @(posedge clk) if (rst_n) begin
    // spurious uart_irq before any byte sent (we never send one here)
    if (uart_irq && !uirq_early) begin
      uirq_early = 1; $display("[!] uart_irq_o asserted at t=%0t with NO byte sent (spurious RX/CTI)", $time);
    end
    samp <= (trap && !td); td <= trap;
    if (samp && mcause==32'h8000000B) begin
      ext=ext+1;
      if (ext<=5) $display("[ext irq #%0d] mcause=0x%08h mepc=0x%08h t=%0t", ext, mcause,
        dut.cpu.execute_stage.csr_block.mepc_q, $time);
    end
    lastpc <= expc;
  end
  initial begin
    uart_rx=1; repeat(10)@(posedge clk); rst_n=1;
    #3_000_000;
    $display("\n[diag] external-int traps=%0d  uart_irq_ever_early=%0d  last_pc=0x%08h",
      ext, uirq_early, lastpc);
    if (ext>100) $display(">>> INTERRUPT STORM: external int fired %0d times -> tasks starved", ext);
    else if (ext==0) $display(">>> no external interrupts (expected, no byte sent)");
    $finish;
  end
endmodule