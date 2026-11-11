module tb_riscv_dv;

    logic clk_i = 0;
    logic rst_ni = 0;

    logic uart_tx_o, uart_irq_o;
    logic [3:0] timer_irq_o;

    logic i2c_scl_o, i2c_scl_oen_o;
    logic i2c_sda_o, i2c_sda_oen_o;
    logic i2c_irq_o;

    logic spi_clk_o, spi_mosi_o;
    logic [3:0] spi_csn_o;
    logic [1:0] spi_irq_o;

    logic [31:0] gpio_out_o, gpio_dir_o;
    logic gpio_irq_o;

    always #5 clk_i = ~clk_i;

    soc_top dut (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),

        .uart_rx_i      (1'b1),
        .uart_tx_o      (uart_tx_o),
        .uart_irq_o     (uart_irq_o),
        .timer_irq_o    (timer_irq_o),

        .i2c_scl_i      (1'b1),
        .i2c_scl_o      (i2c_scl_o),
        .i2c_scl_oen_o  (i2c_scl_oen_o),
        .i2c_sda_i      (1'b1),
        .i2c_sda_o      (i2c_sda_o),
        .i2c_sda_oen_o  (i2c_sda_oen_o),
        .i2c_irq_o      (i2c_irq_o),

        .spi_clk_o      (spi_clk_o),
        .spi_csn_o      (spi_csn_o),
        .spi_mosi_o     (spi_mosi_o),
        .spi_miso_i     (1'b0),
        .spi_irq_o      (spi_irq_o),

        .gpio_in_i      (32'b0),
        .gpio_out_o     (gpio_out_o),
        .gpio_dir_o     (gpio_dir_o),
        .gpio_irq_o     (gpio_irq_o)
    );

    initial begin
        // Initialize data SRAM
        #1;
        $readmemh("dmem.mem", dut.gen_mem[2].i_sram.mem);

        // Release active-low reset
        repeat (5) @(posedge clk_i);
        rst_ni = 1'b1;

        $display("Novacrypt riscv-dv test started");

        // Wait for riscv-dv to signal completion through tohost
        fork
            begin
                wait (dut.gen_mem[2].i_sram.mem[0] == 32'd1);
                $display("TEST PASSED: tohost = 1");
                $finish;
            end

            begin
                repeat (1000000) @(posedge clk_i);
                $display("TEST TIMEOUT");
		$display("PC     = %h", dut.cpu.pc);
$display("MEPC   = %h", dut.cpu.execute_stage.csr_block.mepc_q);
$display("MCAUSE = %h", dut.cpu.execute_stage.csr_block.mcause_q);
$display("MTVAL  = %h", dut.cpu.execute_stage.csr_block.mtval_q);
$display("TOHOST = %h", dut.gen_mem[2].i_sram.mem[0]);
$finish;
            end
        join_any
    end

endmodule
