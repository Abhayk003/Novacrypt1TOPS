#===============================================================================
# Makefile -- VCS compile/run for the top_module blackbox UVM environment.
#
# Usage:
#   make compile
#   make run TEST=test_hazard_fwd PROG=hazard_fwd
#   make run TEST=proc_base_test  PROG=smoke
#   make regress                      # every directed test x its matching program
#   make golden                       # (re)generate all golden/out/* artifacts
#   make clean
#
# WEAKEST PART OF THIS FILE (stated up front, not buried): none of this has
# been run through actual VCS -- there is no simulator available in the
# environment that built it. Treat -ntb_opts uvm version / flag names as
# likely-correct-for-a-recent-VCS, not verified against your specific
# install. Check `vcs -ntb_opts uvm -help` / your site's VCS version notes
# before trusting the exact flags.
#===============================================================================

VCS        ?= vcs
SIMV       ?= ./simv
TB_DIR     := .
GOLDEN_DIR := ../golden

CM_DIR    := ./cm.vdb

GOLDEN_PORT ?= 45721
GOLDEN_HOST ?= 127.0.0.1
GOLDEN_SERVER := $(GOLDEN_DIR)/golden_server.py
COV_HIER := ./tgl_cov.hier

VCS_FLAGS := -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
             -debug_access+all -kdb -lca -assert svaext \
             +define+UVM_NO_DEPRECATED \
             -cm line+cond+fsm+tgl+branch \
             -cm_hier $(COV_HIER) \
             -cm_dir $(CM_DIR)
COV_FLAGS := -cm line+cond+fsm+tgl+branch \
             -cm_hier $(COV_HIER) \
             -cm_dir $(CM_DIR) \
             -cm_name $(TEST)_$(PROG)

RUN_FLAGS := $(COV_FLAGS) -l run_$(TEST)_$(PROG).log

TESTS := test_hazard_fwd:hazard_fwd \
         test_muldiv_corner:muldiv_corner \
         test_csr_exception:csr_exception \
         test_axi_burst_boundary:axi_burst_boundary \
         test_random_regression:random_regression \
         test_smoke:smoke \
         test_branch_not_taken:branch_not_taken \
         test_jalr_lsb_clear:jalr_lsb_clear \
         test_store_load_fwd:store_load_fwd \
         test_x0_writes:x0_writes \
         test_burst_redirect_loop:burst_redirect_loop \
         test_irq_timer:irq_timer \
         test_irq_software:irq_software \
         test_irq_external:irq_external \
         test_irq_priority:irq_priority \
         test_irq_masking:irq_masking \
         test_wide_regfile_toggle:wide_regfile_toggle \
         test_dmem_bit_walk:dmem_bit_walk \
         test_imem_sram_reach:imem_sram_reach \
         test_imem_bit12_toggle:imem_bit12_toggle \
         test_far_branch_toggle:far_branch_toggle \
         test_store_wstrb_transition:store_wstrb_transition

.PHONY: imem golden compile run debug regress cov clean golden_server

imem:
	python3 $(GOLDEN_DIR)/gen_imem.py
# All directed programs in gen_imem.py are listed in TESTS above.
# Backward-compatible alias. It now means image generation only; it never
# executes the ISS.
golden: imem

golden_server:
	@python3 $(GOLDEN_SERVER) --host $(GOLDEN_HOST) --port $(GOLDEN_PORT) > golden_server.log 2>&1 & echo $$! > .golden_server.pid
	@sleep 0.2

compile: imem
	$(VCS) $(VCS_FLAGS) -CFLAGS "-I$(VCS_HOME)/include" golden_dpi.c -f $(TB_DIR)/core_rtl.f -f $(TB_DIR)/tb.f -top tb_top -l compile.log

run: golden_server
	@set -e; trap 'if [ -f .golden_server.pid ]; then kill $$(cat .golden_server.pid) 2>/dev/null || true; rm -f .golden_server.pid; fi' EXIT; \
	GOLDEN_HOST=$(GOLDEN_HOST) GOLDEN_PORT=$(GOLDEN_PORT) $(SIMV) +UVM_TESTNAME=$(TEST) +PROG_NAME=$(PROG) $(RUN_FLAGS)

debug: compile golden_server
	@set -e; trap 'if [ -f .golden_server.pid ]; then kill $$(cat .golden_server.pid) 2>/dev/null || true; rm -f .golden_server.pid; fi' EXIT; \
	GOLDEN_HOST=$(GOLDEN_HOST) GOLDEN_PORT=$(GOLDEN_PORT) $(SIMV) +UVM_TESTNAME=test_hazard_fwd +PROG_NAME=hazard_fwd \
	        +DEBUG_TRACE=1 +DEBUG_CYCLES=300 \
	        -l debug_hazard_fwd.log
	@echo "Trace printed to uvm_tb/debug_hazard_fwd.log -- grep for '\[TRACE\]'"

regress: compile golden_server
	@set -e; trap 'if [ -f .golden_server.pid ]; then kill $$(cat .golden_server.pid) 2>/dev/null || true; rm -f .golden_server.pid; fi' EXIT; \
	for pair in $(TESTS); do \
		t=$${pair%%:*}; p=$${pair##*:}; \
		echo "=== $$t (PROG_NAME=$$p) ==="; \
		GOLDEN_HOST=$(GOLDEN_HOST) GOLDEN_PORT=$(GOLDEN_PORT) $(SIMV) +UVM_TESTNAME=$$t +PROG_NAME=$$p \
		        -cm line+cond+fsm+tgl+branch -cm_dir $(CM_DIR) -cm_name $${t}_$${p} \
		        -l run_$${t}_$${p}.log; \
	done


# ============================================================
# Coverage reports
#
# cm.vdb contains BOTH:
#   1. RTL/code coverage
#   2. SystemVerilog functional/group coverage
#
# We intentionally generate separate URG reports so that
# functional coverage is NOT mixed into the code coverage score.
# ============================================================

FUNC_REPORT := funcReport
CODE_REPORT := codeReport

cov: regress
	rm -rf $(FUNC_REPORT) $(CODE_REPORT)

	@echo ""
	@echo "=============================================="
	@echo " Generating FUNCTIONAL coverage report"
	@echo "=============================================="

	urg -dir $(CM_DIR) \
	    -metric group \
	    -group ratio \
	    -show ratios \
	    -report $(FUNC_REPORT)

	@echo ""
	@echo "=============================================="
	@echo " Generating CODE coverage report"
	@echo "=============================================="

	urg -dir $(CM_DIR) \
	    -metric line+cond+fsm+tgl+branch \
	    -show ratios \
	    -report $(CODE_REPORT)

	@echo ""
	@echo "=============================================="
	@echo " Coverage reports generated"
	@echo "=============================================="
	@echo " Functional : $(FUNC_REPORT)/dashboard.html"
	@echo " Code       : $(CODE_REPORT)/dashboard.html"
	@echo ""

clean:
	rm -rf simv simv.daidir csrc DVEfiles ucli.key vc_hdrs.h *.log *.vpd *.fsdb *.vcd work.lib++ AN.DB novas.* cm.vdb urgReport funcReport codeReport *.vdb $(GOLDEN_DIR)/out