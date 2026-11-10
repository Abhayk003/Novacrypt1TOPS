"""
core.py

Top-level ISS (Instruction Set Simulator) object for the RV32IM golden
reference model. Ties cpu_state / memory / csr / clint / decoder /
execute / trace together and implements the per-instruction execution
flow described at the top of the spec:

    1. Fetch instruction from memory using current PC.
    2. Decode instruction fields.
    3. Execute instruction.
    4. Update architectural state.
    5. Handle traps/interrupts if required.
    6. Emit retirement trace entry.
    7. Advance PC.

Steps 3/4/7 (for the common case) and step 5's *exception* half are
already handled inside execute.execute(), per that module's own
docstring: "execute() takes full ownership of updating state.pc for
whichever instruction it's given". core.py's job is:

  - step 1 (fetch) and step 2 (decode), before calling execute()
  - the *interrupt* half of step 5 -- mtime advance (Section 14), mip
    re-derivation (Section 9), and the pending-interrupt check
    (Section 11) -- which must run AFTER execute() so a CLINT register
    written by *this* instruction (e.g. a store to MSIP) or a
    just-ticked mtime crossing mtimecmp can trigger on the very same
    retiring step, and must be SKIPPED if this step already took a
    synchronous exception (Section 12: "Exception > Interrupt")
  - step 6 (assembling and recording the POST-instruction TraceEntry)

No new architectural behavior is invented here -- every ordering
decision below (tick-then-sync-then-check, exception-suppresses-
interrupt-this-step, trap_pc = the retiring instruction's own PC even
for interrupts) is already spelled out in csr.py's / clint.py's /
execute.py's own docstrings; this module just wires those documented
contracts together in the order they require.
"""

from typing import List, Optional

import clint
import csr
import decoder
import execute
from cpu_state import CPUState, u32
from memory import Memory
from trace import TraceEntry, TraceLog, make_default_entry
from bus import MemoryBus
from address_map import decode_address


class ISS:
    """
    Golden-model instruction set simulator.

    Owns one CPUState, one Memory, and one TraceLog. Exactly one
    retired instruction is executed per step() call (spec Section 16:
    "Golden model executes exactly one retired instruction at a
    time.") -- there is no pipelining, buffering, or lookahead of any
    kind here.
    """

    def __init__(self) -> None:
      self.state = CPUState()
      self.memory = Memory()
  
      # Centralized memory/peripheral access interface
      self.bus = MemoryBus(self.memory)
  
      self.trace_log = TraceLog()

    # ------------------------------------------------------------
    # Setup / reset
    # ------------------------------------------------------------

    def reset(self) -> None:
        """
        Reset architectural state to the spec's documented reset
        values (Section 1), via CPUState.reset().

        Memory contents are deliberately NOT cleared: on real
        hardware, Boot ROM / SRAM contents survive a reset pulse --
        only the CPU-internal architectural state (Section 1) is
        specified to reset. The trace log is also left alone; callers
        that want a clean trace after a reset should clear it
        explicitly via self.trace_log.clear().
        """
        self.state.reset()

    def load_mem_file(self, path: str, base_addr: int = 0x00000000) -> None:
        """
        Load a raw binary image into memory starting at `base_addr`.

        ASSUMPTION (not given by the spec): file format. Section 2
        only defines the memory map; nothing in the spec says whether
        a program image arrives as raw binary or as a text hex format
        (e.g. Verilog $readmemh). This method assumes raw binary,
        matching Memory.load_bytes()'s own docstring, which is the
        simplest, format-uniquely-defined choice. `base_addr` defaults
        to 0x00000000 (Boot ROM base), matching the Section 1 PC reset
        value, so a call with no `base_addr` argument loads straight
        into the reset vector. If your flow instead produces a
        $readmemh-style hex file, that needs a different parser (word
        width / @address convention are RTL-specific and not specified
        here) -- flag it and a dedicated loader can be added without
        disturbing this method's signature.

        Region checking is NOT bypassed: an image that doesn't fit
        entirely within Boot ROM / IMEM / DMEM raises
        memory.MemoryAccessError, per Memory.load_bytes()'s own
        design choice of surfacing a memory-map mismatch immediately.
        """
        with open(path, "rb") as f:
            data = f.read()
        self.memory.load_bytes(base_addr, data)

    # ------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------

    def step(self) -> TraceEntry:
        """
        Execute exactly one retired instruction and return its
        TraceEntry (also appended to self.trace_log).
        """
        state = self.state
        current_pc = u32(state.pc)

        # --- 1. Fetch -------------------------------------------------
        # Instruction fetch always goes through flat memory, never
        # CLINT -- CLINT is a data-only memory-mapped peripheral
        # (Section 14), and nothing in the spec suggests instructions
        # are ever fetched from it. No alignment check: Section 6
        # ("No misalignment traps observed in RTL") applies to fetch
        # the same as to loads/stores -- memory.read32() doesn't
        # enforce alignment, it only checks the access lands in a
        # modeled region.
        inst = self.memory.read32(current_pc)

        # --- 2. Decode --------------------------------------------------
        decoded = decoder.decode(inst)

        # --- 3/4. Execute + update state ---------------------------
        # execute() mutates state/memory directly and takes full
        # ownership of state.pc for this instruction -- including
        # synchronous-exception trap entry (illegal / ecall / ebreak),
        # which it performs itself via csr.take_trap(). See
        # execute.py's module docstring.
        result = execute.execute(
            state,
            self.bus,
            decoded,
            current_pc
        )

        # Did this step already take a synchronous exception? Per
        # Section 12 ("Exception > Interrupt"), if so, the interrupt
        # check below must be skipped entirely this step.
        exc_taken = result.is_illegal or result.is_ecall or result.is_ebreak
        trap_taken = exc_taken
        # Exceptions are fully resolved inside execute() by the time it
        # returns (nothing runs afterward that could move pc again this
        # step when exc_taken), so state.pc here is already the final
        # trap target (== mtvec).
        trap_target = u32(state.pc) if exc_taken else 0

        mret_taken = result.mret_taken
        # Snapshot the MRET redirect target NOW, before the interrupt
        # check below runs. csr.take_mret() already moved state.pc to
        # mepc; if an interrupt is *also* recognized later in this same
        # step (e.g. MRET just re-enabled MIE and something was already
        # pending), state.pc will be overwritten again to mtvec -- the
        # mret_target trace field should still reflect what MRET itself
        # did, independent of that later redirect.
        mret_target = u32(state.pc) if mret_taken else 0

        # --- 5. Traps/interrupts (interrupt half) -------------------
        # Section 14's recommended ISS behavior: mtime advances once
        # per retired instruction. Done unconditionally, then mip is
        # re-derived from live CLINT state (Section 9), then interrupt-
        # pending is evaluated (Section 11) -- all AFTER the
        # instruction's own effects, so a CLINT register this very
        # instruction just wrote (e.g. a store to MSIP) or an mtime
        # threshold just crossed by tick() can trigger on this same
        # retiring step. See clint.tick() / csr.sync_mip() docstrings.
        clint.tick(state)
        csr.sync_mip(state)

        if not exc_taken and not mret_taken:
            cause = csr.check_pending_interrupt(state)
            if cause is not None:
                # trap_pc is the PC of the instruction that just
                # retired THIS step (current_pc), not "the next
                # instruction" -- per csr.take_trap()'s documented
                # RTL convention, which applies even though this
                # instruction already completed normally (or was
                # itself an MRET/branch/jump -- take_trap()
                # unconditionally overwrites state.pc to mtvec,
                # superseding any redirect the instruction itself
                # produced).
                csr.take_trap(state, cause, True, current_pc)
                trap_taken = True
                trap_target = u32(state.pc)

        # --- 6. Emit retirement trace entry -------------------------
        # CSR fields are read back through csr.csr_read() (rather than
        # off raw CPUState fields) so the trace reflects exactly what
        # software would observe -- e.g. mstatus's hardwired MPP bits
        # and mip's live CLINT-derived value -- and are POST-
        # instruction, i.e. after the trap/interrupt handling above.
        f = decoded.fields
        entry = make_default_entry(
            pc=current_pc,
            opcode=f.opcode,
            funct3=f.funct3,
            funct7=f.funct7,
            rd=f.rd,
        )

        entry.reg_we = result.reg_we
        entry.wdata = u32(result.wdata)

        entry.mem_read = result.mem_read
        entry.mem_write = result.mem_write
        entry.mem_addr = u32(result.mem_addr)
        entry.mem_wdata = u32(result.mem_wdata)

        entry.branch_taken = result.branch_taken
        entry.jalr_taken = result.jalr_taken
        entry.redirect_target = (
            u32(result.redirect_target) if result.redirect_target is not None else 0
        )

        entry.trap_taken = trap_taken
        entry.exc_taken = exc_taken
        entry.trap_target = trap_target

        entry.mret_taken = mret_taken
        entry.mret_target = mret_target

        entry.is_ecall = result.is_ecall
        entry.is_ebreak = result.is_ebreak
        entry.is_illegal = result.is_illegal

        entry.load_misalign = result.load_misalign
        entry.store_misalign = result.store_misalign

        entry.mstatus = csr.csr_read(state, csr.CSR_MSTATUS)
        entry.mie = csr.csr_read(state, csr.CSR_MIE)
        entry.mtvec = csr.csr_read(state, csr.CSR_MTVEC)
        entry.mscratch = csr.csr_read(state, csr.CSR_MSCRATCH)
        entry.mepc = csr.csr_read(state, csr.CSR_MEPC)
        entry.mcause = csr.csr_read(state, csr.CSR_MCAUSE)
        entry.mtval = csr.csr_read(state, csr.CSR_MTVAL)
        entry.mip = csr.csr_read(state, csr.CSR_MIP)

        self.trace_log.record(entry)

        # --- 7. Advance PC ---------------------------------------------
        # Already done above -- by execute() for the normal/exception
        # case, or by the interrupt take_trap() call just now. Nothing
        # left to do.
        return entry

    def run(self, max_instructions: Optional[int] = None) -> int:
        """
        Repeatedly call step().

        If `max_instructions` is None, runs until an exception
        propagates out of step() -- most commonly
        memory.MemoryAccessError from fetching an unmapped address,
        which is the natural "ran off the end of the program" signal
        for this model (Section 16 defines no HALT instruction or
        other explicit stop condition, so none is invented here).
        Returns the number of instructions actually retired.
        """
        count = 0
        while max_instructions is None or count < max_instructions:
            self.step()
            count += 1
        return count

    def get_trace(self) -> List[str]:
        """
        Return the retirement trace as formatted lines (Section 15
        format), one per retired instruction, in retirement order --
        this is the representation meant for direct textual comparison
        against the RTL monitor's log.

        For other representations (list of TraceEntry objects, dicts,
        CSV), use self.trace_log directly (see trace.py).
        """
        return self.trace_log.as_lines()
        
    def register_peripheral(self, name: str, peripheral) -> None:
        """
        Register a peripheral model using the target name returned by
        address_map.decode_address().

        Example:
            iss.register_peripheral("UART", uart_model)

        The peripheral model must provide read(addr, size) and write(
        addr, value, size) methods. Addresses passed to it are absolute
        system addresses, not offsets.
        """
        valid_names = {"UART", "TIMER", "I2C", "SPI", "GPIO", "PLIC"}
        name = name.upper()

        if name not in valid_names:
            raise ValueError(
                f"Unknown peripheral '{name}'. Expected one of "
                f"{sorted(valid_names)}."
            )

        self.peripherals[name] = peripheral

    def read_bus_word(self, addr: int) -> int:
        """
        Read the aligned 32-bit word containing `addr`, routed using
        address_map.py's central decoder.
        """
        aligned_addr = u32(addr) & ~0x3
        target = decode_address(aligned_addr)

        if target in ("BOOT_ROM", "IMEM", "DMEM"):
            return self.memory.read32(aligned_addr)

        if target == "CLINT":
            return clint.clint_read(self.state, aligned_addr, 4)

        if target in ("UART", "TIMER", "I2C", "SPI", "GPIO", "PLIC"):
            peripheral = self.peripherals.get(target)
            if peripheral is None:
                raise RuntimeError(
                    f"{target} address 0x{aligned_addr:08X} was decoded, "
                    "but no peripheral model has been registered."
                )
            return u32(peripheral.read(aligned_addr, 4))

        if target == "APB_RESERVED":
            raise RuntimeError(
                f"Read from reserved APB address 0x{aligned_addr:08X}."
            )

        raise RuntimeError(
            f"Read from unmapped address 0x{aligned_addr:08X}."
        )

    def write_bus_word(self, addr: int, value: int) -> None:
        """
        Write a 32-bit word through address_map.py's central decoder.
        """
        aligned_addr = u32(addr) & ~0x3
        value = u32(value)
        target = decode_address(aligned_addr)

        if target in ("BOOT_ROM", "IMEM", "DMEM"):
            self.memory.write32(aligned_addr, value)
            return

        if target == "CLINT":
            clint.clint_write(self.state, aligned_addr, value, 4)
            return

        if target in ("UART", "TIMER", "I2C", "SPI", "GPIO", "PLIC"):
            peripheral = self.peripherals.get(target)
            if peripheral is None:
                raise RuntimeError(
                    f"{target} address 0x{aligned_addr:08X} was decoded, "
                    "but no peripheral model has been registered."
                )
            peripheral.write(aligned_addr, value, 4)
            return

        if target == "APB_RESERVED":
            raise RuntimeError(
                f"Write to reserved APB address 0x{aligned_addr:08X}."
            )

        raise RuntimeError(
            f"Write to unmapped address 0x{aligned_addr:08X}."
        )


# ==================================================================
# Self-test suite
# ==================================================================
# Hand-assembles small instruction sequences (using decoder.py's own
# opcode/funct3/funct7 constants, so a decode-table typo would show up
# as a test failure here too) and drives them through ISS end-to-end.
# This exercises the full fetch -> decode -> execute -> trap/interrupt
# -> trace pipeline, not just individual module unit behavior.
# ==================================================================

if __name__ == "__main__":
    from decoder import (
        OPCODE_LUI, OPCODE_JAL, OPCODE_BRANCH, OPCODE_LOAD, OPCODE_STORE,
        OPCODE_OP_IMM, OPCODE_OP, OPCODE_SYSTEM,
        FUNCT7_BASE, FUNCT7_MULDIV,
    )
    from memory import IMEM_BASE, DMEM_BASE
    from clint import ADDR_MSIP

    # ---- Minimal RV32I/M/Zicsr encoders, built directly from Section 3
    # ---- field layout / Section 4 immediate layout (mirrors decoder.py's
    # ---- own bit positions, so these are cross-checked against decode()
    # ---- below rather than independently guessed).

    def enc_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def enc_i(imm12: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
        return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    def enc_s(imm12: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
        imm12 &= 0xFFF
        imm_hi = (imm12 >> 5) & 0x7F
        imm_lo = imm12 & 0x1F
        return (imm_hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_lo << 7) | opcode

    def enc_b(imm13: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
        imm13 &= 0x1FFF
        bit12 = (imm13 >> 12) & 1
        bit11 = (imm13 >> 11) & 1
        bits10_5 = (imm13 >> 5) & 0x3F
        bits4_1 = (imm13 >> 1) & 0xF
        return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
               (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | opcode

    def enc_u(imm20: int, rd: int, opcode: int) -> int:
        return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

    def enc_j(imm21: int, rd: int, opcode: int) -> int:
        imm21 &= 0x1FFFFF
        bit20 = (imm21 >> 20) & 1
        bits10_1 = (imm21 >> 1) & 0x3FF
        bit11 = (imm21 >> 11) & 1
        bits19_12 = (imm21 >> 12) & 0xFF
        return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | opcode

    ADDI = lambda rd, rs1, imm: enc_i(imm, rs1, 0b000, rd, OPCODE_OP_IMM)
    ADD = lambda rd, rs1, rs2: enc_r(FUNCT7_BASE, rs2, rs1, 0b000, rd, OPCODE_OP)
    MUL = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b000, rd, OPCODE_OP)
    DIV = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b100, rd, OPCODE_OP)
    REM = lambda rd, rs1, rs2: enc_r(FUNCT7_MULDIV, rs2, rs1, 0b110, rd, OPCODE_OP)
    LUI = lambda rd, imm20: enc_u(imm20, rd, OPCODE_LUI)
    SW = lambda rs2, imm, rs1: enc_s(imm, rs2, rs1, 0b010, OPCODE_STORE)
    LW = lambda rd, imm, rs1: enc_i(imm, rs1, 0b010, rd, OPCODE_LOAD)
    BEQ = lambda rs1, rs2, imm: enc_b(imm, rs2, rs1, 0b000, OPCODE_BRANCH)
    JAL = lambda rd, imm: enc_j(imm, rd, OPCODE_JAL)
    CSRRW = lambda rd, csr_addr, rs1: enc_i(csr_addr, rs1, 0b001, rd, OPCODE_SYSTEM)
    CSRRS = lambda rd, csr_addr, rs1: enc_i(csr_addr, rs1, 0b010, rd, OPCODE_SYSTEM)

    from decoder import FUNCT12_MRET
    MRET_INST = enc_i(FUNCT12_MRET, 0, 0b000, 0, OPCODE_SYSTEM)

    def load_program(iss: "ISS", words: List[int], base: int = IMEM_BASE) -> None:
        data = bytearray()
        for w in words:
            data += (w & 0xFFFFFFFF).to_bytes(4, "little")
        iss.memory.load_bytes(base, bytes(data))
        iss.state.pc = base

    failures = []

    def check(label: str, cond: bool) -> None:
        status = "PASS" if cond else "FAIL"
        print(f"[{status}] {label}")
        if not cond:
            failures.append(label)

    # ---- Arithmetic --------------------------------------------------
    iss = ISS()
    load_program(iss, [
        ADDI(1, 0, 5),
        ADDI(2, 0, 7),
        ADD(3, 1, 2),
    ])
    for _ in range(3):
        iss.step()
    check("arithmetic: ADD x3 = x1+x2 == 12", iss.state.regs[3] == 12)

    # ---- Branches ------------------------------------------------------
    iss = ISS()
    load_program(iss, [
        BEQ(0, 0, 8),          # +0: taken, skip next instr
        ADDI(5, 0, 0x7FF),     # +4: should NOT execute
        ADDI(6, 0, 1),         # +8: branch target
    ])
    e = iss.step()
    check("branch: BEQ x0,x0 taken", e.branch_taken and iss.state.pc == IMEM_BASE + 8)
    iss.step()
    check("branch: skipped instruction never executed (x5==0)", iss.state.regs[5] == 0)
    check("branch: target instruction executed (x6==1)", iss.state.regs[6] == 1)

    # ---- Jumps ---------------------------------------------------------
    iss = ISS()
    load_program(iss, [
        JAL(1, 8),
    ])
    e = iss.step()
    check("jump: JAL link == pc+4", iss.state.regs[1] == IMEM_BASE + 4)
    check("jump: JAL target == pc+8", iss.state.pc == IMEM_BASE + 8)

    # ---- Loads / Stores --------------------------------------------
    iss = ISS()
    load_program(iss, [
        LUI(5, DMEM_BASE >> 12),      # x5 = DMEM_BASE
        ADDI(1, 0, 0x123),            # x1 = 0x123
        SW(1, 0, 5),                  # mem[x5] = x1
        LW(6, 0, 5),                  # x6 = mem[x5]
    ])
    for _ in range(4):
        iss.step()
    check("load/store: round-trip through DMEM", iss.state.regs[6] == 0x123)

    # ---- Multiply --------------------------------------------------
    iss = ISS()
    load_program(iss, [
        ADDI(1, 0, 5),
        ADDI(2, 0, 7),
        MUL(3, 1, 2),
    ])
    for _ in range(3):
        iss.step()
    check("multiply: MUL 5*7 == 35", iss.state.regs[3] == 35)

    # ---- Divide ------------------------------------------------------
    iss = ISS()
    load_program(iss, [
        ADDI(1, 0, 7),
        ADDI(2, 0, 5),
        DIV(3, 1, 2),
        REM(4, 1, 2),
    ])
    for _ in range(4):
        iss.step()
    check("divide: DIV 7/5 == 1", iss.state.regs[3] == 1)
    check("divide: REM 7%5 == 2", iss.state.regs[4] == 2)

    # ---- Divide by zero ---------------------------------------------
    iss = ISS()
    load_program(iss, [
        ADDI(1, 0, 5),
        DIV(2, 1, 0),   # divisor x0 == 0
        REM(3, 1, 0),
    ])
    for _ in range(3):
        iss.step()
    check("div-by-zero: DIV x/0 == 0xFFFFFFFF", iss.state.regs[2] == 0xFFFFFFFF)
    check("div-by-zero: REM x/0 == dividend", iss.state.regs[3] == 5)

    # ---- CSR operations ------------------------------------------------
    iss = ISS()
    load_program(iss, [
        ADDI(1, 0, 0x123),
        CSRRW(2, csr.CSR_MSCRATCH, 1),   # x2 = old mscratch (0); mscratch = 0x123
        CSRRS(3, csr.CSR_MSCRATCH, 0),   # x3 = mscratch (src=x0=0, no change)
    ])
    for _ in range(3):
        iss.step()
    check("csr: CSRRW returns old value (0)", iss.state.regs[2] == 0)
    check("csr: mscratch updated to 0x123", iss.state.mscratch == 0x123)
    check("csr: CSRRS read-back == 0x123", iss.state.regs[3] == 0x123)

    # ---- Interrupt entry (MSIP) -------------------------------------
    # Program: set mtvec, enable mie.MSIE + mstatus.MIE, then store to
    # the CLINT MSIP register -- the interrupt must be recognized on
    # this SAME retiring instruction (Section 14 tick-then-check order).
    MTVEC_TARGET = IMEM_BASE + 0x100
    iss = ISS()
    words = [
        LUI(10, MTVEC_TARGET >> 12),            # 0: x10 = upper(mtvec)
        ADDI(10, 10, MTVEC_TARGET & 0xFFF),     # 4: x10 = mtvec target
        CSRRW(0, csr.CSR_MTVEC, 10),            # 8: mtvec = x10
        ADDI(11, 0, 1 << csr.MIE_MSIE_BIT),     # 12: x11 = MSIE mask
        CSRRS(0, csr.CSR_MIE, 11),              # 16: mie |= MSIE
        ADDI(12, 0, 1 << csr.MSTATUS_MIE_BIT),  # 20: x12 = mstatus.MIE mask
        CSRRS(0, csr.CSR_MSTATUS, 12),          # 24: mstatus.MIE = 1
        LUI(13, ADDR_MSIP >> 12),               # 28: x13 = CLINT MSIP addr
        ADDI(14, 0, 1),                         # 32: x14 = 1
        SW(14, 0, 13),                          # 36: MSIP = 1 -> interrupt fires here
    ]
    load_program(iss, words)
    sw_pc = IMEM_BASE + 9 * 4
    last_entry = None
    for _ in range(len(words)):
        last_entry = iss.step()
    check("interrupt: fires on the MSIP-writing instruction itself",
          last_entry.trap_taken and not last_entry.exc_taken)
    check("interrupt: mcause == (1<<31)|MSI(3)", iss.state.mcause == ((1 << 31) | csr.CAUSE_MSI))
    check("interrupt: mepc == retiring instruction's own pc", iss.state.mepc == sw_pc)
    check("interrupt: pc redirected to mtvec", iss.state.pc == MTVEC_TARGET)
    check("interrupt: trace trap_target == mtvec", last_entry.trap_target == MTVEC_TARGET)

    # ---- MRET return -----------------------------------------------
    iss = ISS()
    MEPC_TARGET = IMEM_BASE + 0x200
    iss.state.mepc = MEPC_TARGET
    csr.set_mpie_bit(iss.state, 1)
    csr.set_mie_bit(iss.state, 0)
    load_program(iss, [MRET_INST])
    e = iss.step()
    check("mret: pc restored from mepc", iss.state.pc == MEPC_TARGET)
    check("mret: MIE restored from MPIE (1)", csr.get_mie_bit(iss.state) == 1)
    check("mret: MPIE set to 1 unconditionally", csr.get_mpie_bit(iss.state) == 1)
    check("mret: trace mret_taken/mret_target", e.mret_taken and e.mret_target == MEPC_TARGET)

    # ---- Summary -----------------------------------------------------
    print()
    if failures:
        print(f"{len(failures)} FAILURE(S):")
        for f_name in failures:
            print(f"  - {f_name}")
        raise SystemExit(1)
    else:
        print("All self-tests passed.")
