// ============================================================================
// SecVeriRL — Cadence Incisive File List
// ============================================================================
// Usage: irun -f filelist.f
// ============================================================================

// Package (must be first)
../../rtl/pkg/secverirl_pkg.sv

// Core
../../rtl/core/rv32i_alu.sv
../../rtl/core/rv32i_regfile.sv
../../rtl/core/rv32i_decoder.sv
../../rtl/core/rv32i_lsu.sv
../../rtl/core/rv32i_control.sv
../../rtl/core/rv32i_core.sv

// Security
../../rtl/security/pmp_unit.sv
../../rtl/security/security_monitor.sv

// Bus
../../rtl/bus/axi_lite_interconnect.sv

// Peripherals
../../rtl/peripherals/axi_lite_sram.sv
../../rtl/peripherals/axi_lite_uart.sv
../../rtl/peripherals/axi_lite_gpio.sv

// SoC Top
../../rtl/top/secverirl_soc_top.sv

// Testbench
./tb_secverirl_top.sv

