`timescale 1ns / 1ps
// ============================================================================
// tb_tmr_os.sv - APB timer peripheral interrupt integrated with FreeRTOS.
// Requires the extended firmware with task T. This is the fifth and last PLIC
// source (id 2), completing the "all peripheral interrupts through the OS"
// picture. Distinct from the CLINT timer that drives the scheduler tick.
//
// Chain: task T programs TMR_CMP=20000, enables TMR_CTRL - the internal timer
// counts. On TIMER == CMP, irq_o[1] pulses and PLIC source 2 (level) latches
// it; the ISR notifies task T. The timer register self-resets on match, so
// irq_o de-asserts the same cycle and the timer restarts counting up. This
// "auto-clear on trigger" is the fifth distinct clear pattern (cf. UART
// read-RBR, I2C IACK, SPI read-INTSTA, GPIO W1C).
//
// No peripheral model needed - the timer is internal to the SoC. The TB just
// decodes UART output and checks [T] appears at least twice AND A/B keep flowing.
// ============================================================================
module tb_tmr_os;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic uart_tx,uart_rx,uart_irq,i2c_irq,gpio_irq; logic [3:0] timer_irq;
  logic scl_o,scl_oen,sda_o,sda_oen,spi_clk,spi_mosi; logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in,gpio_out,gpio_dir; assign gpio_in='0;

  soc_top dut(.clk_i(clk),.rst_ni(rst_n),
    .uart_rx_i(uart_rx),.uart_tx_o(uart_tx),.uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1),.i2c_scl_o(scl_o),.i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1),.i2c_sda_o(sda_o),.i2c_sda_oen_o(sda_oen),.i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk),.spi_csn_o(spi_csn),.spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0),.spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in),.gpio_out_o(gpio_out),.gpio_dir_o(gpio_dir),.gpio_irq_o(gpio_irq));

  localparam int BIT_NS = 170;
  integer nA=0, nB=0, nT=0, ab_after_t=0;
  // detect "[T]" via "[T" then "]" state
  integer in_t = 0; byte p0=0, p1=0;
  initial begin : rx
    byte ch; integer i;
    forever begin
      @(negedge uart_tx); #(BIT_NS + BIT_NS/2); ch=0;
      for(i=0;i<8;i++) begin ch[i]=uart_tx; #(BIT_NS); end
      if (ch=="A") begin nA++; if(nT>0) ab_after_t++; end
      if (ch=="B") begin nB++; if(nT>0) ab_after_t++; end
      if (p1=="[" && p0=="T" && ch=="]") nT++;
      p1<=p0; p0<=ch;
      if (ch>=8'h20 && ch<8'h7f) $write("%c", ch);
      else if (ch==8'h0a) $write("\n");
    end
  end

  initial begin
    uart_rx = 1;
    repeat (10) @(posedge clk); rst_n = 1;
    #6_000_000;
    $display("\n[census] A=%0d B=%0d  TMR_events([T])=%0d  A/B-after-T=%0d", nA, nB, nT, ab_after_t);
    if (nT >= 2 && ab_after_t > 0 && nA > 0 && nB > 0)
      $display("TMR_OS PASS: APB timer cmp-match interrupt wakes task T; scheduling undisturbed");
    else
      $display("TMR_OS FAIL");
    $finish;
  end
endmodule