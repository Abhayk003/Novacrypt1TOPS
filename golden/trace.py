"""
trace.py
--------
Retirement trace generation for the RV32IM golden model.

This module is intentionally decoupled from cpu_state / csr / execute:
it does not import architectural state directly. Instead, core.py is
responsible for assembling a TraceEntry after each retired instruction
(step 6 of the execution flow) and handing it to a TraceLog. This keeps
trace formatting independent and easy to unit-test in isolation, per
the "keep modules independent and easy to debug" requirement.

Field order below matches SPEC section 15 EXACTLY. Do not reorder
fields without updating the RTL-side trace comparator in lockstep.

RTL-specific notes:
  * CSR fields (mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip)
    are POST-INSTRUCTION values, per spec section 15's explicit note.
    core.py must snapshot these AFTER trap/interrupt/mret handling
    (execution flow steps 4-5), not before.
  * load_misalign / store_misalign are carried as trace fields even
    though spec section 6 states "No misalignment traps observed in
    RTL" -- the golden model never sets these, but the RTL monitor's
    trace schema still expects the columns for line-format parity.
  * Boolean fields are emitted as 0/1 (not True/False) since the trace
    is diffed textually against an RTL-emitted log.
"""

from dataclasses import dataclass, fields, asdict
from typing import List, Dict, Any, Optional


# ------------------------------------------------------------------
# Trace field order (spec section 15) -- single source of truth.
# ------------------------------------------------------------------
TRACE_FIELDS: List[str] = [
    "pc",
    "opcode",
    "funct3",
    "funct7",
    "rd",
    "reg_we",
    "wdata",
    "mem_read",
    "mem_write",
    "mem_addr",
    "mem_wdata",
    "branch_taken",
    "jalr_taken",
    "redirect_target",
    "trap_taken",
    "exc_taken",
    "trap_target",
    "mret_taken",
    "mret_target",
    "is_ecall",
    "is_ebreak",
    "is_illegal",
    "load_misalign",
    "store_misalign",
    "mstatus",
    "mie",
    "mtvec",
    "mscratch",
    "mepc",
    "mcause",
    "mtval",
    "mip",
]

# Fields that are conceptually boolean/single-bit flags. Everything
# else in TRACE_FIELDS is treated as an integer (register/CSR width).
_BOOL_FIELDS = {
    "reg_we",
    "mem_read",
    "mem_write",
    "branch_taken",
    "jalr_taken",
    "trap_taken",
    "exc_taken",
    "mret_taken",
    "is_ecall",
    "is_ebreak",
    "is_illegal",
    "load_misalign",
    "store_misalign",
}

# Hex field widths (in nibbles) for fixed-width text formatting.
# 32-bit values -> 8 nibbles. Narrow instruction-field values get
# just enough nibbles to hold their bit width, rounded to a nibble.
_HEX_WIDTH = {
    "pc": 8,
    "opcode": 2,   # 7 bits
    "funct3": 1,   # 3 bits
    "funct7": 2,   # 7 bits
    "rd": 2,       # 5 bits
    "wdata": 8,
    "mem_addr": 8,
    "mem_wdata": 8,
    "redirect_target": 8,
    "trap_target": 8,
    "mret_target": 8,
    "mstatus": 8,
    "mie": 8,
    "mtvec": 8,
    "mscratch": 8,
    "mepc": 8,
    "mcause": 8,
    "mtval": 8,
    "mip": 8,
}


def _mask(value: int, bits: int) -> int:
    """Mask an internal Python int down to `bits` bits for display.

    Trace formatting must never let a negative or oversized Python
    int leak into the RTL-comparable text output.
    """
    return value & ((1 << bits) - 1)


@dataclass
class TraceEntry:
    """One retired instruction's worth of trace data.

    All integer fields are stored as plain (already-masked) Python
    ints. Callers (core.py) are expected to pass 32-bit-masked values
    for register/CSR/address fields; this class re-masks defensively
    on formatting so a caller mistake can't corrupt the trace text.
    """

    pc: int = 0
    opcode: int = 0
    funct3: int = 0
    funct7: int = 0
    rd: int = 0
    reg_we: bool = False
    wdata: int = 0

    mem_read: bool = False
    mem_write: bool = False
    mem_addr: int = 0
    mem_wdata: int = 0

    branch_taken: bool = False
    jalr_taken: bool = False
    redirect_target: int = 0

    trap_taken: bool = False
    exc_taken: bool = False
    trap_target: int = 0

    mret_taken: bool = False
    mret_target: int = 0

    is_ecall: bool = False
    is_ebreak: bool = False
    is_illegal: bool = False

    load_misalign: bool = False
    store_misalign: bool = False

    # CSR state -- POST-INSTRUCTION values (see module docstring).
    mstatus: int = 0
    mie: int = 0
    mtvec: int = 0
    mscratch: int = 0
    mepc: int = 0
    mcause: int = 0
    mtval: int = 0
    mip: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Return fields in canonical spec order as a plain dict."""
        d = asdict(self)
        return {name: d[name] for name in TRACE_FIELDS}

    def to_line(self) -> str:
        """Render as one whitespace-separated trace line.

        Integers are printed as fixed-width hex; booleans as 0/1.
        Column order is TRACE_FIELDS (spec section 15).
        """
        parts = []
        d = self.to_dict()
        for name in TRACE_FIELDS:
            value = d[name]
            if name in _BOOL_FIELDS:
                parts.append("1" if value else "0")
            else:
                width = _HEX_WIDTH.get(name, 8)
                masked = _mask(int(value), width * 4)
                parts.append(f"{masked:0{width}x}")
        return " ".join(parts)

    def to_csv_row(self) -> str:
        """Render as a comma-separated row (decimal ints, 0/1 bools).

        Useful for spreadsheet-based debugging alongside the RTL
        waveform, as opposed to to_line()'s hex format meant for
        direct textual diffing against the RTL monitor's log.
        """
        d = self.to_dict()
        parts = []
        for name in TRACE_FIELDS:
            value = d[name]
            if name in _BOOL_FIELDS:
                parts.append("1" if value else "0")
            else:
                parts.append(str(int(value)))
        return ",".join(parts)


class TraceLog:
    """Accumulates TraceEntry records for the whole simulation run.

    core.py should instantiate one TraceLog, call record() once per
    retired instruction (execution flow step 6), and expose it via
    get_trace().
    """

    def __init__(self) -> None:
        self._entries: List[TraceEntry] = []

    def record(self, entry: TraceEntry) -> None:
        self._entries.append(entry)

    def __len__(self) -> int:
        return len(self._entries)

    def clear(self) -> None:
        self._entries.clear()

    def entries(self) -> List[TraceEntry]:
        """Raw TraceEntry objects, in retirement order."""
        return list(self._entries)

    def as_dicts(self) -> List[Dict[str, Any]]:
        return [e.to_dict() for e in self._entries]

    def as_lines(self) -> List[str]:
        """Hex-formatted lines, one per retired instruction, in
        the exact column order required for RTL trace comparison.
        """
        return [e.to_line() for e in self._entries]

    def header_line(self) -> str:
        """Column-name header, useful when dumping to a text file
        for human inspection (not required for RTL comparison, which
        is positional/columnar per spec).
        """
        return " ".join(TRACE_FIELDS)

    def dump_text(self, path: str, with_header: bool = False) -> None:
        with open(path, "w") as f:
            if with_header:
                f.write(self.header_line() + "\n")
            for line in self.as_lines():
                f.write(line + "\n")

    def dump_csv(self, path: str) -> None:
        with open(path, "w") as f:
            f.write(",".join(TRACE_FIELDS) + "\n")
            for e in self._entries:
                f.write(e.to_csv_row() + "\n")


def make_default_entry(pc: int, opcode: int, funct3: int, funct7: int,
                        rd: int) -> TraceEntry:
    """Convenience constructor for the common case: start from an
    all-zero/false entry stamped with the instruction's static decode
    fields, then let the execute-stage caller fill in the dynamic
    fields (reg_we, wdata, mem_*, branch/jalr/trap/mret flags, and
    post-instruction CSR snapshot) via direct attribute assignment.

    Example (in core.py):

        entry = make_default_entry(pc, opcode, funct3, funct7, rd)
        entry.reg_we = True
        entry.wdata = result
        ... (set trap/exc/mret fields as applicable) ...
        entry.mstatus = csr.mstatus   # POST-instruction snapshot
        ...
        trace_log.record(entry)
    """
    return TraceEntry(pc=pc, opcode=opcode, funct3=funct3, funct7=funct7,
                       rd=rd)


# ------------------------------------------------------------------
# Self-test: verifies field order, hex widths, and bool rendering.
# This is a formatting-only smoke test -- it does not exercise the
# CPU/decoder/execute modules, which have their own validation.
# ------------------------------------------------------------------
if __name__ == "__main__":
    # Sanity: TRACE_FIELDS must exactly match TraceEntry's dataclass
    # field order, since to_dict()/to_line() rely on that mapping.
    dc_fields = [f.name for f in fields(TraceEntry)]
    assert dc_fields == TRACE_FIELDS, (
        "TraceEntry field order drifted from TRACE_FIELDS spec list"
    )

    log = TraceLog()

    # Simulated ADDI x1, x0, 5 retiring at pc=0x10000
    e1 = make_default_entry(pc=0x10000, opcode=0x13, funct3=0x0,
                             funct7=0x0, rd=1)
    e1.reg_we = True
    e1.wdata = 5
    e1.mstatus = 0
    e1.mie = 0
    e1.mtvec = 0
    e1.mscratch = 0
    e1.mepc = 0
    e1.mcause = 0
    e1.mtval = 0
    e1.mip = 0
    log.record(e1)

    # Simulated illegal-instruction exception trap entry
    e2 = make_default_entry(pc=0x10004, opcode=0x7f, funct3=0x0,
                             funct7=0x0, rd=0)
    e2.is_illegal = True
    e2.exc_taken = True
    e2.trap_taken = True
    e2.trap_target = 0x00000000
    e2.mepc = 0x10004
    e2.mcause = 2  # illegal instruction exception code
    log.record(e2)

    assert len(log) == 2
    lines = log.as_lines()
    assert len(lines) == 2
    # 32 columns per line
    for line in lines:
        assert len(line.split()) == len(TRACE_FIELDS)

    # Spot-check hex formatting on entry 1
    cols = lines[0].split()
    field_index = {name: i for i, name in enumerate(TRACE_FIELDS)}
    assert cols[field_index["pc"]] == "00010000"
    assert cols[field_index["reg_we"]] == "1"
    assert cols[field_index["wdata"]] == "00000005"
    assert cols[field_index["mem_read"]] == "0"

    # Spot-check trap entry
    cols2 = lines[1].split()
    assert cols2[field_index["is_illegal"]] == "1"
    assert cols2[field_index["exc_taken"]] == "1"
    assert cols2[field_index["mcause"]] == "00000002"
    assert cols2[field_index["trap_target"]] == "00000000"

    print("trace.py self-test: OK")
    print(log.header_line())
    for line in lines:
        print(line)
