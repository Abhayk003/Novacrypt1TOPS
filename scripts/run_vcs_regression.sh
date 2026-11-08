
#!/bin/bash

# ============================================================
# Novacrypt1TOPS - VCS Regression
# Simulator: Synopsys VCS only
# ============================================================

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

RTL_FILE="$ROOT/rtl.f"
RESULTS="$ROOT/vcs_sim/regression"
SUMMARY="$RESULTS/summary.txt"

mkdir -p "$RESULTS"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# VCS compilation options validated on this repository.
VCS_FLAGS=(
    -full64
    -sverilog
    +libext+.sv+.v
    +incdir+vendor/apb_i2c
    -assert svaext
    -timescale=1ns/1ps
    -debug_access+all
)

echo "============================================================"
echo " Novacrypt1TOPS VCS Regression"
echo "============================================================"
echo "Started: $(date)"
echo "Repository: $ROOT"
echo

printf "%-24s %-12s %s\n" "TESTBENCH" "STATUS" "DETAIL" > "$SUMMARY"
printf "%-24s %-12s %s\n" "------------------------" "------------" "------------------------" >> "$SUMMARY"

run_test()
{
    TB="$1"
    FIRMWARE="$2"
    MARKER="$3"

    RUN_DIR="$RESULTS/$TB"

    mkdir -p "$RUN_DIR"

    echo
    echo "------------------------------------------------------------"
    echo "TEST: $TB"
    echo "------------------------------------------------------------"

    # Prepare firmware for full-SoC testbenches.
    if [[ "$FIRMWARE" != "NONE" ]]; then
        if [[ ! -f "$ROOT/sw/$FIRMWARE" ]]; then
            echo "FAIL: Firmware not found: sw/$FIRMWARE"
            echo "$TB FAIL Missing firmware" >> "$SUMMARY"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return
        fi

        cp "$ROOT/sw/$FIRMWARE" "$RUN_DIR/bootrom.mem"
        cp "$ROOT/sw/$FIRMWARE" "$RUN_DIR/program.mem"
    fi

    # Compile.
    echo "[COMPILE] $TB"

    if vcs "${VCS_FLAGS[@]}" \
        -f "$RTL_FILE" \
        "$ROOT/tb/$TB.sv" \
        -top "$TB" \
        -o "$RUN_DIR/simv" \
        > "$RUN_DIR/compile.log" 2>&1
    then
        echo "[COMPILE PASS] $TB"
    else
        echo "[COMPILE FAIL] $TB"
        tail -n 20 "$RUN_DIR/compile.log"
        echo "$TB FAIL Compilation" >> "$SUMMARY"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    # Run from the individual test directory so firmware paths resolve.
    echo "[SIMULATE] $TB"

    if (cd "$RUN_DIR" && ./simv) > "$RUN_DIR/sim.log" 2>&1
    then
        :
    else
        echo "[SIMULATION FAIL] $TB"
        tail -n 30 "$RUN_DIR/sim.log"
        echo "$TB FAIL Runtime error" >> "$SUMMARY"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    # Reject explicit FAIL output.
    if grep -Eiq '(^|[^A-Z])FAIL([^A-Z]|$)' "$RUN_DIR/sim.log"; then
        echo "[TEST FAIL] $TB - FAIL marker found"
        tail -n 30 "$RUN_DIR/sim.log"
        echo "$TB FAIL FAIL marker" >> "$SUMMARY"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    # Require the expected marker, or at least a PASS marker.
    if [[ -n "$MARKER" ]]; then
        if ! grep -Fq "$MARKER" "$RUN_DIR/sim.log"; then
            echo "[TEST FAIL] $TB - expected marker missing: $MARKER"
            tail -n 30 "$RUN_DIR/sim.log"
            echo "$TB FAIL Missing expected marker" >> "$SUMMARY"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return
        fi
    else
        if ! grep -Eiq 'PASS' "$RUN_DIR/sim.log"; then
            echo "[TEST FAIL] $TB - no PASS marker found"
            tail -n 30 "$RUN_DIR/sim.log"
            echo "$TB FAIL No PASS marker" >> "$SUMMARY"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return
        fi
    fi

    echo "[TEST PASS] $TB"
    echo "$TB PASS Simulation and PASS marker verified" >> "$SUMMARY"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# ============================================================
# FULL-SOC TESTBENCHES (19)
# ============================================================

run_test tb_bytelen       bootrom_bytelane.mem       "BYTELANE PASS"
run_test tb_clint         bootrom_clint.mem          ""
run_test tb_ecall         bootrom_ecall.mem          ""
run_test tb_gpio_irq      bootrom_gpio_irq.mem       ""
run_test tb_gpio_sct      bootrom_gpio_sct.mem        ""
run_test tb_i2c_burst     bootrom_i2c_burst.mem      ""
run_test tb_i2c_rd        bootrom_i2c_rd.mem         ""
run_test tb_i2c_wr        bootrom_i2c_wr.mem         ""
run_test tb_rv_plic       bootrom_plic_rvplic.mem    "RV_PLIC PASS"
run_test tb_soc_stage2    bootrom_stage2.mem         ""
run_test tb_soc_stage4    bootrom_stage4.mem         ""
run_test tb_soc_stage5    bootrom_stage5.mem         ""
run_test tb_soc_stage6    bootrom_stage6.mem         ""
run_test tb_soc_stage7    bootrom_stage7.mem         ""
run_test tb_soc_stage8    bootrom_stage8.mem         ""
run_test tb_spi_burst     bootrom_spi_burst.mem      ""
run_test tb_spi_rx        bootrom_spi_rx.mem         ""
run_test tb_timer_repeat  bootrom_timer_repeat.mem   ""
run_test tb_uart_rx       bootrom_uart_rx.mem        ""

# ============================================================
# STANDALONE CPU TESTBENCHES (6)
# No external firmware files required.
# ============================================================

run_test branch_tb          NONE ""
run_test branch_tb_corner   NONE ""
run_test datapath_tb_axi4   NONE ""
run_test tb_final           NONE ""
run_test tb_m_extension     NONE ""
run_test tb_m_exten_corner  NONE ""

# ============================================================
# FINAL SUMMARY
# ============================================================

TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))

echo
echo "============================================================"
echo " VCS REGRESSION SUMMARY"
echo "============================================================"
echo "Total tests : $TOTAL"
echo "Passed      : $PASS_COUNT"
echo "Failed      : $FAIL_COUNT"
echo "Skipped     : $SKIP_COUNT"
echo
echo "Detailed summary: $SUMMARY"
echo "Individual logs:  $RESULTS/<testbench>/"
echo "Finished: $(date)"
echo "============================================================"

{
    echo
    echo "============================================================"
    echo "TOTAL: $TOTAL  PASS: $PASS_COUNT  FAIL: $FAIL_COUNT  SKIP: $SKIP_COUNT"
    echo "============================================================"
} >> "$SUMMARY"

if [[ "$FAIL_COUNT" -eq 0 && "$PASS_COUNT" -eq 25 ]]; then
    echo "REGRESSION RESULT: ALL 25 TESTS PASSED"
    exit 0
else
    echo "REGRESSION RESULT: CHECK FAILED OR UNVERIFIED TESTS"
    exit 1
fi
