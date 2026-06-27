// ============================================================================
// reg_top.f — File list for simulation / synthesis
//
// Usage (Questa / ModelSim):
//   vlog -f reg_top.f
//
// Usage (Vivado):
//   read_verilog [reg_top.f]
//
// Usage (Yosys / Verilator):
//   verilator -f reg_top.f --top reg_top ...
// ============================================================================

// -- RTL sources (order: defines first, then slices, then regions, then top)
../rtl/reg_defines.v
../rtl/reg_slice.v
../rtl/reg_base.v
../rtl/reg_status.v
../rtl/reg_iic.v
../rtl/reg_spi.v
../rtl/reg_ft.v
../rtl/reg_int.v
../rtl/reg_top.v

// -- Testbench
../tb/tb_reg_top.v
