import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from memory import Memory, MemoryAccessError, ReadOnlyMemoryError, BOOT_ROM_BASE, IMEM_BASE
from decoder import decode, Mnemonic

failures = []
def check(label, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label}")
    if not cond:
        failures.append(label)

# ---- Boot ROM is read-only to ISA stores ----
m = Memory()
m.load_bytes(BOOT_ROM_BASE, b"\x01\x02\x03\x04")  # load_bytes bypasses the RO check (boot image load)
try:
    m.write8(BOOT_ROM_BASE, 0xFF)
    check("boot rom write raises ReadOnlyMemoryError", False)
except ReadOnlyMemoryError:
    check("boot rom write raises ReadOnlyMemoryError", True)

# ---- Access outside all modeled regions is a hard error ----
try:
    m.read32(0x00040000)  # not Boot ROM / IMEM / DMEM
    check("unmapped read raises MemoryAccessError", False)
except MemoryAccessError:
    check("unmapped read raises MemoryAccessError", True)

# ---- Decoder: invalid funct7 on SLLI must decode ILLEGAL ----
# SLLI requires funct7 == FUNCT7_BASE (0000000); using FUNCT7_ALT (0100000) instead
# is not a valid SLLI encoding.
bad_slli = (0b0100000 << 25) | (5 << 20) | (1 << 15) | (0b001 << 12) | (2 << 7) | 0b0010011
d = decode(bad_slli)
check("bad-funct7 SLLI decodes ILLEGAL", d.mnemonic == Mnemonic.ILLEGAL)

# ---- Decoder: JALR requires funct3 == 000; anything else is ILLEGAL ----
bad_jalr = (0 << 20) | (1 << 15) | (0b001 << 12) | (2 << 7) | 0b1100111
d2 = decode(bad_jalr)
check("bad-funct3 JALR decodes ILLEGAL", d2.mnemonic == Mnemonic.ILLEGAL)

print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
else:
    print("All round-3 tests passed.")
