# SecVeriRL SoC — Timing Constraints for Sky130 @ 50MHz
# Clock period = 20ns

create_clock -name clk -period 20.0 [get_ports clk]

# Input delays (assume 25% of clock period)
set_input_delay -clock clk 5.0 [get_ports rst_n]
set_input_delay -clock clk 5.0 [get_ports ext_irq]
set_input_delay -clock clk 5.0 [get_ports timer_irq]
set_input_delay -clock clk 5.0 [get_ports sw_irq]
set_input_delay -clock clk 5.0 [get_ports uart_rx]
set_input_delay -clock clk 5.0 [get_ports {gpio_in[*]}]

# Output delays (assume 25% of clock period)
set_output_delay -clock clk 5.0 [get_ports uart_tx]
set_output_delay -clock clk 5.0 [get_ports {gpio_out[*]}]
set_output_delay -clock clk 5.0 [get_ports {gpio_oe[*]}]
set_output_delay -clock clk 5.0 [get_ports sec_alert]
set_output_delay -clock clk 5.0 [get_ports {sec_alert_code[*]}]
set_output_delay -clock clk 5.0 [get_ports {sec_event_count[*]}]
set_output_delay -clock clk 5.0 [get_ports rvfi_valid]
set_output_delay -clock clk 5.0 [get_ports {rvfi_insn[*]}]
set_output_delay -clock clk 5.0 [get_ports {rvfi_pc[*]}]
set_output_delay -clock clk 5.0 [get_ports {rvfi_next_pc[*]}]
set_output_delay -clock clk 5.0 [get_ports {rvfi_rd_addr[*]}]
set_output_delay -clock clk 5.0 [get_ports {rvfi_rd_data[*]}]
set_output_delay -clock clk 5.0 [get_ports rvfi_trap]
set_output_delay -clock clk 5.0 [get_ports {rvfi_priv[*]}]
