//==============================================================================
// proc_scoreboard.sv -- live DUT-vs-reference comparison.
//
// The scoreboard no longer loads a pre-generated bus_trace.txt. The live
// reference component predicts the next architectural data-bus event and
// publishes it here. The DUT transaction is published on the same path by the
// reference adapter after it has obtained the prediction, so ordering is
// deterministic and the scoreboard remains a pure comparator.
//==============================================================================
class proc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(proc_scoreboard)

  // Actual DUT data transactions are forwarded by proc_golden_ref after it
  // has synchronously obtained the corresponding Python prediction.
  uvm_analysis_imp_data   #(proc_pkg::proc_data_txn,   proc_scoreboard) data_imp;
  uvm_analysis_imp_instr  #(proc_pkg::proc_instr_txn,  proc_scoreboard) instr_imp;
  uvm_analysis_imp_golden #(proc_pkg::proc_golden_txn, proc_scoreboard) golden_imp;

  proc_pkg::proc_env_cfg cfg;
  proc_pkg::proc_mem_model shadow_dmem;

  proc_pkg::proc_golden_txn expected_q[$];
  int unsigned events_checked;
  int unsigned mismatches;
// Raw DUT data transactions, independent of golden predictions.
  uvm_analysis_imp_raw_data #(proc_pkg::proc_data_txn,
                            proc_scoreboard) raw_data_imp;

// IRQ handler signature tracking.
  bit irq_test;
  bit irq_signature_valid;
  int unsigned irq_signature_count;
  bit [31:0] expected_irq_cause;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    data_imp   = new("data_imp", this);
    instr_imp  = new("instr_imp", this);
    golden_imp = new("golden_imp", this);
    raw_data_imp = new("raw_data_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(proc_pkg::proc_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("PROC_SB", "env cfg not set")
    shadow_dmem = proc_pkg::proc_mem_model::type_id::create("shadow_dmem");
    irq_test             = 0;
irq_signature_valid  = 0;
irq_signature_count  = 0;
expected_irq_cause   = 32'h0;

case (cfg.prog_name)

    "irq_timer": begin
        irq_test = 1;
        expected_irq_cause = 32'h80000007;
    end

    "irq_software": begin
        irq_test = 1;
        expected_irq_cause = 32'h80000003;
    end

    "irq_external": begin
        irq_test = 1;
        expected_irq_cause = 32'h8000000B;
    end

    "irq_priority": begin
        irq_test = 1;
        expected_irq_cause = 32'h8000000B;
    end

    "irq_masking": begin
        irq_test = 1;
        expected_irq_cause = 32'h8000000B;
    end

    default: begin
        irq_test = 0;
    end

endcase
  endfunction

function void write_raw_data(proc_pkg::proc_data_txn txn);

    if (!irq_test)
        return;

    // The IRQ handler stores mcause at DMEM_BASE.
    if ((txn.dir == proc_pkg::DATA_WRITE) &&
        (txn.addr == proc_pkg::DMEM_BASE)) begin

        irq_signature_count++;

        `uvm_info("PROC_SB",
            $sformatf("IRQ handler signature observed: addr=%08h data=%08h strb=%01h",
                      txn.addr, txn.wdata, txn.wstrb),
            UVM_LOW)

        if (txn.resp != proc_pkg::AXI_OKAY) begin

            `uvm_error("PROC_SB",
                "IRQ handler signature write received a non-OKAY response")

            mismatches++;

        end
        else if (txn.wstrb !== 4'hF) begin

            `uvm_error("PROC_SB",
                $sformatf("IRQ signature has incorrect write strobe: %01h",
                          txn.wstrb))

            mismatches++;

        end
        else if (txn.wdata !== expected_irq_cause) begin

            `uvm_error("PROC_SB",
                $sformatf("IRQ cause mismatch: expected=%08h observed=%08h",
                          expected_irq_cause, txn.wdata))

            mismatches++;

        end
        else begin

            irq_signature_valid = 1;

            `uvm_info("PROC_SB",
                $sformatf("IRQ handler verified successfully. mcause=%08h",
                          txn.wdata),
                UVM_LOW)

        end

    end

endfunction

  function void write_golden(proc_pkg::proc_golden_txn txn);
    expected_q.push_back(txn);
  endfunction

  function void write_data(proc_pkg::proc_data_txn txn);
    proc_pkg::proc_golden_txn exp;

    if (txn.dir == proc_pkg::DATA_WRITE)
      shadow_dmem.write_word(txn.addr, txn.wdata, txn.wstrb);

    if (expected_q.size() == 0) begin
      `uvm_error("PROC_SB", $sformatf(
        "DUT data transaction arrived without a golden prediction: %s",
        txn.convert2str()))
      mismatches++;
      return;
    end

    exp = expected_q.pop_front();
    events_checked++;

    if (exp.dir != txn.dir) begin
      `uvm_error("PROC_SB", $sformatf(
        "event #%0d direction mismatch: golden=%s observed=%s",
        events_checked,
        exp.dir == proc_pkg::DATA_WRITE ? "WRITE" : "READ",
        txn.convert2str()))
      mismatches++;
      return;
    end

    if (exp.addr !== txn.addr) begin
      `uvm_error("PROC_SB", $sformatf(
        "event #%0d address mismatch: golden=%08h observed=%08h pc=%08h",
        events_checked, exp.addr, txn.addr, exp.pc))
      mismatches++;
      return;
    end

    if (txn.dir == proc_pkg::DATA_WRITE) begin
      if (exp.data !== txn.wdata || exp.strb !== txn.wstrb) begin
        `uvm_error("PROC_SB", $sformatf(
          "event #%0d WRITE mismatch: golden=%08h/%01h observed=%08h/%01h addr=%08h pc=%08h",
          events_checked, exp.data, exp.strb, txn.wdata, txn.wstrb,
          txn.addr, exp.pc))
        mismatches++;
      end
    end
    else if (txn.resp == proc_pkg::AXI_OKAY) begin
      // Unlike the old scoreboard, the expected read value now comes from the
      // live ISS rather than the same SV memory model that serves the DUT.
      if (!exp.has_rdata || exp.rdata !== txn.rdata) begin
        `uvm_error("PROC_SB", $sformatf(
          "event #%0d READ data mismatch: golden=%08h observed=%08h addr=%08h pc=%08h",
          events_checked, exp.rdata, txn.rdata, txn.addr, exp.pc))
        mismatches++;
      end
    end
  endfunction

  function void write_instr(proc_pkg::proc_instr_txn txn);
    bit in_rom  = (txn.araddr >= proc_pkg::BOOT_ROM_BASE) &&
                  (txn.araddr <= proc_pkg::BOOT_ROM_LIMIT);
    bit in_imem = (txn.araddr >= proc_pkg::IMEM_BASE) &&
                  (txn.araddr <= proc_pkg::IMEM_LIMIT);
    if (!in_rom && !in_imem) begin
      `uvm_error("PROC_SB", $sformatf(
        "instruction fetch to out-of-range address %08h", txn.araddr))
      mismatches++;
    end
  endfunction

  function void check_phase(uvm_phase phase);
    string got_path;
    string golden_path;
    super.check_phase(phase);
// IRQ tests must execute the handler and produce a valid signature.
if (irq_test && !irq_signature_valid) begin

    `uvm_error("PROC_SB",
        $sformatf(
            "IRQ TEST FAILED: handler signature missing or invalid. Expected mcause=%08h, observed signature writes=%0d",
            expected_irq_cause,
            irq_signature_count
        ))

    mismatches++;

end
    if (expected_q.size() != 0) begin
      `uvm_error("PROC_SB", $sformatf(
        "%0d golden data events were predicted but never observed by the DUT",
        expected_q.size()))
      mismatches += expected_q.size();
    end

    if (cfg.check_final_dmem) begin
      got_path = $sformatf("shadow_dmem_final_%s.mem", cfg.prog_name);
      golden_path = $sformatf("golden_live_final_%s.mem", cfg.prog_name);
      shadow_dmem.dump_range(got_path, proc_pkg::DMEM_BASE, proc_pkg::DMEM_LIMIT);
      if (!golden_dump_dmem(golden_path)) begin
        `uvm_error("PROC_SB", "failed to dump final live-golden DMEM")
        mismatches++;
      end
      else begin
        compare_dmem_files(got_path, golden_path);
      end
    end

    `uvm_info("PROC_SB", $sformatf(
      "scoreboard summary: %0d live bus events checked, %0d mismatches",
      events_checked, mismatches), UVM_LOW)

    if (mismatches != 0)
      `uvm_error("PROC_SB", $sformatf(
        "TEST FAILED: %0d mismatches detected", mismatches))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    golden_stop();
  endfunction

  function void compare_dmem_files(string got_path, string exp_path);
    int fd_got, fd_exp;
    string l_got, l_exp;
    int lineno;
    bit any_mismatch;

    fd_got = $fopen(got_path, "r");
    fd_exp = $fopen(exp_path, "r");
    if (fd_got == 0 || fd_exp == 0) begin
      `uvm_error("PROC_SB", "could not open live DMEM dump(s) for compare")
      mismatches++;
      return;
    end

    lineno = 0;
    any_mismatch = 0;
    while (!$feof(fd_got) && !$feof(fd_exp)) begin
      if ($fgets(l_got, fd_got) == 0) break;
      if ($fgets(l_exp, fd_exp) == 0) break;
      lineno++;
      if (l_got != l_exp) begin
        `uvm_error("PROC_SB", $sformatf(
          "final DMEM mismatch at word #%0d (addr %08h): observed=%s golden=%s",
          lineno - 1, proc_pkg::DMEM_BASE + (lineno - 1) * 4, l_got, l_exp))
        mismatches++;
        any_mismatch = 1;
      end
    end
    $fclose(fd_got);
    $fclose(fd_exp);

    if (!any_mismatch)
      `uvm_info("PROC_SB", "final DMEM matches live golden model", UVM_LOW)
  endfunction

endclass : proc_scoreboard
