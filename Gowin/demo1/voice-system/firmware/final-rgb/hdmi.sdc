create_clock -name clk -period 20.000 [get_ports {i_clk}]
# Match actual reference PLL: 50 MHz *22 /3 and /15; pixel and serial are RELATED.
create_generated_clock -name serial_clk -source [get_ports {i_clk}] -master_clock clk -divide_by 3 -multiply_by 22 [get_pins {u_tmds_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name pixel_clk -source [get_ports {i_clk}] -master_clock clk -divide_by 15 -multiply_by 22 [get_pins {u_tmds_pll/PLLA_inst/CLKOUT1}]
# Toggle handshakes hold status/sample banks; metadata uses dual-clock RAM.
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {pixel_clk serial_clk}]
