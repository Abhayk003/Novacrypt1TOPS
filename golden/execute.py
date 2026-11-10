"""
execute.py

Instruction execution for RV32I (Section 5), RV32M multiply/divide
(Sections 5, 7, 8), CSR instructions (Sections 5, 10), and privileged
instructions (Section 5, 12, 13).

Design: execute() takes full ownership of updating state.pc for whichever
instruction it's given -- every branch below either (a) computes a
control-flow target and sets state.pc directly, or (b) falls through to
state.pc = current_pc + 4. This includes ECALL/EBREAK/MRET/illegal
instructions, which call straight into csr.take_trap()/csr.take_mret()
(those functions set state.pc themselves). core.py's only remaining
responsibility around pc, after calling execute(), is the *interrupt*
check (Section 11) -- and only when this step didn't already take a
synchronous exception, per Section 12's "Exception > Interrupt" priority.

ASSUMPTION: JALR target LSB clearing. The spec lists JALR as supported
(Section 5) but gives no further semantic detail. This module uses the
standard RISC-V behavior -- target = (rs1 + imm) with bit 0 cleared --
since nothing in the spec suggests a deviation.
"""

from dataclasses import dataclass
from typing import Optional

import csr
from cpu_state import CPUState, u32, s32, low32, high32
from decoder import DecodedInstruction, Mnemonic
from bus import MemoryBus

# ------------------------------------------------------------------------
# Execution result -- everything core.py/trace.py need out of one step,
# beyond the state mutations execute() already applied directly.
# ------------------------------------------------------------------------

@dataclass
class ExecutionResult:
    reg_we: bool = False
    wdata: int = 0

    mem_read: bool = False
    mem_write: bool = False
    mem_addr: int = 0
    mem_wdata: int = 0

    branch_taken: bool = False
    jalr_taken: bool = False
    # Populated (non-None) whenever this instruction caused a
    # non-sequential PC change of its own accord: branch taken, JAL, or
    # JALR. NOT used for trap/mret targets -- core.py derives
    # trap_target/mret_target from state.pc after calling
    # csr.take_trap()/csr.take_mret().
    redirect_target: Optional[int] = None

    is_ecall: bool = False
    is_ebreak: bool = False
    is_illegal: bool = False
    mret_taken: bool = False

    # Informational only (Section 6: "No misalignment traps observed in
    # RTL") -- the access still happens normally either way.
    load_misalign: bool = False
    store_misalign: bool = False


# ------------------------------------------------------------------------
# Small arithmetic helpers specific to execute.py
# ------------------------------------------------------------------------

def _trunc_div(a: int, b: int) -> int:
    """Truncating (round-toward-zero) division, per Section 8 -- NOT
    Python's floor //, which rounds toward -inf for mixed-sign operands."""
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def _trunc_rem(a: int, b: int) -> int:
    """Remainder consistent with _trunc_div; sign follows the dividend,
    matching Section 8's 'Remainder sign follows dividend sign'."""
    return a - _trunc_div(a, b) * b


# ------------------------------------------------------------------------
# Main dispatch
# ------------------------------------------------------------------------

def execute(
    state: CPUState,
    bus: MemoryBus,
    decoded: DecodedInstruction,
    current_pc: int,
) -> ExecutionResult:
    """
    Execute one decoded instruction against `state`/`memory`, mutating
    both directly, and return trace-relevant metadata.

    `current_pc` is the fetch address of THIS instruction, supplied by
    core.py (decoder.py never sees PC, only the raw instruction word).
    """
    f = decoded.fields
    m = decoded.mnemonic
    r = ExecutionResult()

    # ------------------------------------------------------------
    # Illegal instruction -- checked first; nothing else applies.
    # ------------------------------------------------------------
    if m == Mnemonic.ILLEGAL:
        r.is_illegal = True
        csr.take_trap(state, csr.CAUSE_ILLEGAL_INSTRUCTION, False, current_pc)
        return r

    # ------------------------------------------------------------
    # Privileged (Section 12, 13)
    # ------------------------------------------------------------
    if m == Mnemonic.ECALL:
        r.is_ecall = True
        csr.take_trap(state, csr.CAUSE_ECALL_FROM_M, False, current_pc)
        return r

    if m == Mnemonic.EBREAK:
        r.is_ebreak = True
        csr.take_trap(state, csr.CAUSE_EBREAK, False, current_pc)
        return r

    if m == Mnemonic.MRET:
        r.mret_taken = True
        csr.take_mret(state)
        return r

    # ------------------------------------------------------------
    # Integer ALU, register-register (Section 5)
    # ------------------------------------------------------------
    if m in (Mnemonic.ADD, Mnemonic.SUB, Mnemonic.SLL, Mnemonic.SLT,
             Mnemonic.SLTU, Mnemonic.XOR, Mnemonic.SRL, Mnemonic.SRA,
             Mnemonic.OR, Mnemonic.AND):
        a = state.read_reg(f.rs1)
        b = state.read_reg(f.rs2)
        shamt = b & 0x1F
        if m == Mnemonic.ADD:
            val = u32(a + b)
        elif m == Mnemonic.SUB:
            val = u32(a - b)
        elif m == Mnemonic.SLL:
            val = u32(a << shamt)
        elif m == Mnemonic.SLT:
            val = 1 if s32(a) < s32(b) else 0
        elif m == Mnemonic.SLTU:
            val = 1 if a < b else 0
        elif m == Mnemonic.XOR:
            val = u32(a ^ b)
        elif m == Mnemonic.SRL:
            val = a >> shamt
        elif m == Mnemonic.SRA:
            val = u32(s32(a) >> shamt)
        elif m == Mnemonic.OR:
            val = u32(a | b)
        else:  # AND
            val = u32(a & b)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Immediate ALU (Section 5) -- ADDI/SLTI/SLTIU/XORI/ORI/ANDI
    # ------------------------------------------------------------
    if m in (Mnemonic.ADDI, Mnemonic.SLTI, Mnemonic.SLTIU,
             Mnemonic.XORI, Mnemonic.ORI, Mnemonic.ANDI):
        a = state.read_reg(f.rs1)
        imm = decoded.imm  # already a signed Python int from imm_i()
        if m == Mnemonic.ADDI:
            val = u32(a + imm)
        elif m == Mnemonic.SLTI:
            val = 1 if s32(a) < imm else 0
        elif m == Mnemonic.SLTIU:
            # Compare unsigned: imm's sign-extended bit pattern, not its
            # small signed numeric value.
            val = 1 if a < u32(imm) else 0
        elif m == Mnemonic.XORI:
            val = u32(a ^ imm)
        elif m == Mnemonic.ORI:
            val = u32(a | imm)
        else:  # ANDI
            val = u32(a & imm)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Immediate shifts (Section 5) -- shamt lives in the rs2 field
    # position (inst[24:20]), per decoder.py's note, NOT in `imm`.
    # ------------------------------------------------------------
    if m in (Mnemonic.SLLI, Mnemonic.SRLI, Mnemonic.SRAI):
        a = state.read_reg(f.rs1)
        shamt = f.rs2 & 0x1F
        if m == Mnemonic.SLLI:
            val = u32(a << shamt)
        elif m == Mnemonic.SRLI:
            val = a >> shamt
        else:  # SRAI
            val = u32(s32(a) >> shamt)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Upper immediate (Section 5)
    # ------------------------------------------------------------
    if m == Mnemonic.LUI:
        val = decoded.imm  # already inst & 0xFFFFF000, nonneg 32-bit
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    if m == Mnemonic.AUIPC:
        val = u32(current_pc + decoded.imm)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Branches (Section 5) -- PC-relative to the branch's own address
    # ------------------------------------------------------------
    if m in (Mnemonic.BEQ, Mnemonic.BNE, Mnemonic.BLT, Mnemonic.BGE,
             Mnemonic.BLTU, Mnemonic.BGEU):
        a = state.read_reg(f.rs1)
        b = state.read_reg(f.rs2)
        if m == Mnemonic.BEQ:
            taken = a == b
        elif m == Mnemonic.BNE:
            taken = a != b
        elif m == Mnemonic.BLT:
            taken = s32(a) < s32(b)
        elif m == Mnemonic.BGE:
            taken = s32(a) >= s32(b)
        elif m == Mnemonic.BLTU:
            taken = a < b
        else:  # BGEU
            taken = a >= b
        r.branch_taken = taken
        if taken:
            target = u32(current_pc + decoded.imm)
            r.redirect_target = target
            state.pc = target
        else:
            state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Jumps (Section 5)
    # ------------------------------------------------------------
    if m == Mnemonic.JAL:
        link = u32(current_pc + 4)
        target = u32(current_pc + decoded.imm)
        r.reg_we = f.rd != 0
        r.wdata = link
        r.redirect_target = target
        state.write_reg(f.rd, link)
        state.pc = target
        return r

    if m == Mnemonic.JALR:
        link = u32(current_pc + 4)
        base = state.read_reg(f.rs1)
        target = u32(base + decoded.imm) & ~1  # ASSUMPTION: clear LSB
        r.reg_we = f.rd != 0
        r.wdata = link
        r.jalr_taken = True
        r.redirect_target = target
        state.write_reg(f.rd, link)
        state.pc = target
        return r

    # ------------------------------------------------------------
    # Loads (Section 5, 6)
    # ------------------------------------------------------------
    if m in (Mnemonic.LB, Mnemonic.LH, Mnemonic.LW, Mnemonic.LBU, Mnemonic.LHU):
        base = state.read_reg(f.rs1)
        addr = u32(base + decoded.imm)
        size = {Mnemonic.LB: 1, Mnemonic.LBU: 1,
                Mnemonic.LH: 2, Mnemonic.LHU: 2,
                Mnemonic.LW: 4}[m]

        if size == 2:
            r.load_misalign = (addr % 2) != 0
        elif size == 4:
            r.load_misalign = (addr % 4) != 0
        # LB/LBU: byte access, never misaligned.

        raw = bus.read(state, addr, size)

        if m == Mnemonic.LB:
            val = u32(_sext_n(raw, 8))
        elif m == Mnemonic.LH:
            val = u32(_sext_n(raw, 16))
        else:  # LW, LBU, LHU -- zero-extended (LW is already full-width)
            val = raw

        r.mem_read = True
        r.mem_addr = addr
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Stores (Section 5, 6)
    # ------------------------------------------------------------
    if m in (Mnemonic.SB, Mnemonic.SH, Mnemonic.SW):
        base = state.read_reg(f.rs1)
        addr = u32(base + decoded.imm)
        size = {Mnemonic.SB: 1, Mnemonic.SH: 2, Mnemonic.SW: 4}[m]

        if size == 2:
            r.store_misalign = (addr % 2) != 0
        elif size == 4:
            r.store_misalign = (addr % 4) != 0

        value = state.read_reg(f.rs2)
        bus.write(state, addr, value, size)

        r.mem_write = True
        r.mem_addr = addr
        r.mem_wdata = value
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Multiply (Section 7)
    # ------------------------------------------------------------
    if m in (Mnemonic.MUL, Mnemonic.MULH, Mnemonic.MULHU, Mnemonic.MULHSU):
        a = state.read_reg(f.rs1)
        b = state.read_reg(f.rs2)
        if m == Mnemonic.MUL:
            val = low32(s32(a) * s32(b))
        elif m == Mnemonic.MULH:
            val = high32(s32(a) * s32(b))
        elif m == Mnemonic.MULHU:
            val = high32(a * b)
        else:  # MULHSU
            val = high32(s32(a) * b)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # Divide (Section 8)
    # ------------------------------------------------------------
    if m in (Mnemonic.DIV, Mnemonic.DIVU, Mnemonic.REM, Mnemonic.REMU):
        a = state.read_reg(f.rs1)
        b = state.read_reg(f.rs2)
        if m == Mnemonic.DIV:
            val = 0xFFFFFFFF if b == 0 else u32(_trunc_div(s32(a), s32(b)))
        elif m == Mnemonic.DIVU:
            val = 0xFFFFFFFF if b == 0 else (a // b)
        elif m == Mnemonic.REM:
            val = a if b == 0 else u32(_trunc_rem(s32(a), s32(b)))
        else:  # REMU
            val = a if b == 0 else (a % b)
        r.reg_we = f.rd != 0
        r.wdata = val
        state.write_reg(f.rd, val)
        state.pc = u32(current_pc + 4)
        return r

    # ------------------------------------------------------------
    # CSR instructions (Section 10)
    # ------------------------------------------------------------
    if m in (Mnemonic.CSRRW, Mnemonic.CSRRS, Mnemonic.CSRRC,
             Mnemonic.CSRRWI, Mnemonic.CSRRSI, Mnemonic.CSRRCI):
        addr = f.csr_addr
        if m in (Mnemonic.CSRRW, Mnemonic.CSRRS, Mnemonic.CSRRC):
            src = state.read_reg(f.rs1)
        else:
            src = decoded.imm  # zimm, from imm_csr()

        if m in (Mnemonic.CSRRW, Mnemonic.CSRRWI):
            old = csr.csr_rw(state, addr, src)
        elif m in (Mnemonic.CSRRS, Mnemonic.CSRRSI):
            old = csr.csr_rs(state, addr, src)
        else:  # CSRRC, CSRRCI
            old = csr.csr_rc(state, addr, src)

        r.reg_we = f.rd != 0
        r.wdata = old
        state.write_reg(f.rd, old)
        state.pc = u32(current_pc + 4)
        return r

    # Should be unreachable: every Mnemonic value is handled above.
    # Fall back to treating it as illegal rather than silently hanging.
    r.is_illegal = True
    csr.take_trap(state, csr.CAUSE_ILLEGAL_INSTRUCTION, False, current_pc)
    return r


# ------------------------------------------------------------------------
# Memory routing: CLINT range vs flat RAM/ROM (see memory.py / clint.py
# module boundary notes)
# ------------------------------------------------------------------------


def _sext_n(value: int, bits: int) -> int:
    """Sign-extend an n-bit unsigned value to a full signed Python int.
    Local helper (loads only) so this module doesn't need decoder.py
    just for bit-width sign extension of memory reads."""
    value &= (1 << bits) - 1
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit
