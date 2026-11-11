#!/usr/bin/env python3
"""Validate a CoreMark/Dhrystone UART log and compute the score.
usage: parse_results.py {coremark|dhrystone} LOG [--info build/x.info] [--out results]
Exit code 0 = output validated, 1 = validation failed."""
import re, sys, json, argparse, pathlib, datetime

ap = argparse.ArgumentParser()
ap.add_argument("bench", choices=["coremark", "dhrystone"])
ap.add_argument("log")
ap.add_argument("--info"); ap.add_argument("--out", default="results")
a = ap.parse_args()
t = pathlib.Path(a.log).read_text(errors="replace").replace("\r", "")

def num(pat, flags=0):
    m = re.search(pat, t, flags)
    return int(m.group(1), 0) if m else None

clk  = num(r"\[BENCH\] clk_hz=(\d+)");  tick = num(r"tick_hz=(\d+)")
xlen = num(r"xlen=(\d+)")
if not clk:
    sys.exit("No [BENCH] banner in log: program never started or UART capture is incomplete")
if "TRAP mcause" in t:
    print(re.search(r"\[BENCH\] TRAP[^\n]*", t).group(0)); sys.exit("Core trapped before finishing")
if "[BENCH] done" not in t:
    sys.exit("No '[BENCH] done' marker: run did not complete (timeout / hang / truncated log)")

res = {"bench": a.bench, "clk_hz": clk, "xlen": xlen,
       "date": datetime.datetime.now().isoformat(timespec="seconds")}
ok, notes = True, []

if a.bench == "coremark":
    ticks, iters = num(r"Total ticks\s*:\s*(\d+)"), num(r"Iterations\s*:\s*(\d+)")
    if not ticks or not iters: sys.exit("CoreMark score lines missing from log")
    expect = {"seedcrc": 0xe9f5, "crclist": 0xe714, "crcmatrix": 0x1fd7, "crcstate": 0x8e3a}
    got = {}
    for k, v in re.findall(r"(seedcrc|crclist|crcmatrix|crcstate)\s*:\s*(0x[0-9a-fA-F]+)", t):
        got[k] = int(v, 16)
    bad = [k for k, v in expect.items() if got.get(k) != v]
    if bad: ok = False; notes.append("CRC mismatch: " + ", ".join(f"{k} got {got.get(k)} exp {hex(expect[k])}" for k in bad))
    # Upstream prints "Errors detected" for ANY run < 10 s even when all CRCs are right, so the
    # CRC check above is the real correctness test; the banner is only enforced for long runs.
    short = "Must execute for at least 10 secs" in t
    if not short and ("Errors detected" in t or "Correct operation validated" not in t):
        ok = False; notes.append("CoreMark reported errors / did not print 'Correct operation validated'")
    cycles = ticks * clk / tick
    secs = cycles / clk
    res.update(iterations=iters, ticks=ticks, cycles=cycles, seconds=secs,
               coremark_per_sec=iters / secs, coremark_per_mhz=iters * 1e6 / cycles, crcs=got)
    if secs < 10: notes.append(f"run lasted {secs:.3f}s < 10s: CoreMark/MHz is valid, but NOT an official-reportable score")
    score = f"{res['coremark_per_mhz']:.4f} CoreMark/MHz   ({res['coremark_per_sec']:.2f} CoreMark/s @ {clk/1e6:g} MHz)"
else:
    runs, cyc = num(r"Execution starts,\s*(\d+)\s*runs"), num(r"\[BENCH\] dhry_cycles=(\d+)")
    if not runs or not cyc: sys.exit("Dhrystone run/cycle lines missing from log")
    pat = re.compile(r"^[ \t]*([A-Za-z_][\w\[\]]*):[ \t]+(.*?)[ \t]*\n[ \t]*should be:[ \t]+(.*?)[ \t]*$", re.M)
    pairs = pat.findall(t); wrong = []
    for name, got, exp in pairs:
        if "Number_Of_Runs" in exp: exp = str(runs + 10)
        if exp.startswith("(implementation-dependent"): continue      # pointer values: not checkable
        if got != exp: wrong.append(f"{name}: got {got!r} expected {exp!r}")
    if len(pairs) < 12: ok = False; notes.append(f"only {len(pairs)} result checks found (expected 12+)")
    if wrong: ok = False; notes += ["Dhrystone value mismatch: " + w for w in wrong]
    cyc_clk = cyc * clk / tick
    dps = runs * clk / cyc_clk
    res.update(runs=runs, cycles=cyc_clk, seconds=cyc_clk / clk, checks=len(pairs),
               dhrystones_per_sec=dps, dmips=dps / 1757, dmips_per_mhz=dps / 1757 / (clk / 1e6))
    if res["seconds"] < 2: notes.append(f"run lasted {res['seconds']:.4f}s < 2s: DMIPS/MHz fine for RTL comparison, not reportable as a final figure")
    score = f"{res['dmips_per_mhz']:.4f} DMIPS/MHz   ({res['dmips']:.2f} DMIPS, {dps:.0f} Dhrystones/s @ {clk/1e6:g} MHz)"

if a.info and pathlib.Path(a.info).exists(): res["build"] = pathlib.Path(a.info).read_text().strip().splitlines()
res.update(validated=ok, notes=notes)
out = pathlib.Path(a.out); out.mkdir(exist_ok=True)
(out / f"{a.bench}.json").write_text(json.dumps(res, indent=2))
with open(out / "summary.md", "a") as f:
    f.write(f"| {res['date']} | {a.bench} | {'PASS' if ok else 'FAIL'} | {score} |\n")
print(f"\n=== {a.bench.upper()} : {'VALIDATED' if ok else 'VALIDATION FAILED'} ===\n{score}")
for n in notes: print(" -", n)
print(f"recorded -> {out}/{a.bench}.json and {out}/summary.md")
sys.exit(0 if ok else 1)