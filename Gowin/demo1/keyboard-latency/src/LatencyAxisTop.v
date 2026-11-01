`timescale 1ns/1ps
// KeyboardAxisTop: 50 MHz 同域 ADC -> 判键 -> AXIS -> PT8211；不依赖电脑发声。
// 合同和时序：../spec/KeyboardAxisTop_spec.md。
module LatencyAxisTop #(
 parameter C_PHASE_CORES=1,parameter C_WAVE_CORES=2,parameter C_ENV_CORES=3,parameter C_MOD_CORES=1,parameter C_FILTER_CORES=1,parameter C_VCA_CORES=1,
 parameter C_LATENCY_TIMEOUT=50000000,parameter C_LATENCY_BUDGET=500000,
 parameter C_SETTLE_CYCLES=10000,parameter C_HALF_CYCLES=6,
 parameter C_UART_CYCLES=434,parameter C_REPORT_CYCLES=5000000,
 parameter C_POWERUP_CYCLES=65535,parameter C_TEST_CYCLES=50000000
)(
 input i_clk,input i_rstn,input i_adc_dout,input i_uart_rx,
 output [2:0] o_mux_sel,output o_mux_en,output o_adc_cs_n,
 output o_adc_sclk,output o_adc_din,output o_uart_tx,
 output HP_BCK,output HP_WS,output HP_DIN,output PA_EN
);
 reg [15:0] cnt_powerup=0;
 reg [1:0] reg_reset=0,reg_adc=0;
 wire flag_rstn;
 wire [4:0] enc_key,enc_cfg_voice;
 wire [11:0] enc_raw;
 wire flag_sample,flag_cfg_valid,flag_cfg_ready,flag_initialized;
 wire [31:0] enc_pressed,enc_effective,enc_delivered,enc_events;
 wire [511:0] enc_cfg_data;
 wire flag_pcm,flag_busy,flag_fault,flag_overrun,flag_underrun;
 wire [23:0] enc_pcm_left,enc_pcm_right;
 wire [15:0] enc_cycles;
 wire [7:0] enc_rx;
 wire flag_rx_valid,flag_rx_error;
 reg [31:0] cnt_test,cnt_frames,cnt_nonzero;
 reg [20:0] cnt_amplifier;
 reg [4:0] reg_key;
 reg [11:0] reg_raw;
 wire [7:0] enc_flags;
 reg [3:0] reg_volume;
 wire flag_ascii,flag_patch,flag_patch_ready,flag_wave,flag_wave_ready,flag_wave_frame,flag_volume;
 wire [7:0] enc_ascii,ack_seq,ack_op,ack_status,ack_key;
 wire [15:0] ack_crc,enc_wave_data;wire [31:0] enc_remote,enc_commits;
 wire [223:0] enc_velocity;wire [3:0] enc_volume;
 wire [511:0] enc_patch;wire [4:0] enc_patch_key;wire [10:0] enc_wave_address;
 StudioControl Control_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_rx_valid(flag_rx_valid),.i_rx_error(flag_rx_error),.i_rx_data(enc_rx),
 .o_ascii_valid(flag_ascii),.o_ascii_data(enc_ascii),.o_patch_valid(flag_patch),.i_patch_ready(flag_patch_ready),.o_patch_key(enc_patch_key),.o_patch_data(enc_patch),
 .o_wave_valid(flag_wave),.i_wave_ready(flag_wave_ready),.o_wave_frame(flag_wave_frame),.o_wave_address(enc_wave_address),.o_wave_data(enc_wave_data),
 .o_remote(enc_remote),.o_velocity(enc_velocity),.o_volume(enc_volume),.o_volume_valid(flag_volume),
 .o_ack_seq(ack_seq),.o_ack_op(ack_op),.o_ack_status(ack_status),.o_ack_key(ack_key),.o_ack_crc(ack_crc),.o_commits(enc_commits));
 wire [5:0] enc_active_count;wire [18:0] enc_gain;
 wire [23:0] enc_input_peak,enc_output_peak;wire [31:0] enc_clips,enc_wave_peak,enc_mod_peak;
 wire [17:0] enc_env_peak;wire [6:0] enc_stages;
 always @(posedge i_clk or negedge flag_rstn)begin
  if(!flag_rstn)reg_volume<=6;
  else if(flag_volume)reg_volume<=enc_volume;
  else if(flag_ascii&&enc_ascii>=8'h30&&enc_ascii<=8'h38)reg_volume<=enc_ascii[3:0];
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin cnt_powerup<=0;reg_reset<=0;end
  else begin
   if(cnt_powerup<C_POWERUP_CYCLES)cnt_powerup<=cnt_powerup+1'b1;
   reg_reset<={reg_reset[0],cnt_powerup==C_POWERUP_CYCLES};
  end
 end
 assign flag_rstn=reg_reset[1];
 always @(posedge i_clk)reg_adc<={reg_adc[0],i_adc_dout};
 KeyboardSampler #(.C_SETTLE_CYCLES(C_SETTLE_CYCLES),.C_HALF_CYCLES(C_HALF_CYCLES)) Scanner_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_adc_dout(reg_adc[1]),.i_ready(1'b1),
 .o_mux_sel(o_mux_sel),.o_mux_en(o_mux_en),.o_adc_cs_n(o_adc_cs_n),
 .o_adc_sclk(o_adc_sclk),.o_adc_din(o_adc_din),.o_key(enc_key),.o_raw(enc_raw),.o_valid(flag_sample));
 wire flag_candidate,flag_confirm,flag_cancel;
 LatencyKeyThresholds Keys_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_key(enc_key),.i_raw(enc_raw),.i_valid(flag_sample),.o_pressed(enc_pressed),.o_candidate(flag_candidate),.o_confirm(flag_confirm),.o_cancel(flag_cancel));
 UartRx #(.C_CLOCK_HZ(C_UART_CYCLES*115200),.C_BAUD(115200)) Rx_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_rx(i_uart_rx),.o_byte(enc_rx),.o_valid(flag_rx_valid),.o_error(flag_rx_error));
 // T: 一秒 C4 数字自测；P: 结束自测。物理键位始终独立采集。
 always @(posedge i_clk or negedge flag_rstn)begin
  if(!flag_rstn)cnt_test<=0;
  else if(flag_ascii&&enc_ascii==8'h54)cnt_test<=C_TEST_CYCLES;
  else if(flag_ascii&&enc_ascii==8'h50)cnt_test<=0;
  else if(cnt_test!=0)cnt_test<=cnt_test-1'b1;
 end
 assign enc_effective=enc_pressed | enc_remote | (cnt_test!=0?32'h00001000:32'd0);
 KeyboardVoiceBridge Bridge_Inst(.i_clk(i_clk),.i_rstn(flag_rstn),.i_pressed(enc_effective),.i_frame_done(flag_pcm),
 .i_patch_valid(flag_patch),.o_patch_ready(flag_patch_ready),.i_patch_key(enc_patch_key),.i_patch_data(enc_patch),.i_velocity(enc_velocity),
 .o_cfg_valid(flag_cfg_valid),.i_cfg_ready(flag_cfg_ready),.o_cfg_voice(enc_cfg_voice),.o_cfg_data(enc_cfg_data),
 .o_initialized(flag_initialized),.o_delivered(enc_delivered),.o_events(enc_events));
 wire flag_result,flag_frame_load,flag_dac_latch,flag_pcm_nonzero;
 wire [4:0] enc_result_key;wire [191:0] enc_result;
 LatencyAudioSystem #(.C_PHASE_CORES(C_PHASE_CORES),.C_WAVE_CORES(C_WAVE_CORES),.C_ENV_CORES(C_ENV_CORES),.C_MOD_CORES(C_MOD_CORES),.C_FILTER_CORES(C_FILTER_CORES),.C_VCA_CORES(C_VCA_CORES),.C_VOICES(32),.C_MIX_SHIFT(5),.C_FRAME_STEP(1),.C_PT8211(1)) Synth_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_run(flag_initialized),
 .i_volume(reg_volume),.o_active_count(enc_active_count),.o_gain(enc_gain),.o_input_peak(enc_input_peak),.o_output_peak(enc_output_peak),.o_clips(enc_clips),
 .o_stages(enc_stages),.o_wave_peak(enc_wave_peak),.o_mod_peak(enc_mod_peak),.o_env_peak(enc_env_peak),
 .i_cfg_valid(flag_cfg_valid),.o_cfg_ready(flag_cfg_ready),.i_cfg_voice(enc_cfg_voice),.i_cfg_data(enc_cfg_data),
 .i_wave_valid(flag_wave),.o_wave_ready(flag_wave_ready),.i_wave_frame(flag_wave_frame),.i_wave_address(enc_wave_address),.i_wave_data(enc_wave_data),
 .o_pcm_valid(flag_pcm),.o_pcm_left(enc_pcm_left),.o_pcm_right(enc_pcm_right),
 .o_busy(flag_busy),.o_overrun(flag_overrun),.o_fault(flag_fault),.o_frame_cycles(enc_cycles),
 .o_result_valid(flag_result),.o_result_voice(enc_result_key),.o_result_data(enc_result),.o_sample_tick(),
 .o_frame_load(flag_frame_load),.o_dac_left_latch(flag_dac_latch),.o_pcm_nonzero(flag_pcm_nonzero),
 .o_bclk(HP_BCK),.o_lrclk(HP_WS),.o_sdata(HP_DIN),.o_mclk(),.o_underrun(flag_underrun));
 assign enc_flags={3'd0,cnt_test!=0,flag_initialized,flag_underrun,flag_overrun,flag_fault};
 always @(posedge i_clk or negedge flag_rstn)begin
  if(!flag_rstn)begin cnt_frames<=0;cnt_nonzero<=0;reg_key<=0;reg_raw<=0;cnt_amplifier<=0;end
  else begin
   if(flag_pcm)begin cnt_frames<=cnt_frames+1'b1;if(enc_pcm_left!=0)cnt_nonzero<=cnt_nonzero+1'b1;end
   if(flag_sample)begin reg_key<=enc_key;reg_raw<=enc_raw;end
   if(!cnt_amplifier[20])cnt_amplifier<=cnt_amplifier+1'b1;
  end
 end
 assign PA_EN=!(flag_rstn&&cnt_amplifier[20]&&!flag_fault&&!flag_overrun);
 wire [879:0] enc_latency;
 LatencySupervisor #(.C_TIMEOUT_CYCLES(C_LATENCY_TIMEOUT),.C_BUDGET_CYCLES(C_LATENCY_BUDGET)) Monitor_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_clear(flag_ascii&&enc_ascii==8'h4c),.i_initialized(flag_initialized),
 .i_sample_valid(flag_sample),.i_sample_key(enc_key),.i_candidate(flag_candidate),.i_confirm(flag_confirm),.i_cancel(flag_cancel),
 .i_physical(enc_pressed),.i_effective(enc_effective),
 .i_commit(flag_cfg_valid&&flag_cfg_ready&&flag_initialized&&enc_cfg_data[170:169]==2'd1),.i_commit_key(enc_cfg_voice),
 .i_result_valid(flag_result),.i_result_key(enc_result_key),.i_result_sample(enc_result[31:0]),
 .i_pcm_valid(flag_pcm),.i_pcm_nonzero(flag_pcm_nonzero),.i_frame_load(flag_frame_load),.i_dac_left_latch(flag_dac_latch),.o_payload(enc_latency));
 LatencySynthTelemetry #(.C_REPORT_CYCLES(C_REPORT_CYCLES),.C_BAUD_CYCLES(C_UART_CYCLES)) Status_Inst(
 .i_clk(i_clk),.i_rstn(flag_rstn),.i_frames(cnt_frames),.i_pressed(enc_pressed),.i_delivered(enc_delivered),
 .i_volume(reg_volume),.i_active_count(enc_active_count),.i_gain(enc_gain),.i_input_peak(enc_input_peak),.i_output_peak(enc_output_peak),.i_clips(enc_clips),
 .i_stages(enc_stages),.i_wave_peak(enc_wave_peak),.i_mod_peak(enc_mod_peak),.i_env_peak(enc_env_peak),
 .i_ack_seq(ack_seq),.i_ack_op(ack_op),.i_ack_status(ack_status),.i_ack_key(ack_key),.i_ack_crc(ack_crc),.i_commits(enc_commits),
 .i_nonzero(cnt_nonzero),.i_events(enc_events),.i_cycles(enc_cycles),.i_flags(enc_flags),.i_key(reg_key),.i_raw(reg_raw),.i_latency(enc_latency),.o_uart_tx(o_uart_tx));
endmodule
