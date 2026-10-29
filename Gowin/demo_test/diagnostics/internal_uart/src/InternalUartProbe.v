module InternalUartProbe(output wire o_uart_tx);
wire clk_probe;
OSCA Oscillator_Inst(.OSCOUT(clk_probe),.OSCEN(1'b1));
defparam Oscillator_Inst.FREQ_DIV=4;
// Internal oscillator nominal 52.5MHz; free-running UART letter U, no external reset/clock.
reg [8:0] cnt_baud=0;
reg reg_tx=1'b1;
always @(posedge clk_probe) begin
 if(cnt_baud==455) begin cnt_baud<=0;reg_tx<=~reg_tx;end
 else cnt_baud<=cnt_baud+1'b1;
end
assign o_uart_tx=reg_tx;
endmodule
