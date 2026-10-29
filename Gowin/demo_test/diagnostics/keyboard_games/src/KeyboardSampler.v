`timescale 1ns / 1ps
// Same ADC double-conversion and mux order as the validated KeyboardDebug.
// 采样结果保持到ready握手，串口反压只影响下一键扫描。
module KeyboardSampler #(
 parameter integer C_SETTLE_CYCLES=10000,parameter integer C_HALF_CYCLES=6
)(
 input i_clk,input i_rstn,input i_adc_dout,input i_ready,
 output [2:0] o_mux_sel,output o_mux_en,output o_adc_cs_n,output o_adc_sclk,output o_adc_din,
 output [4:0] o_key,output [11:0] o_raw,output o_valid
);
localparam [2:0] ST_SETTLE=0,ST_START=1,ST_SPI=2,ST_GAP=3,ST_REPORT=4,ST_ADVANCE=5;
reg [2:0] state_current,state_next,enc_mux;
reg [4:0] reg_key,cnt_spi_bit;
reg [31:0] cnt_wait;
reg [15:0] cnt_half,reg_command,reg_receive;
reg [11:0] reg_sample;
reg flag_dummy,reg_cs_n,reg_sclk;
assign o_key=reg_key;assign o_raw=reg_sample;assign o_valid=state_current==ST_REPORT;
assign o_mux_sel=enc_mux;assign o_mux_en=i_rstn;
assign o_adc_cs_n=reg_cs_n;assign o_adc_sclk=reg_sclk;assign o_adc_din=reg_command[15];
always @(*)begin
 case(reg_key[2:0])
  0:enc_mux=4;1:enc_mux=5;2:enc_mux=6;3:enc_mux=7;
  4:enc_mux=3;5:enc_mux=2;6:enc_mux=1;default:enc_mux=0;
 endcase
end
always @(*)begin
 state_next=state_current;
 case(state_current)
  ST_SETTLE:begin if(cnt_wait==C_SETTLE_CYCLES-1)begin state_next=ST_START; end end
  ST_START:begin state_next=ST_SPI; end
  ST_SPI:begin if(cnt_half==C_HALF_CYCLES-1 && reg_sclk && cnt_spi_bit==15)begin state_next=ST_GAP; end end
  ST_GAP:begin if(cnt_wait==15)begin
   if(flag_dummy)begin state_next=ST_START; end else begin state_next=ST_REPORT; end
  end end
  ST_REPORT:begin if(i_ready)begin state_next=ST_ADVANCE; end end
  ST_ADVANCE:begin state_next=ST_SETTLE; end
  default:begin state_next=ST_SETTLE; end
 endcase
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin state_current<=ST_SETTLE; end else begin state_current<=state_next; end
end
always @(posedge i_clk or negedge i_rstn)begin
 if(!i_rstn)begin
  reg_key<=0;cnt_wait<=0;cnt_half<=0;cnt_spi_bit<=0;flag_dummy<=1;
  reg_cs_n<=1;reg_sclk<=0;reg_command<=0;reg_receive<=0;reg_sample<=0;
 end else begin
  case(state_current)
   ST_SETTLE:begin
    if(state_next==ST_START)begin cnt_wait<=0; end else begin cnt_wait<=cnt_wait+1'b1; end
   end
   ST_START:begin reg_cs_n<=0;reg_sclk<=0;cnt_half<=0;cnt_spi_bit<=0;reg_command<={3'b000,reg_key[4:3],11'b0};reg_receive<=0; end
   ST_SPI:begin
    if(cnt_half==C_HALF_CYCLES-1)begin
     cnt_half<=0;reg_sclk<=!reg_sclk;
     if(!reg_sclk)begin reg_receive<={reg_receive[14:0],i_adc_dout}; end
     else if(cnt_spi_bit==15)begin
      reg_cs_n<=1;cnt_wait<=0;
      if(!flag_dummy)begin reg_sample<=reg_receive[11:0]; end
     end else begin cnt_spi_bit<=cnt_spi_bit+1'b1;reg_command<={reg_command[14:0],1'b0}; end
    end else begin cnt_half<=cnt_half+1'b1; end
   end
   ST_GAP:begin
    if(cnt_wait==15)begin cnt_wait<=0;flag_dummy<=0; end else begin cnt_wait<=cnt_wait+1'b1; end
   end
   ST_ADVANCE:begin reg_key<=reg_key+1'b1;flag_dummy<=1; end
   default:begin reg_cs_n<=1;reg_sclk<=0;cnt_wait<=0; end
  endcase
 end
end
endmodule
