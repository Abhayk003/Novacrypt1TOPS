class test_hazard_fwd extends proc_base_test;
  `uvm_component_utils(test_hazard_fwd)
  function new(string name = "test_hazard_fwd", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "hazard_fwd_vseq";
  endfunction
endclass : test_hazard_fwd

class test_muldiv_corner extends proc_base_test;
  `uvm_component_utils(test_muldiv_corner)
  function new(string name = "test_muldiv_corner", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "muldiv_corner_vseq";
  endfunction
endclass : test_muldiv_corner

class test_smoke extends proc_base_test;
  `uvm_component_utils(test_smoke)
  function new(string name = "test_smoke", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "smoke_vseq";
  endfunction
endclass : test_smoke

class test_csr_exception extends proc_base_test;
  `uvm_component_utils(test_csr_exception)
  function new(string name = "test_csr_exception", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "csr_exception_vseq";
  endfunction
endclass : test_csr_exception

class test_branch_not_taken extends proc_base_test;
  `uvm_component_utils(test_branch_not_taken)
  function new(string name = "test_branch_not_taken", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "branch_not_taken_vseq";
  endfunction
endclass : test_branch_not_taken

class test_jalr_lsb_clear extends proc_base_test;
  `uvm_component_utils(test_jalr_lsb_clear)
  function new(string name = "test_jalr_lsb_clear", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "jalr_lsb_clear_vseq";
  endfunction
endclass : test_jalr_lsb_clear

class test_store_load_fwd extends proc_base_test;
  `uvm_component_utils(test_store_load_fwd)
  function new(string name = "test_store_load_fwd", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "store_load_fwd_vseq";
  endfunction
endclass : test_store_load_fwd

class test_x0_writes extends proc_base_test;
  `uvm_component_utils(test_x0_writes)
  function new(string name = "test_x0_writes", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "x0_writes_vseq";
  endfunction
endclass : test_x0_writes

class test_timer_interrupt extends proc_base_test;
  `uvm_component_utils(test_timer_interrupt)
  function new(string name = "test_timer_interrupt", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "timer_interrupt_vseq";
  endfunction
endclass : test_timer_interrupt

class test_burst_redirect_loop extends proc_base_test;
  `uvm_component_utils(test_burst_redirect_loop)
  function new(string name = "test_burst_redirect_loop", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "burst_redirect_loop_vseq";
  endfunction
endclass : test_burst_redirect_loop

class test_axi_burst_boundary extends proc_base_test;
  `uvm_component_utils(test_axi_burst_boundary)
  function new(string name = "test_axi_burst_boundary", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "axi_burst_boundary_vseq";
  endfunction
endclass : test_axi_burst_boundary

class test_random_regression extends proc_base_test;
  `uvm_component_utils(test_random_regression)
  function new(string name = "test_random_regression", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "random_regression_vseq";
  endfunction
endclass : test_random_regression

class test_irq_timer extends proc_base_test;
  `uvm_component_utils(test_irq_timer)
  function new(string name = "test_irq_timer", uvm_component parent = null);
    super.new(name, parent); default_vseq_type = "irq_timer_vseq";
  endfunction
endclass : test_irq_timer

class test_irq_software extends proc_base_test;
  `uvm_component_utils(test_irq_software)
  function new(string name = "test_irq_software", uvm_component parent = null);
    super.new(name, parent); default_vseq_type = "irq_software_vseq";
  endfunction
endclass : test_irq_software

class test_irq_external extends proc_base_test;
  `uvm_component_utils(test_irq_external)
  function new(string name = "test_irq_external", uvm_component parent = null);
    super.new(name, parent); default_vseq_type = "irq_external_vseq";
  endfunction
endclass : test_irq_external

class test_irq_priority extends proc_base_test;
  `uvm_component_utils(test_irq_priority)
  function new(string name = "test_irq_priority", uvm_component parent = null);
    super.new(name, parent); default_vseq_type = "irq_priority_vseq";
  endfunction
endclass : test_irq_priority

class test_irq_masking extends proc_base_test;
  `uvm_component_utils(test_irq_masking)
  function new(string name = "test_irq_masking", uvm_component parent = null);
    super.new(name, parent); default_vseq_type = "irq_masking_vseq";
  endfunction
endclass : test_irq_masking

class test_wide_regfile_toggle extends proc_base_test;
  `uvm_component_utils(test_wide_regfile_toggle)
  function new(string name = "test_wide_regfile_toggle", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "wide_regfile_toggle_vseq";
  endfunction
endclass : test_wide_regfile_toggle

class test_dmem_bit_walk extends proc_base_test;
  `uvm_component_utils(test_dmem_bit_walk)
  function new(string name = "test_dmem_bit_walk", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "dmem_bit_walk_vseq";
  endfunction
endclass : test_dmem_bit_walk

class test_imem_sram_reach extends proc_base_test;
  `uvm_component_utils(test_imem_sram_reach)
  function new(string name = "test_imem_sram_reach", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "imem_sram_reach_vseq";
  endfunction
endclass : test_imem_sram_reach

class test_msip_software_irq extends proc_base_test;
  `uvm_component_utils(test_msip_software_irq)
  function new(string name = "test_msip_software_irq", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "msip_software_irq_vseq";
  endfunction
endclass : test_msip_software_irq

class test_imem_bit12_toggle extends proc_base_test;
  `uvm_component_utils(test_imem_bit12_toggle)
  function new(string name = "test_imem_bit12_toggle", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "imem_bit12_toggle_vseq";
  endfunction
endclass : test_imem_bit12_toggle

class test_far_branch_toggle extends proc_base_test;
  `uvm_component_utils(test_far_branch_toggle)
  function new(string name = "test_far_branch_toggle", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "far_branch_toggle_vseq";
  endfunction
endclass : test_far_branch_toggle

class test_store_wstrb_transition extends proc_base_test;
  `uvm_component_utils(test_store_wstrb_transition)
  function new(string name = "test_store_wstrb_transition", uvm_component parent = null);
    super.new(name, parent);
    default_vseq_type = "store_wstrb_transition_vseq";
  endfunction
endclass : test_store_wstrb_transition