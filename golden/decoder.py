"""
decoder.py

Instruction field extraction (Section 3), immediate generation
(Section 4), and decode helpers that turn a raw 32-bit instruction word
into a Mnemonic + operand fields for execute.py to dispatch on.

IMMEDIATE GENERATION IS TRANSCRIBED LITERALLY FROM SECTION 4.
Each imm_*() function below mirrors the spec's pseudocode bit-for-bit
(same field order, same shifts, same sext width) rather than being
rewritten into a more "idiomatic" or generalized form. This is
deliberate: the point is to make each function trivially auditable
against the spec text, not to produce the shortest possible code.

ASSUMPTION (not given explicitly by the spec): opcode / funct3 / funct7
*values*. Section 3 only defines where these fields sit in the
instruction word, and Section 5 only lists mnemonics -- neither section
gives the actual 7-bit opcode or funct3/funct7 encodings. Since Section
5's instruction list is exactly the standard RV32IM + Zicsr + M-mode
privileged subset (no custom mnemonics, no reduced/extended set), this
module assumes the standard RISC-V base opcode map. If the RTL uses a
different encoding, only the constants in the "Opcode / funct3 / funct7
constants" section below need to change -- decode() itself doesn't
otherwise care about the numeric values.
"""

from dataclasses import dataclass
from enum import Enum, auto

from cpu_state import sext

# ------------------------------------------------------------------------
# Generic bit extraction
# ------------------------------------------------------------------------

def bits(value: int, hi: int, lo: int) -> int:
    """Extract inst[hi:lo] inclusive, matching the spec's [hi:lo] slice
    notation used throughout Sections 3 and 4."""
    width = hi - lo + 1
    return (value >> lo) & ((1 << width) - 1)


# ------------------------------------------------------------------------
# Instruction field extraction (Section 3)
# ------------------------------------------------------------------------

@dataclass
class InstructionFields:
    """Raw fields pulled directly out of the instruction word, per
    Section 3. No interpretation (mnemonic, immediate meaning) happens
    here -- that's decode()'s job below."""
    opcode: int
    rd: int
    funct3: int
    rs1: int
    rs2: int
    funct7: int
    csr_addr: int


def extract_fields(inst: int) -> InstructionFields:
    """
    Section 3:
        opcode   = inst[6:0]
        rd       = inst[11:7]
        funct3   = inst[14:12]
        rs1      = inst[19:15]
        rs2      = inst[24:20]
        funct7   = inst[31:25]
        csr_addr = inst[31:20]
    """
    return InstructionFields(
        opcode=bits(inst, 6, 0),
        rd=bits(inst, 11, 7),
        funct3=bits(inst, 14, 12),
        rs1=bits(inst, 19, 15),
        rs2=bits(inst, 24, 20),
        funct7=bits(inst, 31, 25),
        csr_addr=bits(inst, 31, 20),
    )


# ------------------------------------------------------------------------
# Immediate generation (Section 4) -- transcribed literally, see module
# docstring.
# ------------------------------------------------------------------------

def imm_i(inst: int) -> int:
    """
    I-Type (Section 4):
        imm = sext(inst[31:20], 12)
    """
    return sext(bits(inst, 31, 20), 12)


def imm_s(inst: int) -> int:
    """
    S-Type (Section 4):
        imm = sext(
            (inst[31:25] << 5) |
            inst[11:7],
            12
        )
    """
    return sext(
        (bits(inst, 31, 25) << 5) |
        bits(inst, 11, 7),
        12
    )


def imm_b(inst: int) -> int:
    """
    B-Type (Section 4):
        imm = sext(
            (inst[31] << 12) |
            (inst[7] << 11) |
            (inst[30:25] << 5) |
            (inst[11:8] << 1),
            13
        )
    """
    return sext(
        (bits(inst, 31, 31) << 12) |
        (bits(inst, 7, 7) << 11) |
        (bits(inst, 30, 25) << 5) |
        (bits(inst, 11, 8) << 1),
        13
    )


def imm_u(inst: int) -> int:
    """
    U-Type (Section 4):
        imm = inst & 0xFFFFF000

    Note: NOT passed through sext() -- the spec's U-Type formula is a
    plain mask, not a sign-extension call, so this stays a mask here too
    even though the result happens to already look "sign-extended" for
    any value with bit31 set.
    """
    return inst & 0xFFFFF000


def imm_j(inst: int) -> int:
    """
    J-Type (Section 4):
        imm = sext(
            (inst[31] << 20) |
            (inst[19:12] << 12) |
            (inst[20] << 11) |
            (inst[30:21] << 1),
            21
        )
    """
    return sext(
        (bits(inst, 31, 31) << 20) |
        (bits(inst, 19, 12) << 12) |
        (bits(inst, 20, 20) << 11) |
        (bits(inst, 30, 21) << 1),
        21
    )


def imm_csr(inst: int) -> int:
    """
    CSR Immediate (Section 4):
        imm = rs1

    i.e. for CSRRWI/CSRRSI/CSRRCI, the "immediate" (zimm) is just the
    raw 5-bit rs1 field value itself, not sign-extended.
    """
    return bits(inst, 19, 15)


# ------------------------------------------------------------------------
# Opcode / funct3 / funct7 constants (ASSUMPTION -- see module docstring)
# ------------------------------------------------------------------------

OPCODE_LUI = 0b0110111
OPCODE_AUIPC = 0b0010111
OPCODE_JAL = 0b1101111
OPCODE_JALR = 0b1100111
OPCODE_BRANCH = 0b1100011
OPCODE_LOAD = 0b0000011
OPCODE_STORE = 0b0100011
OPCODE_OP_IMM = 0b0010011
OPCODE_OP = 0b0110011
OPCODE_SYSTEM = 0b1110011

FUNCT7_BASE = 0b0000000   # ADD/SLL/SLT/.../OR/AND, SLLI/SRLI, MRET n/a
FUNCT7_ALT = 0b0100000    # SUB, SRA, SRAI
FUNCT7_MULDIV = 0b0000001  # RV32M: MUL/MULH/.../REMU

# SYSTEM, funct3=000 sub-dispatch (via csr_addr acting as funct12)
FUNCT12_ECALL = 0x000
FUNCT12_EBREAK = 0x001
FUNCT12_MRET = 0x302


# ------------------------------------------------------------------------
# Mnemonics (Section 5)
# ------------------------------------------------------------------------

class Mnemonic(Enum):
    # Integer ALU (R-type)
    ADD = auto()
    SUB = auto()
    SLL = auto()
    SLT = auto()
    SLTU = auto()
    XOR = auto()
    SRL = auto()
    SRA = auto()
    OR = auto()
    AND = auto()
    # Immediate ALU (I-type)
    ADDI = auto()
    SLTI = auto()
    SLTIU = auto()
    XORI = auto()
    ORI = auto()
    ANDI = auto()
    SLLI = auto()
    SRLI = auto()
    SRAI = auto()
    # Upper immediate (U-type)
    LUI = auto()
    AUIPC = auto()
    # Branches (B-type)
    BEQ = auto()
    BNE = auto()
    BLT = auto()
    BGE = auto()
    BLTU = auto()
    BGEU = auto()
    # Jumps
    JAL = auto()   # J-type
    JALR = auto()  # I-type
    # Loads (I-type)
    LB = auto()
    LH = auto()
    LW = auto()
    LBU = auto()
    LHU = auto()
    # Stores (S-type)
    SB = auto()
    SH = auto()
    SW = auto()
    # Multiply (R-type)
    MUL = auto()
    MULH = auto()
    MULHU = auto()
    MULHSU = auto()
    # Divide (R-type)
    DIV = auto()
    DIVU = auto()
    REM = auto()
    REMU = auto()
    # CSR
    CSRRW = auto()
    CSRRS = auto()
    CSRRC = auto()
    CSRRWI = auto()
    CSRRSI = auto()
    CSRRCI = auto()
    # Privileged
    ECALL = auto()
    EBREAK = auto()
    MRET = auto()
    # Anything not recognized -- execute.py raises the illegal-
    # instruction exception path for this.
    ILLEGAL = auto()


# ------------------------------------------------------------------------
# Per-opcode-group dispatch tables
# ------------------------------------------------------------------------

_BRANCH_TABLE = {
    0b000: Mnemonic.BEQ,
    0b001: Mnemonic.BNE,
    0b100: Mnemonic.BLT,
    0b101: Mnemonic.BGE,
    0b110: Mnemonic.BLTU,
    0b111: Mnemonic.BGEU,
}

_LOAD_TABLE = {
    0b000: Mnemonic.LB,
    0b001: Mnemonic.LH,
    0b010: Mnemonic.LW,
    0b100: Mnemonic.LBU,
    0b101: Mnemonic.LHU,
}

_STORE_TABLE = {
    0b000: Mnemonic.SB,
    0b001: Mnemonic.SH,
    0b010: Mnemonic.SW,
}

# (funct3, funct7) -> Mnemonic, for the OP opcode (R-type ALU + RV32M)
_OP_TABLE = {
    (0b000, FUNCT7_BASE): Mnemonic.ADD,
    (0b000, FUNCT7_ALT): Mnemonic.SUB,
    (0b000, FUNCT7_MULDIV): Mnemonic.MUL,
    (0b001, FUNCT7_BASE): Mnemonic.SLL,
    (0b001, FUNCT7_MULDIV): Mnemonic.MULH,
    (0b010, FUNCT7_BASE): Mnemonic.SLT,
    (0b010, FUNCT7_MULDIV): Mnemonic.MULHSU,
    (0b011, FUNCT7_BASE): Mnemonic.SLTU,
    (0b011, FUNCT7_MULDIV): Mnemonic.MULHU,
    (0b100, FUNCT7_BASE): Mnemonic.XOR,
    (0b100, FUNCT7_MULDIV): Mnemonic.DIV,
    (0b101, FUNCT7_BASE): Mnemonic.SRL,
    (0b101, FUNCT7_ALT): Mnemonic.SRA,
    (0b101, FUNCT7_MULDIV): Mnemonic.DIVU,
    (0b110, FUNCT7_BASE): Mnemonic.OR,
    (0b110, FUNCT7_MULDIV): Mnemonic.REM,
    (0b111, FUNCT7_BASE): Mnemonic.AND,
    (0b111, FUNCT7_MULDIV): Mnemonic.REMU,
}

# funct3 -> Mnemonic for OP-IMM entries that don't need a funct7 check
_OP_IMM_TABLE = {
    0b000: Mnemonic.ADDI,
    0b010: Mnemonic.SLTI,
    0b011: Mnemonic.SLTIU,
    0b100: Mnemonic.XORI,
    0b110: Mnemonic.ORI,
    0b111: Mnemonic.ANDI,
}

# funct3 -> Mnemonic for the register-source CSR ops (SYSTEM opcode)
_CSR_REG_TABLE = {
    0b001: Mnemonic.CSRRW,
    0b010: Mnemonic.CSRRS,
    0b011: Mnemonic.CSRRC,
}

# funct3 -> Mnemonic for the immediate-source CSR ops (SYSTEM opcode)
_CSR_IMM_TABLE = {
    0b101: Mnemonic.CSRRWI,
    0b110: Mnemonic.CSRRSI,
    0b111: Mnemonic.CSRRCI,
}


# ------------------------------------------------------------------------
# Decoded instruction
# ------------------------------------------------------------------------

@dataclass
class DecodedInstruction:
    """
    Full decode result handed to execute.py.

    `imm` holds whichever immediate is architecturally relevant for
    `mnemonic` (already computed by the correct imm_*() function above);
    for R-type ALU/MUL/DIV ops, CSRRW/CSRRS/CSRRC (register-source), and
    ECALL/EBREAK/MRET, `imm` is unused and set to 0.

    Special case -- SLLI/SRLI/SRAI: per the standard RV32I encoding, the
    5-bit shift amount lives in the same bit positions as the rs2 field
    (inst[24:20]), so execute.py should read the shift amount off
    `fields.rs2`, NOT off `imm`. `imm` is still populated with imm_i()
    for these three for debug visibility, but is not the operand to use.
    """
    raw: int
    mnemonic: Mnemonic
    fields: InstructionFields
    imm: int


def decode(inst: int) -> DecodedInstruction:
    """Decode a raw 32-bit instruction word into a DecodedInstruction.
    Unrecognized opcode/funct3/funct7 combinations decode to
    Mnemonic.ILLEGAL with imm=0; execute.py is responsible for turning
    that into the illegal-instruction trap path."""
    f = extract_fields(inst)
    op = f.opcode

    if op == OPCODE_LUI:
        return DecodedInstruction(inst, Mnemonic.LUI, f, imm_u(inst))

    if op == OPCODE_AUIPC:
        return DecodedInstruction(inst, Mnemonic.AUIPC, f, imm_u(inst))

    if op == OPCODE_JAL:
        return DecodedInstruction(inst, Mnemonic.JAL, f, imm_j(inst))

    if op == OPCODE_JALR:
        if f.funct3 == 0b000:
            return DecodedInstruction(inst, Mnemonic.JALR, f, imm_i(inst))
        return DecodedInstruction(inst, Mnemonic.ILLEGAL, f, 0)

    if op == OPCODE_BRANCH:
        mnem = _BRANCH_TABLE.get(f.funct3, Mnemonic.ILLEGAL)
        return DecodedInstruction(inst, mnem, f, imm_b(inst))

    if op == OPCODE_LOAD:
        mnem = _LOAD_TABLE.get(f.funct3, Mnemonic.ILLEGAL)
        return DecodedInstruction(inst, mnem, f, imm_i(inst))

    if op == OPCODE_STORE:
        mnem = _STORE_TABLE.get(f.funct3, Mnemonic.ILLEGAL)
        return DecodedInstruction(inst, mnem, f, imm_s(inst))

    if op == OPCODE_OP_IMM:
        if f.funct3 in _OP_IMM_TABLE:
            return DecodedInstruction(inst, _OP_IMM_TABLE[f.funct3], f, imm_i(inst))
        if f.funct3 == 0b001:  # SLLI
            mnem = Mnemonic.SLLI if f.funct7 == FUNCT7_BASE else Mnemonic.ILLEGAL
            return DecodedInstruction(inst, mnem, f, imm_i(inst))
        if f.funct3 == 0b101:  # SRLI / SRAI
            if f.funct7 == FUNCT7_BASE:
                mnem = Mnemonic.SRLI
            elif f.funct7 == FUNCT7_ALT:
                mnem = Mnemonic.SRAI
            else:
                mnem = Mnemonic.ILLEGAL
            return DecodedInstruction(inst, mnem, f, imm_i(inst))
        return DecodedInstruction(inst, Mnemonic.ILLEGAL, f, 0)

    if op == OPCODE_OP:
        mnem = _OP_TABLE.get((f.funct3, f.funct7), Mnemonic.ILLEGAL)
        return DecodedInstruction(inst, mnem, f, 0)

    if op == OPCODE_SYSTEM:
        if f.funct3 == 0b000:
            if f.rd == 0 and f.rs1 == 0 and f.csr_addr == FUNCT12_ECALL:
                return DecodedInstruction(inst, Mnemonic.ECALL, f, 0)
            if f.rd == 0 and f.rs1 == 0 and f.csr_addr == FUNCT12_EBREAK:
                return DecodedInstruction(inst, Mnemonic.EBREAK, f, 0)
            if f.rd == 0 and f.rs1 == 0 and f.csr_addr == FUNCT12_MRET:
                return DecodedInstruction(inst, Mnemonic.MRET, f, 0)
            return DecodedInstruction(inst, Mnemonic.ILLEGAL, f, 0)
        if f.funct3 in _CSR_REG_TABLE:
            return DecodedInstruction(inst, _CSR_REG_TABLE[f.funct3], f, 0)
        if f.funct3 in _CSR_IMM_TABLE:
            return DecodedInstruction(inst, _CSR_IMM_TABLE[f.funct3], f, imm_csr(inst))
        return DecodedInstruction(inst, Mnemonic.ILLEGAL, f, 0)

    return DecodedInstruction(inst, Mnemonic.ILLEGAL, f, 0)
