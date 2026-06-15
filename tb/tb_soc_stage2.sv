`timescale 1ns / 1ps
// ============================================================================
// tb_soc_stage2.sv - Stage 2 smoke test
//
// Program in bootrom.mem (runs from 0x0):
//   lui  x1, 0x20        ; x1 = 0x0002_0000 (D-SRAM base)
//   addi x2, x0, 0x5A    ; x2 = 0x5A
//   sw   x2, 0(x1)       ; D-SRAM[0] = 0x5A      <- CPU -> xbar -> D-SRAM write
//   lw   x3, 0(x1)       ; x3 = D-SRAM[0]        <- read back through fabric
//   sw   x3, 4(x1)       ; D-SRAM[1] = x3        <- proves the LOAD worked
//   jal  x0, .           ; spin forever
//
// PASS criteria (checked hierarchically):
//   dmem word 0 == 0x5A   (store path works)
//   dmem word 1 == 0x5A   (load path works: value made the round trip)
// ============================================================================
module tb_soc_stage2;

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;   // 100 MHz

  logic tx; logic irq;
  soc_top dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .uart_rx_i  (1'b1),   // idle-high
    .uart_tx_o  (tx),
    .uart_irq_o (irq)
  );

  initial begin
    $dumpfile("stage2.vcd");
    $dumpvars(0, tb_soc_stage2);

    repeat (10) @(posedge clk);
    rst_n = 1;

    repeat (2000) @(posedge clk);   // plenty for a 6-instruction program

    // ---- hierarchical checks into D-SRAM (gen_mem index 2) ----
    if (dut.gen_mem[2].i_sram.mem[0] === 32'h0000005A &&
        dut.gen_mem[2].i_sram.mem[1] === 32'h0000005A) begin
      $display("STAGE2 PASS: dmem[0]=%h dmem[1]=%h",
               dut.gen_mem[2].i_sram.mem[0], dut.gen_mem[2].i_sram.mem[1]);
    end else begin
      $display("STAGE2 FAIL: dmem[0]=%h dmem[1]=%h (expected 0000005a both)",
               dut.gen_mem[2].i_sram.mem[0], dut.gen_mem[2].i_sram.mem[1]);
    end
    $finish;
  end

endmodule
