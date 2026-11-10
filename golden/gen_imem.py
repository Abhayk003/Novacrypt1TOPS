#!/usr/bin/env python3
"""Generate only the program memory images consumed by the UVM testbench.

This script deliberately does NOT instantiate or execute the Python ISS.
It owns assembly/program-image generation only. The live reference model is
started separately by golden_server.py and consumes the same generated images.
"""
import os
import sys
import struct

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from memory import DMEM_BASE, DMEM_LIMIT, IMEM_BASE, IMEM_LIMIT, BOOT_ROM_BASE, BOOT_ROM_LIMIT
from decoder import (
    OPCODE_LUI, OPCODE_AUIPC, OPCODE_JAL, OPCODE_JALR, OPCODE_BRANCH,
    OPCODE_LOAD, OPCODE_STORE, OPCODE_OP_IMM, OPCODE_OP, OPCODE_SYSTEM,
    FUNCT7_BASE, FUNCT7_ALT, FUNCT7_MULDIV, FUNCT12_MRET,
)
from csr import CSR_MTVEC, CSR_MEPC, CSR_MCAUSE, CSR_MIE, CSR_MSTATUS
from clint import ADDR_MSIP

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# ---------------------------------------------------------------------
# Minimal two-pass RV32IM assembler with labels. Good enough for the
# straight-line / single-loop / single-trap-handler programs below --
# it is NOT a general assembler (no macros, no relocations across
# sections, no pseudo-ops beyond the few defined here).
# ---------------------------------------------------------------------
def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    return (((imm12 >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | ((imm12 & 0x1F) << 7) | opcode

def enc_b(imm13, rs2, rs1, funct3, opcode):
    imm13 &= 0x1FFF
    bit12 = (imm13 >> 12) & 1
    bit11 = (imm13 >> 11) & 1
    b10_5 = (imm13 >> 5) & 0x3F
    b4_1  = (imm13 >> 1) & 0xF
    return (bit12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (b4_1 << 8) | (bit11 << 7) | opcode

def enc_u(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

def enc_j(imm21, rd, opcode):
    imm21 &= 0x1FFFFF
    bit20  = (imm21 >> 20) & 1
    b10_1  = (imm21 >> 1) & 0x3FF
    bit11  = (imm21 >> 11) & 1
    b19_12 = (imm21 >> 12) & 0xFF
    return (bit20 << 31) | (b10_1 << 21) | (bit11 << 20) | (b19_12 << 12) | (rd << 7) | opcode


class Asm:
    """Two-pass assembler. Instructions are appended via the mnemonic
    methods below; each returns nothing but records one 32-bit word
    (or a placeholder, patched on pass 2 for branch/jump targets that
    reference a not-yet-defined label)."""

    def __init__(self, base_addr):
        self.base = base_addr
        self.words = []          # final words, filled during finalize()
        self._ops = []           # (mnemonic, args) in program order
        self.labels = {}

    def label(self, name):
        self.labels[name] = self.base + 4 * len(self._ops)

    def _addr_of(self, idx):
        return self.base + 4 * idx

    # R-type
    def _r(self, f7, rs2, rs1, f3, rd, op):
        self._ops.append(("R", (f7, rs2, rs1, f3, rd, op)))
    def ADD(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b000, rd, OPCODE_OP)
    def SUB(self, rd, rs1, rs2):  self._r(FUNCT7_ALT,  rs2, rs1, 0b000, rd, OPCODE_OP)
    def SLL(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b001, rd, OPCODE_OP)
    def SLT(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b010, rd, OPCODE_OP)
    def SLTU(self, rd, rs1, rs2): self._r(FUNCT7_BASE, rs2, rs1, 0b011, rd, OPCODE_OP)
    def XOR(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b100, rd, OPCODE_OP)
    def SRL(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b101, rd, OPCODE_OP)
    def SRA(self, rd, rs1, rs2):  self._r(FUNCT7_ALT,  rs2, rs1, 0b101, rd, OPCODE_OP)
    def OR(self, rd, rs1, rs2):   self._r(FUNCT7_BASE, rs2, rs1, 0b110, rd, OPCODE_OP)
    def AND(self, rd, rs1, rs2):  self._r(FUNCT7_BASE, rs2, rs1, 0b111, rd, OPCODE_OP)
    def MUL(self, rd, rs1, rs2):    self._r(FUNCT7_MULDIV, rs2, rs1, 0b000, rd, OPCODE_OP)
    def MULH(self, rd, rs1, rs2):   self._r(FUNCT7_MULDIV, rs2, rs1, 0b001, rd, OPCODE_OP)
    def MULHSU(self, rd, rs1, rs2): self._r(FUNCT7_MULDIV, rs2, rs1, 0b010, rd, OPCODE_OP)
    def MULHU(self, rd, rs1, rs2):  self._r(FUNCT7_MULDIV, rs2, rs1, 0b011, rd, OPCODE_OP)
    def DIV(self, rd, rs1, rs2):    self._r(FUNCT7_MULDIV, rs2, rs1, 0b100, rd, OPCODE_OP)
    def DIVU(self, rd, rs1, rs2):   self._r(FUNCT7_MULDIV, rs2, rs1, 0b101, rd, OPCODE_OP)
    def REM(self, rd, rs1, rs2):    self._r(FUNCT7_MULDIV, rs2, rs1, 0b110, rd, OPCODE_OP)
    def REMU(self, rd, rs1, rs2):   self._r(FUNCT7_MULDIV, rs2, rs1, 0b111, rd, OPCODE_OP)

    # I-type ALU / loads / jalr / system
    def _i(self, imm, rs1, f3, rd, op):
        self._ops.append(("I", (imm, rs1, f3, rd, op)))
    def ADDI(self, rd, rs1, imm):  self._i(imm, rs1, 0b000, rd, OPCODE_OP_IMM)
    def SLTI(self, rd, rs1, imm):  self._i(imm, rs1, 0b010, rd, OPCODE_OP_IMM)
    def SLTIU(self, rd, rs1, imm): self._i(imm, rs1, 0b011, rd, OPCODE_OP_IMM)
    def XORI(self, rd, rs1, imm):  self._i(imm, rs1, 0b100, rd, OPCODE_OP_IMM)
    def ORI(self, rd, rs1, imm):   self._i(imm, rs1, 0b110, rd, OPCODE_OP_IMM)
    def ANDI(self, rd, rs1, imm):  self._i(imm, rs1, 0b111, rd, OPCODE_OP_IMM)
    def NOP(self): self.ADDI(0, 0, 0)
    def LB(self, rd, imm, rs1):  self._i(imm, rs1, 0b000, rd, OPCODE_LOAD)
    def LH(self, rd, imm, rs1):  self._i(imm, rs1, 0b001, rd, OPCODE_LOAD)
    def LW(self, rd, imm, rs1):  self._i(imm, rs1, 0b010, rd, OPCODE_LOAD)
    def LBU(self, rd, imm, rs1): self._i(imm, rs1, 0b100, rd, OPCODE_LOAD)
    def LHU(self, rd, imm, rs1): self._i(imm, rs1, 0b101, rd, OPCODE_LOAD)
    def JALR(self, rd, rs1, imm): self._i(imm, rs1, 0b000, rd, OPCODE_JALR)
    def CSRRW(self, rd, csr_addr, rs1): self._i(csr_addr, rs1, 0b001, rd, OPCODE_SYSTEM)
    def CSRRS(self, rd, csr_addr, rs1): self._i(csr_addr, rs1, 0b010, rd, OPCODE_SYSTEM)
    def ECALL(self):  self._i(0x000, 0, 0b000, 0, OPCODE_SYSTEM)
    def EBREAK(self): self._i(0x001, 0, 0b000, 0, OPCODE_SYSTEM)
    def MRET(self):   self._i(FUNCT12_MRET, 0, 0b000, 0, OPCODE_SYSTEM)

    # Shifts: shamt lives in rs2 field, funct7 selects logical/arith
    def SLLI(self, rd, rs1, shamt): self._r(FUNCT7_BASE, shamt, rs1, 0b001, rd, OPCODE_OP_IMM)
    def SRLI(self, rd, rs1, shamt): self._r(FUNCT7_BASE, shamt, rs1, 0b101, rd, OPCODE_OP_IMM)
    def SRAI(self, rd, rs1, shamt): self._r(FUNCT7_ALT,  shamt, rs1, 0b101, rd, OPCODE_OP_IMM)

    # S-type stores
    def _s(self, imm, rs2, rs1, f3):
        self._ops.append(("S", (imm, rs2, rs1, f3, OPCODE_STORE)))
    def SB(self, rs2, imm, rs1): self._s(imm, rs2, rs1, 0b000)
    def SH(self, rs2, imm, rs1): self._s(imm, rs2, rs1, 0b001)
    def SW(self, rs2, imm, rs1): self._s(imm, rs2, rs1, 0b010)

    # U-type
    def LUI(self, rd, imm20):   self._ops.append(("U", (imm20, rd, OPCODE_LUI)))
    def AUIPC(self, rd, imm20): self._ops.append(("U", (imm20, rd, OPCODE_AUIPC)))

    # Branches / jumps -- label-relative, resolved on finalize()
    def _b(self, rs1, rs2, f3, target_label):
        self._ops.append(("B", (rs1, rs2, f3, target_label)))
    def BEQ(self, rs1, rs2, lbl):  self._b(rs1, rs2, 0b000, lbl)
    def BNE(self, rs1, rs2, lbl):  self._b(rs1, rs2, 0b001, lbl)
    def BLT(self, rs1, rs2, lbl):  self._b(rs1, rs2, 0b100, lbl)
    def BGE(self, rs1, rs2, lbl):  self._b(rs1, rs2, 0b101, lbl)
    def BLTU(self, rs1, rs2, lbl): self._b(rs1, rs2, 0b110, lbl)
    def BGEU(self, rs1, rs2, lbl): self._b(rs1, rs2, 0b111, lbl)
    def JAL(self, rd, lbl): self._ops.append(("J", (rd, lbl)))
    def JAL_SELF(self):
        # terminal self-loop: JAL x0, . (branch to own address)
        self._ops.append(("JSELF", ()))
    def JAL_ABS(self, rd, target_addr):
        # JAL to a plain absolute address rather than a same-segment
        # label -- needed to cross into a different memory region (e.g.
        # Boot ROM -> Instruction SRAM) whose base isn't this Asm
        # instance's own `self.base`. Still a single JAL, so the target
        # must be within +/-1MiB of the jump instruction (true for any
        # jump between the three small regions this spec defines).
        self._ops.append(("JABS", (rd, target_addr)))

    # Pseudo-op: materialize an arbitrary 32-bit constant with LUI+ADDI,
    # using the standard "round the upper 20 bits up by one if the lower
    # 12-bit immediate would be sign-negative" trick every RV32 assembler
    # uses for the `li` pseudo-instruction. Needed because a single ADDI
    # only carries a 12-bit signed immediate.
    def LI(self, rd, imm32):
        imm32 &= 0xFFFFFFFF
        lower = imm32 & 0xFFF
        if lower & 0x800:
            upper = ((imm32 >> 12) + 1) & 0xFFFFF
            lower_signed = lower - 0x1000
        else:
            upper = (imm32 >> 12) & 0xFFFFF
            lower_signed = lower
        self.LUI(rd, upper)
        self.ADDI(rd, rd, lower_signed)

    def finalize(self):
        words = []
        for idx, (kind, args) in enumerate(self._ops):
            addr = self._addr_of(idx)
            if kind == "R":
                words.append(enc_r(*args))
            elif kind == "I":
                words.append(enc_i(*args))
            elif kind == "S":
                words.append(enc_s(*args))
            elif kind == "U":
                words.append(enc_u(*args))
            elif kind == "B":
                rs1, rs2, f3, lbl = args
                tgt = self.labels[lbl]
                words.append(enc_b(tgt - addr, rs2, rs1, f3, OPCODE_BRANCH))
            elif kind == "J":
                rd, lbl = args
                tgt = self.labels[lbl]
                words.append(enc_j(tgt - addr, rd, OPCODE_JAL))
            elif kind == "JSELF":
                words.append(enc_j(0, 0, OPCODE_JAL))
            elif kind == "JABS":
                rd, target_addr = args
                words.append(enc_j(target_addr - addr, rd, OPCODE_JAL))
            else:
                raise ValueError(kind)
        self.words = words
        return words


# ---------------------------------------------------------------------
# Lane replication -- must match top_module's ex.sv store-data path and
# top_module.sv's store_wstrb block EXACTLY (see PDF transcript: SB
# replicates the byte to all 4 lanes, SH replicates the halfword to
# both halves, regardless of address alignment; wstrb is the one-hot/
# two-hot/all-ones select derived from funct3 + addr[1:0]).
# ---------------------------------------------------------------------
def apply_lane_replication(funct3, addr, raw_value):
    raw_value &= 0xFFFFFFFF
    if funct3 == 0b000:  # SB
        b = raw_value & 0xFF
        data = b | (b << 8) | (b << 16) | (b << 24)
        lane = addr & 0x3
        strb = {0: 0b0001, 1: 0b0010, 2: 0b0100, 3: 0b1000}[lane]
    elif funct3 == 0b001:  # SH
        h = raw_value & 0xFFFF
        data = h | (h << 16)
        strb = 0b1100 if (addr & 0x2) else 0b0011
    else:  # SW (funct3 == 0b010) and any other default
        data = raw_value
        strb = 0b1111
    return data, strb



# ---------------------------------------------------------------------
# readmemh emission helpers
# ---------------------------------------------------------------------
def write_readmemh_regions(path, regions):
    """regions: list of (word_base_addr, [words...]) -- each region gets
    its own '@<hex word index>' marker followed by its words."""
    with open(path, "w") as f:
        for base_addr, words in regions:
            f.write("@%x\n" % (base_addr >> 2))
            for w in words:
                f.write("%08x\n" % (w & 0xFFFFFFFF))


def dump_dmem_readmemh(iss, path):
    with open(path, "w") as f:
        addr = DMEM_BASE
        while addr <= DMEM_LIMIT:
            f.write("%08x\n" % iss.memory.read32(addr))
            addr += 4


# =======================================================================
# Test programs
# =======================================================================
def prog_smoke():
    """
    Directed RV32IM instruction coverage program.

    Goal:
      - Execute/fetch every legal RV32IM instruction variant
      - Exercise both sides of control-flow where meaningful
      - Exercise all load/store sizes
      - Exercise all AXI WSTRB lanes
      - Exercise system instructions
    """

    a = Asm(BOOT_ROM_BASE)

    # ==============================================================
    # SETUP
    # ==============================================================

    a.LUI(10, 0x20)          # x10 = DMEM_BASE

    a.ADDI(1, 0, 5)
    a.ADDI(2, 0, 3)

    # ==============================================================
    # RV32I R-TYPE
    # ==============================================================

    a.ADD(3, 1, 2)
    a.SUB(3, 1, 2)
    a.SLL(3, 1, 2)
    a.SLT(3, 1, 2)
    a.SLTU(3, 1, 2)
    a.XOR(3, 1, 2)
    a.SRL(3, 1, 2)
    a.SRA(3, 1, 2)
    a.OR(3, 1, 2)
    a.AND(3, 1, 2)

    # ==============================================================
    # RV32M
    # ==============================================================

    a.MUL(3, 1, 2)
    a.MULH(3, 1, 2)
    a.MULHSU(3, 1, 2)
    a.MULHU(3, 1, 2)
    a.DIV(3, 1, 2)
    a.DIVU(3, 1, 2)
    a.REM(3, 1, 2)
    a.REMU(3, 1, 2)

    # ==============================================================
    # IMMEDIATE ALU
    # ==============================================================

    a.ADDI(3, 1, 10)
    a.SLLI(3, 1, 2)
    a.SLTI(3, 1, 10)
    a.SLTIU(3, 1, 10)
    a.XORI(3, 1, 0x55)
    a.SRLI(3, 1, 2)
    a.SRAI(3, 1, 2)
    a.ORI(3, 1, 0x55)
    a.ANDI(3, 1, 0x55)

    # ==============================================================
    # U-TYPE
    # ==============================================================

    a.LUI(3, 0x12345)
    a.AUIPC(4, 0)

    # ==============================================================
    # LOADS
    # ==============================================================
    
    # Byte loads: byte accesses can legally use any byte offset
    a.LB(3, 0, 10)       # READ + offset_0
    a.LB(3, 1, 10)       # READ + offset_1
    a.LB(3, 2, 10)       # READ + offset_2
    a.LB(3, 3, 10)       # READ + offset_3
    
    a.LBU(3, 0, 10)      # READ + offset_0
    a.LBU(3, 1, 10)      # READ + offset_1
    a.LBU(3, 2, 10)      # READ + offset_2
    a.LBU(3, 3, 10)      # READ + offset_3
    
    # Halfword loads: naturally aligned addresses
    a.LH(3, 0, 10)       # READ + offset_0
    a.LH(3, 2, 10)       # READ + offset_2
    
    a.LHU(3, 0, 10)      # READ + offset_0
    a.LHU(3, 2, 10)      # READ + offset_2
    
    # Word load: naturally aligned
    a.LW(3, 0, 10)       # READ + offset_0

    # ==============================================================
    # STORES / ALL WSTRB PATTERNS
    # ==============================================================

    # SB
    a.SB(1, 0, 10)       # 0001
    a.SB(1, 1, 10)       # 0010
    a.SB(1, 2, 10)       # 0100
    a.SB(1, 3, 10)       # 1000

    # SH
    a.SH(1, 4, 10)       # 0011
    a.SH(1, 6, 10)       # 1100

    # SW
    a.SW(1, 8, 10)       # 1111
    
    a.LUI(10, 0x20)          # x10 = DMEM_BASE
    a.ADDI(1, 0, 0xA5)       # x1 = 0x000000A5

    # SB:
    #   WDATA = A5A5A5A5
    #   WSTRB = 0001
    a.SB(1, 0, 10)

    # SW:
    #   WDATA = A5A5A5A5
    #   WSTRB = 1111
    #
    # Same address, same WDATA, different WSTRB.
    a.SW(1, 0, 10)

    # Read final result.
    a.LW(2, 0, 10)
    a.SW(2, 4, 10)

    # ==============================================================
    # BRANCHES
    # ==============================================================

    # BEQ taken
    a.BEQ(1, 1, "after_beq")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_beq")

    # BNE taken
    a.BNE(1, 2, "after_bne")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_bne")

    # BLT taken
    a.BLT(1, 2, "after_blt")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_blt")

    # BGE taken
    a.BGE(1, 2, "after_bge")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_bge")

    # BLTU taken
    a.BLTU(1, 2, "after_bltu")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_bltu")

    # BGEU taken
    a.BGEU(1, 2, "after_bgeu")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_bgeu")

    # ==============================================================
    # JAL
    # ==============================================================

    a.JAL(0, "after_jal")
    a.ADDI(20, 0, 0xBAD)
    a.label("after_jal")

    # ==============================================================
    # JALR
    # ==============================================================

    # Put address of next target into x5.
    # AUIPC gives current PC.
    a.AUIPC(5, 0)
    a.JALR(0, 5, 8)

    # skipped
    a.ADDI(20, 0, 0xBAD)

    # ==============================================================
    # FENCE
    # ==============================================================

    a._ops.append(("I", (
        0x000,
        0,
        0b000,
        0,
        0x0F
    )))

    # ==============================================================
    # EBREAK
    # ==============================================================

    a.EBREAK()

    # Terminal loop
    a.label("done")
    a.JAL_SELF()

    words = a.finalize()

    return words, [], a.labels["done"]


def prog_hazard_fwd():
    """Back-to-back RAW hazards: every instruction consumes the previous
    instruction's result with zero cycles of separation, plus one
    explicit load-use hazard (LW immediately followed by a consumer)."""
    a = Asm(BOOT_ROM_BASE)
    a.ADDI(1, 0, 5)
    a.ADD(2, 1, 1)     # x2 = x1+x1, forwarded from EX
    a.ADD(3, 2, 1)     # x3 = x2+x1, x2 forwarded from EX, x1 from further back
    a.SUB(4, 3, 2)     # x4 = x3-x2
    a.LUI(10, 0x20)    # x10 = DMEM_BASE
    a.SW(4, 0, 10)     # store x4 so it's DMEM-visible before the load-use test
    a.LW(5, 0, 10)     # load-use hazard: x5 immediately consumed below
    a.ADDI(6, 5, 1)    # x6 = x5 + 1 (must stall for dmem_rvalid, then forward)
    a.SW(6, 4, 10)     # signature
    a.LUI(10, 0x20)
    a.ADDI(1, 0, 0x123)
    a.SW(1, 0, 10)
    a.LW(2, 0, 10)
# x11 = 0x00028000
# bit15 = 1, still inside DMEM
    a.LUI(11, 0x28)

    a.SW(1, 0, 11)
    a.LW(2, 0, 11)

# Return to bit15 = 0
    a.SW(1, 0, 10)
    a.LW(2, 0, 10)
    a.BEQ(2, 2, "taken")

    a.ADDI(20, 0, 0xBAD)

    a.label("taken")

    a.ADDI(3, 0, 0x5DE)
    a.SW(3, 4, 10)
    a.label("done")
    a.JAL_SELF()
    
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_muldiv_corner():
    """MUL/DIV/REM corner cases per the RISC-V spec's mandated special
    cases: INT_MIN / -1 overflow, division by zero (signed+unsigned),
    REM by zero. Each result is stored to a distinct signature word."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(1, 0x80000)      # x1 = 0x80000000 (INT_MIN), LUI imm20=0x80000
    a.ADDI(2, 0, -1)       # x2 = -1
    a.DIV(3, 1, 2)         # x3 = INT_MIN / -1  => INT_MIN (overflow case)
    a.REM(4, 1, 2)         # x4 = INT_MIN % -1  => 0
    a.ADDI(5, 0, 0)        # x5 = 0
    a.DIVU(6, 1, 5)        # x6 = unsigned divide by zero => 0xFFFFFFFF
    a.REM(7, 2, 5)         # x7 = -1 % 0        => -1 (dividend, per spec)
    a.LUI(10, 0x20)        # x10 = DMEM_BASE
    a.SW(3, 0, 10)
    a.SW(4, 4, 10)
    a.SW(6, 8, 10)
    a.SW(7, 12, 10)
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_csr_exception():
    """Point mtvec at a handler, ECALL into it, handler stores a marker
    and MRETs back; confirms trap entry/exit is bus-visible through its
    memory side-effects (blackbox scoreboard can't see mepc/mcause
    directly, only what the handler chooses to store)."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)              # x10 = DMEM_BASE (signature pointer, reused in handler)
    a.ADDI(1, 0, 0x40)           # x1 = handler byte offset from BOOT_ROM_BASE (patched below if needed)
    a.CSRRW(0, CSR_MTVEC, 1)     # mtvec = x1 (rd=x0, discard old value)
    a.ADDI(2, 0, 0xAAA)          # marker value, pre-trap
    a.SW(2, 0, 10)               # mem[DMEM_BASE+0] = 0xAAA (proves normal execution reached here)
    a.ECALL()                    # -> traps to mtvec
    a.label("post_ecall")
    a.ADDI(3, 0, 0xCCC)          # only reached after MRET brings us back here
    a.SW(3, 8, 10)               # mem[DMEM_BASE+8] = 0xCCC (proves MRET returned correctly)
    a.label("done")
    a.JAL_SELF()

    # Handler must sit at a fixed, known offset (mtvec is written as a
    # plain immediate above, not label-relative) -- pad up to that
    # offset with NOPs, then emit the handler, then MRET back to
    # post_ecall.
    HANDLER_OFFSET = 0x40
    while 4 * len(a._ops) < HANDLER_OFFSET:
        a.NOP()
    a.label("handler")
    a.ADDI(4, 0, 0xBBB)
    a.SW(4, 4, 10)                # mem[DMEM_BASE+4] = 0xBBB (proves handler ran)
    # This golden model's take_trap() sets mepc = the retiring instruction's
    # OWN pc (a deliberate deviation from the usual "next instruction"
    # convention -- see GM2/README.md section 2). A bare MRET would
    # therefore re-execute the ECALL forever. Software must bump mepc by 4
    # itself before MRET, same as real M-mode ECALL handlers do.
    a.CSRRS(5, CSR_MEPC, 0)        # x5 = mepc (rs1=x0 -> pure read, no modify)
    a.ADDI(5, 5, 4)
    a.CSRRW(0, CSR_MEPC, 5)        # mepc = x5 + 4
    a.MRET()

    words = a.finalize()
    assert a.labels["handler"] == BOOT_ROM_BASE + HANDLER_OFFSET, \
        "handler landed at an unexpected address -- fix HANDLER_OFFSET padding"
    return words, [], a.labels["done"]


def prog_axi_burst_boundary():
    """Long straight-line ALU sequence (>16 instructions => spans more
    than 4 instruction-fetch bursts at 4 words/burst) to stress the
    burst boundary / redirect-during-burst path in prefetch_controller.
    No control-flow redirects until the very end, so any burst-boundary
    corruption shows up as a wrong final signature value."""
    a = Asm(BOOT_ROM_BASE)
    a.ADDI(1, 0, 1)
    for i in range(30):
        # x1 = x1 + x1 alternated with +1, kept small to avoid relying
        # on overflow semantics the assembler doesn't model specially
        if i % 2 == 0:
            a.ADD(1, 1, 1)
        else:
            a.ADDI(1, 1, 1)
    a.LUI(10, 0x20)
    a.SW(1, 0, 10)                 # signature: deterministic function of 30 fixed ops
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_random_regression(seed=1234, n_ops=40):
    """Seeded pseudo-random ALU op stream, each result stored to its own
    signature word, so the final-DMEM diff exercises a broad mix of
    opcodes in one run. Deliberately excludes DIV/REM by literal zero
    divisors chosen at random (edge cases are muldiv_corner's job, not
    this test's) and excludes branches/jumps (kept single-path so the
    instruction-fetch address stream stays trivially predictable)."""
    import random
    rng = random.Random(seed)
    ops = ["ADD", "SUB", "XOR", "OR", "AND", "SLL", "SRL", "SRA", "SLT", "SLTU",
           "MUL", "MULH", "MULHU", "DIVU", "REMU"]
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)  # x10 = DMEM_BASE, reserved as pointer -- never overwritten below
    # seed x1/x2 with nonzero values so DIVU/REMU by them isn't trivially 0
    a.ADDI(1, 0, 7)
    a.ADDI(2, 0, 3)
    store_off = 0
    for i in range(n_ops):
        op = rng.choice(ops)
        rd = 3 + (i % 4)          # cycle x3..x6, never touching x10
        rs1 = 1 + (i % 2)         # x1 or x2
        rs2 = 2 - (i % 2)         # x2 or x1
        getattr(a, op)(rd, rs1, rs2)
        a.SW(rd, store_off, 10)
        store_off += 4
        # occasionally feed a result back in as an operand for the next op
        if i % 5 == 4:
            a.ADDI(1, rd, 1)
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_branch_not_taken():
    """Every branch mnemonic's NOT-taken side (smoke.py only ever takes
    the branch), plus a backward-branch counting loop so negative
    immediate encoding/decoding on branches gets exercised at all."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)            # x10 = DMEM_BASE
    a.ADDI(1, 0, 5)
    a.ADDI(2, 0, 5)            # equal to x1
    a.ADDI(3, 0, 3)            # unequal, smaller
    a.ADDI(4, 0, -1)           # 0xFFFFFFFF: huge unsigned, negative signed
    a.ADDI(5, 0, 6)            # unequal, larger

    # BEQ not taken (5 != 3)
    a.BEQ(1, 3, "bad1")
    a.ADDI(20, 0, 1)
    a.label("bad1")

    # BNE not taken (5 == 5)
    a.BNE(1, 2, "bad2")
    a.ADDI(21, 0, 1)
    a.label("bad2")

    # BLT not taken (5 !< 5, signed)
    a.BLT(1, 2, "bad3")
    a.ADDI(22, 0, 1)
    a.label("bad3")

    # BGE not taken (-1 !>= 5, signed)
    a.BGE(4, 1, "bad4")
    a.ADDI(23, 0, 1)
    a.label("bad4")

    # BLTU not taken (5 !<u 5)
    a.BLTU(1, 2, "bad5")
    a.ADDI(24, 0, 1)
    a.label("bad5")

    # BGEU not taken (5 !>=u 6)
    a.BGEU(1, 5, "bad6")
    a.ADDI(25, 0, 1)
    a.label("bad6")

    # Backward-branch loop: decrement x6 5->0, negative-offset BNE taken 4x
    a.ADDI(6, 0, 5)
    a.label("loop_top")
    a.ADDI(6, 6, -1)
    a.BNE(6, 0, "loop_top")

    for i, reg in enumerate([20, 21, 22, 23, 24, 25, 6]):
        a.SW(reg, 4 * i, 10)   # signature words: all must read back as 1 (x6 as 0)

    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_jalr_lsb_clear():
    """Per spec, JALR's computed target address has bit0 forced to 0
    before use. Deliberately compute a target with bit0 set and verify
    the core lands one address lower (the well-defined even address),
    not on the odd address or off by a full instruction."""
    a = Asm(BOOT_ROM_BASE)
    a.AUIPC(5, 0)              # x5 = pc of THIS instruction (call it X)
    a.ADDI(5, 5, 4 * 4 + 1)    # x5 = X + 16 + 1 (LSB deliberately set)
    a.JALR(1, 5, 0)            # target = (X+17) & ~1 = X+16; link = pc_of_jalr+4 = X+12
    a.ADDI(20, 0, 0xBAD)       # X+12: must be SKIPPED (proves LSB really got cleared)
    a.label("target")         # X+16
    a.ADDI(21, 0, 0x5DE)       # only this must execute (imm is 12-bit)
    a.LUI(10, 0x20)
    a.SW(21, 0, 10)            # must be 0x5DE
    a.SW(1, 4, 10)             # link register: must equal X+12 (odd-target case)
    
    # First JALR target: low address, bit6 = 0
    a.LI(5, BOOT_ROM_BASE + 0x20)
    a.JALR(1, 5, 0)

    # Pad until 0x20
    while len(a._ops) < 8:
        a.NOP()

    # At 0x20
    a.LI(5, BOOT_ROM_BASE + 0x60)  # bit6 = 1
    a.JALR(1, 5, 0)

    # Pad until 0x60
    while len(a._ops) < 24:
        a.NOP()

    a.label("target_high")
    a.ADDI(3, 0, 0x333)

    # Return to a target where bit6 = 0
    a.LI(5, BOOT_ROM_BASE + 0x20)
    a.JALR(0, 5, 0)
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    assert a.labels["target"] == BOOT_ROM_BASE + 16
    return words, [], a.labels["done"]


def prog_store_load_fwd():
    """Back-to-back store immediately followed by a load of the same
    address (RAW hazard through DMEM, zero cycles of separation),
    across several size/overlap combinations the existing tests don't
    hit together: SW->LW same word, SB->LBU same byte, SH->LW same
    word (mixed size), and two back-to-back SW's to the same word
    where only the second must be visible."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)

    a.ADDI(1, 0, 0x7E)
    a.SW(1, 0, 10)
    a.LW(2, 0, 10)             # immediate reload, same word
    a.SW(2, 4, 10)             # expect 0x7E

    a.ADDI(3, 0, -1)           # 0xFF
    a.SB(3, 8, 10)
    a.LBU(4, 8, 10)            # immediate reload, same byte
    a.SW(4, 12, 10)            # expect 0xFF

    a.ADDI(5, 0, 0x234)
    a.SH(5, 16, 10)
    a.LW(6, 16, 10)            # word load right after halfword store
    a.SW(6, 20, 10)            # expect 0x00000234 (upper half was zero-inited; imm is 12-bit)

    a.ADDI(7, 0, 0x111)
    a.ADDI(8, 0, 0x222)
    a.SW(7, 24, 10)
    a.SW(8, 24, 10)            # second store, same address, zero cycles later
    a.LW(9, 24, 10)
    a.SW(9, 28, 10)            # expect 0x222 (second store must win)

    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_x0_writes():
    """Every legal way to target x0 as rd must be architecturally
    invisible: x0 reads back as 0 no matter what value was computed,
    and instructions with side effects other than the register
    writeback (like a load) must still fully execute -- only the
    writeback into x0 is dropped."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)
    a.ADDI(1, 0, 0x123)
    a.SW(1, 0, 10)

    a.ADDI(0, 0, 0x7FF)        # ADDI x0, x0, imm
    a.ADD(0, 1, 1)             # nonzero ALU result, discarded
    a.SUB(0, 1, 1)
    a.MUL(0, 1, 1)
    a.SLLI(0, 1, 5)
    a.LW(0, 0, 10)             # load into x0: bus transaction must still happen

    a.ADDI(2, 0, 0)            # x2 = x0 + 0
    a.SW(2, 4, 10)             # expect 0
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_timer_interrupt():
    """ASYNC CLINT timer interrupt (as opposed to csr_exception's SYNC
    ECALL): mtimecmp is armed to 0 so mtip is pending the instant
    mie.MTIE + mstatus.MIE go high, while the core is mid-way through
    an unrelated backward-branch loop. Verifies the interrupt lands
    correctly mid-loop, the handler's own mepc+4/MRET convention
    (documented deviation: mepc = retiring insn's own pc, same as the
    ECALL case) resumes the loop, and the loop then runs to a correct,
    untouched completion."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)                 # x10 = DMEM_BASE (signature pointer)

    a.ADDI(1, 0, 0x60)
    a.CSRRW(0, CSR_MTVEC, 1)        # mtvec = fixed handler offset

    a.LUI(11, 0x10014)              # x11 = ADDR_MTIMECMP_LOW (0x10014000)
    a.SW(0, 0, 11)                  # mtimecmp_low  = 0  -> mtip pending as soon as enabled
    a.SW(0, 4, 11)                  # mtimecmp_high = 0

    a.ADDI(2, 0, 0x80)
    # BUGFIX: this used to be `a.CSRRS(0, 1, 2)` -- CSRRS's 2nd argument
    # is a CSR *address*, and literal 1 is not CSR_MIE (0x304). csr.py
    # silently no-ops writes to unrecognized CSR addresses, so the
    # original code never actually set mie.MTIE: the interrupt was
    # never enabled, and the test passed only because "ran the loop to
    # completion uninterrupted" and "interrupt fired then resumed the
    # loop correctly" happen to produce the same final DMEM signature.
    # This silently defeated the entire point of the test.
    a.CSRRS(0, 0x304, 2)          # mie.MTIE = 1
    a.ADDI(3, 0, 0x8)
    a.CSRRS(0, 0x300, 3)      # mstatus.MIE = 1 -- interrupt becomes takeable here

    a.ADDI(4, 0, 20)                # unrelated backward-branch loop; the
    a.label("loop_top")             # interrupt must land somewhere inside
    a.ADDI(4, 4, -1)                # this and resume it correctly after MRET
    a.BNE(4, 0, "loop_top")

    a.SW(4, 8, 10)                  # loop signature: must be exactly 0
    a.ADDI(5, 0, 0x5DE)
    a.SW(5, 12, 10)                 # proves control returned to normal stream
    a.label("done")
    a.JAL_SELF()

    HANDLER_OFFSET = 0x60
    while 4 * len(a._ops) < HANDLER_OFFSET:
        a.NOP()
    a.label("handler")
    a.ADDI(6, 0, 0x7ED)
    a.SW(6, 0, 10)                  # handler signature 0x7ED: proves handler ran

    a.ADDI(7, 0, -1)
    a.SW(7, 0, 11)                  # disarm: mtimecmp = 0xFFFFFFFF_FFFFFFFF
    a.SW(7, 4, 11)                  # so it can't refire on the way out
    a.CSRRS(8, CSR_MEPC, 0)
    a.ADDI(8, 8, 4)                 # same +4 skip csr_exception uses
    a.CSRRW(0, CSR_MEPC, 8)
    a.MRET()

    words = a.finalize()
    assert a.labels["handler"] == BOOT_ROM_BASE + HANDLER_OFFSET
    return words, [], a.labels["done"]


def prog_burst_redirect_loop():
    """axi_burst_boundary.py stresses straight-line fetch across burst
    boundaries but never redirects mid-burst. This loops a body that
    spans several bursts (4 words/burst) with a taken backward branch
    at the end of every iteration, forcing prefetch_controller to
    flush/redirect while a later burst may still be outstanding."""
    a = Asm(BOOT_ROM_BASE)
    a.ADDI(1, 0, 8)            # iteration count
    a.ADDI(2, 0, 0)            # accumulator
    a.label("loop_top")
    for _ in range(10):        # body spans 3 fetch bursts (12 instrs / 4 per burst)
        a.ADDI(2, 2, 1)
    a.ADDI(1, 1, -1)
    a.BNE(1, 0, "loop_top")    # backward redirect, every iteration, mid/post-burst

    a.LUI(10, 0x20)
    a.SW(2, 0, 10)             # expect 8*10 = 80
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]



def prog_wide_regfile_toggle():
    """Toggle-coverage booster #1 -- register-field bits.

    Every other directed program only ever names registers in roughly
    the x1..x11 range. rs1/rs2/rd are 5-bit fields at fixed positions in
    every instruction word (bits [19:15] / [24:20] / [11:7]), so bit 4
    of each of those fields (instruction bits 19, 24, 11) is 1 only when
    a register number >=16 is used. The coverage report shows
    instruction bit 19 (rs1[4]) permanently stuck at 0 across the whole
    regression -- no program ever uses x16..x31 as a source register.

    This program walks every general-purpose register x1..x31 through
    R-type, I-type, load/store, branch and JALR instructions, using
    high (>=16) and low (<16) registers interchangeably as rs1/rs2/rd,
    so every register-field bit toggles 0->1 and 1->0 repeatedly.
    """
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)          # x10 = DMEM_BASE, reserved as store pointer

    # Seed every register except x0 (hardwired) and x10 (store pointer)
    # with a small distinct nonzero value.
    val = 1
    for r in range(1, 32):
        if r == 10:
            continue
        a.ADDI(r, 0, val)
        val = (val % 100) + 1

    hi_regs = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    lo_regs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15]

    store_off = 0
    # R-type: alternate which operand/rd is high vs low so rs1[4], rs2[4]
    # and rd[4] each see both a 0 and a 1 many times over, not just once.
    for i, hi in enumerate(hi_regs):
        lo = lo_regs[i % len(lo_regs)]
        rd_hi = hi_regs[(i + 1) % len(hi_regs)]
        a.ADD(rd_hi, hi, lo)     # rs1=hi, rs2=lo, rd=hi
        a.SW(rd_hi, store_off, 10); store_off += 4
        a.SUB(lo_regs[(i + 2) % len(lo_regs)], lo, hi)   # rs1=lo, rs2=hi, rd=lo
        a.SW(lo_regs[(i + 2) % len(lo_regs)], store_off, 10); store_off += 4
        a.XOR(hi, hi, lo)        # rs1=hi, rs2=lo, rd=hi (self)
        a.SW(hi, store_off, 10); store_off += 4

    # I-type ALU with rs1 walking through every high register.
    for r in hi_regs:
        a.ADDI(3, r, 0x55)
        a.SW(3, store_off, 10); store_off += 4

    # Load/store with the *base* register (rs1) itself >=16.
    a.ADD(16, 10, 0)             # x16 = DMEM_BASE (valid pointer in a hi reg)
    a.SW(1, 0, 16)               # store, base=hi
    a.LW(17, 0, 16)              # load, base=hi, rd=hi
    a.SW(17, store_off, 10); store_off += 4

    # Store with the *data* register (rs2) >=16.
    a.SW(18, store_off, 10); store_off += 4

    # Branch with both operands >=16.
    a.BEQ(20, 20, "hi_taken")
    a.ADDI(9, 0, 0xBAD)
    a.label("hi_taken")
    a.BLT(19, 21, "hi_taken2")
    a.ADDI(9, 0, 0xBAD)
    a.label("hi_taken2")

    # JALR with rs1 >=16.
    a.AUIPC(22, 0)
    a.JALR(0, 22, 8)
    a.ADDI(9, 0, 0xBAD)

    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_dmem_bit_walk():
    """Toggle-coverage booster #2 -- data-path bit diversity.

    Every existing program only ever stores small immediates (<=12
    bits) or ALU results derived from them, so most individual bits of
    dmem_rdata / RDATA_D never see both a 0 and a 1 -- the report shows
    roughly half the data-path bits permanently stuck. This program
    stores an explicit walking-ones, walking-zeros, and alternating
    (0x55555555 / 0xAAAAAAAA) pattern set, then immediately reads each
    one back with LW *and* with LB/LBU/LH/LHU at every byte offset, so
    every bit of every byte lane toggles in both directions in a known
    sequence.
    """
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)     # x10 = DMEM_BASE
    a.SW(1, 0, 10)
    a.LW(2, 0, 10)
    
    # bit 9
    a.LI(11, 0x00020200)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 10
    a.LI(11, 0x00020400)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 11
    a.LI(11, 0x00020800)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 12
    a.LI(11, 0x00021000)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 13
    a.LI(11, 0x00022000)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 14
    a.LI(11, 0x00024000)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # bit 15
    a.LI(11, 0x00028000)
    a.SW(1, 0, 11)
    a.LW(2, 0, 11)
    
    # Return to low address so all bits get 1->0 as well.
    a.SW(1, 0, 10)
    a.LW(2, 0, 10)
    
    a.LUI(10, 0x20)     # x10 = DMEM_BASE
   
    
    off = 0
    

    def store_and_reload(value, rd_store=1, rd_load_base=2):
        nonlocal off
        a.LI(rd_store, value)
        a.SW(rd_store, off, 10)
        # Full-word reload.
        a.LW(rd_load_base, off, 10)
        # Every byte lane, signed and unsigned.
        a.LB(rd_load_base + 1, off + 0, 10)
        a.LB(rd_load_base + 1, off + 1, 10)
        a.LB(rd_load_base + 1, off + 2, 10)
        a.LB(rd_load_base + 1, off + 3, 10)
        a.LBU(rd_load_base + 1, off + 0, 10)
        a.LBU(rd_load_base + 1, off + 1, 10)
        a.LBU(rd_load_base + 1, off + 2, 10)
        a.LBU(rd_load_base + 1, off + 3, 10)
        a.LH(rd_load_base + 1, off + 0, 10)
        a.LH(rd_load_base + 1, off + 2, 10)
        a.LHU(rd_load_base + 1, off + 0, 10)
        a.LHU(rd_load_base + 1, off + 2, 10)
        off += 4

    # Walking ones: exactly one bit set, sweeping through all 32
    # positions -- guarantees every bit sees a 0->1 (and, on the next
    # pattern, a 1->0) transition at least once.
    for bit in range(32):
        store_and_reload(1 << bit)

    # Walking zeros: the complement sweep, so every bit also sees a
    # 1->0 immediately followed by 0->1 in the *other* direction from
    # a mostly-1s background (catches lane-mux bugs the walking-ones
    # sweep alone could miss).
    for bit in range(32):
        store_and_reload(0xFFFFFFFF ^ (1 << bit))

    # Alternating patterns and the all-0 / all-1 extremes.
    for pattern in (0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA,
                    0x0F0F0F0F, 0xF0F0F0F0, 0x00FF00FF, 0xFF00FF00):
        store_and_reload(pattern)
    # ---------------------------------------------------------------
    # AXI data-address/strobe toggle coverage
    # ---------------------------------------------------------------

    # x11 = CLINT MSIP address.
    #
    # This is deliberately written with zero. We are NOT enabling
    # MSIP, so this does not generate an interrupt. It is only being
    # used as a legal high-address AXI transaction.
    a.LUI(11, 0x10010)          # 0x10010000

    a.SW(0, 0, 11)              # AWADDR_D = 0x10010000
    a.LW(12, 0, 11)             # ARADDR_D = 0x10010000
    
    # ---------------------------------------------------------------
    # Additional AXI DATA ADDRESS toggle coverage
    # ---------------------------------------------------------------
    #
    # Current DMEM accesses mostly use offsets below 0x400.
    #
    # We deliberately jump across:
    #
    #   bit 9  : 0x0000 -> 0x0200
    #   bit 15 : 0x0000 -> 0x8000
    #
    # while remaining in the DMEM region.
    #
    # NOTE:
    #   These addresses must be legal according to memory.py / SoC map.
    #

    # Toggle dmem_addr[9].
    a.SW(1, 0x0200, 10)
    a.LW(2, 0x0200, 10)

    a.SW(1, 0x0000, 10)
    a.LW(2, 0x0000, 10)

    # Toggle dmem_addr[15].
    #
    # 0x0000 -> bit15 = 0
    # 0x8000 -> bit15 = 1
    a.SW(1, 0x8000, 10)
    a.LW(2, 0x8000, 10)

    a.SW(1, 0x0000, 10)
    a.LW(2, 0x0000, 10)

    # Return to normal DMEM address.
    # This creates transitions between:
    #
    #   0x10010000
    #   0x00020xxx
    #
    # which toggles address bits 28, 17 and 16.
    a.LUI(11, 0x20)

    # ---------------------------------------------------------------
    # Force all four byte-address bits through the AXI write address.
    # ---------------------------------------------------------------

    a.LI(1, 0xA5)

    a.SB(1, 0x300, 10)           # AWADDR_D[1:0] = 00, WSTRB = 0001
    a.SB(1, 0x301, 10)           #                 01,        = 0010
    a.SB(1, 0x302, 10)           #                 10,        = 0100
    a.SB(1, 0x303, 10)           #                 11,        = 1000


    a.SH(1, 0x304, 10)           # WSTRB = 0011
    a.SH(1, 0x306, 10)           # WSTRB = 1100

    # Full word.
    a.SW(1, 0x308, 10)           # WSTRB = 1111

    # And read the unaligned addresses back.
    a.LB(2, 0x300, 10)
    a.LB(2, 0x301, 10)
    a.LB(2, 0x302, 10)
    a.LB(2, 0x303, 10)

    a.LH(2, 0x304, 10)
    a.LH(2, 0x306, 10)
    a.label("done")
    a.JAL_SELF()
    words = a.finalize()
    return words, [], a.labels["done"]


def prog_imem_sram_reach():
    boot = Asm(BOOT_ROM_BASE)

    boot.LUI(10, 0x20)
    boot.ADDI(1, 0, 0x111)
    boot.SW(1, 0, 10)

    # Redirect to 0x10004, not 0x10000.
    # This makes ARADDR_I[2] = 1.
    boot.JAL_ABS(0, BOOT_ROM_BASE + 4)
    boot_words = boot.finalize()

    sram = Asm(BOOT_ROM_BASE)

    # Address 0x10000.
    # We'll return here later, so ARADDR_I[2] also becomes 0.
    sram.JAL_ABS(0, BOOT_ROM_BASE + 0x20)

    # Address 0x10004 -- first real SRAM entry.
    sram.ADDI(2, 0, 0x222)
    sram.LUI(10, 0x20)
    sram.SW(2, 4, 10)

    # Redirect back to 0x10000.
    sram.JAL_ABS(0, BOOT_ROM_BASE)

    # Pad until 0x10020.
    while len(sram._ops) < 8:
        sram.NOP()

    # 0x10020
    sram.LUI(10, 0x20)
    sram.ADDI(3, 0, 0)
    sram.SW(3, 8, 10)

    sram.label("done")
    sram.JAL_SELF()

    sram_words = sram.finalize()

    return (
        boot_words,
        [],
        sram.labels["done"],
        [(BOOT_ROM_BASE, sram_words)]
    )

def prog_imem_bit12_toggle():
    boot = Asm(BOOT_ROM_BASE)

    # Start at 0x0000.
    boot.ADDI(1, 0, 0x111)

    # Jump to 0x1000.
    # This makes ARADDR_I[12] = 1.
    boot.JAL_ABS(0, BOOT_ROM_BASE + 0x1000)
    boot_words = boot.finalize()

    # Code located at 0x1000.
    high = Asm(BOOT_ROM_BASE + 0x1000)

    high.ADDI(2, 0, 0x222)

    # Return to 0x0008.
    # This makes ARADDR_I[12] go back to 0.
    high.JAL_ABS(0, BOOT_ROM_BASE + 8)

    high.label("done")
    high.JAL_SELF()

    high_words = high.finalize()

    return (
        boot_words,
        [],
        high.labels["done"],
        [(BOOT_ROM_BASE + 0x1000, high_words)]
    )


def prog_msip_software_irq():
    """Toggle-coverage booster #4 -- software-interrupt CSR/MMIO path.

    timer_interrupt.py already exercises mtimecmp/MTIE/MTIP end-to-end,
    but nothing in the suite ever writes CLINT's MSIP register
    (0x1001_0000) or sets mie.MSIE, so the whole software-interrupt leg
    of csr.py's mip/mie/priority logic (and the mip.MSIP bit itself) has
    never been exercised. This mirrors prog_timer_interrupt()'s
    structure exactly, but arms MSIP instead of mtimecmp.

    NOTE (scope): this only reaches the *architectural* mip.MSIP path
    modeled by csr.py/clint.py. The RTL toggle report's irq_timer_i /
    irq_software_i / irq_external_i top_module ports are driven live,
    per-cycle, straight from the testbench's IRQ agent
    (golden_server.py: self.iss.state.software_irq = self.irq["software"]),
    completely independent of the instruction stream. No gen_imem
    program can toggle those three specific ports -- that requires a
    testbench-side (UVM sequence / virtual interface) change. See the
    accompanying note for a sample sequence.
    """
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)                  # x10 = DMEM_BASE (signature pointer)

    a.ADDI(1, 0, 0x50)
    a.CSRRW(0, CSR_MTVEC, 1)         # mtvec = fixed handler offset

    a.LI(11, ADDR_MSIP)              # x11 = CLINT MSIP register address
    a.ADDI(12, 0, 1)
    a.SW(12, 0, 11)                  # MSIP = 1 -> mip.MSIP pending immediately

    a.ADDI(2, 0, 0x08)
    a.CSRRS(0, CSR_MIE, 2)           # mie.MSIE = 1
    a.ADDI(3, 0, 0x8)
    a.CSRRS(0, CSR_MSTATUS, 3)       # mstatus.MIE = 1 -- takeable here

    a.ADDI(4, 0, 20)                 # unrelated backward-branch loop, same
    a.label("loop_top")              # shape as timer_interrupt.py so the
    a.ADDI(4, 4, -1)                 # two tests are directly comparable
    a.BNE(4, 0, "loop_top")

    a.SW(4, 8, 10)                   # loop signature: must be exactly 0
    a.ADDI(5, 0, 0x5DE)
    a.SW(5, 12, 10)                  # proves control returned to normal stream
    a.label("done")
    a.JAL_SELF()

    HANDLER_OFFSET = 0x50
    while 4 * len(a._ops) < HANDLER_OFFSET:
        a.NOP()
    a.label("handler")
    a.ADDI(6, 0, 0x7EE)
    a.SW(6, 0, 10)                   # handler signature: proves handler ran
    a.CSRRW(0, CSR_MIE, 0)  # Disable further interrupts before MRET
    a.SW(0, 0, 11)                   # disarm: MSIP = 0 so it can't refire
    a.CSRRS(7, CSR_MEPC, 0)
    a.ADDI(7, 7, 4)
    a.CSRRW(0, CSR_MEPC, 7)
    a.MRET()

    words = a.finalize()
    assert a.labels["handler"] == BOOT_ROM_BASE + HANDLER_OFFSET
    return words, [], a.labels["done"]

def prog_far_branch_toggle():
    a = Asm(BOOT_ROM_BASE)

    a.ADDI(1, 0, 1)

    # Taken branch to a relatively far location.
    a.BEQ(1, 1, "far_target")

    a.ADDI(20, 0, 0xBAD)

    # Pad until target around +0x400.
    while len(a._ops) < (0x400 // 4):
        a.NOP()

    a.label("far_target")
    a.ADDI(2, 0, 0x222)

    a.label("done")
    a.JAL_SELF()

    words = a.finalize()
    return words, [], a.labels["done"]
    
def prog_store_wstrb_transition():
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)

    # Same effective address, same WDATA=0,
    # but different write strobes.

    a.SB(0, 0, 10)     # WDATA 00000000, WSTRB 0001
    a.SW(0, 0, 10)     # WDATA 00000000, WSTRB 1111

    a.LW(2, 0, 10)

    a.label("done")
    a.JAL_SELF()

    words = a.finalize()
    return words, [], a.labels["done"]

def prog_live_irq(irq_kind):
    """Program for a UVM-driven top_module IRQ input.

    UVM asserts the selected live IRQ after 120 cycles. The ISS receives the
    same level through golden_irq(). Handler stores mcause at DMEM_BASE.
    """
    masks = {"timer": 0x080, "software": 0x008,
             "external": 0x800, "priority": 0x888}
    if irq_kind not in masks:
        raise ValueError("unsupported live IRQ kind: %s" % irq_kind)

    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)                  # x10 = DMEM_BASE
    a.ADDI(1, 0, 0x80)
    a.CSRRW(0, CSR_MTVEC, 1)         # direct trap vector at 0x80
    if masks[irq_kind] <= 0x7ff:
        a.ADDI(2, 0, masks[irq_kind])
    else:
        a.LI(2, masks[irq_kind])
    a.CSRRW(0, CSR_MIE, 2)           # enable selected local interrupt(s)
    a.ADDI(3, 0, 8)
    a.CSRRS(0, CSR_MSTATUS, 3)       # global MIE

    a.label("irq_loop")
    a.ADDI(4, 4, 1)
    a.JAL(0, "irq_loop")            # instruction-only loop, no data traffic

    HANDLER_OFFSET = 0x80
    while 4 * len(a._ops) < HANDLER_OFFSET:
        a.JAL(0, "irq_loop")
    a.label("irq_handler")
    a.CSRRS(6, CSR_MCAUSE, 0)
    a.SW(6, 0, 10)                   # signature = mcause
    a.CSRRW(0, CSR_MIE, 0)  # Disable further interrupts before MRET
    a.CSRRS(7, CSR_MEPC, 0)
    a.ADDI(7, 7, 4)                  # RTL/ISS convention used by existing tests
    a.CSRRW(0, CSR_MEPC, 7)
    a.MRET()

    words = a.finalize()
    assert a.labels["irq_handler"] == BOOT_ROM_BASE + HANDLER_OFFSET
    return words, [], a.labels["irq_loop"]


def prog_irq_masking():
    """External IRQ is pending while global MIE=0, then accepted after MIE=1."""
    a = Asm(BOOT_ROM_BASE)
    a.LUI(10, 0x20)
    a.ADDI(1, 0, 0x100)
    a.CSRRW(0, CSR_MTVEC, 1)
    a.LI(2, 0x800)
    a.CSRRW(0, CSR_MIE, 2)          # local MEIE enabled
    a.ADDI(4, 0, 0)
    a.ADDI(5, 0, 10)
    a.label("masked_loop")
    a.ADDI(4, 4, 1)
    a.BNE(4, 5, "masked_loop")    # IRQ remains pending, global MIE is still 0
    a.ADDI(3, 0, 8)
    a.CSRRS(0, CSR_MSTATUS, 3)      # now accept pending MEI

    HANDLER_OFFSET = 0x100
    while 4 * len(a._ops) < HANDLER_OFFSET:
        a.JAL(0, "masked_loop")
    a.label("irq_handler")
    a.CSRRS(6, CSR_MCAUSE, 0)
    a.SW(6, 0, 10)
    a.CSRRW(0, CSR_MIE, 0)  # Disable further interrupts before MRET
    a.CSRRS(7, CSR_MEPC, 0)
    a.ADDI(7, 7, 4)
    a.CSRRW(0, CSR_MEPC, 7)
    a.MRET()
    words = a.finalize()
    assert a.labels["irq_handler"] == BOOT_ROM_BASE + HANDLER_OFFSET
    return words, [], a.labels["masked_loop"]



def prog_irq_timer(): return prog_live_irq("timer")
def prog_irq_software(): return prog_live_irq("software")
def prog_irq_external(): return prog_live_irq("external")
def prog_irq_priority(): return prog_live_irq("priority")


PROGRAMS = {
    "smoke": prog_smoke,
    "hazard_fwd": prog_hazard_fwd,
    "muldiv_corner": prog_muldiv_corner,
    "csr_exception": prog_csr_exception,
    "axi_burst_boundary": prog_axi_burst_boundary,
    "random_regression": prog_random_regression,
    "branch_not_taken": prog_branch_not_taken,
    "jalr_lsb_clear": prog_jalr_lsb_clear,
    "store_load_fwd": prog_store_load_fwd,
    "x0_writes": prog_x0_writes,
    "timer_interrupt": prog_timer_interrupt,
    "burst_redirect_loop": prog_burst_redirect_loop,
    "wide_regfile_toggle": prog_wide_regfile_toggle,
    "dmem_bit_walk": prog_dmem_bit_walk,
    "imem_sram_reach": prog_imem_sram_reach,
    "msip_software_irq": prog_msip_software_irq,
    "imem_bit12_toggle": prog_imem_bit12_toggle,
    "far_branch_toggle": prog_far_branch_toggle,
    "store_wstrb_transition": prog_store_wstrb_transition,
    "irq_timer": prog_irq_timer,
    "irq_software": prog_irq_software,
    "irq_external": prog_irq_external,
    "irq_priority": prog_irq_priority,
    "irq_masking": prog_irq_masking,
}



def emit_images(name, words, dmem_init_words, extra_instr_regions=None):
    """extra_instr_regions: optional list of (base_addr, words) for
    programs that place code in more than one memory region (e.g. Boot
    ROM + Instruction SRAM), so the emitted .instr.mem carries multiple
    '@'-addressed blocks that the testbench's readmemh call loads in
    one shot."""
    os.makedirs(OUT_DIR, exist_ok=True)
    regions = [(BOOT_ROM_BASE, words)]
    if extra_instr_regions:
        regions.extend(extra_instr_regions)
    write_readmemh_regions(os.path.join(OUT_DIR, "%s.instr.mem" % name), regions)
    if dmem_init_words:
        write_readmemh_regions(os.path.join(OUT_DIR, "%s.dmem_init.mem" % name), [(DMEM_BASE, dmem_init_words)])
    else:
        write_readmemh_regions(os.path.join(OUT_DIR, "%s.dmem_init.mem" % name), [(DMEM_BASE, [0])])


def _normalize_program_result(result):
    """Program functions historically return a 3-tuple
    (words, dmem_init, done_addr). Toggle-coverage programs that need a
    second instruction region (see prog_imem_sram_reach below) return a
    4-tuple with an extra_instr_regions list on the end. Accept both so
    existing PROGRAMS entries don't need to change."""
    if len(result) == 3:
        words, dmem_init, done_addr = result
        return words, dmem_init, done_addr, []
    return result


def main():
    names = sys.argv[1:] if len(sys.argv) > 1 else list(PROGRAMS.keys())
    for name in names:
        if name not in PROGRAMS:
            print("unknown program %r -- known: %s" % (name, list(PROGRAMS.keys())), file=sys.stderr)
            sys.exit(1)
        print("generating image %s ..." % name)
        words, dmem_init, _done_addr, extra_regions = _normalize_program_result(PROGRAMS[name]())
        emit_images(name, words, dmem_init, extra_regions)
        print("  %d instruction words" % len(words))


if __name__ == "__main__":
    main()