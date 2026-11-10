#!/usr/bin/env python3
"""Persistent live golden-model server for the UVM reference model.

The UVM side talks to this process through a tiny line-delimited JSON protocol.
The server owns one ISS instance per simulation and never pre-runs the program.

Commands:
  {"cmd":"init", "instr":..., "dmem":...}
  {"cmd":"irq", "line":"timer|software|external", "value":0|1}
  {"cmd":"step"}
  {"cmd":"dump_dmem", "path":...}
  {"cmd":"stop"}

step() advances the ISS until the next architectural data-memory operation,
then returns the expected AXI-visible event. This preserves the existing
black-box scoreboard's useful observation boundary while removing the offline
bus-trace coupling.
"""
import argparse
import json
import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import ISS
from memory import DMEM_BASE, DMEM_LIMIT, BOOT_ROM_BASE


def load_readmemh(path, iss):
    """Load the UVM $readmemh-style sparse image into the ISS memory."""
    if not path:
        return
    word_index = 0
    with open(path, "r") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("@"):
                word_index = int(line[1:], 16)
                continue
            word = int(line.split()[0], 16) & 0xFFFFFFFF
            addr = word_index << 2
            iss.memory.load_bytes(addr, word.to_bytes(4, "little"))
            word_index += 1


def apply_lane_replication(funct3, addr, raw_value):
    raw_value &= 0xFFFFFFFF
    if funct3 == 0b000:  # SB
        b = raw_value & 0xFF
        return b | (b << 8) | (b << 16) | (b << 24), 1 << (addr & 0x3)
    if funct3 == 0b001:  # SH
        h = raw_value & 0xFFFF
        return h | (h << 16), 0b1100 if (addr & 0x2) else 0b0011
    return raw_value, 0b1111  # SW


class GoldenSession:
    def __init__(self):
        self.iss = None
        self.irq = {"timer": 0, "software": 0, "external": 0}

    def init(self, instr_path, dmem_path):
        self.iss = ISS()
        self.irq = {"timer": 0, "software": 0, "external": 0}
        load_readmemh(instr_path, self.iss)
        load_readmemh(dmem_path, self.iss)
        self.iss.reset()

    def set_irq(self, line, value):
        if line not in self.irq:
            raise ValueError("unknown IRQ line: %s" % line)
        value = 1 if value else 0
        self.irq[line] = value
        self.iss.state.timer_irq = self.irq["timer"]
        self.iss.state.software_irq = self.irq["software"]
        self.iss.state.external_irq = self.irq["external"]
        

    def step_to_data_event(self, max_steps=100000):
        if self.iss is None:
            raise RuntimeError("golden model not initialized")

        for _ in range(max_steps):
            # Inputs are live state on the architectural model. They are sampled
            # by core.py's interrupt check after each retired instruction.
            self.iss.state.timer_irq = self.irq["timer"]
            self.iss.state.software_irq = self.irq["software"]
            self.iss.state.external_irq = self.irq["external"]

            entry = self.iss.step()
            if entry.mem_write:
                data, strb = apply_lane_replication(
                    entry.funct3, entry.mem_addr, entry.mem_wdata
                )
                return {
                    "kind": "W",
                    "pc": entry.pc,
                    "opcode": entry.opcode,
    		    "funct3": entry.funct3,
   		    "funct7": entry.funct7,
                    "addr": entry.mem_addr,
                    "data": data,
                    "strb": strb,
                }
            if entry.mem_read:
              # AXI RDATA is the full 32-bit word containing the requested
              # memory address. The CPU performs byte/halfword extraction
              # and signed/unsigned extension internally.
              #
              # Align the load address to the containing 32-bit word.
              word_addr = entry.mem_addr & ~0x3
              rdata = self.iss.read_bus_word(word_addr)
          
              return {
                  "kind": "R",
                  "pc": entry.pc,
                  "opcode": entry.opcode,
                  "funct3": entry.funct3,
                  "funct7": entry.funct7,
                  "addr": entry.mem_addr,
                  "rdata": rdata & 0xFFFFFFFF,
              }
#                
#            if entry.mem_read:
#              raw_value = entry.wdata & 0xFFFFFFFF
#          
#              if entry.funct3 == 0b000:          # LB
#                  byte_value = raw_value & 0xFF
#          
#                  # Sign-extended byte replicated on AXI bus
#                  rdata = (
#                      byte_value
#                      | (byte_value << 8)
#                      | (byte_value << 16)
#                      | (byte_value << 24)
#                  )
#          
#              elif entry.funct3 == 0b100:        # LBU
#                  byte_value = raw_value & 0xFF
#          
#                  # Zero-extended byte
#                  rdata = byte_value
#          
#              elif entry.funct3 == 0b001:        # LH
#                  half_value = raw_value & 0xFFFF
#          
#                  # Halfword replicated on AXI bus
#                  rdata = half_value | (half_value << 16)
#          
#              elif entry.funct3 == 0b101:        # LHU
#                  half_value = raw_value & 0xFFFF
#          
#                  # Zero-extended halfword
#                  rdata = half_value
#          
#              elif entry.funct3 == 0b010:        # LW
#                  rdata = raw_value
#          
#              else:
#                  raise ValueError(
#                      "unsupported load funct3: %03b" % entry.funct3
#                  )
#          
#              return {
#                  "kind": "R",
#                  "pc": entry.pc,
#                  "opcode": entry.opcode,
#                  "funct3": entry.funct3,
#                  "funct7": entry.funct7,
#                  "addr": entry.mem_addr,
#                  "rdata": rdata & 0xFFFFFFFF,
#              }
#            if entry.mem_read:
#              # The DUT returns load data replicated across the 32-bit AXI RDATA bus:
#              #
#              #   LB/LBU -> byte replicated 4 times
#              #   LH/LHU -> halfword replicated 2 times
#              #   LW     -> full 32-bit word
#              #
#              # entry.wdata is the architectural load result produced by the ISS.
#              raw_value = entry.wdata & 0xFFFFFFFF
          
#              if entry.funct3 in (0b000, 0b100):       # LB / LBU
#                  byte_value = raw_value & 0xFF
#                  rdata = (
#                      byte_value
#                      | (byte_value << 8)
#                      | (byte_value << 16)
#                      | (byte_value << 24)
#                  )
#          
#              elif entry.funct3 in (0b001, 0b101):     # LH / LHU
#                  half_value = raw_value & 0xFFFF
#                  rdata = half_value | (half_value << 16)
#          
#              elif entry.funct3 == 0b010:              # LW
#                  rdata = raw_value
#          
#              else:
#                  raise ValueError(
#                      "unsupported load funct3: %03b" % entry.funct3
#                  )
          
#              return {
#                  "kind": "R",
#                  "pc": entry.pc,
#                  "opcode": entry.opcode,
#                  "funct3": entry.funct3,
#                  "funct7": entry.funct7,
#                  "addr": entry.mem_addr,
#                  "rdata": rdata & 0xFFFFFFFF,
#              }

        raise RuntimeError("golden step cap reached without a data-bus event")

    def dump_dmem(self, path):
        if self.iss is None:
            raise RuntimeError("golden model not initialized")
        with open(path, "w") as f:
            addr = DMEM_BASE
            while addr <= DMEM_LIMIT:
                f.write("%08x\n" % self.iss.memory.read32(addr))
                addr += 4


def serve(host, port):
    session = GoldenSession()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((host, port))
        srv.listen(1)

        print(
            "golden_server listening on %s:%d" % (host, port),
            flush=True
        )

        while True:
            conn, addr = srv.accept()

            print(
                "golden_server connected by %s:%d" % addr,
                flush=True
            )

            with conn:
                fp = conn.makefile("rwb")

                for raw in fp:
                    try:
                        req = json.loads(raw.decode("utf-8"))
                        cmd = req.get("cmd")

                        if cmd == "init":
                            session.init(
                                req["instr"],
                                req.get("dmem", "")
                            )
                            resp = {"ok": True}

                        elif cmd == "irq":
                            session.set_irq(
                                req["line"],
                                req["value"]
                            )
                            resp = {"ok": True}

                        elif cmd == "step":
                            resp = {
                                "ok": True,
                                "event": session.step_to_data_event()
                            }

                        elif cmd == "dump_dmem":
                            session.dump_dmem(req["path"])
                            resp = {"ok": True}

                        elif cmd == "stop":
                            resp = {"ok": True}

                            fp.write(
                                (json.dumps(resp) + "\n").encode("utf-8")
                            )
                            fp.flush()

                            break

                        else:
                            raise ValueError(
                                "unknown command %r" % cmd
                            )

                    except Exception as exc:
                        resp = {
                            "ok": False,
                            "error": "%s: %s" % (
                                type(exc).__name__,
                                exc
                            )
                        }

                    fp.write(
                        (
                            json.dumps(
                                resp,
                                separators=(",", ":")
                            ) + "\n"
                        ).encode("utf-8")
                    )
                    fp.flush()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=45721)
    args = ap.parse_args()
    serve(args.host, args.port)


if __name__ == "__main__":
    main()
