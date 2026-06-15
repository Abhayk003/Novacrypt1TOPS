`timescale 1ns / 1ps
module tb_soc_stage5;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [3:0] tirq; logic uirq, iirq;
  logic i2c_scl_o,i2c_scl_oen,i2c_sda_o,i2c_sda_oen;
  soc_top dut (
    .clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(uirq),
    .timer_irq_o(tirq),
    .i2c_scl_i(1'b1), .i2c_scl_o(i2c_scl_o), .i2c_scl_oen_o(i2c_scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(i2c_sda_o), .i2c_sda_oen_o(i2c_sda_oen),
    .i2c_irq_o(iirq)
  );
  logic saw_timer_irq = 0;
  always @(posedge clk) if (rst_n && |tirq) saw_timer_irq <= 1;
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    repeat (2000) @(posedge clk);
    if (saw_timer_irq) $display("STAGE5 PASS: timer compare IRQ fired (timer_irq=%b)", tirq);
    else $display("STAGE5 FAIL: no timer IRQ seen");
    $finish;
  end
endmodule
