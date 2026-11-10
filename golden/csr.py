"""
csr.py

Machine-mode CSR subsystem for the RV32IM golden reference model:
CSR read/write mechanics (Section 10), the mstatus/mie/mip bit layout
(Section 9), interrupt-pending evaluation (Section 11), trap entry
(Section 12), and MRET (Section 13).

ASSUMPTION (not given explicitly by the spec): CSR *addresses*. The spec
defines the CSR names and their bit layout, but the instruction encoding
only says "csr_addr = inst[31:20]" (Section 3) without giving the actual
12-bit values for mstatus/mie/mtvec/etc. Since this core implements
exactly the standard RV32I machine-mode CSR subset described in Section 9
and no others, this module assumes the standard RISC-V addresses for
them. If the RTL uses different encodings, only the constants in the
"CSR address map" section below need to change -- nothing else in this
file depends on the specific numeric values.

ASSUMPTION: synchronous exception cause numbers. Section 11 gives cause
numbers for the three interrupts (MEI=11, MSI=3, MTI=7), but the spec
never states mcause values for ECALL / EBREAK / illegal instruction.
Standard RISC-V privileged-spec values are used here (2 / 3 / 11
respectively) since nothing in the spec suggests otherwise.
"""

from typing import Optional

from cpu_state import CPUState, u32

# ------------------------------------------------------------------------
# CSR address map (ASSUMPTION -- see module docstring)
# ------------------------------------------------------------------------

CSR_MSTATUS = 0x300
CSR_MIE = 0x304
CSR_MTVEC = 0x305
CSR_MSCRATCH = 0x340
CSR_MEPC = 0x341
CSR_MCAUSE = 0x342
CSR_MTVAL = 0x343
CSR_MIP = 0x344

# ------------------------------------------------------------------------
# mstatus bit layout (Section 9)
# ------------------------------------------------------------------------

MSTATUS_MIE_BIT = 3
MSTATUS_MPIE_BIT = 7
MSTATUS_MPP_SHIFT = 11
MSTATUS_MPP_FIXED_VALUE = 0b11 << MSTATUS_MPP_SHIFT  # bits[12:11] = 11, hardwired

# ------------------------------------------------------------------------
# mie / mip bit layout (Section 9) -- identical bit positions on both
# ------------------------------------------------------------------------

MIE_MSIE_BIT = 3
MIE_MTIE_BIT = 7
MIE_MEIE_BIT = 11
MIE_DEFINED_MASK = (1 << MIE_MSIE_BIT) | (1 << MIE_MTIE_BIT) | (1 << MIE_MEIE_BIT)

MIP_MSIP_BIT = 3
MIP_MTIP_BIT = 7
MIP_MEIP_BIT = 11

# ------------------------------------------------------------------------
# Interrupt causes (Section 11)
# ------------------------------------------------------------------------

CAUSE_MSI = 3
CAUSE_MTI = 7
CAUSE_MEI = 11

# Section 11 lists MEIP, then MSIP, then MTIP -- taken as descending
# priority when more than one is simultaneously pending and enabled.
_INTERRUPT_PRIORITY = (
    (MIP_MEIP_BIT, CAUSE_MEI),
    (MIP_MSIP_BIT, CAUSE_MSI),
    (MIP_MTIP_BIT, CAUSE_MTI),
)

# ------------------------------------------------------------------------
# Synchronous exception causes (ASSUMPTION -- see module docstring)
# ------------------------------------------------------------------------

# TODO / ASSUMPTION: the spec never states an mcause value for illegal
# instructions anywhere (Section 11 only defines the three interrupt
# causes). 2 is the standard RISC-V value, used here as a placeholder --
# CONFIRM against RTL and update if this core uses a different encoding.
CAUSE_ILLEGAL_INSTRUCTION = 2  # TODO: confirm against RTL
CAUSE_EBREAK = 3
CAUSE_ECALL_FROM_M = 11


# ------------------------------------------------------------------------
# mstatus read/write
# ------------------------------------------------------------------------

def mstatus_read(state: CPUState) -> int:
    """
    Reconstruct the externally visible mstatus value.

    Only MIE (bit3) and MPIE (bit7) are stored/mutable; MPP is hardwired
    to 0b11 per Section 9, and every other bit is reserved/zero.
    """
    value = state.mstatus & ((1 << MSTATUS_MIE_BIT) | (1 << MSTATUS_MPIE_BIT))
    value |= MSTATUS_MPP_FIXED_VALUE
    return u32(value)


def mstatus_write(state: CPUState, value: int) -> None:
    """
    Write mstatus. Only MIE and MPIE are writable; MPP and all reserved
    bits are dropped silently (MPP is fixed per Section 9, so a write to
    it has no architectural effect on this core).
    """
    value = u32(value)
    keep_mask = (1 << MSTATUS_MIE_BIT) | (1 << MSTATUS_MPIE_BIT)
    state.mstatus = value & keep_mask


def get_mie_bit(state: CPUState) -> int:
    """Read mstatus.MIE (the global interrupt-enable bit)."""
    return (state.mstatus >> MSTATUS_MIE_BIT) & 1


def set_mie_bit(state: CPUState, val: int) -> None:
    if val:
        state.mstatus |= (1 << MSTATUS_MIE_BIT)
    else:
        state.mstatus &= ~(1 << MSTATUS_MIE_BIT)


def get_mpie_bit(state: CPUState) -> int:
    """Read mstatus.MPIE (the previous interrupt-enable bit)."""
    return (state.mstatus >> MSTATUS_MPIE_BIT) & 1


def set_mpie_bit(state: CPUState, val: int) -> None:
    if val:
        state.mstatus |= (1 << MSTATUS_MPIE_BIT)
    else:
        state.mstatus &= ~(1 << MSTATUS_MPIE_BIT)


# ------------------------------------------------------------------------
# mip derivation (Section 9 & 14)
# ------------------------------------------------------------------------

def compute_mip(state: CPUState) -> int:
    """
    Compute the live mip value from CLINT state and the external
    interrupt line.

    - MSIP (bit3)  <- architectural state.msip OR live software IRQ input
    - MTIP (bit7)  <- mtime >= mtimecmp OR live timer IRQ input
    - MEIP (bit11) <- live external IRQ input

    The live inputs are needed because the isolated RTL exposes all three
    interrupt inputs directly, while the original offline ISS only modeled
    the external line. CLINT state is retained so existing software-driven
    MSIP/MTIP tests continue to work.
    """
    value = 0
    if (state.msip | state.software_irq) & 1:
        value |= (1 << MIP_MSIP_BIT)
    if (state.mtime >= state.mtimecmp) or (state.timer_irq & 1):
        value |= (1 << MIP_MTIP_BIT)
    if state.external_irq & 1:
        value |= (1 << MIP_MEIP_BIT)
    return value


def sync_mip(state: CPUState) -> None:
    """
    Recompute state.mip from live CLINT state and store it back onto
    the CPUState.

    core.py must call this once per step -- before both the interrupt
    check and trace emission -- so that trace.py's post-instruction mip
    snapshot (Section 15) is accurate and check_pending_interrupt()
    below observes current CLINT status.
    """
    state.mip = compute_mip(state)


# ------------------------------------------------------------------------
# Generic CSR read/write (Section 10)
# ------------------------------------------------------------------------

# CSRs with no special bit layout: a plain 32-bit value, passed straight
# through to/from the matching CPUState field.
_PASSTHROUGH_FIELDS = {
    CSR_MTVEC: "mtvec",
    CSR_MSCRATCH: "mscratch",
    CSR_MEPC: "mepc",
    CSR_MCAUSE: "mcause",
    CSR_MTVAL: "mtval",
}


def csr_read(state: CPUState, addr: int) -> int:
    """
    Read a CSR by address.

    Returns 0 for any address outside the Section 9 machine CSR set --
    this core defines no other CSRs, so there's nothing else to return.
    execute.py may choose to treat an unrecognized csr_addr as an illegal
    instruction; csr.py itself stays permissive and never raises here.
    """
    if addr == CSR_MSTATUS:
        return mstatus_read(state)
    if addr == CSR_MIE:
        return state.mie & MIE_DEFINED_MASK
    if addr == CSR_MIP:
        # Re-derive on every read (rather than trusting state.mip) so a
        # read is accurate even if sync_mip() hasn't run yet this step.
        return compute_mip(state)
    if addr in _PASSTHROUGH_FIELDS:
        return u32(getattr(state, _PASSTHROUGH_FIELDS[addr]))
    return 0


def csr_write(state: CPUState, addr: int, value: int) -> None:
    """
    Write a CSR by address.

    mip is read-only (Section 9): writes to it are silently dropped.
    Writes to an unrecognized address are also silently dropped.
    """
    value = u32(value)
    if addr == CSR_MSTATUS:
        mstatus_write(state, value)
        return
    if addr == CSR_MIE:
        state.mie = value & MIE_DEFINED_MASK
        return
    if addr == CSR_MIP:
        return  # read-only, no effect
    if addr in _PASSTHROUGH_FIELDS:
        setattr(state, _PASSTHROUGH_FIELDS[addr], value)
        return
    # Unrecognized CSR address: no-op.


def csr_rw(state: CPUState, addr: int, src: int) -> int:
    """CSRRW / CSRRWI (Section 10): csr = src. Returns the OLD csr value
    (execute.py writes this into rd)."""
    old = csr_read(state, addr)
    csr_write(state, addr, src)
    return old


def csr_rs(state: CPUState, addr: int, src: int) -> int:
    """CSRRS / CSRRSI (Section 10): csr = csr | src. Returns the OLD csr
    value."""
    old = csr_read(state, addr)
    csr_write(state, addr, old | u32(src))
    return old


def csr_rc(state: CPUState, addr: int, src: int) -> int:
    """CSRRC / CSRRCI (Section 10): csr = csr & ~src. Returns the OLD csr
    value."""
    old = csr_read(state, addr)
    csr_write(state, addr, old & ~u32(src))
    return old


# ------------------------------------------------------------------------
# Interrupt evaluation (Section 11)
# ------------------------------------------------------------------------

def check_pending_interrupt(state: CPUState) -> Optional[int]:
    """
    Evaluate whether an interrupt should be taken right now.

    Condition (Section 11): mstatus.MIE == 1 AND (mie & mip) != 0.

    Assumes state.mip is already current -- core.py must call sync_mip()
    before this on every step. Returns the cause number of the highest-
    priority pending+enabled interrupt (Section 11 order: MEIP > MSIP >
    MTIP), or None if no interrupt should be taken.
    """
    if get_mie_bit(state) == 0:
        return None

    pending_enabled = state.mie & state.mip
    if pending_enabled == 0:
        return None

    for bit, cause in _INTERRUPT_PRIORITY:
        if pending_enabled & (1 << bit):
            return cause
    return None


# ------------------------------------------------------------------------
# Trap entry (Section 12)
# ------------------------------------------------------------------------

def take_trap(state: CPUState, cause: int, is_interrupt: bool, trap_pc: int) -> None:
    """
    Enter a trap (synchronous exception or interrupt).

    `trap_pc` must be the PC of the instruction retiring in the step
    where the trap is taken -- for BOTH exceptions and interrupts.

    Note this differs from the usual RISC-V convention (where an
    interrupt's mepc points at the next instruction, since the
    interrupted instruction already retired cleanly). This core's RTL
    instead always latches the PC of whatever instruction is retiring in
    the same step the trap is recognized, even for interrupts, so
    core.py must pass that PC here regardless of trap type -- do not
    special-case interrupts to pass "the next PC".

    Per Section 12:
        mepc   = pc
        mcause = cause               (exception)
        mcause = (1<<31) | cause     (interrupt)
        MPIE   = MIE
        MIE    = 0
        pc     = mtvec
    """
    state.mepc = u32(trap_pc)
    if is_interrupt:
        state.mcause = u32((1 << 31) | cause)
    else:
        state.mcause = u32(cause)

    set_mpie_bit(state, get_mie_bit(state))
    set_mie_bit(state, 0)
    state.pc = u32(state.mtvec)


# ------------------------------------------------------------------------
# MRET (Section 13)
# ------------------------------------------------------------------------

def take_mret(state: CPUState) -> None:
    """
    Execute MRET:
        MIE  = MPIE
        MPIE = 1
        pc   = mepc
    """
    set_mie_bit(state, get_mpie_bit(state))
    set_mpie_bit(state, 1)
    state.pc = u32(state.mepc)
