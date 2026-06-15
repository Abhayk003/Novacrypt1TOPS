`timescale 1ns / 1ps

module mem_wb(
    input  logic clk,
    input  logic reset,
    input  logic [31:0] ex_result,
    input  logic [31:0] mem_address,
    input  logic [31:0] mem_write_data,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic        reg_write,     // ← writeback enable from EX (0 for stores/branches)
    input  logic [2:0]  funct3,        // ← NEW PORT
    input  logic [4:0]  rd,

    // DATA MEMORY INTERFACE
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic        dmem_we,
    output logic        dmem_re,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_rvalid,

    // REGISTER FILE WRITEBACK
    output logic [4:0]  reg_waddr,
    output logic [31:0] reg_wdata,
    output logic        reg_we
);

assign dmem_addr  = mem_address;
assign dmem_wdata = mem_write_data;
assign dmem_we    = mem_write;
assign dmem_re    = mem_read;

// ── Load data extraction ──────────────────────────────────────────────────
// mem_address[1:0] tells us which byte within the word the load targets.
// funct3 encoding (same as RISC-V spec):
//   000 = LB  (signed byte)
//   001 = LH  (signed halfword)
//   010 = LW  (word - no extension needed)
//   100 = LBU (unsigned byte)
//   101 = LHU (unsigned halfword)

logic [7:0]  load_byte;
logic [15:0] load_half;
logic [31:0] load_data;
logic [1:0]  byte_offset;

assign byte_offset = mem_address[1:0];

// Select the target byte from the 32-bit word
always_comb begin
    case (byte_offset)
        2'b00: load_byte = dmem_rdata[7:0];
        2'b01: load_byte = dmem_rdata[15:8];
        2'b10: load_byte = dmem_rdata[23:16];
        2'b11: load_byte = dmem_rdata[31:24];
    endcase
end

// Select the target halfword (only offsets 0 and 2 are valid for LH/LHU)
always_comb begin
    case (byte_offset[1])
        1'b0: load_half = dmem_rdata[15:0];
        1'b1: load_half = dmem_rdata[31:16];
    endcase
end

// Build the final load result with sign/zero extension
always_comb begin
    case (funct3)
        3'b000: load_data = {{24{load_byte[7]}},  load_byte};  // LB
        3'b001: load_data = {{16{load_half[15]}}, load_half};  // LH
        3'b010: load_data = dmem_rdata;                         // LW
        3'b100: load_data = {24'b0, load_byte};                 // LBU
        3'b101: load_data = {16'b0, load_half};                 // LHU
        default: load_data = dmem_rdata;
    endcase
end

assign reg_waddr = rd;
assign reg_wdata = mem_read ? load_data : ex_result;  // ← was dmem_rdata, now load_data
assign reg_we    = reg_write && (rd != 0) && (!mem_read || dmem_rvalid);

endmodule