#!/usr/bin/env python3
"""bin -> $readmemh text.   usage: bin2memh.py in.bin out.hex [--bytes 4] [--depth N] [--big-endian]
--bytes 4 : one 32-bit word per line (little-endian byte order, what RV32 memories expect)
--bytes 1 : one byte per line (for byte-organised memories)
--depth N : zero-pad to N words/bytes so $readmemh leaves no X's in a fixed-size array"""
import argparse
ap = argparse.ArgumentParser()
ap.add_argument("inp"); ap.add_argument("out")
ap.add_argument("--bytes", type=int, default=4, choices=[1, 2, 4, 8])
ap.add_argument("--depth", type=int, default=0)
ap.add_argument("--big-endian", action="store_true")
a = ap.parse_args()
d = open(a.inp, "rb").read()
d += b"\0" * (-len(d) % a.bytes)
w = a.bytes
lines = [int.from_bytes(d[i:i+w], "big" if a.big_endian else "little") for i in range(0, len(d), w)]
if a.depth:
    if len(lines) > a.depth: raise SystemExit(f"image has {len(lines)} entries > --depth {a.depth}: it does not fit your memory")
    lines += [0] * (a.depth - len(lines))
open(a.out, "w").write("".join(f"{v:0{w*2}x}\n" for v in lines))
print(f"{a.out}: {len(d)} bytes -> {len(lines)} lines of {w*2} hex digits")