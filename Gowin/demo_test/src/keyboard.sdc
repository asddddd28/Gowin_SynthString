create_clock -name sys_clk -period 20.000 [get_ports {i_clk}]
set_false_path -from [get_ports {i_rstn}]
# ADC output arrives after the preceding falling SCLK edge, 120ns before capture.
# Conservative budget includes 40ns ADC delay plus PCB/level translator delay.
set_max_delay 60.000 -from [get_ports {i_adc_dout}]
set_min_delay 0.000 -from [get_ports {i_adc_dout}]
set_max_delay 20.000 -to [get_ports {o_adc_cs_n o_adc_sclk o_adc_din o_mux_sel[*] o_mux_en o_uart_tx o_rgb}]
set_min_delay 0.000 -to [get_ports {o_adc_cs_n o_adc_sclk o_adc_din o_mux_sel[*] o_mux_en o_uart_tx o_rgb}]
