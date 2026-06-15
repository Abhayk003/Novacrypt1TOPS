`timescale 1ns / 1ps

module if_id
#(
    parameter RESET_PC = 32'h0000_0000
)
(
    input  logic        clk,
    input  logic        reset,

    // Prefetch buffer interface
    input  logic [31:0] instr_in,
    input  logic        instr_valid,
    output logic        consume,

//    input  logic [31:0] next_pc,

    // decoded outputs
    output logic [31:0] pc,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,

    output logic [31:0] immediate,
    output logic [6:0]  opcode,
    output logic [2:0]  funct3,
    output logic [6:0]  funct7,

    output logic [11:0] csr_addr,

    input logic stall,
    input logic branch_taken,
    input logic [31:0] branch_immediate,
    input logic [31:0] jalr_target,
    input logic        jalr_taken
);

////////////////////////////////////////////////////////////
// PC REGISTER
////////////////////////////////////////////////////////////
//logic [31:0] branch_imm;
logic [31:0] instruction;

//assign branch_imm = {{19{instruction[31]}},
//                         instruction[31],
//                         instruction[7],
//                         instruction[30:25],
//                         instruction[11:8],
//                         1'b0};
reg flag;
reg [31:0] next_pc;

always_ff @(posedge clk) begin
    if (reset) begin pc <= RESET_PC; end
    else pc <= next_pc;
end

always_comb begin
if (jalr_taken)
    next_pc = jalr_target;
else if (branch_taken)
    next_pc =  branch_immediate;
else if (!stall && instr_valid)
    next_pc = pc + 4;
else
    next_pc = pc;
end

////////////////////////////////////////////////////////////
// INSTRUCTION REGISTER
////////////////////////////////////////////////////////////


assign instruction = (reset)? 32'h00000013 : instr_in;

// tell FIFO we consumed an instruction
assign consume = (!stall && instr_valid && !branch_taken && !jalr_taken);


////////////////////////////////////////////////////////////
// INSTRUCTION DECODE
////////////////////////////////////////////////////////////

assign opcode = instruction[6:0];
assign rd     = instruction[11:7];
assign funct3 = instruction[14:12];
assign rs1    = instruction[19:15];
assign rs2    = instruction[24:20];
assign funct7 = instruction[31:25];
assign csr_addr = instruction[31:20];


////////////////////////////////////////////////////////////
// IMMEDIATE GENERATOR
////////////////////////////////////////////////////////////

always_comb begin

//    immediate = 32'h0;

    case(opcode)

        // I-type
        7'b0010011,
        7'b0000011,
        7'b1100111:
            immediate = {{20{instruction[31]}}, instruction[31:20]};

        // S-type
        7'b0100011:
            immediate = {{20{instruction[31]}},
                         instruction[31:25],
                         instruction[11:7]};

        // B-type
        7'b1100011:
            immediate = {{19{instruction[31]}},
                         instruction[31],
                         instruction[7],
                         instruction[30:25],
                         instruction[11:8],
                         1'b0};

        // U-type
        7'b0110111,
        7'b0010111:
            immediate = {instruction[31:12], 12'b0};

        // J-type
        7'b1101111:
            immediate = {{11{instruction[31]}},
                         instruction[31],
                         instruction[19:12],
                         instruction[20],
                         instruction[30:21],
                         1'b0};

        // CSR
        7'b1110011:
            immediate = {27'b0, rs1};

        default:
            immediate = 32'h0;

    endcase

end

endmodule