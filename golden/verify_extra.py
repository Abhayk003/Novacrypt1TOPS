"""
Additional corner-case verification for the RV32IM golden model.
Exercises cases not covered (or not fully covered) by core.py's
built-in __main__ self-test: signed division overflow, MULH/MULHU/
MULHSU, CSRRS/CSRRC with x0, writes to x0, writes to mip, negative
JAL/branch offsets, JALR LSB clearing, CLINT timer interrupt, ECALL,
EBREAK, exception-vs-interrupt priority, interrupt priority ordering.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import ISS
import csr
import decoder
from decoder import (
    OPCODE_OP_IMM, OPCODE_OP, OPCODE_LUI, OPCODE_STORE, OPCODE_LOAD,
    OPCODE_BRANCH, OPCODE_JAL, OPCODE_JALR, OPCODE_SYSTEM,
    FUNCT7_BASE, FUNCT7_MULDIV, FUNCT12_ECALL, FUNCT12_EBREAK, FUNCT12_MRET,
)
from memory import IMEM_BASE, DMEM_BASE
from clint import ADDR_MSIP, ADDR_MTIME_LOW, ADDR_MTIMECMP_LOW, ADDR_MTIMECMP_HIGH

failures = []
def check(label, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label}")
    if not cond:
        failures.append(label)

# --- encoders (same shapes as core.py's) ---
def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    return (((imm12 >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm12 & 0x1F) << 7) | opcode
def enc_b(imm13, rs2, rs1, funct3, opcode):
    imm13 &= 0x1FFF
    bit12 = (imm13 >> 12) & 1
    bit11 = (imm13 >> 11) & 1
    bits10_5 = (imm13 >> 5) & 0x3F
    bits4_1 = (imm13 >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | opcode
def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode
def enc_j(imm21, rd, opcode):
    imm21 &= 0x1FFFFF
    bit20 = (imm21 >> 20) & 1
    bits10_1 = (imm21 >> 1) & 0x3FF
    bit11 = (imm21 >> 11) & 1
    bits19_12 = (imm21 >> 12) & 0xFF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | opcode

ADDI = lambda rd, rs1, imm: enc_i(imm, rs1, 0b000, rd, OPCODE_OP_IMM)
ADD  = lambda rd, rs1, rs2: enc_r(FUNCT7_BASE, rs2, rs1, 0b000, rd, OPCODE_OP)
MUL    = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b000, rd, OPCODE_OP)
MULH   = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b001, rd, OPCODE_OP)
MULHSU = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b010, rd, OPCODE_OP)
MULHU  = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b011, rd, OPCODE_OP)
DIV  = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b100, rd, OPCODE_OP)
DIVU = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b101, rd, OPCODE_OP)
REM  = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b110, rd, OPCODE_OP)
REMU = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b111, rd, OPCODE_OP)
LUI  = lambda rd, imm20: enc_u(imm20, rd, OPCODE_LUI)
SW = lambda rs2, imm, rs1: enc_s(imm, rs2, rs1, 0b010, OPCODE_STORE)
LW = lambda rd, imm, rs1: enc_i(imm, rs1, 0b010, rd, OPCODE_LOAD)
BEQ = lambda rs1, rs2, imm: enc_b(imm, rs2, rs1, 0b000, OPCODE_BRANCH)
BNE = lambda rs1, rs2, imm: enc_b(imm, rs2, rs1, 0b001, OPCODE_BRANCH)
JAL = lambda rd, imm: enc_j(imm, rd, OPCODE_JAL)
JALR = lambda rd, rs1, imm: enc_i(imm, rs1, 0b000, rd, OPCODE_JALR)
CSRRW = lambda rd, csr_addr, rs1: enc_i(csr_addr, rs1, 0b001, rd, OPCODE_SYSTEM)
CSRRS = lambda rd, csr_addr, rs1: enc_i(csr_addr, rs1, 0b010, rd, OPCODE_SYSTEM)
CSRRC = lambda rd, csr_addr, rs1: enc_i(csr_addr, rs1, 0b011, rd, OPCODE_SYSTEM)
ECALL_INST = enc_i(FUNCT12_ECALL, 0, 0b000, 0, OPCODE_SYSTEM)
EBREAK_INST = enc_i(FUNCT12_EBREAK, 0, 0b000, 0, OPCODE_SYSTEM)
MRET_INST = enc_i(FUNCT12_MRET, 0, 0b000, 0, OPCODE_SYSTEM)

def load_program(iss, words, base=IMEM_BASE):
    data = bytearray()
    for w in words:
        data += (w & 0xFFFFFFFF).to_bytes(4, "little")
    iss.memory.load_bytes(base, bytes(data))
    iss.state.pc = base

def s32v(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x

# =====================================================================
# Signed division overflow: 0x80000000 / -1 and 0x80000000 % -1
# =====================================================================
iss = ISS()
load_program(iss, [
    LUI(1, 0x80000),        # x1 = 0x80000000
    ADDI(2, 0, -1),         # x2 = 0xFFFFFFFF (-1)
    DIV(3, 1, 2),
    REM(4, 1, 2),
])
for _ in range(4):
    iss.step()
check("DIV overflow: 0x80000000 / -1 == 0x80000000", iss.state.regs[3] == 0x80000000)
check("REM overflow: 0x80000000 % -1 == 0", iss.state.regs[4] == 0)

# =====================================================================
# DIVU / REMU by zero
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(1, 0, 9),
    DIVU(2, 1, 0),
    REMU(3, 1, 0),
])
for _ in range(3):
    iss.step()
check("DIVU by zero == 0xFFFFFFFF", iss.state.regs[2] == 0xFFFFFFFF)
check("REMU by zero == dividend", iss.state.regs[3] == 9)

# =====================================================================
# MULH / MULHU / MULHSU
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(1, 0, -1),         # x1 = -1
    ADDI(2, 0, -1),         # x2 = -1
    MULH(3, 1, 2),          # signed*signed high: (-1)*(-1)=1 -> high=0
])
for _ in range(3):
    iss.step()
check("MULH (-1)*(-1) high32 == 0", iss.state.regs[3] == 0)

iss = ISS()
load_program(iss, [
    ADDI(1, 0, -1),         # x1 = 0xFFFFFFFF unsigned
    ADDI(2, 0, -1),         # x2 = 0xFFFFFFFF unsigned
    MULHU(3, 1, 2),         # 0xFFFFFFFF * 0xFFFFFFFF high32
])
for _ in range(3):
    iss.step()
expected_mulhu = ((0xFFFFFFFF * 0xFFFFFFFF) >> 32) & 0xFFFFFFFF
check("MULHU 0xFFFFFFFF*0xFFFFFFFF high32", iss.state.regs[3] == expected_mulhu)

iss = ISS()
load_program(iss, [
    ADDI(1, 0, -1),         # x1 = -1 signed
    ADDI(2, 0, -1),         # x2 = 0xFFFFFFFF unsigned (4294967295)
    MULHSU(3, 1, 2),        # -1 * 4294967295 (unsigned) -> high32
])
for _ in range(3):
    iss.step()
expected_mulhsu = (((-1) * 0xFFFFFFFF) & 0xFFFFFFFFFFFFFFFF) >> 32
check("MULHSU (-1)*0xFFFFFFFF(unsigned) high32", iss.state.regs[3] == expected_mulhsu)

# Also cross-check MULHSU against a case with known simple answer:
# rs1 = -2 (signed), rs2 = 3 (unsigned) => product = -6
# 64-bit two's complement of -6 -> high32 = 0xFFFFFFFF
iss = ISS()
load_program(iss, [
    ADDI(1, 0, -2),
    ADDI(2, 0, 3),
    MULHSU(3, 1, 2),
])
for _ in range(3):
    iss.step()
check("MULHSU (-2)*3 high32 == 0xFFFFFFFF (sign-extended)", iss.state.regs[3] == 0xFFFFFFFF)

# =====================================================================
# CSRRS / CSRRC with x0 as source (read-only semantics, no modify)
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(1, 0, 0x77),
    CSRRW(0, csr.CSR_MSCRATCH, 1),  # mscratch = 0x77
    CSRRS(2, csr.CSR_MSCRATCH, 0),  # x2 = mscratch, no modification (src=x0)
    CSRRC(3, csr.CSR_MSCRATCH, 0),  # x3 = mscratch, no modification (src=x0)
])
for _ in range(4):
    iss.step()
check("CSRRS with x0 src doesn't modify CSR", iss.state.mscratch == 0x77)
check("CSRRS with x0 src returns old value", iss.state.regs[2] == 0x77)
check("CSRRC with x0 src doesn't modify CSR", iss.state.mscratch == 0x77)
check("CSRRC with x0 src returns old value", iss.state.regs[3] == 0x77)

# CSRRS/CSRRC with x0 as rd (rd=0): should NOT write result back (no side effect on x0),
# but should still perform the read/modify/write on the CSR itself if src != 0.
iss = ISS()
load_program(iss, [
    ADDI(1, 0, 0xF),
    CSRRS(0, csr.CSR_MSCRATCH, 1),  # rd=0: mscratch |= 0xF, but x0 unaffected/no write
])
for _ in range(2):
    iss.step()
check("CSRRS with rd=x0 still updates CSR", iss.state.mscratch == 0xF)
check("CSRRS with rd=x0 leaves x0 == 0", iss.state.regs[0] == 0)

# =====================================================================
# Writes to x0 are discarded
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(0, 0, 123),   # attempt to write x0
])
iss.step()
check("write to x0 discarded (stays 0)", iss.state.regs[0] == 0)

# =====================================================================
# Writes to mip are silently dropped (mip is read-only / derived)
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(1, 0, 0x7FF),
    CSRRW(0, csr.CSR_MIP, 1),   # attempt to write mip directly
])
for _ in range(2):
    iss.step()
check("write to mip is a no-op (mip stays derived/0)", csr.csr_read(iss.state, csr.CSR_MIP) == 0)

# =====================================================================
# JAL negative offset
# =====================================================================
iss = ISS()
# place JAL at IMEM_BASE + 0x40 so a negative offset stays in-region
words = [ADDI(0, 0, 0)] * 16 + [JAL(1, -16)]
load_program(iss, words)
iss.state.pc = IMEM_BASE + 16 * 4
e = iss.step()
check("JAL negative offset: target == pc-16", iss.state.pc == IMEM_BASE + 16 * 4 - 16)
check("JAL negative offset: link == pc+4", iss.state.regs[1] == IMEM_BASE + 16 * 4 + 4)

# =====================================================================
# Branch negative offset
# =====================================================================
iss = ISS()
words = [ADDI(0, 0, 0)] * 4 + [BEQ(0, 0, -8)]
load_program(iss, words)
iss.state.pc = IMEM_BASE + 4 * 4
e = iss.step()
check("branch negative offset taken: target == pc-8", e.branch_taken and iss.state.pc == IMEM_BASE + 4*4 - 8)

# =====================================================================
# JALR bit0 clearing
# =====================================================================
iss = ISS()
load_program(iss, [
    ADDI(1, 0, (IMEM_BASE + 0x37) - IMEM_BASE),   # will compute odd target via imm below
])
# x1 = IMEM_BASE + 0x37 (odd), then JALR x2, x1, 1  => target=(x1+1) & ~1 = IMEM_BASE+0x38
iss2 = ISS()
load_program(iss2, [
    LUI(1, IMEM_BASE >> 12),
    ADDI(1, 1, 0x37),      # x1 = IMEM_BASE + 0x37 (odd address)
    JALR(2, 1, 1),         # target = (x1 + 1) & ~1
])
for _ in range(3):
    iss2.step()
expected_target = (IMEM_BASE + 0x37 + 1) & ~1
check("JALR clears LSB of target", iss2.state.pc == expected_target)
check("JALR link == pc+4", iss2.state.regs[2] == IMEM_BASE + 2*4 + 4)

# =====================================================================
# CLINT timer interrupt (MTIP)
# =====================================================================
MTVEC_TARGET = IMEM_BASE + 0x300
iss = ISS()
words = [
    LUI(10, MTVEC_TARGET >> 12),
    ADDI(10, 10, MTVEC_TARGET & 0xFFF),
    CSRRW(0, csr.CSR_MTVEC, 10),
    ADDI(11, 0, 1 << csr.MIE_MTIE_BIT),
    CSRRS(0, csr.CSR_MIE, 11),
    ADDI(12, 0, 1 << csr.MSTATUS_MIE_BIT),
    CSRRS(0, csr.CSR_MSTATUS, 12),
    # set mtimecmp = 0 (both 32-bit halves -- reset value is 0xFFFFFFFF_FFFFFFFF,
    # so the high half must be cleared too) so mtime (ticks +1/instr) >= mtimecmp
    LUI(13, ADDR_MTIMECMP_LOW >> 12),
    ADDI(14, 0, 0),
    SW(14, 0, 13),                                        # mtimecmp_low = 0
    SW(14, ADDR_MTIMECMP_HIGH - ADDR_MTIMECMP_LOW, 13),    # mtimecmp_high = 0 -> mtime>=mtimecmp
                                                            # crosses on THIS instruction; the
                                                            # interrupt fires here (same-step),
                                                            # not on some later instruction.
]
load_program(iss, words)
last = None
for i in range(len(words)):
    last = iss.step()
    if last.trap_taken:
        break
check("timer interrupt: mcause == (1<<31)|MTI(7)", iss.state.mcause == ((1 << 31) | csr.CAUSE_MTI))
check("timer interrupt: pc redirected to mtvec", iss.state.pc == MTVEC_TARGET)
check("timer interrupt: trap_taken flagged, not exception", last.trap_taken and not last.exc_taken)
check("timer interrupt: fires on the mtimecmp-writing instruction itself (same-step)",
      last.trap_taken)

# =====================================================================
# Interrupt priority: MEI > MSI > MTI when multiple pending simultaneously
# =====================================================================
iss = ISS()
iss.state.mie = (1 << csr.MIE_MEIE_BIT) | (1 << csr.MIE_MSIE_BIT) | (1 << csr.MIE_MTIE_BIT)
csr.set_mie_bit(iss.state, 1)
iss.state.msip = 1
iss.state.mtimecmp = 0  # mtime(0) >= mtimecmp(0) once ticked -> MTIP will be pending too
iss.state.external_irq = 1  # MEIP pending
iss.state.mtvec = IMEM_BASE + 0x400
load_program(iss, [ADDI(0, 0, 0)])
iss.step()
check("interrupt priority: MEI wins over MSI/MTI when all pending",
      iss.state.mcause == ((1 << 31) | csr.CAUSE_MEI))

# =====================================================================
# Exception priority over interrupt (Section 12: Exception > Interrupt)
# =====================================================================
iss = ISS()
iss.state.mie = (1 << csr.MIE_MSIE_BIT)
csr.set_mie_bit(iss.state, 1)
iss.state.msip = 1  # interrupt pending & enabled
iss.state.mtvec = IMEM_BASE + 0x500
# ILLEGAL instruction word: all 1s is not a valid recognized opcode -> ILLEGAL
load_program(iss, [0xFFFFFFFF])
e = iss.step()
check("exception beats interrupt when both pending same step",
      e.exc_taken and e.is_illegal and iss.state.mcause == csr.CAUSE_ILLEGAL_INSTRUCTION)

# =====================================================================
# ECALL / EBREAK
# =====================================================================
iss = ISS()
iss.state.mtvec = IMEM_BASE + 0x600
load_program(iss, [ECALL_INST])
e = iss.step()
check("ECALL sets is_ecall + trap_taken", e.is_ecall and e.trap_taken)
check("ECALL mcause == 11", iss.state.mcause == csr.CAUSE_ECALL_FROM_M)
check("ECALL pc -> mtvec", iss.state.pc == IMEM_BASE + 0x600)

iss = ISS()
iss.state.mtvec = IMEM_BASE + 0x700
load_program(iss, [EBREAK_INST])
e = iss.step()
check("EBREAK sets is_ebreak + trap_taken", e.is_ebreak and e.trap_taken)
check("EBREAK mcause == 3", iss.state.mcause == csr.CAUSE_EBREAK)
check("EBREAK pc -> mtvec", iss.state.pc == IMEM_BASE + 0x700)

# =====================================================================
# mstatus MPP hardwired bits always read as 11
# =====================================================================
iss = ISS()
val = csr.mstatus_read(iss.state)
check("mstatus MPP bits hardwired to 11", ((val >> csr.MSTATUS_MPP_SHIFT) & 0b11) == 0b11)

# =====================================================================
# Trace field ordering matches TRACE_FIELDS / TraceEntry dataclass
# =====================================================================
from dataclasses import fields as dc_fields
from trace import TraceEntry, TRACE_FIELDS
check("trace field order matches TraceEntry dataclass order",
      [f.name for f in dc_fields(TraceEntry)] == TRACE_FIELDS)

print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
else:
    print("All extra corner-case tests passed.")
