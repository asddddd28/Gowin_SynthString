create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
# PLL output physically halved: 50 MHz * 58/59, 512 core cycles per audio frame.
create_generated_clock -name audio_core -source [get_ports {sys_clk}] -multiply_by 58 -divide_by 59 [get_pins {Clock_Inst/u_pll/PLLA_inst/CLKOUT0}]
set_clock_uncertainty 0.100 -to [get_clocks {audio_core}]
# Only asynchronous inputs and reset-synchronizer assertion pins are excluded.
set_false_path -from [get_ports {sys_rst_n Key_in[0] Key_in[1] uart_rx}]
set_false_path -to [get_pins {Reset_Inst/reg_release_0_s0/CLEAR Reset_Inst/reg_release_1_s0/CLEAR}]
# Serialized data updates 6 core clocks before the DAC sampling edge (~122 ns).
# Bound all audio pin paths to 10 ns, within the serial setup budget.
set_max_delay 10.000 -to [get_ports {HP_BCK HP_WS HP_DIN}]
set_min_delay 0.000 -to [get_ports {HP_BCK HP_WS HP_DIN}]
set_max_delay 20.000 -to [get_ports {PA_EN}]
set_min_delay 0.000 -to [get_ports {PA_EN}]
set_max_delay 20.000 -to [get_ports {uart_tx}]
set_min_delay 0.000 -to [get_ports {uart_tx}]
