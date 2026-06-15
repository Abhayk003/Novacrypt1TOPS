// ============================================================================
// rtl.f - compile order for the RV32IM SoC (use with: verilator -f rtl.f ...)
// Packages and include-defining files come first.
// ============================================================================

// include search paths
+incdir+vendor/axi/include
+incdir+vendor/common_cells/include
+incdir+vendor/apb/include
+incdir+vendor/register_interface/include

// packages first
vendor/common_cells/src/cf_math_pkg.sv
vendor/axi/src/axi_pkg.sv
vendor/apb/src/apb_pkg.sv
vendor/register_interface/src/reg_intf.sv
vendor/rv_plic/rtl/rv_plic_reg_pkg.sv
vendor/gpio/src/gpio_reg_pkg.sv

// files whose module name != filename (must be listed explicitly)
vendor/rv_plic/rtl/plic_regmap.sv
vendor/tech_cells_generic/src/rtl/tc_clk.sv
vendor/gpio/src/gpio.sv

// --- vendored IP (library search dirs) ---
-y vendor/axi/src
-y vendor/common_cells/src
-y vendor/apb/src
-y vendor/apb_uart_sv
-y vendor/apb_timer/src
-y vendor/apb_i2c
-y vendor/apb_spi_master
-y vendor/axi_spi_master
-y vendor/gpio/src
-y vendor/register_interface/src
-y vendor/register_interface/src/deprecated
-y vendor/register_interface/vendor/lowrisc_opentitan/src
-y vendor/rv_plic/rtl

// --- our RTL ---
-y rtl/cpu
-y rtl
rtl/soc_top.sv
rtl/sram.sv
rtl/axi_to_apb_custom.sv
