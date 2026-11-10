"""
clint.py

CLINT (Core-Local Interruptor) model for the RV32IM golden reference model:
mtime, mtimecmp, msip, and their memory-mapped register interface
(Section 14, register addresses from Section 2).

CLINT state itself (msip / mtime / mtimecmp) lives on CPUState (see
cpu_state.py), not in a separate object here -- Section 1 lists it as
core architectural state, and keeping it on CPUState means core.py's
reset()/snapshotting story stays uniform for all architectural state.
This module supplies the *behavior* on top of that state: mtime tick,
mtip derivation, and the register-level read/write interface that
execute.py's load/store path calls into for CLINT-range addresses.

Per module boundary agreed in memory.py: memory.py knows nothing about
these addresses. core.py / execute.py must check whether a load/store
address falls in CLINT_BASE..CLINT_LIMIT and route to this module's
clint_read()/clint_write() instead of calling into the Memory object.
"""

from cpu_state import CPUState, u32

# ------------------------------------------------------------------------
# CLINT register addresses (Section 2)
# ------------------------------------------------------------------------

ADDR_MSIP = 0x10010000
ADDR_MTIMECMP_LOW = 0x10014000
ADDR_MTIMECMP_HIGH = 0x10014004
ADDR_MTIME_LOW = 0x1001BFF8
ADDR_MTIME_HIGH = 0x1001BFFC

# Overall CLINT address span, used by core.py/execute.py to decide
# whether a given load/store address should be routed here instead of
# to memory.py. Spans from the lowest to the highest defined register,
# each of which is a 4-byte word.
CLINT_BASE = 0x10010000
CLINT_SIZE = 0x0000C000
CLINT_LIMIT = CLINT_BASE + CLINT_SIZE - 1

_WORD_ADDRS = (
    ADDR_MSIP,
    ADDR_MTIMECMP_LOW,
    ADDR_MTIMECMP_HIGH,
    ADDR_MTIME_LOW,
    ADDR_MTIME_HIGH,
)


class ClintAccessError(Exception):
    """
    Raised when a load/store lands inside the overall CLINT span
    (CLINT_BASE..CLINT_LIMIT) but not on one of the five defined 4-byte
    registers, or is not word-sized/word-aligned.

    Design choice mirrors memory.py's MemoryAccessError: the spec defines
    exactly five CLINT registers and gives no behavior for anything else
    in that address range, so treating an odd-sized or off-register
    access as a hard error surfaces a testbench/address-decode mismatch
    immediately rather than silently returning 0.
    """


def is_clint_address(addr: int) -> bool:
    """True if `addr` falls anywhere within the CLINT's overall address
    span. Used by core.py/execute.py to route loads/stores here instead
    of to memory.py."""
    return CLINT_BASE <= addr <= CLINT_LIMIT


# ------------------------------------------------------------------------
# mtime advancement (Section 14)
# ------------------------------------------------------------------------

def tick(state: CPUState) -> None:
    """
    Advance mtime by one, per the spec's recommended ISS behavior
    (Section 14): "mtime += 1 per retired instruction".

    core.py calls this once per step(), after the instruction retires
    and before the trap/interrupt check, so a newly-crossed mtime >=
    mtimecmp threshold can trigger MTIP on the same step it occurs.

    mtime is a 64-bit free-running counter; masked to 64 bits so it
    wraps rather than growing an unbounded Python int forever.
    """
    state.mtime = (state.mtime + 1) & 0xFFFFFFFFFFFFFFFF


def mtip_pending(state: CPUState) -> bool:
    """MTIP condition (Section 14): mtime >= mtimecmp. Exposed here as a
    convenience; csr.py's compute_mip() re-implements the same check
    directly against CPUState so csr.py has no import dependency on
    clint.py -- keep both in sync if this condition ever changes."""
    return state.mtime >= state.mtimecmp


# ------------------------------------------------------------------------
# Register-level read/write interface
# ------------------------------------------------------------------------

def clint_read(state: CPUState, addr: int, size: int) -> int:
    """
    Read from a CLINT register.

    `size` is the access width in bytes (1/2/4), matching the LB/LH/LW
    family so execute.py can call this the same way it calls
    memory.read8/16/32. Every CLINT register is architecturally 32 bits
    wide; sub-word reads return the corresponding slice of that 32-bit
    value (little-endian), matching how a real memory-mapped peripheral
    would behave on a narrower bus access.
    """
    word = _read_word(state, addr & ~0x3)
    byte_offset = addr & 0x3
    return _slice_bytes(word, byte_offset, size)


def clint_write(state: CPUState, addr: int, value: int, size: int) -> None:
    """
    Write to a CLINT register.

    Sub-word writes are read-modify-write against the containing 32-bit
    register, same reasoning as clint_read()'s sub-word reads.
    """
    aligned_addr = addr & ~0x3
    byte_offset = addr & 0x3

    if size == 4 and byte_offset == 0:
        new_word = u32(value)
    else:
        old_word = _read_word(state, aligned_addr)
        new_word = _merge_bytes(old_word, byte_offset, size, value)

    _write_word(state, aligned_addr, new_word)


def _read_word(state: CPUState, aligned_addr: int) -> int:
    if aligned_addr == ADDR_MSIP:
        return state.msip & 0x1  # only bit0 is architecturally defined
    if aligned_addr == ADDR_MTIMECMP_LOW:
        return state.mtimecmp & 0xFFFFFFFF
    if aligned_addr == ADDR_MTIMECMP_HIGH:
        return (state.mtimecmp >> 32) & 0xFFFFFFFF
    if aligned_addr == ADDR_MTIME_LOW:
        return state.mtime & 0xFFFFFFFF
    if aligned_addr == ADDR_MTIME_HIGH:
        return (state.mtime >> 32) & 0xFFFFFFFF
    raise ClintAccessError(
        f"Address 0x{aligned_addr:08X} is inside the CLINT span but is "
        f"not one of the five defined registers."
    )


def _write_word(state: CPUState, aligned_addr: int, new_word: int) -> None:
    new_word = u32(new_word)
    if aligned_addr == ADDR_MSIP:
        state.msip = new_word & 0x1
        return
    if aligned_addr == ADDR_MTIMECMP_LOW:
        state.mtimecmp = (state.mtimecmp & ~0xFFFFFFFF) | new_word
        return
    if aligned_addr == ADDR_MTIMECMP_HIGH:
        state.mtimecmp = (state.mtimecmp & 0xFFFFFFFF) | (new_word << 32)
        return
    if aligned_addr == ADDR_MTIME_LOW:
        state.mtime = (state.mtime & ~0xFFFFFFFF) | new_word
        return
    if aligned_addr == ADDR_MTIME_HIGH:
        state.mtime = (state.mtime & 0xFFFFFFFF) | (new_word << 32)
        return
    raise ClintAccessError(
        f"Address 0x{aligned_addr:08X} is inside the CLINT span but is "
        f"not one of the five defined registers."
    )


def _slice_bytes(word: int, byte_offset: int, size: int) -> int:
    """Extract `size` bytes starting at `byte_offset` from a 32-bit
    little-endian word."""
    shift = byte_offset * 8
    mask = (1 << (size * 8)) - 1
    return (word >> shift) & mask


def _merge_bytes(word: int, byte_offset: int, size: int, value: int) -> int:
    """Return `word` with `size` bytes starting at `byte_offset`
    replaced by the low `size` bytes of `value` (little-endian)."""
    shift = byte_offset * 8
    mask = (1 << (size * 8)) - 1
    cleared = word & ~(mask << shift)
    return cleared | ((value & mask) << shift)
