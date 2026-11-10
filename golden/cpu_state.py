"""
cpu_state.py

Architectural state container for the RV32IM golden reference model.

This module holds ONLY architectural state (Section 1 of the spec) plus a
handful of generic bit-manipulation helpers shared by every other module in
the ISS (decoder.py, execute.py, csr.py, clint.py, ...).

Per the spec's "COMPLETELY IGNORE" section (16), this model has no notion of
pipeline stages, hazards, forwarding, AXI timing, or latency of any kind.
core.py executes exactly one retired instruction per step() call, and this
class only ever reflects the state *after* a fully completed instruction.
"""

from dataclasses import dataclass, field
from typing import List

# ------------------------------------------------------------------------
# Generic bit-manipulation helpers
# ------------------------------------------------------------------------
# Centralized here so decoder.py, execute.py, and csr.py all use the exact
# same masking/sign-extension logic instead of re-deriving it per module.

MASK32 = 0xFFFFFFFF
MASK64 = 0xFFFFFFFFFFFFFFFF


def u32(value: int) -> int:
    """Mask an arbitrary (possibly negative, possibly >32-bit) Python int
    down to an unsigned 32-bit value. Used any time architectural state
    (a register, a CSR, a memory word) is written back, per constraint #7."""
    return value & MASK32


def s32(value: int) -> int:
    """Reinterpret the low 32 bits of value as a signed 32-bit integer.
    Used wherever the spec calls for a signed 32-bit operand, e.g. SLT,
    BLT/BGE, DIV/REM, MULH/MULHSU."""
    value &= MASK32
    if value & 0x80000000:
        return value - (1 << 32)
    return value


def sext(value: int, bits: int) -> int:
    """
    Sign-extend `value`, treated as a `bits`-wide two's complement field,
    to a full-width signed Python int.

    Used by decoder.py for I/S/B/J-type immediate generation (Section 4).
    """
    value &= (1 << bits) - 1
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit


def low32(value: int) -> int:
    """Return the low 32 bits of a (possibly wider, possibly negative)
    Python integer, as an unsigned 32-bit value. Used by MUL (Section 7)."""
    return value & MASK32


def high32(value: int, width: int = 64) -> int:
    """
    Return the high 32 bits of a `width`-bit two's-complement product, as
    an unsigned 32-bit value. `value` must already be reduced into the
    two's-complement representation for that width (i.e. negative products
    should be passed in pre-masked to `width` bits by the caller).

    Used by MULH / MULHU / MULHSU (Section 7), which are all 64-bit
    (32x32) products on this core.
    """
    mask = (1 << width) - 1
    value &= mask
    return (value >> 32) & MASK32


# ------------------------------------------------------------------------
# CPU architectural state
# ------------------------------------------------------------------------

@dataclass
class CPUState:
    """
    Full architectural state of the RV32IM core, per spec Section 1.

    Register file, PC, machine-mode CSRs, and CLINT-visible state
    (msip / mtime / mtimecmp) all live here.

    Note on `mip`: Section 9 states mip is read-only from software's point
    of view (bit3=MSIP, bit7=MTIP, bit11=MEIP, all reflecting CLINT/PLIC
    status). It is stored here as a plain field purely so trace.py has
    something to read post-instruction (trace format requires it, Section
    15) -- csr.py is responsible for recomputing it from CLINT state every
    step rather than letting CSRRW/CSRRS/CSRRC touch it directly.
    """

    # Program counter
    pc: int = 0x00000000

    # Integer register file. x0 must always read as 0 and ignore writes;
    # enforced by read_reg()/write_reg() below rather than special-cased
    # by every caller in execute.py.
    regs: List[int] = field(default_factory=lambda: [0] * 32)

    # Machine-mode CSRs (Section 9)
    mstatus: int = 0
    mie: int = 0
    mtvec: int = 0
    mscratch: int = 0
    mepc: int = 0
    mcause: int = 0
    mtval: int = 0
    mip: int = 0  # read-only to software; derived from CLINT state

    # CLINT-visible state (Sections 1 & 14)
    msip: int = 0
    mtime: int = 0
    mtimecmp: int = 0xFFFFFFFFFFFFFFFF

    # Live interrupt inputs driven by the verification environment / DUT ports.
    # The isolated RTL exposes timer, software, and external interrupt lines
    # directly, so the live golden model keeps the three inputs explicitly.
    # CLINT-derived MSIP/MTIP state remains below as well; csr.compute_mip()
    # ORs the live inputs with the architectural CLINT conditions.
    timer_irq: int = 0
    software_irq: int = 0
    external_irq: int = 0

    def read_reg(self, index: int) -> int:
        """Read a GPR. x0 is hardwired to 0."""
        if index == 0:
            return 0
        return self.regs[index] & MASK32

    def write_reg(self, index: int, value: int) -> None:
        """Write a GPR. Writes to x0 are silently discarded (Section 1)."""
        if index == 0:
            return
        self.regs[index] = u32(value)

    def reset(self) -> None:
        """Reset all architectural state to the spec's documented reset
        values (Section 1). Kept as an explicit method (rather than just
        re-instantiating CPUState()) so core.py can reset a live instance
        without disturbing any external references to it."""
        self.pc = 0x00000000
        self.regs = [0] * 32

        self.mstatus = 0
        self.mie = 0
        self.mtvec = 0
        self.mscratch = 0
        self.mepc = 0
        self.mcause = 0
        self.mtval = 0
        self.mip = 0

        self.msip = 0
        self.mtime = 0
        self.mtimecmp = 0xFFFFFFFFFFFFFFFF
        self.timer_irq = 0
        self.software_irq = 0
        self.external_irq = 0
