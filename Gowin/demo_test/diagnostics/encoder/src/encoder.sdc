create_clock -name board_clock -period 20.000 [get_ports {i_clk}]
set_false_path -from [get_ports {i_rstn}]
# 异步触点仅到第一级同步器，不约束成同步输入总线。
set_false_path -from [get_ports {i_encoder_a[*] i_encoder_b[*]}]
# UART接收端异步采样；此值保留15ns寄存器至管脚预算，不表示外部同步时钟。
set_output_delay -clock board_clock -max 5.000 [get_ports {o_uart_tx}]
