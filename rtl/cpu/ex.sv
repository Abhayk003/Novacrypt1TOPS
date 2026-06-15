`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.03.2026 17:28:42
// Design Name: 
// Module Name: ex
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
////////////////////////////////////////////////////////////
// Execute Stage (Unpipelined)
////////////////////////////////////////////////////////////

module ex(
    input logic clk,
    input logic reset,
    input  logic [31:0] pc,
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic [31:0] reg_rdata1, //fetched operands
    input  logic [31:0] reg_rdata2,
    input  logic [31:0] immediate,

    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    input  logic [6:0]  opcode,
    input  logic [4:0]  rd_i,
    output logic [4:0]  rd_o,

//    output logic [31:0] next_pc,
    
    output logic [31:0] mem_address, //for ld/st
    output logic [31:0] mem_write_data, //for st
    output logic mem_read,//enable
    output logic mem_write, //enable
    
    input logic [11:0] csr_addr,
    output logic [31:0] ex_result,
    
    //hazard handling
    output logic ex_regwrite,
    output logic ex_memread,
    input  logic stall,
    input  logic forwardA,
    input  logic forwardB,
    input  logic [31:0] ex_forward,
    
    output logic branch_taken,
    output logic [31:0] branch_immediate,
    output logic [31:0] jalr_target,
    output logic jalr_taken,
    
        // MUL DEBUG
    output logic mul_en,
    output logic mul_busy,
    output logic mul_done,
    output logic mul_stall,
    
        // DIV DEBUG
    output logic div_en,
    output logic div_busy,
    output logic div_done,
    output logic div_stall,

    // interrupt pins + trap/mret redirect (trap support)
    input  logic        irq_timer_i,
    input  logic        irq_software_i,
    input  logic        irq_external_i,
    output logic        trap_taken_o,
    output logic [31:0] trap_target_o,
    output logic        mret_taken_o,
    output logic [31:0] mret_target_o
);

////////////////////////////////////////////////////////////
// OPCODES
////////////////////////////////////////////////////////////

localparam OP       = 7'b0110011; //arr
localparam OP_IMM   = 7'b0010011; //arri
localparam BRANCH   = 7'b1100011;
localparam JAL      = 7'b1101111;
localparam JALR     = 7'b1100111;
localparam LUI      = 7'b0110111;
localparam LOAD  = 7'b0000011;
localparam STORE = 7'b0100011;
localparam SYSTEM = 7'b1110011; //csr
localparam AUIPC = 7'b0010111;

////////////////////////////////////////////////////////////
// ALU OPERANDS
////////////////////////////////////////////////////////////
logic [31:0] op1_temp;
logic [31:0] op2_temp;
logic [31:0] op1;
logic [31:0] op2;

assign op1_temp = reg_rdata1;
assign op2_temp = (opcode == OP_IMM) ? immediate : reg_rdata2;

// rs2 is a true register source only for R-type, STORE and BRANCH. For all other
// opcodes (OP_IMM, LOAD, LUI, AUIPC, JAL, JALR, SYSTEM) bits[24:20] are part of an
// immediate, NOT a register, so forwardB must NOT override op2 with a forwarded value.
logic uses_rs2;
assign uses_rs2 = (opcode == OP) || (opcode == STORE) || (opcode == BRANCH);

assign op1 = (forwardA == 1) ? ex_forward : op1_temp;
assign op2 = (forwardB == 1 && uses_rs2) ? ex_forward : op2_temp;


assign rd_o = rd_i;

assign ex_regwrite = ~((opcode == BRANCH) || (opcode == STORE));
assign ex_memread = (opcode == LOAD);

assign branch_immediate = ((opcode == BRANCH)|| (opcode == JAL))? (pc+immediate) : 0;
assign jalr_target = (opcode == JALR) ? (op1 + immediate) & ~32'd1 : 32'd0;
//assign jalr_taken = (opcode == JALR);
////////////////////////////////////////////////////////////
// ALU
////////////////////////////////////////////////////////////
logic [31:0] alu_result;
always_comb
begin

    alu_result = 32'h0;
    mem_address    = 0;
    mem_write_data = 0;
    mem_read       = 0;
    mem_write      = 0;

    case(opcode)

        OP, OP_IMM:
        begin alu_result = 0;
            case(funct3)

                3'b000: begin
                    if(opcode == OP && funct7 == 7'b0100000)
                        alu_result = op1 - op2;
                    else
                        alu_result = op1 + op2;
                end

                3'b111: alu_result = op1 & op2;
                3'b110: alu_result = op1 | op2;
                3'b100: alu_result = op1 ^ op2;

                3'b001: alu_result = op1 << op2[4:0];
                3'b101:
                begin
                    if(funct7 == 7'b0100000)
                        alu_result = $signed(op1) >>> op2[4:0];
                    else
                        alu_result = op1 >> op2[4:0];
                end

                3'b010: alu_result = ($signed(op1) < $signed(op2));
                3'b011: alu_result = (op1 < op2);

            endcase
        end

        LUI:
            alu_result = immediate;
            
        AUIPC:
             alu_result = pc + immediate;

        JAL, JALR:
            alu_result = pc + 4; 
            //rd= pc+4 and pc=pc+offset for [jal rd,offset]
            //rd= pc+4 and rs1+imm for [jalr rd, imm(rs1)]
            
        LOAD: begin
            mem_address = op1 + immediate;
            mem_read    = 1;
        end

            STORE: begin
            mem_address = op1 + immediate;
            mem_write   = 1;
            case (funct3) //added for sw variants
                3'b000: mem_write_data = {4{op2[7:0]}};   // SB: replicate byte to all lanes
                3'b001: mem_write_data = {2{op2[15:0]}};  // SH: replicate halfword to both lanes
                3'b010: mem_write_data = op2;              // SW: full word, no change
                default: mem_write_data = op2;
            endcase
        end
    endcase

end

////////////////////////////////////////////////////////////
// BRANCH UNIT
////////////////////////////////////////////////////////////
//logic branch_taken;
logic [31:0] diff;
logic zero;
logic sign;
logic overflow;
logic carry;


always_comb
begin

    branch_taken = 0;
    jalr_taken = 0;
    diff = 0;
    zero = 0;
    sign = 0;
    overflow = 0;
    carry = 0;
    case(opcode)
        BRANCH: begin
        
        diff = op1 - op2;  
        zero = (diff == 0);
        sign = diff[31];
        overflow = (op1[31] != op2[31]) &&
               (diff[31] != op1[31]);
        carry = (op1 < op2);  
        
            case(funct3)
                3'b000: branch_taken = zero;        // BEQ
                3'b001: branch_taken = !zero;       // BNE              
                3'b100: branch_taken = sign ^ overflow; // BLT
                3'b101: branch_taken = !(sign ^ overflow); // BGE                
                3'b110: branch_taken = carry;       // BLTU
                3'b111: branch_taken = !carry;      // BGEU
                default : branch_taken=0;
            endcase

//            if(branch_taken)
////                next_pc = pc + immediate;

        end

        JAL:
        begin
            branch_taken = 1;
//            next_pc = pc + immediate;
        end

        JALR:
        begin
            jalr_taken = 1;
//            next_pc = (op1 + immediate) & ~1;
        end
        
//        default: begin
//            branch_taken = 0;
//            next_pc = pc + 4;
//        end

    endcase

end
////////////////////////////////////////////////////////////
// MUL Instructions 
logic [63:0] mul_result;
logic mul_en_sp;

// Detect MUL
assign mul_en = (opcode == OP) && (funct7 == 7'b0000001) &&(
        funct3 == 3'b000 || // MUL
        funct3 == 3'b001 || // MULH
        funct3 == 3'b010 || // MULHU
        funct3 == 3'b011    //MULHSU
    );
assign mul_en_sp = mul_en & ~mul_busy;

// Mode
logic [1:0] mul_mode;

always_comb begin
    case(funct3)
        3'b000: mul_mode = 2'b00; // MUL
        3'b001: mul_mode = 2'b01; // MULH
        3'b010: mul_mode = 2'b11; // MULHSU
        3'b011: mul_mode = 2'b10; // MULHU
        default: mul_mode = 2'b00;
    endcase
end
// Multiplier
wallace_mul_pipeline mul_unit (
    .clk(clk),
    .reset(reset),
    .start(mul_en_sp),
    .a(op1),
    .b(op2),
    .mul_mode(mul_mode),
    .result(mul_result),
    .done(mul_done)
);

always_ff @(posedge clk or posedge reset) begin
    if (reset)
        mul_busy <= 0;
    else if (mul_done)
        mul_busy <= 0;   // ⭐ THIS has priority
    else if (mul_en && !mul_busy)
        mul_busy <= 1;
end

assign mul_stall = (mul_en_sp) || (mul_busy && !mul_done);
////////////////////////////////////////////////////////////
// DIV Instructions
logic [31:0] div_result;
logic div_en_sp;

assign div_en =
    (opcode == OP) &&
    (funct7 == 7'b0000001) &&
    (
        funct3 == 3'b100 || // DIV
        funct3 == 3'b101 || // DIVU
        funct3 == 3'b110 || // REM
        funct3 == 3'b111    // REMU
    );
 
 assign div_en_sp = div_en & ~div_busy;
 
 rv32m_div_radix4 div_unit (
    .clk(clk),
    .reset(reset),

    .div_start(div_en_sp),
    .op_a(op1),
    .op_b(op2),
    .funct3(funct3),

    .div_result(div_result),
    .div_done(div_done)
);

always_ff @(posedge clk or posedge reset) begin
    if (reset)
        div_busy <= 0;

    else if (div_done)
        div_busy <= 0;

    else if (div_en && !div_busy)
        div_busy <= 1;
end

assign div_stall =(div_en_sp) || (div_busy && !div_done);


// M extension 
logic [31:0] final_result;

always_comb begin

    // MULTIPLY
    if (mul_busy) begin

        if (mul_done)
            final_result = (funct3==3'b000)
                           ? mul_result[31:0]
                           : mul_result[63:32];
        else
            final_result = 32'b0;
    end

    // DIVIDE
    else if (div_busy) begin

        if (div_done)
            final_result = div_result;
        else
            final_result = 32'b0;
    end

    // NORMAL ALU
    else begin
        final_result = alu_result;
    end
end
////////////////////////////////////////////////////////////
// CSR
////////////////////////////////////////////////////////////
logic is_csr;
assign is_csr = (opcode == SYSTEM);
logic [31:0] csr_result;

// MRET = SYSTEM, funct3=000, instr[31:20]=0x302 (exposed here as csr_addr).
logic is_mret;
assign is_mret = (opcode == SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h302);

csr csr_block (
    .clk(clk),
    .reset(reset),
    .csr_en(is_csr),
    .funct3(funct3),
    .csr_addr(csr_addr),
    .rs1_data(op1),
    .imm(immediate),
    .csr_rdata(csr_result),
    .cur_pc(pc),
    .is_mret(is_mret),
    .inst_valid(1'b1),
    .irq_timer_i(irq_timer_i),
    .irq_software_i(irq_software_i),
    .irq_external_i(irq_external_i),
    .trap_taken_o(trap_taken_o),
    .trap_target_o(trap_target_o),
    .mret_taken_o(mret_taken_o),
    .mret_target_o(mret_target_o)
);


assign ex_result = (is_csr) ? csr_result : final_result;

endmodule