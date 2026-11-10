class irq_driver extends uvm_driver #(proc_pkg::proc_irq_txn);
  `uvm_component_utils(irq_driver)

  virtual irq_if.DRV vif;
  uvm_analysis_port #(proc_pkg::proc_irq_txn) ap;

  bit irq_timer_level;
  bit irq_software_level;
  bit irq_external_level;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual irq_if.DRV)::get(this, "", "vif", vif))
      `uvm_fatal("IRQ_DRV", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    proc_pkg::proc_irq_txn txn;
    bit changed;

    irq_timer_level    = 1'b0;
    irq_software_level = 1'b0;
    irq_external_level = 1'b0;

    vif.drv_cb.irq_timer    <= 1'b0;
    vif.drv_cb.irq_software <= 1'b0;
    vif.drv_cb.irq_external <= 1'b0;

    @(negedge vif.reset);

    forever begin
      seq_item_port.get_next_item(txn);
      changed = 1'b0;

      if (txn.atomic_levels) begin
        changed = ({irq_external_level, irq_software_level, irq_timer_level}
                   != txn.levels);
        if (changed) begin
          irq_timer_level    = txn.levels[0];
          irq_software_level = txn.levels[1];
          irq_external_level = txn.levels[2];
          vif.drv_cb.irq_timer    <= txn.levels[0];
          vif.drv_cb.irq_software <= txn.levels[1];
          vif.drv_cb.irq_external <= txn.levels[2];
        end
      end
      else begin
        case (txn.line)
          proc_pkg::IRQ_TIMER: begin
            changed = (irq_timer_level != txn.value);
            if (changed) begin
              irq_timer_level = txn.value;
              vif.drv_cb.irq_timer <= txn.value;
            end
          end
          proc_pkg::IRQ_SOFTWARE: begin
            changed = (irq_software_level != txn.value);
            if (changed) begin
              irq_software_level = txn.value;
              vif.drv_cb.irq_software <= txn.value;
            end
          end
          proc_pkg::IRQ_EXTERNAL: begin
            changed = (irq_external_level != txn.value);
            if (changed) begin
              irq_external_level = txn.value;
              vif.drv_cb.irq_external <= txn.value;
            end
          end
          default:
            `uvm_fatal("IRQ_DRV", $sformatf("Invalid IRQ line %0d", txn.line))
        endcase
      end

      if (changed) begin
        `uvm_info("IRQ_DRV",
          $sformatf("IRQ update atomic=%0b line=%0d value=%0b levels[T,S,E]=%b%b%b hold=%0d",
                    txn.atomic_levels, txn.line, txn.value,
                    irq_timer_level, irq_software_level, irq_external_level,
                    txn.hold_cycles), UVM_MEDIUM)
        ap.write(txn);
      end

      repeat (txn.hold_cycles) @(vif.drv_cb);
      seq_item_port.item_done();
    end
  endtask
endclass : irq_driver
