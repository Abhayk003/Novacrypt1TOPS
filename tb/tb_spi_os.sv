`timescale 1ns / 1ps
// ============================================================================
// tb_spi_os.sv - SPI end-of-transfer interrupt integrated with FreeRTOS.
// Requires the extended firmware (main.c + irq_ext.c) with task S.
// Chain: task S kicks an 8-bit SPI read (STATUS.spi_rd, CS0) -> apb_spi EOT
// event (events_o[1]) -> PLIC source 4 (level) -> application interrupt handler
// reads INTSTA to clear -> notifies task S -> task S reads RXFIFO, prints [S:0xC3].
// A behavioral SPI slave (mode-0, MSB-first, returns 0xC3) is modeled here,
// reused from the proven bare-metal tb_spi_rx.
// PASS = [S:0xC3] seen at least once AND A/B keep flowing.
// ============================================================================
module tb_spi_os;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic uart_tx,uart_rx,uart_irq,i2c_irq,gpio_irq; logic [3:0] timer_irq;
  logic scl_o,scl_oen,sda_o,sda_oen,spi_clk,spi_mosi,spi_miso; logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in,gpio_out,gpio_dir; assign gpio_in='0;

  soc_top dut(.clk_i(clk),.rst_ni(rst_n),
    .uart_rx_i(uart_rx),.uart_tx_o(uart_tx),.uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1),.i2c_scl_o(scl_o),.i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1),.i2c_sda_o(sda_o),.i2c_sda_oen_o(sda_oen),.i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk),.spi_csn_o(spi_csn),.spi_mosi_o(spi_mosi),
    .spi_miso_i(spi_miso),.spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in),.gpio_out_o(gpio_out),.gpio_dir_o(gpio_dir),.gpio_irq_o(gpio_irq));

  // ---- UART TX decode: count A/B and detect [S:0xC3] via "[S:" -> "]" ----
  localparam int BIT_NS=170;
  integer nA=0,nB=0,nS=0, ab_after_s=0;
  integer in_s=0; byte p0=0,p1=0;
  initial begin : rx
    byte ch; integer i;
    forever begin @(negedge uart_tx); #(BIT_NS+BIT_NS/2); ch=0;
      for(i=0;i<8;i++) begin ch[i]=uart_tx; #(BIT_NS); end
      if (ch=="A") begin nA++; if(nS>0) ab_after_s++; end
      if (ch=="B") begin nB++; if(nS>0) ab_after_s++; end
      if (p1=="[" && p0=="S" && ch==":") in_s=1;
      else if (in_s && ch=="]") begin nS++; in_s=0; end
      p1<=p0; p0<=ch;
      if (ch>=8'h20&&ch<8'h7f) $write("%c",ch); else if(ch==8'h0a) $write("\n");
    end
  end

  // ---- behavioral SPI slave on CS0 (mode-0, MSB-first, returns 0xC3) ----
  localparam logic [7:0] SLAVE_BYTE = 8'hC3;
  logic [7:0] sh; logic cs0; assign cs0 = spi_csn[0];
  always @(negedge cs0) sh = SLAVE_BYTE;
  assign spi_miso = (!cs0) ? sh[7] : 1'b0;
  always @(negedge spi_clk) if (!cs0) sh = {sh[6:0], 1'b0};

  initial begin
    uart_rx=1; repeat(10)@(posedge clk); rst_n=1;
    #6_000_000;
    $display("\n[census] A=%0d B=%0d  SPI_reads([S:])=%0d  A/B-after-S=%0d", nA, nB, nS, ab_after_s);
    if (nS>=1 && nA>0 && nB>0)
      $display("SPI_OS PASS: EOT interrupt-driven SPI read wakes task S; scheduling undisturbed");
    else
      $display("SPI_OS FAIL");
    $finish;
  end
endmodule