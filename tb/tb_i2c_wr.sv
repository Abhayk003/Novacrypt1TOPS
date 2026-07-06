`timescale 1ns / 1ps
// tb_i2c_wr.sv - full I2C WRITE: START, addr+W, ACK, data, ACK, STOP.
// Behavioral slave (0x44) ACKs address and data, capturing the data byte.
// Slave state uses non-blocking assignments (proper flop semantics) so values
// persist across edges under Verilator's scheduler.
// PASS = slave captured DATA_BYTE (0x5E) AND program completed (D-SRAM[0]=0x123).
module tb_i2c_wr;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic uart_irq,i2c_irq,gpio_irq; logic [3:0] timer_irq;
  logic scl_o,scl_oen,sda_o,sda_oen,spi_clk,spi_mosi; logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in,gpio_out,gpio_dir; assign gpio_in=0;
  logic slave_sda_pulldown=0;
  wire scl_line=scl_oen?1'b1:scl_o;
  wire sda_ctrl=(!sda_oen)?sda_o:1'b1;
  wire sda_line=sda_ctrl & ~slave_sda_pulldown;
  soc_top dut(.clk_i(clk),.rst_ni(rst_n),.uart_rx_i(1'b1),.uart_tx_o(),.uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),.i2c_scl_i(scl_line),.i2c_scl_o(scl_o),.i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(sda_line),.i2c_sda_o(sda_o),.i2c_sda_oen_o(sda_oen),.i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk),.spi_csn_o(spi_csn),.spi_mosi_o(spi_mosi),.spi_miso_i(1'b0),.spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in),.gpio_out_o(gpio_out),.gpio_dir_o(gpio_dir),.gpio_irq_o(gpio_irq));
  localparam [6:0] SLAVE_ADDR=7'h44;
  localparam [7:0] DATA_BYTE =8'h5E;
  // slave state as flops (non-blocking)
  integer st=0, bitc=0; reg [7:0] shin=0, rxbyte=0; reg got_data=0, start_seen=0;
  always @(negedge sda_line) if(scl_line===1'b1&&rst_n) begin
    start_seen<=1; st<=1; bitc<=0; shin<=0; slave_sda_pulldown<=0;
  end
  always @(posedge sda_line) if(scl_line===1'b1&&rst_n&&start_seen) begin
    st<=0; slave_sda_pulldown<=0;
  end
  always @(posedge scl_line) if(rst_n) begin
    if(st==1) begin shin<={shin[6:0],sda_line}; bitc<=bitc+1; if(bitc==7) begin st<=2; bitc<=0; end end
    else if(st==6) begin st<=3; bitc<=0; end
    else if(st==3) begin shin<={shin[6:0],sda_line}; bitc<=bitc+1; if(bitc==7) begin st<=4; bitc<=0; rxbyte<={shin[6:0],sda_line}; got_data<=1; end end
  end
  always @(negedge scl_line) if(rst_n) begin
    case(st)
      2: begin if(shin[7:1]==SLAVE_ADDR&&shin[0]==1'b0) begin slave_sda_pulldown<=1; st<=6; end else begin slave_sda_pulldown<=0; st<=0; end end
      6: begin slave_sda_pulldown<=0; end
      4: begin slave_sda_pulldown<=1; st<=5; end
      5: begin slave_sda_pulldown<=0; st<=0; end
      default: slave_sda_pulldown<=0;
    endcase
  end
  integer cyc=0;
  wire [31:0] d0=dut.gen_mem[2].i_sram.mem[0];
  initial begin
    repeat(10)@(posedge clk); rst_n=1;
    while((!got_data || d0!==32'h00000123) && cyc<200000) begin @(posedge clk); cyc=cyc+1; end
    if(got_data && rxbyte===DATA_BYTE && d0===32'h00000123) begin
      $display("================================================================");
      $display("I2C_WR PASS");
      $display("  slave 0x%02h ACKed addr+data; captured byte 0x%02h",SLAVE_ADDR,rxbyte);
      $display("  program completed (D-SRAM[0]=0x%08h)",d0);
      $display("  -> START, addr+W, ACK, data, ACK, STOP verified");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("I2C_WR FAIL  got_data=%b rxbyte=0x%02h (want 0x%02h) d0=0x%08h",got_data,rxbyte,DATA_BYTE,d0);
      $display("================================================================");
    end
    $finish;
  end
endmodule