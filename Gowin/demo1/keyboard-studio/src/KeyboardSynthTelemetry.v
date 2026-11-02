`timescale 1ns/1ps
// KeyboardSynthTelemetry: 固定 32 字节快照，10 Hz，异或校验用于调试传输。
// 合同和时序：../spec/KeyboardSynthTelemetry_spec.md。
module KeyboardSynthTelemetry #(
 parameter C_REPORT_CYCLES=5000000,parameter C_BAUD_CYCLES=434
)(
 input i_clk,input i_rstn,input [31:0] i_frames,input [31:0] i_pressed,
 input [31:0] i_delivered,input [31:0] i_nonzero,input [31:0] i_events,
 input [15:0] i_cycles,input [7:0] i_flags,input [4:0] i_key,input [11:0] i_raw,
 input [3:0] i_volume,input [5:0] i_active_count,input [18:0] i_gain,
 input [23:0] i_input_peak,input [23:0] i_output_peak,input [31:0] i_clips,
 input [6:0] i_stages,input [31:0] i_wave_peak,input [31:0] i_mod_peak,input [17:0] i_env_peak,
 input [7:0] i_ack_seq,i_ack_op,i_ack_status,i_ack_key,input [15:0] i_ack_crc,input [31:0] i_commits,
 output o_uart_tx
);
 localparam [1:0] C_IDLE=0,C_SUM=1,C_SEND=2,C_WAIT=3;
 reg [1:0] state_current,state_next;
 reg [31:0] cnt_report;
 reg [639:0] reg_packet;
 reg [6:0] cnt_byte;
 reg [7:0] reg_checksum;
 wire flag_busy,flag_start;
 assign flag_start=state_current==C_SEND&&!flag_busy;
 EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES)) Uart_Inst(
 .i_clk(i_clk),.i_rstn(i_rstn),.i_start(flag_start),.i_data(reg_packet[7:0]),.o_busy(flag_busy),.o_tx(o_uart_tx));
 always @(*)begin
  state_next=state_current;
  case(state_current)
   C_IDLE:if(cnt_report==C_REPORT_CYCLES-1)state_next=C_SUM;
   C_SUM:if(cnt_byte==77)state_next=C_SEND;
   C_SEND:if(flag_start)state_next=C_WAIT;
   C_WAIT:if(!flag_busy)begin if(cnt_byte==79)state_next=C_IDLE;else state_next=C_SEND;end
   default:state_next=C_IDLE;
  endcase
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)state_current<=C_IDLE;else state_current<=state_next;
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin cnt_report<=0;reg_packet<=0;cnt_byte<=0;reg_checksum<=0;end
  else begin
   case(state_current)
    C_IDLE:begin
     if(cnt_report==C_REPORT_CYCLES-1)begin
      cnt_report<=0;cnt_byte<=0;reg_checksum<=0;
      reg_packet<={8'h0d,8'd0,16'd0,32'h0000001f,i_commits,i_ack_crc,i_ack_key,i_ack_status,i_ack_op,i_ack_seq,4'd0,i_volume,1'b0,i_stages,i_mod_peak,i_wave_peak,14'd0,i_env_peak,i_clips,8'd0,i_output_peak,8'd0,i_input_peak,13'd0,i_gain,2'd0,i_active_count,4'd0,i_volume,4'd0,i_raw,3'd0,i_key,i_flags,i_cycles,
                   i_events,i_nonzero,i_delivered,i_pressed,i_frames,32'h50035aa5};
     end else cnt_report<=cnt_report+1'b1;
    end
    C_SUM:begin
     reg_checksum<=reg_checksum^reg_packet[cnt_byte*8+:8];
     if(cnt_byte==77)begin reg_packet[631:624]<=reg_checksum^reg_packet[623:616];cnt_byte<=0;end
     else cnt_byte<=cnt_byte+1'b1;
    end
    C_WAIT:if(!flag_busy)begin cnt_byte<=cnt_byte+1'b1;reg_packet<={8'd0,reg_packet[639:8]};end
    default:begin end
   endcase
  end
 end
endmodule
