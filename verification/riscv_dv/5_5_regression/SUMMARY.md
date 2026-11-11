
# RISC-V DV Regression Stability — Acceptance Criterion 5.5

## Regression Configuration

- Test: riscv_arithmetic_basic_test
- ISA: rv32im_zicsr_zifencei
- ABI: ilp32
- Privilege mode: Machine (M)
- Simulator: Synopsys VCS R-2020.12-SP2-1
- Test generator: riscv-dv
- Number of iterations: 100
- Starting seed: 1000
- DUT: Novacrypt RISC-V SoC

## Regression Results

| Metric | Result |
|---|---:|
| Total simulations | 100 |
| Passed | 100 |
| Failed | 0 |
| Timed out | 0 |
| Pass rate | 100% |

## Pass Criteria

Each simulation was considered successful when the testbench detected:

`TEST PASSED: tohost = 1`

All 100 individual simulation logs contain this PASS message.

## Memory Configuration

- Boot ROM: Generated test instruction image
- Data SRAM: Generated test data and stack image
- Instruction SRAM: Existing program.mem preserved

## Evidence

Individual simulation logs are available in:

`logs/seed_0.log` through `logs/seed_99.log`

## Conclusion

The 100-iteration RISC-V DV pilot regression completed with a
100% observed pass rate and zero timeouts on the Novacrypt SoC.

This result demonstrates successful execution of the selected
randomized arithmetic test across the 100-run pilot. Larger
regressions are required to establish stability at 1,000–10,000 seeds.