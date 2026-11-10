import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import ISS
import csr
from decoder import decode, Mnemonic, OPCODE_OP_IMM, OPCODE_SYSTEM, FUNCT12_MRET
from memory import IMEM_BASE

failures = []
def check(label, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label}")
    if not cond:
        failures.append(label)

def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

ADDI = lambda rd, rs1, imm: enc_i(imm, rs1, 0b000, rd, OPCODE_OP_IMM)
MRET_INST = enc_i(FUNCT12_MRET, 0, 0b000, 0, OPCODE_SYSTEM)

def load_program(iss, words, base=IMEM_BASE):
    data = bytearray()
    for w in words:
        data += (w & 0xFFFFFFFF).to_bytes(4, "little")
    iss.memory.load_bytes(base, bytes(data))
    iss.state.pc = base

# =====================================================================
# 1) Invalid SYSTEM encodings
#
# opcode=SYSTEM, funct3=000, but the immediate/csr_addr field (inst[31:20])
# is none of ECALL(0x000)/EBREAK(0x001)/MRET(0x302) -> must decode ILLEGAL.
# =====================================================================
invalid_system_words = [0x00200073, 0x12300073, 0x55500073]

for w in invalid_system_words:
    d = decode(w)
    check(f"invalid SYSTEM 0x{w:08X} decodes Mnemonic.ILLEGAL",
          d.mnemonic == Mnemonic.ILLEGAL)
    check(f"invalid SYSTEM 0x{w:08X} is NOT ECALL/EBREAK/MRET",
          d.mnemonic not in (Mnemonic.ECALL, Mnemonic.EBREAK, Mnemonic.MRET))

# =====================================================================
# 2) Pending interrupt while global mstatus.MIE=0
#
# mie.MSIE=1 and msip=1 (interrupt pending+individually-enabled), but
# mstatus.MIE=0 (globally disabled) -> interrupt must NOT be taken.
# =====================================================================
iss = ISS()
csr.set_mie_bit(iss.state, 0)                    # mstatus.MIE = 0
iss.state.mie = (1 << csr.MIE_MSIE_BIT)          # mie.MSIE = 1
iss.state.msip = 1                                # pending software interrupt
load_program(iss, [ADDI(1, 0, 5)])               # one ordinary instruction

mepc_before = iss.state.mepc
mcause_before = iss.state.mcause

e = iss.step()

check("MIE=0: interrupt NOT taken (trap_taken false)", not e.trap_taken)
check("MIE=0: pc increments normally (pc == base+4)", iss.state.pc == IMEM_BASE + 4)
check("MIE=0: mepc unchanged", iss.state.mepc == mepc_before)
check("MIE=0: mcause unchanged", iss.state.mcause == mcause_before)
check("MIE=0: instruction itself still executed normally (x1==5)",
      iss.state.regs[1] == 5)

# =====================================================================
# 3) MRET when MPIE=0
#
#   MIE  <- MPIE (=0)
#   MPIE <- 1 (unconditionally)
#   PC   <- mepc
# =====================================================================
iss = ISS()
csr.set_mie_bit(iss.state, 0)     # mstatus.MIE  = 0
csr.set_mpie_bit(iss.state, 0)    # mstatus.MPIE = 0
iss.state.mepc = 0x12345678
load_program(iss, [MRET_INST])

e = iss.step()

check("MRET (MPIE=0): MIE <- MPIE == 0", csr.get_mie_bit(iss.state) == 0)
check("MRET (MPIE=0): MPIE <- 1 unconditionally", csr.get_mpie_bit(iss.state) == 1)
check("MRET (MPIE=0): PC <- mepc == 0x12345678", iss.state.pc == 0x12345678)
check("MRET (MPIE=0): trace mret_taken/mret_target correct",
      e.mret_taken and e.mret_target == 0x12345678)

print()
if failures:
    print(f"{len(failures)} FAILURE(S):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
else:
    print("All round-4 tests passed.")
