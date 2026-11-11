`timescale 1ns / 1ps
// ============================================================================
// tb_ecall_os.sv - verify the OS-level SYNCHRONOUS trap path (ECALL, cause 11).
//
// In the FreeRTOS RV32 port, portYIELD() is an `ecall` instruction: every
// vTaskDelay() ends in an ECALL trap that the freertos_risc_v_trap_handler
// must classify (mcause=0x0000000B), run the scheduler, and mret into the
// next task. This TB runs the working blinky binary and:
//   - counts traps by cause: timer IRQ (0x80000007) vs ECALL (0x0000000B)
//   - checks every ECALL trap saves a valid mepc (an ECALL site in I-SRAM)
//   - decodes UART to confirm tasks A/B still alternate
// PASS = both trap kinds observed, all ECALL mepc values sane, A and B seen.
// ============================================================================
module tb_ecall_os;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic uart_tx, uart_irq, i2c_irq, gpio_irq;
  logic [3:0] timer_irq;
  logic scl_o, scl_oen, sda_o, sda_oen, spi_clk, spi_mosi;
  logic [3:0] spi_csn; logic [1:0] spi_irq;
  logic [31:0] gpio_in, gpio_out, gpio_dir; assign gpio_in = '0;
  soc_top dut (.clk_i(clk), .rst_ni(rst_n),
    .uart_rx_i(1'b1), .uart_tx_o(uart_tx), .uart_irq_o(uart_irq),
    .timer_irq_o(timer_irq),
    .i2c_scl_i(1'b1), .i2c_scl_o(scl_o), .i2c_scl_oen_o(scl_oen),
    .i2c_sda_i(1'b1), .i2c_sda_o(sda_o), .i2c_sda_oen_o(sda_oen), .i2c_irq_o(i2c_irq),
    .spi_clk_o(spi_clk), .spi_csn_o(spi_csn), .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0), .spi_irq_o(spi_irq),
    .gpio_in_i(gpio_in), .gpio_out_o(gpio_out), .gpio_dir_o(gpio_dir), .gpio_irq_o(gpio_irq));

  // ---- UART decode; remember which task letters we saw --------------------
  localparam int BIT_NS = 170;
  integer sawA = 0, sawB = 0;
  initial begin : rx
    byte ch; integer i;
    forever begin
      @(negedge uart_tx); #(BIT_NS + BIT_NS/2); ch = 0;
      for (i = 0; i < 8; i++) begin ch[i] = uart_tx; #(BIT_NS); end
      if (ch == "A") sawA = sawA + 1;
      if (ch == "B") sawB = sawB + 1;
      if (ch >= 8'h20 && ch < 8'h7f) $write("%c", ch);
      else if (ch == 8'h0a) $write("\n");
    end
  end

  // ---- trap census by cause ------------------------------------------------
  wire        trap   = dut.cpu.trap_taken;
  wire [31:0] mcause = dut.cpu.execute_stage.csr_block.mcause_q;
  wire [31:0] mepc   = dut.cpu.execute_stage.csr_block.mepc_q;
  // trap_taken can be level-held and mcause_q/mepc_q update one cycle after the
  // trap fires, so: detect the RISING EDGE of trap_taken, then sample the CSRs
  // one cycle later, when they hold THIS trap's cause and return PC.
  reg trap_d = 0, sample = 0;
  integer n_timer = 0, n_ecall = 0, n_other = 0, bad_mepc = 0, shown = 0;
  always @(posedge clk) if (rst_n) begin
    sample <= (trap && !trap_d);   // one cycle after the trap edge
    trap_d <= trap;
    if (sample) begin
      if (mcause == 32'h8000_0007) n_timer = n_timer + 1;
      else if (mcause == 32'h0000_000B) begin
        n_ecall = n_ecall + 1;
        // mepc must point at one of the ECALL instructions in this binary
        if (!(mepc inside {32'h0001_0880, 32'h0001_0ba8, 32'h0001_1094,
                           32'h0001_10a4, 32'h0001_1108})) bad_mepc = bad_mepc + 1;
        if (shown < 8) begin
          $display("[ECALL trap] mepc=0x%08h  (t=%0t)", mepc, $time);
          shown = shown + 1;
        end
      end
      else n_other = n_other + 1;
    end
  end

  // ---- run + verdict --------------------------------------------------------
  initial begin
    repeat (10) @(posedge clk); rst_n = 1;
    repeat (4_000_000) @(posedge clk);
    $display("\n---- census: timer=%0d ecall=%0d other=%0d bad_ecall_mepc=%0d  A=%0d B=%0d",
             n_timer, n_ecall, n_other, bad_mepc, sawA, sawB);
    if (n_ecall > 0 && n_timer > 0 && bad_mepc == 0 && sawA > 0 && sawB > 0)
      $display("ECALL_OS PASS: ECALL traps flow through the FreeRTOS handler alongside timer ticks; tasks keep running");
    else
      $display("ECALL_OS FAIL");
    $finish;
  end
endmodule