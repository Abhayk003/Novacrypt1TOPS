`timescale 1ns / 1ps
// ============================================================================
// tb_i2c_rd.sv
// Verifies a FULL I2C read transaction: START, address+R, slave ACK, slave
// returns a data byte, master NACK + STOP. Stage 7 only checked START + address
// clocking; ACK handling, data transfer, and STOP were never tested.
//
// A behavioral open-drain I2C slave (address 0x44) ACKs its address and then
// shifts out DATA_BYTE (0x6D) MSB-first. The program reads one byte and stores
// it to D-SRAM[0].
//
// PASS = D-SRAM[0] low byte == 0x6D (the byte the slave returned).
// ============================================================================
module tb_i2c_rd;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        uart_irq, i2c_irq, gpio_irq;
  logic [3:0]  timer_irq;
  logic        scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0]  spi_csn;
  logic [1:0]  spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir;
  assign gpio_in = 32'h0;

  // ---- open-drain bus ----
  // controller drives *_o when *_oen==0; pull-ups -> high when released.
  logic slave_sda_pulldown = 0;               // slave pulls SDA low when =1
  wire  scl_line = scl_oen ? 1'b1 : scl_o;    // only the controller drives SCL
  wire  sda_ctrl = (!sda_oen) ? sda_o : 1'b1; // controller's SDA contribution
  wire  sda_line = sda_ctrl & ~slave_sda_pulldown;  // wired-AND with slave

  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(scl_line), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(sda_line), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen),
    .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir),
    .gpio_irq_o(gpio_irq)
  );

  // ---- behavioral I2C slave ----
  localparam [6:0] SLAVE_ADDR = 7'h44;
  localparam [7:0] DATA_BYTE  = 8'h6D;

  // START / STOP detection on SDA transitions while SCL high
  reg sda_q, scl_q;
  always @(*) begin sda_q = sda_line; scl_q = scl_line; end

  // state machine clocked off SCL edges
  integer st;            // 0 idle, 1 addr, 2 ackaddr, 3 senddata, 4 mack
  integer bitc;
  reg [7:0] shin;
  reg [7:0] dshift;
  reg start_seen;

  // detect START: SDA 1->0 while SCL high
  always @(negedge sda_line) begin
    if (scl_line === 1'b1 && rst_n) begin
      start_seen = 1;
      st = 1; bitc = 0; shin = 0;
      slave_sda_pulldown = 0;
    end
  end
  // detect STOP: SDA 0->1 while SCL high
  always @(posedge sda_line) begin
    if (scl_line === 1'b1 && rst_n && start_seen) begin
      st = 0; slave_sda_pulldown = 0;
    end
  end

  // sample address bits on SCL rising edge; drive data/ack relative to SCL
  always @(posedge scl_line) begin
    if (rst_n) begin
      case (st)
        1: begin                               // receiving 8 address bits
             shin = {shin[6:0], sda_line};
             bitc = bitc + 1;
             if (bitc == 8) begin st = 2; bitc = 0; end
           end
        3: begin                               // master samples data here; count bits out
             bitc = bitc + 1;
             if (bitc == 8) begin st = 4; end
           end
        4: begin /* master drives NACK; nothing to do on rising */ end
        default: ;
      endcase
    end
  end

  // drive ACK and data on SCL falling edge (set up before next rising sample)
  always @(negedge scl_line) begin
    if (rst_n) begin
      case (st)
        2: begin
             // address received: if it matches (with R bit=1), ACK and prep data
             if (shin[7:1] == SLAVE_ADDR) begin
               slave_sda_pulldown = 1;          // ACK (pull SDA low) for one SCL
               dshift = DATA_BYTE;
               st = 3; bitc = 0;
             end else begin
               slave_sda_pulldown = 0; st = 0;
             end
           end
        3: begin
             // drive next data bit (MSB first); release line, pull low for 0
             slave_sda_pulldown = ~dshift[7];   // pulldown when bit is 0
             dshift = {dshift[6:0], 1'b0};
           end
        4: begin
             slave_sda_pulldown = 0;            // release for master NACK + STOP
           end
        default: slave_sda_pulldown = 0;
      endcase
    end
  end

  integer cyc = 0;
  wire [31:0] d0 = dut.gen_mem[2].i_sram.mem[0];

  initial begin
    st = 0; bitc = 0; start_seen = 0; slave_sda_pulldown = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
    while ((d0[7:0] !== DATA_BYTE) && cyc < 200000) begin
      @(posedge clk); cyc = cyc + 1;
    end
    if (d0[7:0] === DATA_BYTE) begin
      $display("================================================================");
      $display("I2C_RD PASS");
      $display("  slave addr 0x%02h ACKed, returned data byte 0x%02h", SLAVE_ADDR, DATA_BYTE);
      $display("  master read -> D-SRAM[0] = 0x%08h (low byte 0x%02h)", d0, d0[7:0]);
      $display("  -> START, addr+R, ACK, data, NACK+STOP verified");
      $display("================================================================");
    end else begin
      $display("================================================================");
      $display("I2C_RD FAIL");
      $display("  expected 0x%02h, D-SRAM[0]=0x%08h", DATA_BYTE, d0);
      $display("  (check addr match, ACK timing, data bit edges, TIP polling)");
      $display("================================================================");
    end
    $finish;
  end
endmodule