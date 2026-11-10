#!/usr/bin/env python3
"""Compatibility wrapper.

The old gen_golden.py used to assemble a program and immediately execute the
ISS, producing static bus/final-memory traces. That coupling is intentionally
gone. Image generation now lives in gen_imem.py; the live ISS is served by
 golden_server.py and driven by UVM stimulus.
"""
from gen_imem import main

if __name__ == "__main__":
    main()
