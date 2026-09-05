# ============================================================================
# SecVeriRL — cocotb Simulation Makefile
# ============================================================================
# Usage:
#   make SIM=verilator TESTCASE=test_basic_reset
#   make SIM=verilator TESTCASE=test_rl_driven
#   make SIM=icarus TESTCASE=test_security_scenarios
# ============================================================================

TOPLEVEL_LANG = verilog
SIM ?= verilator

# RTL source files
VERILOG_SOURCES = \
    $(PWD)/rtl/pkg/secverirl_pkg.sv \
    $(PWD)/rtl/core/rv32i_alu.sv \
    $(PWD)/rtl/core/rv32i_regfile.sv \
    $(PWD)/rtl/core/rv32i_decoder.sv \
    $(PWD)/rtl/core/rv32i_lsu.sv \
    $(PWD)/rtl/core/rv32i_control.sv \
    $(PWD)/rtl/core/rv32i_core.sv \
    $(PWD)/rtl/security/pmp_unit.sv \
    $(PWD)/rtl/security/security_monitor.sv \
    $(PWD)/rtl/peripherals/axi_lite_sram.sv \
    $(PWD)/rtl/peripherals/axi_lite_uart.sv \
    $(PWD)/rtl/peripherals/axi_lite_gpio.sv \
    $(PWD)/rtl/bus/axi_lite_interconnect.sv \
    $(PWD)/rtl/top/secverirl_soc_top.sv

# Top-level module
TOPLEVEL = secverirl_soc_top

# Python test module
MODULE = verification.cocotb_env.tb_top

# Verilator-specific flags
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace --coverage
    EXTRA_ARGS += -Wno-fatal
    EXTRA_ARGS += --timing
endif

# Icarus-specific flags
ifeq ($(SIM),icarus)
    EXTRA_ARGS += -g2012
endif

# Include cocotb Makefile
include $(shell cocotb-config --makefiles)/Makefile.sim

# Clean up
clean::
	rm -rf results.xml sim_build __pycache__
	rm -rf results/coverage_result.json results/coverage_vector.json
