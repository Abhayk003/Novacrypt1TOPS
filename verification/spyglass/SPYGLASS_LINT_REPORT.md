# SpyGlass RTL Lint Report --- `soc_top`

## 1. Scope

-   **Tool:** Synopsys SpyGlass U-2023.03-SP2
-   **Goal:** `lint/lint_rtl`
-   **Top module:** `soc_top` (`rtl/soc_top.sv`)
-   **Final status:** **0 reported errors, 0 reported warnings, 3
    information messages**

This report records the RTL corrections and warning waivers reviewed
during the lint run. A zero-warning result means all generated warnings
were either corrected or waived; it does not mean every warning was
fixed in RTL.

## 2. Final result

  Metric                             Final result
  -------------------------------- --------------
  Generated messages                        1,095
  Generated errors                              0
  Generated warnings                        1,087
  Generated information messages                8
  Waived warnings                           1,087
  Waived information messages                   5
  Reported errors                           **0**
  Reported warnings                         **0**
  Reported information messages                 3

Final policy summary: Command-line read, Design Read, Blackbox
Resolution, SGDC Checks, Policy lint, Policy STARC2005 and Policy ERC
all reported zero errors and zero warnings.

## 3. RTL corrections

Two inferred-latch issues were investigated and corrected. Only the
missing combinational defaults below were added; existing conditional
assignments were preserved.

### PLIC --- `ip_re_o`

-   **File:** `vendor/rv_plic/rtl/plic_regmap.sv`
-   **Finding:** `ip_re_o[0]` was asserted in the address-decode branch
    for `32'hc001000`, but `ip_re_o` had no default assignment at the
    beginning of the `always_comb` block.
-   **Correction:** Added `ip_re_o = '0;` with the other read-enable
    defaults.
-   **Reason:** Ensure the signal is assigned on every combinational
    path and prevent unintended latch inference.

### UART --- `fifo_tx_data`

-   **File:** `vendor/apb_uart_sv/apb_uart_sv.sv`
-   **Finding:** `fifo_tx_data` was assigned `PWDATA[7:0]` only during a
    THR write, with no default assignment in the `always_comb` block.
-   **Correction:** Added `fifo_tx_data = '0;` with the other FIFO
    defaults.
-   **Reason:** Ensure a defined combinational value when the THR write
    condition is false. `fifo_tx_valid` remains defaulted low outside
    the write condition.

After these corrections, the lint run reported zero errors and three
warnings.

## 4. Reviewed warning waivers

The following reasons reflect the comments recorded in the SpyGlass
waiver file. Counts are the findings reviewed for each rule during this
work.

  --------------------------------------------------------------------------------
  Rule                             Findings reviewed Review rationale
  --------------------- ---------------------------- -----------------------------
  `W287b`                                        719 Intentional unconnected
                                                     output ports: unused optional
                                                     interface outputs, GPIO
                                                     subregister outputs, FIFO
                                                     status/usage outputs, arbiter
                                                     indices and read-enable
                                                     outputs. Functional data,
                                                     control and handshake paths
                                                     remain connected.

  `W240`                                          78 Unused inputs across AXI/APB
                                                     sideband fields, optional
                                                     test/flush controls, CPU
                                                     interface inputs and vendor
                                                     FIFO/arbiter inputs.

  `W415a`                                        171 Multiple procedural
                                                     assignments across SoC
                                                     integration, CPU pipeline,
                                                     Wallace multiplier, CSR, AXI,
                                                     FIFO, GPIO, PLIC, CLINT and
                                                     peripheral logic. Reviewed as
                                                     defaults, conditional
                                                     overrides, loops and priority
                                                     updates.

  `W528`                          71 warnings plus 1 Reviewed unused signals
                                 information message classified as redundant
                                                     state, unused interface
                                                     fields, inactive
                                                     configuration signals, unused
                                                     internal outputs or
                                                     intentional unused sinks.

  `W486`                                           6 Width mismatches in AXI ID
                                                     counter/mux logic and the I2C
                                                     filter counter reviewed and
                                                     accepted for the implemented
                                                     configurations.

  `W362`                                           4 APB timer width mismatches
                                                     involving `prescaler_int` and
                                                     `cycle_counter_q` reviewed
                                                     for the implemented timer
                                                     configuration.

  `W263`                                          10 I2C APB case-label width
                                                     mismatches reviewed; 3-bit
                                                     case labels are used in the
                                                     4-bit `s_apb_addr` register
                                                     decode.

  `W339a`                                          2 Case-equality operator usage
                                                     in CPU execute-stage logic
                                                     reviewed and accepted.

  `STARC05-2.2.3.3`                                2 Sequential multiple
                                                     assignments involving
                                                     `store_completed` and `r_cmd`
                                                     reviewed and accepted for the
                                                     intended procedural behavior.

  `STARC05-2.11.3.1`                               3 FSM coding warnings in
                                                     `rv32m_div_radix4`,
                                                     `i2c_master_byte_ctrl` and
                                                     `i2c_master_bit_ctrl`
                                                     reviewed and accepted.

  `STARC05-1.3.1.3`                                1 Asynchronous reset usage in
                                                     SRAM enable logic
                                                     (`rtl/sram.sv`) reviewed and
                                                     accepted.

  `WRN_69`                                         1 Timescale directive warning
                                                     in `rtl/soc_top.sv` reviewed
                                                     for the simulation setup.

  `WRN_26`                                         1 `REG_STATUS` macro
                                                     redefinition in
                                                     `vendor/apb_i2c/apb_i2c.sv`
                                                     reviewed.

  `WRN_1024`                                       4 Redundant unsigned conversion
                                                     applied to the
                                                     already-unsigned
                                                     `rx_elements_i` signal
                                                     reviewed and accepted.

  `SYNTH_5014`                                     3 SRAM memory-analysis
                                                     synthesis diagnostics for the
                                                     implemented SRAM variants
                                                     reviewed and accepted.

  `SYNTH_5143`                                     4 Messages indicating `initial`
                                                     blocks are ignored for
                                                     synthesis in SRAM variants
                                                     and `addr_decode_dync`
                                                     reviewed and accepted as
                                                     known synthesis diagnostics.

  `SYNTH_5064`                                     5 GPIO assertion messages
                                                     reviewed as verification
                                                     checks ignored during
                                                     synthesis.

  `SYNTH_5058`                                     2 Synthesis messages indicating
                                                     case equality is treated as
                                                     logical equality reviewed and
                                                     accepted.

  `FlopEConst`                                     3 Constant-enable flop
                                                     diagnostics involving UART
                                                     `parity_error`, AXI spill
                                                     register `a_data_q` and AXI
                                                     error-slave FIFO `mem_q`
                                                     reviewed and accepted.
  --------------------------------------------------------------------------------

### Waiver caveats

-   Waivers document reviewed findings; they do not modify RTL behavior.
-   A waiver is not proof that a finding is harmless in every
    configuration. The rationale applies to the reviewed
    design/configuration.
-   `SYNTH_5143` concerns `initial` blocks ignored for synthesis. If
    hardware power-up or memory initialization depends on those blocks,
    verify that behavior separately for the target implementation.
-   Revisit the `FlopEConst` waivers if the relevant UART or AXI logic
    changes.

## 5. Final information messages

The final run reported three information messages: -
`checkCMD_ignore01`: option `enableSV` ignored because `enableSV09` was
also specified. - `ElabSummary`: points to the elaboration summary
report. - `DetectTopDesignUnits`: identifies `soc_top` as a top-level
design unit.

These are information messages, not errors or warnings.

## 6. Evidence files on the server

**Consolidated reports directory**

``` text
spyglass_lint_final/novacrypt_spyglass_final/consolidated_reports/soc_top_lint_lint_rtl/
```

**SpyGlass log**

``` text
spyglass_lint_final/novacrypt_spyglass_final/soc_top/lint/lint_rtl/spyglass.log
```

**Waiver file**

``` text
spyglass_lint_final/novacrypt_spyglass_final/soc_top/lint/lint_rtl/novacrypt_spyglass_final_waiver_file.awl
```

**HTML goal summary**

``` text
spyglass_lint_final/novacrypt_spyglass_final/html_reports/goals_summary.html
```

Recommended evidence to commit: 1. `SPYGLASS_LINT_REPORT.md` (this
report). 2. The final `spyglass.log`. 3. The `.awl` waiver file. 4.
Relevant final reports such as `waiver.rpt` and the goal summary, if
present.

Review `.gitignore` and any university/company data-sharing rules before
uploading. Avoid committing temporary databases or large intermediate
files unless required.

## 7. Reproduction

From the project root, after configuring the SpyGlass environment and
opening the project:

``` tcl
read_file -type awl ./spyglass_lint_final/novacrypt_spyglass_final/soc_top/lint/lint_rtl/novacrypt_spyglass_final_waiver_file.awl
run_goal -goal lint/lint_rtl
```

The final verified run for this report produced **0 errors, 0 warnings
and 3 information messages**.

------------------------------------------------------------------------

**Status:** Core RTL lint completed with zero reported errors and zero
reported warnings. Reviewed warning findings are documented in the
waiver file.
