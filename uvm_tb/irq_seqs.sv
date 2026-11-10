// IRQ sequences. Every driver transaction has a legal 1..50-cycle hold.
class irq_idle_seq extends uvm_sequence #(proc_pkg::proc_irq_txn);
  `uvm_object_utils(irq_idle_seq)
  function new(string name = "irq_idle_seq"); super.new(name); endfunction
  task body(); endtask
endclass : irq_idle_seq

class irq_pulse_seq extends uvm_sequence #(proc_pkg::proc_irq_txn);
  `uvm_object_utils(irq_pulse_seq)
  proc_pkg::irq_line_e line = proc_pkg::IRQ_EXTERNAL;
  int unsigned delay_cycles = 120;
  int unsigned pulse_width_cycles = 20;

  function new(string name = "irq_pulse_seq"); super.new(name); endfunction

  task send_level(proc_pkg::irq_line_e which, bit level, int unsigned cycles);
    proc_pkg::proc_irq_txn tx;
    int unsigned chunk;
    while (cycles != 0) begin
      chunk = (cycles > 50) ? 50 : cycles;
      tx = proc_pkg::proc_irq_txn::type_id::create("tx");
      start_item(tx);
      tx.line = which;
      tx.value = level;
      tx.hold_cycles = chunk;
      tx.atomic_levels = 1'b0;
      tx.levels = '0;
      finish_item(tx);
      cycles -= chunk;
    end
  endtask

  task body();
    if (pulse_width_cycles == 0)
      `uvm_fatal("IRQ_SEQ", "pulse_width_cycles must be non-zero")
    send_level(line, 1'b0, delay_cycles);
    send_level(line, 1'b1, pulse_width_cycles);
    send_level(line, 1'b0, 1);
  endtask
endclass : irq_pulse_seq

class irq_periodic_pulse_seq extends uvm_sequence #(proc_pkg::proc_irq_txn);
  `uvm_object_utils(irq_periodic_pulse_seq)
  rand proc_pkg::irq_line_e line = proc_pkg::IRQ_TIMER;
  rand int unsigned n_pulses = 4;
  rand int unsigned period_cycles = 200;
  rand int unsigned pulse_width_cycles = 5;
  function new(string name = "irq_periodic_pulse_seq"); super.new(name); endfunction

  task send(proc_pkg::irq_line_e which, bit level, int unsigned cycles);
    proc_pkg::proc_irq_txn tx;
    int unsigned chunk;
    while (cycles != 0) begin
      chunk = (cycles > 50) ? 50 : cycles;
      tx = proc_pkg::proc_irq_txn::type_id::create("tx");
      start_item(tx);
      tx.line = which; tx.value = level; tx.hold_cycles = chunk;
      tx.atomic_levels = 0; tx.levels = '0;
      finish_item(tx);
      cycles -= chunk;
    end
  endtask

  task body();
    if (n_pulses == 0 || pulse_width_cycles == 0 || pulse_width_cycles > 50 ||
        period_cycles < pulse_width_cycles)
      `uvm_fatal("IRQ_SEQ", "Illegal periodic IRQ parameters")
    repeat (n_pulses) begin
      send(line, 1'b1, pulse_width_cycles);
      send(line, 1'b0, period_cycles - pulse_width_cycles);
    end
  endtask
endclass : irq_periodic_pulse_seq

class irq_priority_seq extends uvm_sequence #(proc_pkg::proc_irq_txn);
  `uvm_object_utils(irq_priority_seq)
  int unsigned delay_cycles = 120;
  int unsigned pulse_width_cycles = 20;
  function new(string name = "irq_priority_seq"); super.new(name); endfunction

  task wait_low(int unsigned cycles);
    proc_pkg::proc_irq_txn tx;
    int unsigned chunk;
    while (cycles != 0) begin
      chunk = (cycles > 50) ? 50 : cycles;
      tx = proc_pkg::proc_irq_txn::type_id::create("wait_tx");
      start_item(tx);
      tx.line = proc_pkg::IRQ_TIMER; tx.value = 0; tx.hold_cycles = chunk;
      tx.atomic_levels = 0; tx.levels = 0;
      finish_item(tx);
      cycles -= chunk;
    end
  endtask

  task drive_all(bit [2:0] levels, int unsigned cycles);
    proc_pkg::proc_irq_txn tx;
    tx = proc_pkg::proc_irq_txn::type_id::create("all_irq_tx");
    start_item(tx);
    tx.line = proc_pkg::IRQ_TIMER; tx.value = levels[0];
    tx.hold_cycles = cycles; tx.atomic_levels = 1; tx.levels = levels;
    finish_item(tx);
  endtask

  task body();
    if (pulse_width_cycles == 0)
      `uvm_fatal("IRQ_SEQ", "pulse_width_cycles must be non-zero")
    wait_low(delay_cycles);
    drive_all(3'b111, pulse_width_cycles);
    drive_all(3'b000, 1);
  endtask
endclass : irq_priority_seq

class irq_random_seq extends uvm_sequence #(proc_pkg::proc_irq_txn);
  `uvm_object_utils(irq_random_seq)
  rand int unsigned n_events = 30;
  bit [2:0] levels = 3'b000;
  function new(string name = "irq_random_seq"); super.new(name); endfunction
  task body();
    proc_pkg::proc_irq_txn tx;
    int unsigned idx, hold;
    bit new_level;
    repeat (n_events) begin
      idx = $urandom_range(0,2);
      new_level = ~levels[idx];
      levels[idx] = new_level;
      hold = $urandom_range(1,50);
      tx = proc_pkg::proc_irq_txn::type_id::create("random_irq_tx");
      start_item(tx);
      tx.line = proc_pkg::irq_line_e'(idx);
      tx.value = new_level;
      tx.hold_cycles = hold;
      tx.atomic_levels = 0;
      tx.levels = levels;
      finish_item(tx);
    end
    // Return every line to inactive.
    for (int i=0; i<3; i++) begin
      if (levels[i]) begin
        tx = proc_pkg::proc_irq_txn::type_id::create("random_irq_clear");
        start_item(tx);
        tx.line = proc_pkg::irq_line_e'(i);
        tx.value = 0;
        tx.hold_cycles = 1;
        tx.atomic_levels = 0;
        tx.levels = '0;
        finish_item(tx);
      end
    end
  endtask
endclass : irq_random_seq

