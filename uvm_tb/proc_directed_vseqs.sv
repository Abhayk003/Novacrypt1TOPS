//==============================================================================
// proc_directed_vseqs.sv
//
// Each of these differs from proc_base_vseq only in which AXI-injection
// profile runs concurrently with the (test-class-selected) program image.
// Naming matches the test-plan categories in TEAM_BRIEF.md's Track B list.
//
// The dedicated irq_* virtual sequences below drive the live top_module IRQ
// inputs. The Python ISS already accepts the same live IRQ levels through
// golden_irq(), so the IRQ driver forwards each applied transition to it.
// Existing non-IRQ tests retain the default idle sequence.
//==============================================================================

// Load-use hazard / forwarding and mul/div corner cases: pure program
// content, no irq or bus-fault stimulus needed -- the base sequence
// (idle irq, clean bus) already covers this; kept as named aliases so
// test classes have a self-documenting sequence to point at.
class hazard_fwd_vseq extends proc_base_vseq;
  `uvm_object_utils(hazard_fwd_vseq)
  function new(string name = "hazard_fwd_vseq");
    super.new(name);
  endfunction
endclass : hazard_fwd_vseq

class muldiv_corner_vseq extends proc_base_vseq;
  `uvm_object_utils(muldiv_corner_vseq)
  function new(string name = "muldiv_corner_vseq");
    super.new(name);
  endfunction
endclass : muldiv_corner_vseq

class smoke_vseq extends proc_base_vseq;
  `uvm_object_utils(smoke_vseq)
  function new(string name = "smoke_vseq");
    super.new(name);
  endfunction
endclass : smoke_vseq

class branch_not_taken_vseq extends proc_base_vseq;
  `uvm_object_utils(branch_not_taken_vseq)
  function new(string name = "branch_not_taken_vseq");
    super.new(name);
  endfunction
endclass : branch_not_taken_vseq

class jalr_lsb_clear_vseq extends proc_base_vseq;
  `uvm_object_utils(jalr_lsb_clear_vseq)
  function new(string name = "jalr_lsb_clear_vseq");
    super.new(name);
  endfunction
endclass : jalr_lsb_clear_vseq

class store_load_fwd_vseq extends proc_base_vseq;
  `uvm_object_utils(store_load_fwd_vseq)
  function new(string name = "store_load_fwd_vseq");
    super.new(name);
  endfunction
endclass : store_load_fwd_vseq

class x0_writes_vseq extends proc_base_vseq;
  `uvm_object_utils(x0_writes_vseq)
  function new(string name = "x0_writes_vseq");
    super.new(name);
  endfunction
endclass : x0_writes_vseq

class timer_interrupt_vseq extends proc_base_vseq;
  `uvm_object_utils(timer_interrupt_vseq)
  function new(string name = "timer_interrupt_vseq");
    super.new(name);
  endfunction
endclass : timer_interrupt_vseq


// Toggle-coverage / address-range programs: pure program content, idle irq,
// clean bus (MSIP/mtimecmp are driven through CLINT MMIO by the program itself,
// not through the live irq_*_i inputs).
class wide_regfile_toggle_vseq extends proc_base_vseq;
  `uvm_object_utils(wide_regfile_toggle_vseq)
  function new(string name = "wide_regfile_toggle_vseq");
    super.new(name);
  endfunction
endclass : wide_regfile_toggle_vseq

class dmem_bit_walk_vseq extends proc_base_vseq;
  `uvm_object_utils(dmem_bit_walk_vseq)
  function new(string name = "dmem_bit_walk_vseq");
    super.new(name);
  endfunction
endclass : dmem_bit_walk_vseq

class imem_sram_reach_vseq extends proc_base_vseq;
  `uvm_object_utils(imem_sram_reach_vseq)
  function new(string name = "imem_sram_reach_vseq");
    super.new(name);
  endfunction
endclass : imem_sram_reach_vseq

class msip_software_irq_vseq extends proc_base_vseq;
  `uvm_object_utils(msip_software_irq_vseq)
  function new(string name = "msip_software_irq_vseq");
    super.new(name);
  endfunction
endclass : msip_software_irq_vseq

class imem_bit12_toggle_vseq extends proc_base_vseq;
  `uvm_object_utils(imem_bit12_toggle_vseq)
  function new(string name = "imem_bit12_toggle_vseq");
    super.new(name);
  endfunction
endclass : imem_bit12_toggle_vseq

class far_branch_toggle_vseq extends proc_base_vseq;
  `uvm_object_utils(far_branch_toggle_vseq)
  function new(string name = "far_branch_toggle_vseq");
    super.new(name);
  endfunction
endclass : far_branch_toggle_vseq

class store_wstrb_transition_vseq extends proc_base_vseq;
  `uvm_object_utils(store_wstrb_transition_vseq)
  function new(string name = "store_wstrb_transition_vseq");
    super.new(name);
  endfunction
endclass : store_wstrb_transition_vseq

// Direct live-input IRQ tests. The program configures mtvec/mie/mstatus
// before entering its instruction-only loop; the sequence asserts after 120 cycles.
class irq_timer_vseq extends proc_base_vseq;
  `uvm_object_utils(irq_timer_vseq)
  function new(string name = "irq_timer_vseq"); super.new(name); endfunction
  task body();
    irq_pulse_seq s = irq_pulse_seq::type_id::create("timer_pulse");
    s.line = proc_pkg::IRQ_TIMER; s.delay_cycles = 120; s.pulse_width_cycles = 50;
    irq_seq = s; super.body();
  endtask
endclass

class irq_software_vseq extends proc_base_vseq;
  `uvm_object_utils(irq_software_vseq)
  function new(string name = "irq_software_vseq"); super.new(name); endfunction
  task body();
    irq_pulse_seq s = irq_pulse_seq::type_id::create("software_pulse");
    s.line = proc_pkg::IRQ_SOFTWARE; s.delay_cycles = 120; s.pulse_width_cycles = 50;
    irq_seq = s; super.body();
  endtask
endclass

class irq_external_vseq extends proc_base_vseq;
  `uvm_object_utils(irq_external_vseq)
  function new(string name = "irq_external_vseq"); super.new(name); endfunction
  task body();
    irq_pulse_seq s = irq_pulse_seq::type_id::create("external_pulse");
    s.line = proc_pkg::IRQ_EXTERNAL; s.delay_cycles = 120; s.pulse_width_cycles = 50;
    irq_seq = s; super.body();
  endtask
endclass


class irq_masking_vseq extends proc_base_vseq;
  `uvm_object_utils(irq_masking_vseq)
  function new(string name = "irq_masking_vseq"); super.new(name); endfunction
  task body();
    irq_pulse_seq s = irq_pulse_seq::type_id::create("masked_external_pulse");
    s.line = proc_pkg::IRQ_EXTERNAL;
    s.delay_cycles = 40;
    s.pulse_width_cycles = 200;
    irq_seq = s;
    super.body();
  endtask
endclass

class irq_priority_vseq extends proc_base_vseq;
  `uvm_object_utils(irq_priority_vseq)
  function new(string name = "irq_priority_vseq"); super.new(name); endfunction
  task body();
    irq_priority_seq s = irq_priority_seq::type_id::create("priority_pulse");
    s.delay_cycles = 120; s.pulse_width_cycles = 50;
    irq_seq = s; super.body();
  endtask
endclass

class burst_redirect_loop_vseq extends proc_base_vseq;
  `uvm_object_utils(burst_redirect_loop_vseq)
  function new(string name = "burst_redirect_loop_vseq");
    super.new(name);
  endfunction
endclass : burst_redirect_loop_vseq

// CSR / exception / mret round-trip: intentionally IDLE irq (not periodic
// timer pulses as originally planned). gen_golden.py's ISS run never
// asserts irq_timer_i/irq_software_i/irq_external_i, so any real interrupt
// injected here would make the DUT diverge from the golden bus trace for
// a reason that has nothing to do with a DUT bug -- a false failure, not a
// real one. Exercises ECALL/MRET only, via the base sequence's default
// (irq_idle_seq). Re-enable timer injection only after the golden model
// drives the same irq lines in lockstep with whatever the irq agent does.
class csr_exception_vseq extends proc_base_vseq;
  `uvm_object_utils(csr_exception_vseq)
  function new(string name = "csr_exception_vseq");
    super.new(name);
  endfunction
endclass : csr_exception_vseq

// AXI instruction-bus burst-boundary conditions: back-pressure the
// slave's accept/beat timing so RREADY/ARREADY stalls line up across a
// burst boundary the way the directed test program's branch targets are
// laid out to probe.
class axi_burst_boundary_vseq extends proc_base_vseq;
  `uvm_object_utils(axi_burst_boundary_vseq)
  function new(string name = "axi_burst_boundary_vseq");
    super.new(name);
  endfunction
  task body();
    mem_inject_cfg_helper inj = mem_inject_cfg_helper::type_id::create("inj");
    inj.apply_backpressure(60);
    inj.apply_latency(0, 4);
    super.body();
    inj.clear();
  endtask
endclass : axi_burst_boundary_vseq

// Constrained-random-friendly regression: mild AXI latency/backpressure
// variation. IRQ stimulus remains idle in this test; dedicated irq_* tests
// exercise the live interrupt inputs.
class random_regression_vseq extends proc_base_vseq;
  `uvm_object_utils(random_regression_vseq)
  function new(string name = "random_regression_vseq");
    super.new(name);
  endfunction
  task body();
    mem_inject_cfg_helper inj = mem_inject_cfg_helper::type_id::create("inj");
    inj.apply_latency(0, 3);
    inj.apply_backpressure(20);
    super.body();
    inj.clear();
  endtask
endclass : random_regression_vseq