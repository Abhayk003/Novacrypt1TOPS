"""
memory.py

Flat byte-addressable memory model for the RV32IM golden reference model.

Implements the three RAM/ROM regions from spec Section 2:

    0x00000000 - 0x00003FFF   Boot ROM
    0x00010000 - 0x0001FFFF   Instruction SRAM
    0x00020000 - 0x0002FFFF   Data SRAM

CLINT (0x1001_0000 / 0x1001_4000 / 0x1001_BFF8 region) and PLIC
(0x1040_0000) are deliberately NOT modeled here. They are live, stateful
peripherals with their own read/write semantics (Section 14), owned by
clint.py. core.py / execute.py are responsible for routing any load/store
whose address falls in the CLINT range to the CLINT model instead of this
Memory object. This keeps memory.py a pure, dumb byte array with zero
knowledge of peripheral behavior -- easier to debug in isolation.

The CPU is little-endian (Section 6): the lowest address holds the least
significant byte.

No misalignment traps are modeled (Section 6): any byte address is honored
exactly as requested ("no misalignment traps observed in RTL").
"""

from typing import Dict

from cpu_state import u32, MASK32


# ==========================================================
# SoC MEMORY MAP
# ==========================================================

BOOT_ROM_BASE  = 0x00000000
BOOT_ROM_SIZE  = 0x00004000
BOOT_ROM_LIMIT = BOOT_ROM_BASE + BOOT_ROM_SIZE - 1

IMEM_BASE  = 0x00010000
IMEM_SIZE  = 0x00010000
IMEM_LIMIT = IMEM_BASE + IMEM_SIZE - 1

DMEM_BASE  = 0x00020000
DMEM_SIZE  = 0x00010000
DMEM_LIMIT = DMEM_BASE + DMEM_SIZE - 1

APB_BASE  = 0x10000000
APB_SIZE  = 0x00C00000
APB_LIMIT = APB_BASE + APB_SIZE - 1

UART_BASE  = 0x10000000
TIMER_BASE = 0x10001000
I2C_BASE   = 0x10002000
SPI_BASE   = 0x10003000
GPIO_BASE  = 0x10004000

CLINT_BASE = 0x10010000

PLIC_BASE  = 0x10400000
PLIC_SIZE  = 0x00400000
PLIC_LIMIT = PLIC_BASE + PLIC_SIZE - 1

_REGIONS = (
    (BOOT_ROM_BASE, BOOT_ROM_LIMIT, "Boot ROM"),
    (IMEM_BASE, IMEM_LIMIT, "Instruction SRAM"),
    (DMEM_BASE, DMEM_LIMIT, "Data SRAM"),
)


class MemoryAccessError(Exception):
    """
    Raised when an access falls outside every modeled region.

    Design choice: this is a hard error rather than a silent
    return-0 / drop-the-write. For a UVM golden-model comparison, an
    access to unmapped space almost always means the test program or the
    ISS/RTL address decode disagree about the memory map -- surfacing
    that immediately is more useful than masking it and producing a
    trace mismatch several instructions later with no obvious cause.
    """


class ReadOnlyMemoryError(Exception):
    """
    Raised when an ISA store instruction (SB/SH/SW) targets Boot ROM.

    Boot ROM is instruction/data supplied at load time (reset vectors,
    boot code) and is not writable by the running program on real
    hardware. Only Memory.load_bytes() -- used by core.py at startup --
    may populate it; see the internal _write_byte() bypass in
    load_bytes().
    """


class Memory:
    """
    Sparse, byte-addressable flat memory.

    Backed by a dict of address -> byte rather than a preallocated array:
    the modeled regions span far more address space (Boot ROM + IMEM +
    DMEM) than any single test program will actually touch, so a dict
    keeps this cheap regardless of region size.
    """

    def __init__(self) -> None:
        self._bytes: Dict[int, int] = {}

    # --------------------------------------------------------------
    # Region checking
    # --------------------------------------------------------------

    @staticmethod
    def _in_known_region(addr: int) -> bool:
        for base, limit, _name in _REGIONS:
            if base <= addr <= limit:
                return True
        return False

    def _check_region(self, addr: int, length: int) -> None:
        """Verify every byte touched by an access of `length` bytes
        starting at `addr` falls within a modeled region."""
        for offset in range(length):
            a = addr + offset
            if not self._in_known_region(a):
                raise MemoryAccessError(
                    f"Access at 0x{a:08X} falls outside all modeled "
                    f"memory regions (Boot ROM / IMEM / DMEM)."
                )

    @staticmethod
    def _check_writable(addr: int, length: int) -> None:
        """Reject any ISA store (SB/SH/SW) that touches Boot ROM."""
        for offset in range(length):
            a = addr + offset
            if BOOT_ROM_BASE <= a <= BOOT_ROM_LIMIT:
                raise ReadOnlyMemoryError(
                    f"Store to 0x{a:08X} rejected: Boot ROM is read-only."
                )

    # --------------------------------------------------------------
    # Raw byte access
    # --------------------------------------------------------------

    def _read_byte(self, addr: int) -> int:
        return self._bytes.get(addr & MASK32, 0)

    def _write_byte(self, addr: int, value: int) -> None:
        self._bytes[addr & MASK32] = value & 0xFF

    # --------------------------------------------------------------
    # Public read/write API (Required Deliverables)
    # --------------------------------------------------------------

    def read8(self, addr: int) -> int:
        """Unsigned 8-bit read. Sign/zero extension (LB vs LBU) is the
        caller's responsibility -- see execute.py."""
        self._check_region(addr, 1)
        return self._read_byte(addr)

    def read16(self, addr: int) -> int:
        """Unsigned 16-bit little-endian read. Sign/zero extension
        (LH vs LHU) is the caller's responsibility."""
        self._check_region(addr, 2)
        lo = self._read_byte(addr)
        hi = self._read_byte(addr + 1)
        return lo | (hi << 8)

    def read32(self, addr: int) -> int:
        """Unsigned 32-bit little-endian read."""
        self._check_region(addr, 4)
        b0 = self._read_byte(addr)
        b1 = self._read_byte(addr + 1)
        b2 = self._read_byte(addr + 2)
        b3 = self._read_byte(addr + 3)
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

    def write8(self, addr: int, value: int) -> None:
        """Write the low 8 bits of `value` to `addr`. Raises
        ReadOnlyMemoryError if `addr` is in Boot ROM."""
        self._check_region(addr, 1)
        self._check_writable(addr, 1)
        self._write_byte(addr, value)

    def write16(self, addr: int, value: int) -> None:
        """Write the low 16 bits of `value`, little-endian, starting at
        `addr`. Raises ReadOnlyMemoryError if any touched byte is in
        Boot ROM."""
        self._check_region(addr, 2)
        self._check_writable(addr, 2)
        value = u32(value)
        self._write_byte(addr, value & 0xFF)
        self._write_byte(addr + 1, (value >> 8) & 0xFF)

    def write32(self, addr: int, value: int) -> None:
        """Write all 32 bits of `value`, little-endian, starting at
        `addr`. Raises ReadOnlyMemoryError if any touched byte is in
        Boot ROM."""
        self._check_region(addr, 4)
        self._check_writable(addr, 4)
        value = u32(value)
        self._write_byte(addr, value & 0xFF)
        self._write_byte(addr + 1, (value >> 8) & 0xFF)
        self._write_byte(addr + 2, (value >> 16) & 0xFF)
        self._write_byte(addr + 3, (value >> 24) & 0xFF)

    # --------------------------------------------------------------
    # Bulk loading helper (used by core.py's load_mem_file())
    # --------------------------------------------------------------

    def load_bytes(self, base_addr: int, data: bytes) -> None:
        """
        Load a raw byte blob into memory starting at `base_addr`.

        Used by core.py to populate Boot ROM / IMEM / DMEM from a binary
        or hex file at startup. Region checking is NOT bypassed here --
        an attempt to load outside a modeled region still raises
        MemoryAccessError, since that almost certainly means the memory
        file and the memory map have drifted apart.

        The read-only check IS bypassed (goes straight to _write_byte)
        since this is initial image loading, not an ISA store -- it's
        the only sanctioned way to put boot code into Boot ROM.
        """
        for i, b in enumerate(data):
            addr = base_addr + i
            self._check_region(addr, 1)
            self._write_byte(addr, b)
