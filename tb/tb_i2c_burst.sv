`timescale 1ns / 1ps
// tb_i2c_burst.sv - multi-byte I2C read (2 bytes: ACK after byte1, NACK+STOP).
// Slave (0x44) returns 0xA1 then 0xB2. Data driven on SCL falling with a
// dedicated falling-edge bit counter (decoupled from the address sampler).
module tb_i2c_burst;
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
  localparam [7:0] BYTE1=8'hA1, BYTE2=8'hB2;
  // phase: 0 idle, 1 recv-addr, 2 ack-addr+send byte1, 3 send byte1 bits,
  //        4 master-ack1, 5 send byte2 bits, 6 done
  integer ph=0, acnt=0, dcnt=0;
  reg [7:0] shin=0;
  reg started=0;
  always @(negedge sda_line) if(scl_line===1'b1 && rst_n) begin started<=1; ph<=1; acnt<=0; shin<=0; slave_sda_pulldown<=0; end
  always @(posedge sda_line) if(scl_line===1'b1 && rst_n && started) begin ph<=0; slave_sda_pulldown<=0; end

  // address sampling on rising
  always @(posedge scl_line) if(rst_n && ph==1) begin
    shin<={shin[6:0],sda_line};
    if(acnt==7) ph<=2; else acnt<=acnt+1;
  end

  // everything driven on falling edge
  always @(negedge scl_line) if(rst_n) begin
    case(ph)
      2: begin // ACK address (pull low), then byte1 starts next falling
           if(shin[7:1]==SLAVE_ADDR && shin[0]==1'b1) begin
             slave_sda_pulldown<=1; ph<=3; dcnt<=0;
           end else begin slave_sda_pulldown<=0; ph<=0; end
         end
      3: begin // drive byte1 bit dcnt (MSB first)
           slave_sda_pulldown <= ~BYTE1[7-dcnt];
           if(dcnt==7) begin ph<=4; end else dcnt<=dcnt+1;
         end
      4: begin // master ACKs byte1 (master drives); slave releases; byte2 next
           slave_sda_pulldown<=0; ph<=5; dcnt<=0;
         end
      5: begin // drive byte2 bit dcnt
           slave_sda_pulldown <= ~BYTE2[7-dcnt];
           if(dcnt==7) begin ph<=6; end else dcnt<=dcnt+1;
         end
      6: begin slave_sda_pulldown<=0; end
      default: slave_sda_pulldown<=0;
    endcase
  end

  integer cyc=0;
  wire [31:0] d0=dut.gen_mem[2].i_sram.mem[0];
  wire [31:0] d1=dut.gen_mem[2].i_sram.mem[1];
  initial begin
    repeat(10)@(posedge clk); rst_n=1;
    while(((d0[7:0]!==BYTE1)||(d1[7:0]!==BYTE2)) && cyc<300000) begin @(posedge clk); cyc=cyc+1; end
    if(d0[7:0]===BYTE1 && d1[7:0]===BYTE2) begin
      $display("================================================================");
      $display("I2C_BURST PASS");
      $display("  2-byte read: byte1=0x%02h byte2=0x%02h (ACK then NACK+STOP)", d0[7:0], d1[7:0]);
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("I2C_BURST FAIL  d0=0x%08h d1=0x%08h (want %02h,%02h)", d0,d1,BYTE1,BYTE2);
      $display("================================================================");
    end
    $finish;
  end
endmodule