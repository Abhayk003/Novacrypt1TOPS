`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.03.2026 22:46:08
// Design Name: 
// Module Name: registers
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module registers(
    input  logic        clk,
    input  logic        reset,

    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic [4:0]  rd,

    input  logic [31:0] write_data,
    input  logic        reg_write,

    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

logic [31:0] regs [31:0];

integer i;

// Synchronous write, asynchronous read register file.
// Write occurs on the clock edge; reads are combinational.
always_ff @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] <= 32'b0;
    end else if (reg_write && (rd != 5'd0)) begin
        regs[rd] <= write_data;
    end
end

// Asynchronous read with internal write-first bypass: if a register is being
// written this cycle and simultaneously read, return the new value. x0 reads 0.
assign rs1_data = (rs1 == 5'd0) ? 32'b0 :
                  (reg_write && (rd != 5'd0) && (rd == rs1)) ? write_data :
                  regs[rs1];
assign rs2_data = (rs2 == 5'd0) ? 32'b0 :
                  (reg_write && (rd != 5'd0) && (rd == rs2)) ? write_data :
                  regs[rs2];

endmodule
