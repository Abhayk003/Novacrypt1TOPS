// TEMPORARY: at div_start, dump the divisor path so we see exactly which signal is X.
module opb_probe (
  input logic clk, input logic reset,
  input logic        div_en, input logic div_busy,
  input logic [31:0] op2, input logic [31:0] op2_temp, input logic [31:0] reg_rdata2,
  input logic        forwardB, input logic uses_rs2, input logic [31:0] ex_forward,
  input logic [31:0] op1, input logic [6:0] opcode, input logic [2:0] funct3,
  input logic [4:0] rs2
);
  wire div_start = div_en & ~div_busy;
  always @(posedge clk) if (!reset && div_start) begin
    $display("[OPB] t=%0t opcode=%02h funct3=%b rs2=%0d | op2=%08h op2_temp=%08h reg_rdata2=%08h forwardB=%b uses_rs2=%b ex_forward=%08h op1=%08h",
      $time, opcode, funct3, rs2, op2, op2_temp, reg_rdata2, forwardB, uses_rs2, ex_forward, op1);
  end
endmodule

bind ex opb_probe u_opb_probe (
  .clk(clk), .reset(reset),
  .div_en(div_en), .div_busy(div_busy),
  .op2(op2), .op2_temp(op2_temp), .reg_rdata2(reg_rdata2),
  .forwardB(forwardB), .uses_rs2(uses_rs2), .ex_forward(ex_forward),
  .op1(op1), .opcode(opcode), .funct3(funct3), .rs2(rs2)
);
