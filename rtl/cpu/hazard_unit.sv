`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.03.2026 21:47:26
// Design Name: 
// Module Name: hazard_unit
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

module hazard_unit(
input  logic       reset,
input  logic [4:0] id_rs1,
input  logic [4:0] id_rs2,
input  logic [4:0] ex_rd,
input  logic       ex_memread,
input  logic       ex_regwrite,

input  logic [4:0] mem_rd,
input  logic       mem_memread,
input logic        mul_stall,
input logic        div_stall,
input logic dmem_rvalid,

output logic stall,
output logic forwardA,
output logic forwardB
);


//assign forwardA =
//    (ex_regwrite && (mem_rd != 0) && (ex_rd == id_rs1));

//assign forwardB =
//    (ex_regwrite && (mem_rd != 0) && (ex_rd == id_rs2));


assign forwardA = (ex_regwrite && (ex_rd != 0) && (ex_rd == id_rs1));
assign forwardB = (ex_regwrite && (ex_rd != 0) && (ex_rd == id_rs2));
//assign forwardA =
//    (mem_rd != 0) && (mem_rd == id_rs1);

//assign forwardB =
//    (mem_rd != 0) && (mem_rd == id_rs2);
    
//assign forwardA_mem =
//    (mem_regwrite && (mem_rd != 0) && (mem_rd == id_rs1));

//assign forwardB_mem =
//    (mem_regwrite && (mem_rd != 0) && (mem_rd == id_rs2));
    
//assign stall =
//    (ex_memread &&
//   (ex_rd == id_rs1 || ex_rd == id_rs2) &&
//   (ex_rd != 0));

always_comb begin

    if (reset)
        stall = 1'b0;

    else begin
//        stall =
//            ( ex_memread &&
//             ((ex_rd == id_rs1) || (ex_rd == id_rs2)) &&
//              (ex_rd != 0)
//            ) || div_stall || mul_stall;
stall = (ex_memread && ((ex_rd==id_rs1)||(ex_rd==id_rs2)) && (ex_rd!=0) && !dmem_rvalid)
        || div_stall || mul_stall;
end
end
endmodule
