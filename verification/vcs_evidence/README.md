# Synopsys VCS Verification Evidence

## Overview

This directory contains the verification evidence generated using Synopsys VCS for the Novacrypt1TOPS RISC-V SoC project.

The regression suite includes 25 testbenches covering processor functionality, RV32IM instructions, pipeline hazards, interrupts, memory access, and peripheral interfaces.

## Regression Summary

- Simulator: Synopsys VCS R-2020.12-SP2-1
- Total testbenches: 25
- Passed: 25
- Failed: 0
- Skipped: 0
- Overall result: ALL 25 TESTS PASSED

Refer to `regression_summary.txt` for the consolidated regression result.

## Directory Structure

- `regression_summary.txt` – Overall regression results.
- `individual_logs/` – Individual compilation and simulation logs for each testbench.

Each testbench directory contains:

- `compile.log` – VCS compilation output.
- `sim.log` – Simulation output and test results.

## Verification Evidence

The individual simulation logs provide testbench-level evidence of the checks performed and their PASS results. Compilation logs provide supporting evidence that each testbench was successfully compiled.

## Reproducibility

The regression script is available at:

`scripts/run_vcs_regression.sh`

The regression can be executed on a system configured with Synopsys VCS and the required environment and license.
