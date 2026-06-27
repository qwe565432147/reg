# ============================================================================
# run_sim.tcl — Run simulation with ModelSim / Questa / vsim
#
# Usage:
#   vsim -do run_sim.tcl
#   or open in ModelSim GUI: Tools → Execute Macro...
# ============================================================================

onbreak {resume}

# Clean
if {[file exists work]} {
    vdel -all
}

# Create library
vlib work

# Compile all sources
vlog -sv -work work -f reg_top.f

# Load the testbench
vsim -voptargs="+acc" work.tb_reg_top

# Add waves
log -r /*

add wave -divider "Clock & Reset"
add wave clk rst_n

add wave -divider "Bus Interface"
add wave bus_req bus_we bus_addr bus_wdata bus_rdata bus_rdy bus_err

add wave -divider "Interrupt"
add wave irq intr_sources

add wave -divider "reg_base"
add wave ver_major ver_minor chip_id scratch

add wave -divider "reg_status"
add wave init_done cal_done system_error error_count error_clr_pulse

add wave -divider "reg_int"
add wave u_dut/u_reg_int/enable_val
add wave u_dut/u_reg_int/pending_val
add wave u_dut/u_reg_int/int_status
add wave u_dut/u_reg_int/vector_rdata

add wave -divider "Region Selects"
add wave u_dut/reg_sel_base u_dut/reg_sel_status u_dut/reg_sel_int
add wave u_dut/reg_sel_iic u_dut/reg_sel_spi u_dut/reg_sel_ft

# Run
run 2000 ns

# Report
echo ""
echo "=== Simulation complete ==="

# Show pass/fail from transcript
if {[string match "*ALL TESTS PASSED*" [transcript]]} {
    echo "Result: ALL TESTS PASSED"
} else {
    echo "Result: SOME TESTS FAILED — check transcript"
}
