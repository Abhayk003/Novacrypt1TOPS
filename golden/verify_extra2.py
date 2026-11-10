import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core import ISS
import csr, clint
from decoder import OPCODE_OP_IMM, OPCODE_OP, OPCODE_LUI, OPCODE_STORE, OPCODE_LOAD, OPCODE_SYSTEM, FUNCT7_BASE, FUNCT7_ALT
from memory import IMEM_BASE, DMEM_BASE
from clint import ADDR_MSIP

failures = []
def check(label, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label}")
    if not cond:
        failures.append(label)

def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    return (((imm12 >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm12 & 0x1F) << 7) | opcode
def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

ADDI = lambda rd, rs1, imm: enc_i(imm, rs1, 0b000, rd, OPCODE_OP_IMM)
SLLI = lambda rd, rs1, sh: enc_i(sh, rs1, 0b001, rd, OPCODE_OP_IMM)
SRLI = lambda rd, rs1, sh: enc_r(FUNCT7_BASE, sh, rs1, 0b101, rd, OPCODE_OP_IMM)
SRAI = lambda rd, rs1, sh: enc_r(FUNCT7_ALT, sh, rs1, 0b101, rd, OPCODE_OP_IMM)
LUI  = lambda rd, imm20: enc_u(imm20, rd, OPCODE_LUI)
AUIPC = lambda rd, imm20: enc_u(imm20, rd, 0b0010111)
SB = lambda rs2, imm, rs1: enc_s(imm, rs2, rs1, 0b000, OPCODE_STORE)
SH = lambda rs2, imm, rs1: enc_s(imm, rs2, rs1, 0b001, OPCODE_STORE)
LB = lambda rd, imm, rs1: enc_i(imm, rs1, 0b000, rd, OPCODE_LOAD)
LBU = lambda rd, imm, rs1: enc_i(imm, rs1, 0b100, rd, OPCODE_LOAD)
LH = lambda rd, imm, rs1: enc_i(imm, rs1, 0b001, rd, OPCODE_LOAD)
LHU = lambda rd, imm, rs1: enc_i(imm, rs1, 0b101, rd, OPCODE_LOAD)
CSRRWI = lambda rd, csr_addr, zimm: enc_i(csr_addr, zimm, 0b101, rd, OPCODE_SYSTEM)
CSRRSI = lambda rd, csr_addr, zimm: enc_i(csr_addr, zimm, 0b110, rd, OPCODE_SYSTEM)
CSRRCI = lambda rd, csr_addr, zimm: enc_i(csr_addr, zimm, 0b111, rd, OPCODE_SYSTEM)

def load_program(iss, words, base=IMEM_BASE):
    data = bytearray()
    for w in words:
        data += (w & 0xFFFFFFFF).to_bytes(4, "little")
    iss.memory.load_bytes(base, bytes(data))
    iss.state.pc = base

# ---- LB/LH sign extension ----
iss = ISS()
load_program(iss, [
    LUI(5, DMEM_BASE >> 12),
    ADDI(1, 0, -1),           # x1 = 0xFFFFFFFF
    SB(1, 0, 5),               # mem[DMEM]   = 0xFF
    ADDI(1, 0, 0x1FF & 0xFFF), # can't directly load 0xFFFF via ADDI (12-bit imm); use two SB
])
iss.step(); iss.step(); iss.step()  # LUI, ADDI x1=-1, SB byte
# store 0xFFFF as halfword via two-byte pattern using SH with x1=-1 (0xFFFFFFFF -> low16=0xFFFF)
iss2 = ISS()
load_program(iss2, [
    LUI(5, DMEM_BASE >> 12),
    ADDI(1, 0, -1),      # x1 = 0xFFFFFFFF
    SB(1, 4, 5),          # mem[DMEM+4] = 0xFF (single byte -1)
    LB(2, 4, 5),          # x2 = sign-extend(0xFF) = 0xFFFFFFFF
    LBU(3, 4, 5),         # x3 = zero-extend(0xFF) = 0x000000FF
    SH(1, 8, 5),           # mem[DMEM+8..9] = 0xFFFF
    LH(4, 8, 5),           # x4 = sign-extend(0xFFFF) = 0xFFFFFFFF
    LHU(5, 8, 5) if False else ADDI(0,0,0),  # placeholder, LHU needs rs1 preserved; skip
])
for _ in range(7):
    iss2.step()
check("LB sign-extends negative byte", iss2.state.regs[2] == 0xFFFFFFFF)
check("LBU zero-extends byte", iss2.state.regs[3] == 0x000000FF)
check("LH sign-extends negative halfword", iss2.state.regs[4] == 0xFFFFFFFF)

# LHU zero-extend, separate program (avoid clobbering x5 base reg)
iss3 = ISS()
load_program(iss3, [
    LUI(5, DMEM_BASE >> 12),
    ADDI(1, 0, -1),
    SH(1, 12, 5),
    enc_i(12, 5, 0b101, 6, OPCODE_LOAD),  # LHU x6, 12(x5)
])
for _ in range(4):
    iss3.step()
check("LHU zero-extends halfword", iss3.state.regs[6] == 0x0000FFFF)

# ---- SLLI / SRLI / SRAI with shamt up to 31 ----
iss = ISS()
load_program(iss, [
    ADDI(1, 0, 1),
    SLLI(2, 1, 31),   # 1 << 31 = 0x80000000
])
for _ in range(2):
    iss.step()
check("SLLI shamt=31: 1<<31 == 0x80000000", iss.state.regs[2] == 0x80000000)

iss = ISS()
load_program(iss, [
    ADDI(1, 0, -1),      # x1 = 0xFFFFFFFF
    SRLI(2, 1, 31),      # logical: 0xFFFFFFFF >> 31 == 1
    SRAI(3, 1, 31),      # arithmetic: stays 0xFFFFFFFF
])
for _ in range(3):
    iss.step()
check("SRLI of -1 by 31 == 1 (logical)", iss.state.regs[2] == 1)
check("SRAI of -1 by 31 == 0xFFFFFFFF (arithmetic)", iss.state.regs[3] == 0xFFFFFFFF)

# ---- AUIPC ----
iss = ISS()
load_program(iss, [
    AUIPC(1, 0x12345),
])
iss.step()
expected = (IMEM_BASE + (0x12345 << 12)) & 0xFFFFFFFF
check("AUIPC == pc + (imm20<<12)", iss.state.regs[1] == expected)

# ---- CSRRWI / CSRRSI / CSRRCI ----
iss = ISS()
load_program(iss, [
    CSRRWI(1, csr.CSR_MSCRATCH, 0x1F),   # mscratch = 0x1F (zimm, unsigned 5-bit), x1 = old (0)
    CSRRSI(2, csr.CSR_MSCRATCH, 0x01),   # mscratch |= 1 (no-op, already set), x2 = old (0x1F)
    CSRRCI(3, csr.CSR_MSCRATCH, 0x1F),   # mscratch &= ~0x1F -> 0, x3 = old (0x1F)
])
for _ in range(3):
    iss.step()
check("CSRRWI writes zimm literally", iss.state.mscratch == 0x00)
check("CSRRWI returns old (0)", iss.state.regs[1] == 0)
check("CSRRSI returns old (0x1F)", iss.state.regs[2] == 0x1F)
check("CSRRCI returns old (0x1F) and clears bits", iss.state.regs[3] == 0x1F and iss.state.mscratch == 0)

# ---- CLINT byte/halfword sub-word access on MSIP ----
iss = ISS()
load_program(iss, [
    LUI(5, ADDR_MSIP >> 12),
    ADDI(1, 0, 0x7F),          # low byte nonzero pattern (0x7F -- fits 12-bit imm as positive)
    SB(1, 0, 5),                # byte store into MSIP register (only bit0 architecturally defined)
])
for _ in range(3):
    iss.step()
check("CLINT MSIP byte-store: only bit0 sticks", iss.state.msip == 1)

# read back full MSIP word via LW
iss2 = ISS()
load_program(iss2, [
    LUI(5, ADDR_MSIP >> 12),
    ADDI(1, 0, 1),
    SB(1, 0, 5),
    enc_i(0, 5, 0b010, 6, OPCODE_LOAD),  # LW x6, 0(x5)
])
for _ in range(4):
    iss2.step()
check("CLINT MSIP readback via LW == 1", iss2.state.regs[6] == 1)

print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
else:
    print("All round-2 tests passed.")
