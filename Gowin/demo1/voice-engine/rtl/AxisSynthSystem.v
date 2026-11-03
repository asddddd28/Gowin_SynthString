`timescale 1ns / 1ps
// Three execution domains with an independent, fixed-rate stereo effects queue.
// Contract: spec/AxisSynthSystem_spec.md. Private streams are internal AXI-MM adapters.
module AxisSynthSystem #(
	parameter LEGACY_ENABLE=1,
	parameter C_TOUCH_ENABLE=0,parameter C_FX_ENABLE=1,
	parameter C_DELAY_ADDR_BITS=15
)(
	    input [17:0] i_touch_gain,input [31:0] i_touch_pitch,input [19:0] i_touch_cutoff,input i_touch_cutoff_active,
input i_axis_aclk,
	input i_axis_arstn,
	input [383:0] i_s_axis_tdata,
	input [31:0] i_s_axis_tuser,
	input [7:0] i_s_axis_tdest,
	input i_s_axis_tlast,
	input i_s_axis_tvalid,
	output o_s_axis_tready,
	output [127:0] o_m_axis_tdata,
	output [31:0] o_m_axis_tuser,
	output [7:0] o_m_axis_tdest,
	output o_m_axis_tlast,
	output o_m_axis_tvalid,
	input i_m_axis_tready,
	output [31:0] o_count_executed,
	output [31:0] o_count_replayed,
	output [31:0] o_count_rejected,
	output [31:0] o_count_bound,
	output o_pcm_valid,
	input i_pcm_ready,
	output [63:0] o_pcm_data,
	output [31:0] o_pcm_frame,
	output [31:0] o_overruns,
	output [31:0] o_pcm_dropped,
	output [31:0] o_render_cycles,
	output [7:0] o_active,
	output [31:0] o_fx_frames,
	output [31:0] o_fx_clipped,
	output [31:0] o_fx_dropped,
	output [31:0] o_fx_cycles
);
	reg flag_drain;
	reg [1:0] reg_priority;
	wire flag_voice_select = !flag_drain && i_s_axis_tlast &&
		((i_s_axis_tdest >= 8'ha0 && i_s_axis_tdest <= 8'ha9) || (i_s_axis_tdest >= 8'hb0 && i_s_axis_tdest <= 8'hb3));
	wire flag_effects_select = C_FX_ENABLE && !flag_drain && i_s_axis_tlast && i_s_axis_tdest>=8'hc0 && i_s_axis_tdest<=8'hc4;
    wire flag_filter_select = !flag_drain && i_s_axis_tlast && (i_s_axis_tdest==8'hd0 || i_s_axis_tdest==8'hd1);
    wire flag_fx_select = flag_effects_select || flag_filter_select;
    wire flag_effects_ready,flag_effects_valid,flag_filter_ready,flag_filter_valid;
    wire [127:0] wire_effects_result,wire_filter_result;
    wire [31:0] wire_effects_tag,wire_filter_tag;
    wire [7:0] wire_effects_opcode,wire_filter_opcode;
    wire flag_pre_pcm,flag_filter_audio_ready;
    wire [63:0] wire_pre_pcm;
    wire [31:0] wire_pre_frame;
	wire flag_fx_ready, flag_fx_valid;
	wire [127:0] wire_fx_result;
	wire [31:0] wire_fx_tag;
	wire [7:0] wire_fx_opcode;
	wire flag_legacy_ready, flag_voice_ready, flag_legacy_valid, flag_voice_valid;
	wire [127:0] wire_legacy_result, wire_voice_result;
	wire [31:0] wire_legacy_tag, wire_voice_tag;
	wire [7:0] wire_legacy_opcode, wire_voice_opcode;
	wire flag_legacy_last;
	reg [167:0] reg_completion;
	reg flag_completion;
	reg [167:0] reg_completion_spare; // 输出暂停时额外保存一个已接受的完成包
	reg flag_completion_spare; // 备用槽有效必然意味着输出槽有效
	wire flag_advance = !flag_completion_spare; // 接收只看本地容量，切断远端READY的组合传播
	wire flag_completion_pop = flag_completion && i_m_axis_tready; // 出队严格遵守输出握手
	reg flag_take_voice, flag_take_legacy, flag_take_fx;
	wire flag_completion_push = flag_advance && (flag_take_voice || flag_take_legacy || flag_take_fx);
	wire [167:0] wire_completion_selected = flag_take_voice ? {wire_voice_opcode,wire_voice_tag,wire_voice_result} :
		(flag_take_legacy ? {wire_legacy_opcode,wire_legacy_tag,wire_legacy_result} : {wire_fx_opcode,wire_fx_tag,wire_fx_result});
	reg [9:0] cnt_sample_clock;
	wire flag_tick = cnt_sample_clock == 10'd1023;
	wire flag_pcm;
	wire [63:0] wire_pcm;
	wire [31:0] wire_frame;
	wire flag_voice_pcm;
	wire [63:0] wire_voice_pcm;
	wire [31:0] wire_voice_frame;
	reg [95:0] mem_fx_input [0:1];
	reg reg_fx_write, reg_fx_read;
	reg [1:0] cnt_fx_input;
	reg [31:0] cnt_fx_dropped;
	wire flag_fx_audio_ready;
	wire flag_fx_pop=C_FX_ENABLE && cnt_fx_input!=0 && flag_fx_audio_ready;
	wire flag_fx_push=C_FX_ENABLE && flag_voice_pcm && (cnt_fx_input<2 || flag_fx_pop);
	reg [95:0] mem_pcm [0:3];
	reg [1:0] reg_write_pointer, reg_read_pointer;
	reg [2:0] cnt_pcm;
	reg [31:0] cnt_dropped;
	wire flag_pop = cnt_pcm != 0 && i_pcm_ready;
	wire flag_push = flag_pcm && (cnt_pcm < 4 || flag_pop);
	assign o_s_axis_tready = flag_voice_select ? flag_voice_ready : flag_fx_select ? flag_fx_ready : flag_legacy_ready;
	assign o_m_axis_tdata = reg_completion[127:0];
	assign o_m_axis_tuser = reg_completion[159:128];
	assign o_m_axis_tdest = reg_completion[167:160];
	assign o_m_axis_tvalid = flag_completion;
	assign o_m_axis_tlast = 1'b1;
	assign o_pcm_valid = cnt_pcm != 0;
	assign o_pcm_data = mem_pcm[reg_read_pointer][63:0];
	assign o_pcm_frame = mem_pcm[reg_read_pointer][95:64];
	assign o_pcm_dropped = cnt_dropped;
	assign o_fx_dropped = C_FX_ENABLE ? cnt_fx_dropped : 32'd0;

	// Fair completion selection; priority advances only when the local queue accepts.
	always @(*) begin
		flag_take_legacy=0;
		flag_take_voice=0;
		flag_take_fx=0;
		case (reg_priority)
			0: if (flag_legacy_valid) flag_take_legacy=1;
				else if (flag_voice_valid) flag_take_voice=1;
				else if (flag_fx_valid) flag_take_fx=1;
			1: if (flag_voice_valid) flag_take_voice=1;
				else if (flag_fx_valid) flag_take_fx=1;
				else if (flag_legacy_valid) flag_take_legacy=1;
			default: if (flag_fx_valid) flag_take_fx=1;
				else if (flag_legacy_valid) flag_take_legacy=1;
				else if (flag_voice_valid) flag_take_voice=1;
		endcase
	end

	always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
		if (!i_axis_arstn) begin
			flag_drain<=0; reg_priority<=0; reg_completion<=0; flag_completion<=0;
			reg_completion_spare<=0; flag_completion_spare<=0;
			cnt_sample_clock<=0; reg_write_pointer<=0; reg_read_pointer<=0; cnt_pcm<=0; cnt_dropped<=0;
			reg_fx_write<=0; reg_fx_read<=0; cnt_fx_input<=0; cnt_fx_dropped<=0;
		end else begin
			cnt_sample_clock<=cnt_sample_clock+1'b1;
			if (i_s_axis_tvalid && o_s_axis_tready) flag_drain<=!i_s_axis_tlast;
			if (flag_completion_push) begin
				if (flag_take_voice) reg_priority<=2;
				else if (flag_take_legacy) reg_priority<=1;
				else reg_priority<=0;
			end
			// 满队列即使本拍出队也不前视接收；下一拍恢复，避免READY组合旁路。
			case ({flag_completion_push,flag_completion_pop})
				2'b10: begin
					if (flag_completion) begin
						reg_completion_spare<=wire_completion_selected; flag_completion_spare<=1;
					end else begin
						reg_completion<=wire_completion_selected; flag_completion<=1;
					end
				end
				2'b01: begin
					if (flag_completion_spare) reg_completion<=reg_completion_spare;
					flag_completion<=flag_completion_spare; flag_completion_spare<=0;
				end
				2'b11: begin
					// 只含输出槽时允许同时消费和补入，维持每拍一个完成包。
					reg_completion<=wire_completion_selected; flag_completion<=1;
				end
				default: begin end
			endcase
			case({flag_push,flag_pop})
				2'b10: cnt_pcm<=cnt_pcm+1'b1;
				2'b01: cnt_pcm<=cnt_pcm-1'b1;
				default: cnt_pcm<=cnt_pcm;
			endcase
			if (flag_pop) reg_read_pointer<=reg_read_pointer+1'b1;
			if (flag_push) reg_write_pointer<=reg_write_pointer+1'b1;
			if ((flag_pcm && !flag_push) || (flag_pre_pcm && !flag_filter_audio_ready)) cnt_dropped<=cnt_dropped+1'b1;
			case ({flag_fx_push,flag_fx_pop})
				2'b10: cnt_fx_input<=cnt_fx_input+1'b1;
				2'b01: cnt_fx_input<=cnt_fx_input-1'b1;
				default: cnt_fx_input<=cnt_fx_input;
			endcase
			if (flag_fx_push) reg_fx_write<=!reg_fx_write;
			if (flag_fx_pop) reg_fx_read<=!reg_fx_read;
			if (C_FX_ENABLE && flag_voice_pcm && !flag_fx_push) cnt_fx_dropped<=cnt_fx_dropped+1'b1;
		end
	end
	always @(posedge i_axis_aclk) begin
		if (flag_push) mem_pcm[reg_write_pointer]<={wire_frame,wire_pcm};
		if (flag_fx_push) mem_fx_input[reg_fx_write]<={wire_voice_frame,wire_voice_pcm};
	end
	generate if (LEGACY_ENABLE) begin: LegacyDomain
	AxisVoiceRuntime Legacy_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),
		.i_s_axis_tuser(i_s_axis_tuser),.i_s_axis_tdest(i_s_axis_tdest),.i_s_axis_tlast(i_s_axis_tlast),
		.i_s_axis_tvalid(i_s_axis_tvalid && !flag_voice_select && !flag_fx_select),.o_s_axis_tready(flag_legacy_ready),
		.o_m_axis_tdata(wire_legacy_result),.o_m_axis_tuser(wire_legacy_tag),.o_m_axis_tdest(wire_legacy_opcode),
		.o_m_axis_tlast(flag_legacy_last),.o_m_axis_tvalid(flag_legacy_valid),.i_m_axis_tready(flag_advance && flag_take_legacy),
		.o_count_executed(o_count_executed),.o_count_replayed(o_count_replayed),.o_count_rejected(o_count_rejected),.o_count_bound(o_count_bound)
	);
	end else begin: UnsupportedDomain
		reg flag_valid;
		reg [31:0] reg_tag;
		reg [7:0] reg_opcode;
		reg [31:0] cnt_rejected;
		assign flag_legacy_ready=!flag_valid || (flag_advance && flag_take_legacy);
		assign flag_legacy_valid=flag_valid;
		assign wire_legacy_result=128'h00000000000000010000000000000000;
		assign wire_legacy_tag=reg_tag;
		assign wire_legacy_opcode=reg_opcode;
		assign flag_legacy_last=1'b1;
		assign o_count_executed=0;
		assign o_count_replayed=0;
		assign o_count_rejected=cnt_rejected;
		assign o_count_bound=0;
		always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
			if (!i_axis_arstn) begin
				flag_valid<=0;
				reg_tag<=0;
				reg_opcode<=0;
				cnt_rejected<=0;
			end else begin
				if (flag_advance && flag_take_legacy) flag_valid<=0;
				if (i_s_axis_tvalid && !flag_voice_select && !flag_fx_select && flag_legacy_ready && i_s_axis_tlast) begin
					flag_valid<=1;
					reg_tag<=i_s_axis_tuser;
					reg_opcode<=i_s_axis_tdest;
					cnt_rejected<=cnt_rejected+1'b1;
				end
			end
		end
	end endgenerate
	VoiceSynthEngine #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE)) Voice_Inst(
        .i_touch_gain(i_touch_gain),.i_touch_pitch(i_touch_pitch),
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),
		.i_s_axis_tuser(i_s_axis_tuser),.i_s_axis_tdest(i_s_axis_tdest),
		.i_s_axis_tvalid(i_s_axis_tvalid && flag_voice_select),.o_s_axis_tready(flag_voice_ready),
		.o_m_axis_tdata(wire_voice_result),.o_m_axis_tuser(wire_voice_tag),.o_m_axis_tdest(wire_voice_opcode),
		.o_m_axis_tvalid(flag_voice_valid),.i_m_axis_tready(flag_advance && flag_take_voice),
		.i_sample_tick(flag_tick),.o_pcm_valid(flag_voice_pcm),.o_pcm_data(wire_voice_pcm),.o_frame(wire_voice_frame),
		.o_overruns(o_overruns),.o_render_cycles(o_render_cycles),.o_active(o_active)
	);
	generate if (C_FX_ENABLE) begin: FxDomain
	AxisFxEngine #(.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS)) Fx_Inst(
		.i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),.i_s_axis_tdata(i_s_axis_tdata),
		.i_s_axis_tuser(i_s_axis_tuser),.i_s_axis_tdest(i_s_axis_tdest),
		.i_s_axis_tvalid(i_s_axis_tvalid && flag_effects_select),.o_s_axis_tready(flag_effects_ready),
		.o_m_axis_tdata(wire_effects_result),.o_m_axis_tuser(wire_effects_tag),.o_m_axis_tdest(wire_effects_opcode),
		.o_m_axis_tvalid(flag_effects_valid),.i_m_axis_tready(flag_advance && flag_take_fx && !flag_filter_valid),
		.i_audio_data(mem_fx_input[reg_fx_read][63:0]),.i_audio_frame(mem_fx_input[reg_fx_read][95:64]),
		.i_audio_valid(cnt_fx_input!=0),.o_audio_ready(flag_fx_audio_ready),
		.o_audio_data(wire_pre_pcm),.o_audio_frame(wire_pre_frame),.o_audio_valid(flag_pre_pcm),.i_audio_ready(1'b1),
		.o_frames(o_fx_frames),.o_clipped_frames(o_fx_clipped),.o_cycles(o_fx_cycles)
	);
	end else begin: DryDomain
		// FX命令不被此域选中，由既有unsupported路径回复；干声保留原PCM队列语义。
		assign flag_effects_ready=1'b0;
		assign flag_effects_valid=1'b0;
		assign wire_effects_result=128'd0;
		assign wire_effects_tag=32'd0;
		assign wire_effects_opcode=8'd0;
		assign flag_fx_audio_ready=1'b0;
		assign flag_pre_pcm=flag_voice_pcm;
		assign wire_pre_pcm=wire_voice_pcm;
		assign wire_pre_frame=wire_voice_frame;
		assign o_fx_frames=32'd0;
		assign o_fx_clipped=32'd0;
		assign o_fx_cycles=32'd0;
	end endgenerate
    assign flag_fx_ready=flag_filter_select ? flag_filter_ready : flag_effects_ready;
    assign flag_fx_valid=flag_filter_valid || flag_effects_valid;
    assign wire_fx_result=flag_filter_valid ? wire_filter_result : wire_effects_result;
    assign wire_fx_tag=flag_filter_valid ? wire_filter_tag : wire_effects_tag;
    assign wire_fx_opcode=flag_filter_valid ? wire_filter_opcode : wire_effects_opcode;
    AxisMasterLowpass #(.C_TOUCH_ENABLE(C_TOUCH_ENABLE)) Filter_Inst(
        .i_touch_cutoff(i_touch_cutoff),.i_touch_cutoff_active(i_touch_cutoff_active),
        .i_clk(i_axis_aclk),.i_rstn(i_axis_arstn),.i_command(i_s_axis_tdata),.i_tag(i_s_axis_tuser),.i_opcode(i_s_axis_tdest),
        .i_command_valid(i_s_axis_tvalid && flag_filter_select),.o_command_ready(flag_filter_ready),
        .o_result(wire_filter_result),.o_tag(wire_filter_tag),.o_opcode(wire_filter_opcode),.o_result_valid(flag_filter_valid),
        .i_result_ready(flag_advance && flag_take_fx),
        .i_audio(wire_pre_pcm),.i_frame(wire_pre_frame),.i_audio_valid(flag_pre_pcm),.o_audio_ready(flag_filter_audio_ready),
        .o_audio(wire_pcm),.o_frame(wire_frame),.o_audio_valid(flag_pcm),.i_audio_ready(1'b1)
    );
endmodule
