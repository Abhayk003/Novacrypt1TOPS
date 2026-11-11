#!/usr/bin/env python3
"""Copy upstream CoreMark's barebones port and wire its platform hooks to platform.c.
Fails loudly if an expected upstream pattern is missing, so a changed upstream
can never silently produce a bad build.   usage: make_coremark_port.py SRC DST"""
import re, shutil, sys, pathlib

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)

def patch(fname, subs):
    p = dst / fname
    t = p.read_text()
    for pat, rep in subs:
        t, n = re.subn(pat, lambda m, r=rep: r, t, count=1, flags=re.S)
        if n == 0:
            sys.exit(f"PATCH FAILED in {fname}: pattern not found: {pat[:60]!r}")
    p.write_text(t)

patch("core_portme.c", [
    (r'#include "core_portme.h"\n',
     '#include "core_portme.h"\n#include "platform.h"\nextern unsigned long long plat_cycles(void);\n'),
    (r'(barebones_clock\(\)\s*\{)\s*#error\s*\\\s*\n[^\n]*\n(\})',
     'barebones_clock()\n{\n    return (CORETIMETYPE)plat_cycles();\n}'),
    (r'#error\s*\\\s*\n\s*"Call board[^\n]*\n', ''),
    (r'\(CLOCKS_PER_SEC / TIMER_RES_DIVIDER\)', '(PLAT_TICK_HZ / TIMER_RES_DIVIDER)'),
])
patch("core_portme.h", [
    (r'#define CORE_PORTME_H\n', '#define CORE_PORTME_H\n#include <stddef.h>\n#include <stdint.h>\n'),
    (r'#define HAS_FLOAT 1',   '#define HAS_FLOAT 0'),
    (r'#define HAS_TIME_H 1',  '#define HAS_TIME_H 0'),
    (r'#define USE_CLOCK 1',   '#define USE_CLOCK 0'),
    (r'typedef ee_u32\s+ee_ptr_int;', 'typedef __UINTPTR_TYPE__ ee_ptr_int;'),   # 64-bit safe
])
patch("ee_printf.c", [
    (r'void\s*\nuart_send_char\(char c\)\s*\{\s*#error[^\n]*\n',
     'void\nuart_send_char(char c)\n{\n    extern void plat_putc(char);\n    plat_putc(c);\n    return;\n'),
])
patch("cvt.c", [
    (r'#include <math.h>', 'double modf(double, double *);   /* provided by minilibc.c: no libm/newlib needed */'),
])
print(f"CoreMark port patched -> {dst}")