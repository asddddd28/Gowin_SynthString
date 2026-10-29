`timescale 1ns / 1ps
// VoiceBank: bounded time-multiplexed dual-oscillator polyphonic engine.
// 声部库：每帧处理一个事件，再遍历每个槽一次；独立保存两套相位。
module VoiceBank #(parameter C_VOICES=8)(
	input i_clk, input i_rstn, input i_tick, input i_panic,
    input i_table_write, input [10:0] i_table_address, input [15:0] i_table_data,
    input i_table_bank, input i_table_available,
    input i_table_frame,input i_table_two,
    input i_position_write,input [3:0] i_position_address,input [15:0] i_position_data,
    input [3:0] i_position_query,output [15:0] o_position_status,
    input i_pcm_write,input [13:0] i_pcm_address,input [15:0] i_pcm_data,
    input i_pcm_available,input [14:0] i_pcm_loop_start,input [14:0] i_pcm_loop_end,input [6:0] i_pcm_root,
    input i_profile_write,input [3:0] i_profile_address,input [287:0] i_profile_data,
	input i_event_valid, input [55:0] i_event, output o_event_ready,
	output signed [23:0] o_sample, output o_sample_valid, output o_busy,
	output o_overrun, output [7:0] o_active_voices, output [7:0] o_active_oscillators,
	output [15:0] o_max_cycles, output [31:0] o_clip_count,
	output [31:0] o_sample_count, output o_status_request
);
	localparam ST_IDLE=0, ST_SCAN=1, ST_APPLY=2, ST_BEGIN=3, ST_LOAD=4,
		ST_WAVE=5, ST_GAIN=6, ST_SUM=7, ST_ENV=8, ST_VEL=9, ST_ACC=10,
		ST_MASTER=11, ST_ROUND=12, ST_DONE=13, ST_SELECT=14, ST_MOD_ENV=15, ST_DEPTH=16, ST_DEPTH_VEL=17,
        ST_MOD_PRODUCT=18, ST_PHASE=19, ST_WAIT=20, ST_AM=21,
        ST_WAVE_ALIGN=22, ST_WAVE_PRODUCT=23, ST_PHASE_ALIGN=24,
        ST_PHASE_SELECT=25, ST_PHASE_DELTA=26, ST_PHASE_PRODUCT=27, ST_PHASE_SAMPLE=28,
        ST_PAIR_B_START=29,ST_PAIR_B_PRODUCT=30,ST_PAIR_B_SAMPLE=31,
        ST_PAIR_A_START=32,ST_PAIR_A_PRODUCT=33,ST_PAIR_A_SAMPLE=34;
	localparam C_MIX_SHIFT=(C_VOICES==1) ? 5 : ((C_VOICES==8) ? 2 : 0);
	reg [5:0] state_current, state_next;
	reg [5:0] cnt_voice, cnt_scan;
	reg [31:0] reg_phase_a [0:C_VOICES-1];
	reg [31:0] reg_phase_b [0:C_VOICES-1];
	reg [31:0] reg_increment_a [0:C_VOICES-1];
	reg [31:0] reg_increment_b [0:C_VOICES-1];
	reg [17:0] reg_level [0:C_VOICES-1];
	reg [13:0] reg_level_fraction [0:C_VOICES-1]; // 每个声部独立保留包络的分数余量
	reg [2:0] reg_stage [0:C_VOICES-1];
	reg [7:0] reg_id [0:C_VOICES-1];
	reg [6:0] reg_note [0:C_VOICES-1];
	reg [6:0] reg_velocity [0:C_VOICES-1];
	reg [31:0] reg_age [0:C_VOICES-1];
	reg flag_pending [0:C_VOICES-1];
	reg [7:0] reg_pending_id [0:C_VOICES-1];
	reg [6:0] reg_pending_note [0:C_VOICES-1];
	reg [6:0] reg_pending_velocity [0:C_VOICES-1];
	reg [31:0] reg_pending_increment [0:C_VOICES-1];
	reg [31:0] reg_phase_table [0:127];
	reg [31:0] reg_event_increment;
	reg [55:0] reg_event;
	reg flag_event;
	reg [5:0] enc_match, enc_free, enc_release, enc_oldest;
	reg flag_match, flag_free, flag_release;
	reg [17:0] reg_quietest;
	reg [31:0] reg_oldest_age;
	reg [5:0] enc_target;
	reg [17:0] reg_attack, reg_decay, reg_sustain, reg_release;
	reg [17:0] reg_gain_a, reg_gain_b, reg_master_target, reg_master;
	reg [2:0] reg_wave_a, reg_wave_b;
	reg signed [15:0] reg_detune;
	reg [5:0] reg_limit;
	reg flag_tone;
	reg [31:0] reg_tone_phase;
	reg [31:0] reg_read_phase_a, reg_read_phase_b;
	reg [17:0] reg_read_level;
	reg [13:0] reg_read_fraction, reg_next_fraction;
	reg [2:0] reg_read_stage;
	reg [6:0] reg_read_velocity;
	wire [31:0] wire_next_level;
	wire [2:0] wire_next_stage;
	reg [17:0] enc_next_level;
	reg [2:0] enc_next_stage;
	wire signed [17:0] wire_wave_a, wire_wave_b;
	reg signed [36:0] reg_product_a, reg_product_b;
	reg signed [18:0] reg_osc_sum;
	reg signed [37:0] reg_env_product;
	reg signed [27:0] reg_velocity_product;
	reg signed [39:0] reg_accumulator;
	wire signed [39:0] enc_mix_scaled;
	reg signed [24:0] reg_normalized;
	reg signed [43:0] reg_master_product;
	reg signed [44:0] reg_rounded;
	reg signed [23:0] reg_sample_o;
	reg flag_valid_o, flag_overrun_o, flag_status_o;
	reg [7:0] cnt_active,cnt_osc,reg_active_o,reg_oscillators_o;
	reg [15:0] cnt_cycles, reg_max_cycles_o;
	reg [31:0] reg_clips_o, reg_samples_o;
    reg [287:0] reg_event_profile,reg_read_profile;
    reg [287:0] reg_profiles [0:15];
    reg [15:0] flag_profiles;
    reg [287:0] reg_active_profile [0:C_VOICES-1];
    reg [287:0] reg_pending_profile [0:C_VOICES-1];
    reg [15:0] reg_positions [0:15];
    reg [15:0] reg_event_position,reg_read_position,reg_position_status;
    reg [15:0] reg_active_position [0:C_VOICES-1];
    reg [15:0] reg_pending_position [0:C_VOICES-1];
    integer idx_position;
    integer idx_active_position;
    assign o_position_status=reg_position_status;
    // 位置控制独立于十八字旧profile；复位为前帧，读回比查询请求晚一拍。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_event_position<=0;reg_position_status<=0;
            for(idx_position=0;idx_position<16;idx_position=idx_position+1) reg_positions[idx_position]<=0;
        end else begin
            if(i_position_write) reg_positions[i_position_address]<=i_position_data;
            reg_event_position<=reg_positions[reg_event[43:40]];
            reg_position_status<=reg_positions[i_position_query];
        end
    end
    wire flag_install_event=(state_current==ST_APPLY)&&flag_event&&(reg_event[55:48]==1)&&
        (reg_event[31:24]!=0)&&(reg_event[39:32]<128)&&(reg_event[31:24]<128)&&
        ((reg_stage[enc_target]==0)||(reg_id[enc_target]==reg_event[47:40]&&!flag_pending[enc_target]));
    wire flag_install_pending=(state_current==ST_ACC)&&(cnt_voice<reg_limit)&&(enc_next_stage==0)&&flag_pending[cnt_voice];
    wire [5:0] profile_write_address=flag_install_event ? enc_target : cnt_voice;
    wire [287:0] profile_write_data=flag_install_event ? reg_event_profile : reg_pending_profile[cnt_voice];
    always @(posedge i_clk) begin
        if(i_rstn&&!i_panic&&(flag_install_event||flag_install_pending)) begin
            reg_active_profile[profile_write_address]<=profile_write_data;
        end
    end
    // 少量位置元数据使用可复位寄存器，避免占用为音频缓存预留的块RAM。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            for(idx_active_position=0;idx_active_position<C_VOICES;idx_active_position=idx_active_position+1) reg_active_position[idx_active_position]<=0;
        end else if(!i_panic&&(flag_install_event||flag_install_pending)) begin
            reg_active_position[profile_write_address]<=flag_install_event ? reg_event_position : reg_pending_position[cnt_voice];
        end
    end
    reg flag_perkey [0:C_VOICES-1];
    reg flag_pending_perkey [0:C_VOICES-1];
    reg [31:0] reg_pending_mod_increment [0:C_VOICES-1];
    reg [17:0] reg_mod_level [0:C_VOICES-1];
    reg [13:0] reg_mod_fraction [0:C_VOICES-1];
    reg [2:0] reg_mod_stage [0:C_VOICES-1];
    reg flag_event_perkey,flag_read_perkey;
    reg [47:0] reg_ratio_product;
    reg [31:0] reg_event_mod_increment;
    reg [17:0] reg_read_mod_level,reg_next_mod_level;
    reg [13:0] reg_read_mod_fraction,reg_next_mod_fraction;
    reg [2:0] reg_read_mod_stage,reg_next_mod_stage;
    wire [31:0] wire_next_mod_level;
    wire [2:0] wire_next_mod_stage;
    reg [33:0] reg_depth_product;
    reg [26:0] reg_depth_velocity;
    reg [8:0] reg_velocity_factor;
    reg [15:0] reg_sensitivity_product;
    reg [17:0] reg_effective_depth;
    reg signed [36:0] reg_mod_product,reg_am_product;
    reg signed [17:0] reg_am_gain;
    wire [2:0] wire_mode=flag_read_perkey ? reg_read_profile[2:0] : 3'd0;
    wire [17:0] wire_gain_a=flag_read_perkey ? {reg_read_profile[271:256],2'b00} : reg_gain_a;
    wire [17:0] wire_gain_b=flag_read_perkey ? {reg_read_profile[223:208],2'b00} : reg_gain_b;
    // One write / one read PCM RAM; read neighbouring points in separate cycles.
    reg signed [15:0] reg_pcm_memory [0:16383];
    reg signed [15:0] reg_pcm_read,reg_pcm_first,reg_pcm_second;
    reg signed [33:0] reg_pcm_product;
    reg signed [17:0] reg_pcm_interpolated;
    reg [31:0] reg_pcm_table [0:255];
    reg [31:0] reg_pcm_event_increment,reg_pcm_next;
    wire [7:0] pcm_note_index={1'b0,reg_event[38:32]}+8'd128-{1'b0,i_pcm_root};
    wire [14:0] pcm_next_index={1'b0,reg_read_phase_a[29:16]}+15'd1;
    wire [13:0] pcm_second_address=(pcm_next_index>=i_pcm_loop_end) ? i_pcm_loop_start[13:0] : pcm_next_index[13:0];
    wire [13:0] pcm_read_address=(state_current==ST_MOD_ENV) ? pcm_second_address : reg_read_phase_a[29:16];
    wire signed [16:0] pcm_difference=$signed({reg_pcm_second[15],reg_pcm_second})-$signed({reg_pcm_first[15],reg_pcm_first});
    wire signed [17:0] pcm_audio=i_pcm_available ? (reg_pcm_interpolated<<<2) : 18'sd0;
    wire [31:0] selected_event_increment=(flag_event_perkey&&reg_event_profile[2:0]==4) ? reg_pcm_event_increment : reg_event_increment;
    initial $readmemh("rtl/synth/pcm_phase.hex",reg_pcm_table);
    always @(posedge i_clk) begin
        if(i_pcm_write) reg_pcm_memory[i_pcm_address]<=i_pcm_data;
        reg_pcm_read<=reg_pcm_memory[pcm_read_address];
        reg_pcm_event_increment<=reg_pcm_table[pcm_note_index];
    end
    always @(posedge i_clk) begin
        if(i_profile_write) reg_profiles[i_profile_address]<=i_profile_data;
        reg_event_profile<=reg_profiles[reg_event[43:40]];
        reg_ratio_product<=reg_event_increment*reg_event_profile[63:48];
        if(reg_event_profile[255:240]!=0)
            reg_event_mod_increment<=reg_event_profile[255:240]*32'd2796;
        else if(reg_ratio_product[47:8]>40'h0040000000) reg_event_mod_increment<=32'h40000000;
        else reg_event_mod_increment<=reg_ratio_product[39:8]+{{16{reg_event_profile[287]}},reg_event_profile[287:272]};
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin flag_profiles<=0;flag_event_perkey<=0;end
        else begin
            if(i_profile_write) flag_profiles[i_profile_address]<=1;
            flag_event_perkey<=flag_profiles[reg_event[43:40]]&&(reg_event[47:45]==3'b001);
        end
    end
	integer idx_reset;
	assign o_event_ready=(state_current==ST_IDLE)&&i_tick&&!i_panic;
	assign o_sample=reg_sample_o; assign o_sample_valid=flag_valid_o;
	assign o_busy=(state_current!=ST_IDLE); assign o_overrun=flag_overrun_o;
	assign o_active_voices=reg_active_o; assign o_active_oscillators=reg_oscillators_o;
	assign o_max_cycles=reg_max_cycles_o; assign o_clip_count=reg_clips_o;
	assign o_sample_count=reg_samples_o; assign o_status_request=flag_status_o;
	assign enc_mix_scaled=flag_tone ? (reg_accumulator<<<5) : (reg_accumulator<<<C_MIX_SHIFT);
	initial begin $readmemh("rtl/synth/phase.hex",reg_phase_table); end
	// 同步音符表读取在分配扫描期间完成，避免进入相位更新关键路径。
	always @(posedge i_clk) begin reg_event_increment<=reg_phase_table[reg_event[38:32]]; end
	WavetablePairRom WaveA_Inst(.i_table_frame(i_table_frame),.i_table_two(i_table_two),.i_frame_fraction(flag_read_perkey ? reg_read_position : 16'd0),.i_rstn(i_rstn),.i_table_write(i_table_write),.i_table_address(i_table_address),.i_table_data(i_table_data),
            .i_table_bank(i_table_bank),.i_table_available(i_table_available),.i_clk(i_clk),.i_phase(reg_read_phase_a),.i_wave(flag_tone ? 3'd0 : (flag_read_perkey ? reg_read_profile[18:16] : reg_wave_a)),.o_sample(wire_wave_a));
	WavetablePairRom WaveB_Inst(.i_table_frame(i_table_frame),.i_table_two(i_table_two),.i_frame_fraction(flag_read_perkey ? reg_read_position : 16'd0),.i_rstn(i_rstn),.i_table_write(i_table_write),.i_table_address(i_table_address),.i_table_data(i_table_data),
            .i_table_bank(i_table_bank),.i_table_available(i_table_available),.i_clk(i_clk),.i_phase(reg_read_phase_b),.i_wave(flag_read_perkey ? reg_read_profile[34:32] : reg_wave_b),.o_sample(wire_wave_b));
	EnvelopePrecision Envelope_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_precise(flag_read_perkey&&reg_read_profile[15]),
        .i_stage(reg_read_stage),.i_level({reg_read_level,reg_read_fraction}),
		.i_attack(flag_read_perkey ? {2'd0,reg_read_profile[95:80]} : reg_attack),
        .i_decay(flag_read_perkey ? {2'd0,reg_read_profile[111:96]} : reg_decay),
        .i_sustain(flag_read_perkey ? {reg_read_profile[127:112],2'd0} : reg_sustain),
        .i_release(flag_read_perkey ? {2'd0,reg_read_profile[143:128]} : reg_release),
		.o_stage(wire_next_stage),.o_level(wire_next_level));
    EnvelopePrecision ModEnvelope_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_precise(flag_read_perkey&&reg_read_profile[15]),
        .i_stage(reg_read_mod_stage),.i_level({reg_read_mod_level,reg_read_mod_fraction}),
        .i_attack({2'd0,reg_read_profile[159:144]}),.i_decay({2'd0,reg_read_profile[175:160]}),
        .i_sustain({reg_read_profile[191:176],2'd0}),.i_release({2'd0,reg_read_profile[207:192]}),
        .o_stage(wire_next_mod_stage),.o_level(wire_next_mod_level));
	// 分配优先级在完整扫描结束后使用；同 id 始终先于空闲槽。
	always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin enc_target<=0; enc_next_level<=0; enc_next_stage<=0;reg_next_mod_level<=0;reg_next_mod_stage<=0;
            reg_next_fraction<=0;reg_next_mod_fraction<=0;end
        else begin
            if(state_current==ST_SELECT) begin
                if(flag_match) enc_target<=enc_match;
                else if(flag_free) enc_target<=enc_free;
                else if(flag_release) enc_target<=enc_release;
                else enc_target<=enc_oldest;
            end
            // Envelope inputs have been stable since LOAD; register before ENV/ACC.
            if(state_current==ST_MOD_ENV) begin
                enc_next_level<=wire_next_level[31:14]; enc_next_stage<=wire_next_stage;
                reg_next_fraction<=wire_next_level[13:0];
                reg_next_mod_level<=wire_next_mod_level[31:14];reg_next_mod_stage<=wire_next_mod_stage;
                reg_next_mod_fraction<=wire_next_mod_level[13:0];
            end
        end
    end
	always @(*) begin
		state_next=state_current;
		case(state_current)
			ST_IDLE: begin if(i_tick) begin state_next=ST_SCAN; end end
			ST_SCAN: begin if(cnt_scan==C_VOICES-1) begin state_next=ST_SELECT; end end
            ST_SELECT: begin state_next=ST_APPLY; end
			ST_APPLY: begin state_next=ST_BEGIN; end
			ST_BEGIN: begin state_next=ST_LOAD; end
			ST_LOAD: begin state_next=ST_WAVE; end
			ST_WAVE: begin state_next=ST_MOD_ENV; end
            ST_MOD_ENV: begin state_next=ST_DEPTH; end
            ST_DEPTH: begin state_next=ST_DEPTH_VEL; end
            ST_DEPTH_VEL: begin state_next=ST_WAVE_ALIGN; end
            // 六拍波表读出先完成，再用 B 路样值计算调制深度。
            ST_WAVE_ALIGN: begin state_next=ST_WAVE_PRODUCT; end
            ST_WAVE_PRODUCT: begin state_next=ST_PAIR_B_START; end
            ST_PAIR_B_START: begin state_next=ST_PAIR_B_PRODUCT; end
            ST_PAIR_B_PRODUCT: begin state_next=ST_PAIR_B_SAMPLE; end
            ST_PAIR_B_SAMPLE: begin state_next=ST_MOD_PRODUCT; end
            ST_MOD_PRODUCT: begin state_next=ST_PHASE; end
            ST_PHASE: begin state_next=ST_WAIT; end
            // FM 改变 A 相位后重新等待完整查表与插值流水，不复用旧相位样值。
            ST_WAIT: begin state_next=ST_PHASE_ALIGN; end
            ST_PHASE_ALIGN: begin state_next=ST_PHASE_SELECT; end
            ST_PHASE_SELECT: begin state_next=ST_PHASE_DELTA; end
            ST_PHASE_DELTA: begin state_next=ST_PHASE_PRODUCT; end
            ST_PHASE_PRODUCT: begin state_next=ST_PHASE_SAMPLE; end
            ST_PHASE_SAMPLE: begin state_next=ST_PAIR_A_START; end
            ST_PAIR_A_START: begin state_next=ST_PAIR_A_PRODUCT; end
            ST_PAIR_A_PRODUCT: begin state_next=ST_PAIR_A_SAMPLE; end
            ST_PAIR_A_SAMPLE: begin state_next=ST_GAIN; end
			ST_GAIN: begin state_next=ST_SUM; end
			ST_SUM: begin state_next=ST_AM; end
            ST_AM: begin state_next=ST_ENV; end
			ST_ENV: begin state_next=ST_VEL; end
			ST_VEL: begin state_next=ST_ACC; end
			ST_ACC: begin if(cnt_voice==C_VOICES-1) begin state_next=ST_MASTER; end else begin state_next=ST_LOAD; end end
			ST_MASTER: begin state_next=ST_ROUND; end
			ST_ROUND: begin state_next=ST_DONE; end
			ST_DONE: begin state_next=ST_IDLE; end
			default: begin state_next=ST_IDLE; end
		endcase
	end
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin state_current<=ST_IDLE; end
		else if(i_panic) begin state_current<=ST_IDLE; end
		else begin state_current<=state_next; end
	end
	// 参数只在 APPLY 更新，后续整帧计算期间不再变化，形成帧边界快照。
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin
			reg_attack<=273; reg_decay<=27; reg_sustain<=196608; reg_release<=27;
			reg_gain_a<=262143; reg_gain_b<=0; reg_master_target<=65536; reg_master<=0;
			reg_wave_a<=0; reg_wave_b<=0; reg_detune<=0; reg_limit<=C_VOICES; flag_tone<=0;
		end else begin
			if(state_current==ST_APPLY && flag_event && reg_event[55:48]==3) begin
				case(reg_event[47:40])
					0: begin reg_master_target<={reg_event[23:8],2'b00}; end
					1: begin reg_attack<={2'b00,reg_event[23:8]}; end
					2: begin reg_decay<={2'b00,reg_event[23:8]}; end
					3: begin reg_sustain<={reg_event[23:8],2'b00}; end
					4: begin reg_release<={2'b00,reg_event[23:8]}; end
					5: begin reg_wave_a<=reg_event[10:8]; end
					6: begin reg_wave_b<=reg_event[10:8]; end
					7: begin reg_gain_a<={reg_event[23:8],2'b00}; end
					8: begin reg_gain_b<={reg_event[23:8],2'b00}; end
					9: begin reg_detune<=reg_event[23:8]; end
					10: begin
						if(reg_event[23:8]<1) begin reg_limit<=1; end
						else if(reg_event[23:8]>C_VOICES) begin reg_limit<=C_VOICES; end
						else begin reg_limit<=reg_event[13:8]; end
					end
					11: begin flag_tone<=reg_event[8]; end
					default: begin end
				endcase
			end
			if(state_current==ST_BEGIN) begin
				if(reg_master<reg_master_target) begin
					if(reg_master_target-reg_master<=256) begin reg_master<=reg_master_target; end
					else begin reg_master<=reg_master+18'd256; end
				end else if(reg_master>reg_master_target) begin
					if(reg_master-reg_master_target<=256) begin reg_master<=reg_master_target; end
					else begin reg_master<=reg_master-18'd256; end
				end
			end
			if(i_panic) begin flag_tone<=0; end
		end
	end
	// 状态槽只有本过程写入，避免多驱动；空闲槽也每帧经过调度一次。
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin
			for(idx_reset=0;idx_reset<C_VOICES;idx_reset=idx_reset+1) begin
				reg_phase_a[idx_reset]<=0; reg_phase_b[idx_reset]<=0;
                flag_perkey[idx_reset]<=0;flag_pending_perkey[idx_reset]<=0;
                reg_pending_position[idx_reset]<=0;
                reg_pending_mod_increment[idx_reset]<=0;
                reg_mod_level[idx_reset]<=0;reg_mod_stage[idx_reset]<=0;
                reg_level_fraction[idx_reset]<=0;reg_mod_fraction[idx_reset]<=0;
				reg_increment_a[idx_reset]<=0; reg_increment_b[idx_reset]<=0;
				reg_level[idx_reset]<=0; reg_stage[idx_reset]<=0; reg_id[idx_reset]<=0;
				reg_note[idx_reset]<=0; reg_velocity[idx_reset]<=0; reg_age[idx_reset]<=0;
				flag_pending[idx_reset]<=0; reg_pending_id[idx_reset]<=0;
				reg_pending_note[idx_reset]<=0; reg_pending_velocity[idx_reset]<=0;
				reg_pending_increment[idx_reset]<=0;
			end
		end else if(i_panic) begin
			for(idx_reset=0;idx_reset<C_VOICES;idx_reset=idx_reset+1) begin
				reg_stage[idx_reset]<=0; reg_level[idx_reset]<=0; flag_pending[idx_reset]<=0;
                reg_mod_stage[idx_reset]<=0;reg_mod_level[idx_reset]<=0;
                reg_level_fraction[idx_reset]<=0;reg_mod_fraction[idx_reset]<=0;
			end
		end else begin
			if(state_current==ST_APPLY && flag_event) begin
				if(reg_event[55:48]==1 && reg_event[31:24]!=0 && reg_event[39:32]<128 && reg_event[31:24]<128) begin
					if((reg_stage[enc_target]==0) || (reg_id[enc_target]==reg_event[47:40] && !flag_pending[enc_target])) begin
						reg_id[enc_target]<=reg_event[47:40]; reg_note[enc_target]<=reg_event[38:32];
						reg_velocity[enc_target]<=reg_event[30:24]; reg_increment_a[enc_target]<=selected_event_increment;
						reg_increment_b[enc_target]<=flag_event_perkey ? reg_event_mod_increment : reg_event_increment+{{16{reg_detune[15]}},reg_detune};
                        flag_perkey[enc_target]<=flag_event_perkey;
                        reg_mod_level[enc_target]<=0;reg_mod_stage[enc_target]<=1;reg_mod_fraction[enc_target]<=0;
						reg_phase_a[enc_target]<=0; reg_phase_b[enc_target]<=0; reg_stage[enc_target]<=1;
						reg_age[enc_target]<=0; flag_pending[enc_target]<=0;
					end else begin
						reg_stage[enc_target]<=5; flag_pending[enc_target]<=1;
						reg_pending_id[enc_target]<=reg_event[47:40]; reg_pending_note[enc_target]<=reg_event[38:32];
						reg_pending_velocity[enc_target]<=reg_event[30:24]; reg_pending_increment[enc_target]<=selected_event_increment;
                        reg_pending_profile[enc_target]<=reg_event_profile;flag_pending_perkey[enc_target]<=flag_event_perkey;
                        reg_pending_position[enc_target]<=reg_event_position;
                        reg_pending_mod_increment[enc_target]<=reg_event_mod_increment;reg_mod_stage[enc_target]<=5;
					end
				end else if(reg_event[55:48]==2 || (reg_event[55:48]==1 && reg_event[31:24]==0)) begin
					if(flag_match) begin
						if(flag_pending[enc_match] && reg_pending_id[enc_match]==reg_event[47:40]) begin flag_pending[enc_match]<=0; end
						else if(reg_stage[enc_match]!=5) begin reg_stage[enc_match]<=4;reg_mod_stage[enc_match]<=4; end
					end
				end
			end
			if(state_current==ST_ACC) begin
				if(cnt_voice>=reg_limit) begin
					reg_stage[cnt_voice]<=0; reg_level[cnt_voice]<=0; flag_pending[cnt_voice]<=0;
                    reg_mod_stage[cnt_voice]<=0;reg_mod_level[cnt_voice]<=0;
                    reg_level_fraction[cnt_voice]<=0;reg_mod_fraction[cnt_voice]<=0;
				end else if(enc_next_stage==0 && flag_pending[cnt_voice]) begin
					reg_id[cnt_voice]<=reg_pending_id[cnt_voice]; reg_note[cnt_voice]<=reg_pending_note[cnt_voice];
					reg_velocity[cnt_voice]<=reg_pending_velocity[cnt_voice];
					reg_increment_a[cnt_voice]<=reg_pending_increment[cnt_voice];
					reg_increment_b[cnt_voice]<=flag_pending_perkey[cnt_voice] ? reg_pending_mod_increment[cnt_voice] : reg_pending_increment[cnt_voice]+{{16{reg_detune[15]}},reg_detune};
                    flag_perkey[cnt_voice]<=flag_pending_perkey[cnt_voice];
                    reg_mod_stage[cnt_voice]<=1;reg_mod_level[cnt_voice]<=0;
                    reg_level_fraction[cnt_voice]<=0;reg_mod_fraction[cnt_voice]<=0;
					reg_phase_a[cnt_voice]<=0; reg_phase_b[cnt_voice]<=0;
					reg_stage[cnt_voice]<=1; reg_level[cnt_voice]<=0; reg_age[cnt_voice]<=0; flag_pending[cnt_voice]<=0;
				end else begin
					reg_stage[cnt_voice]<=enc_next_stage; reg_level[cnt_voice]<=enc_next_level;
                    reg_level_fraction[cnt_voice]<=reg_next_fraction;
                    reg_mod_stage[cnt_voice]<=reg_next_mod_stage;reg_mod_level[cnt_voice]<=reg_next_mod_level;
                    reg_mod_fraction[cnt_voice]<=reg_next_mod_fraction;
					if(reg_stage[cnt_voice]!=0) begin
						if(flag_perkey[cnt_voice]&&reg_read_profile[15:0]==4) reg_phase_a[cnt_voice]<=reg_pcm_next;
                        else reg_phase_a[cnt_voice]<=reg_phase_a[cnt_voice]+reg_increment_a[cnt_voice];
						reg_phase_b[cnt_voice]<=reg_phase_b[cnt_voice]+reg_increment_b[cnt_voice];
						if(!flag_perkey[cnt_voice]) reg_increment_b[cnt_voice]<=reg_increment_a[cnt_voice]+{{16{reg_detune[15]}},reg_detune};
						if(reg_age[cnt_voice]!=32'hffffffff) begin reg_age[cnt_voice]<=reg_age[cnt_voice]+1'b1; end
					end
				end
			end
		end
	end
	// 计算流水：查表 -> A/B 增益 -> 求和 -> 包络 -> 力度 -> 宽累加。
	always @(posedge i_clk or negedge i_rstn) begin
		if(!i_rstn) begin
			cnt_voice<=0; cnt_scan<=0; reg_event<=0; flag_event<=0;
			enc_match<=0;enc_free<=0;enc_release<=0;enc_oldest<=0;
			flag_match<=0;flag_free<=0;flag_release<=0;reg_quietest<=18'h3ffff;reg_oldest_age<=0;
			reg_read_phase_a<=0;reg_read_phase_b<=0;
            reg_read_profile<=0;reg_read_position<=0;flag_read_perkey<=0;reg_read_mod_level<=0;reg_read_mod_stage<=0;
            reg_read_fraction<=0;reg_read_mod_fraction<=0;
            reg_pcm_first<=0;reg_pcm_second<=0;reg_pcm_product<=0;reg_pcm_interpolated<=0;reg_pcm_next<=0;
            reg_depth_product<=0;reg_depth_velocity<=0;reg_sensitivity_product<=0;reg_velocity_factor<=128;reg_effective_depth<=0;
            reg_mod_product<=0;reg_am_product<=0;reg_am_gain<=65536;reg_read_level<=0;reg_read_stage<=0;reg_read_velocity<=0;
			reg_product_a<=0;reg_product_b<=0;reg_osc_sum<=0;reg_env_product<=0;reg_velocity_product<=0;
			reg_accumulator<=0;reg_normalized<=0;reg_master_product<=0;reg_rounded<=0;
			reg_sample_o<=0;flag_valid_o<=0;flag_overrun_o<=0;flag_status_o<=0;
			cnt_active<=0;cnt_osc<=0;reg_active_o<=0;reg_oscillators_o<=0;cnt_cycles<=0;reg_max_cycles_o<=0;
			reg_clips_o<=0;reg_samples_o<=0;reg_tone_phase<=0;
		end else if(i_panic) begin
			flag_valid_o<=1;reg_sample_o<=0;reg_active_o<=0;reg_oscillators_o<=0;cnt_cycles<=0;flag_status_o<=0;
		end else begin
			flag_valid_o<=0;flag_status_o<=0;
			if(i_tick && state_current!=ST_IDLE) begin flag_overrun_o<=1; end
			if(state_current!=ST_IDLE) begin cnt_cycles<=cnt_cycles+1'b1; end
			case(state_current)
				ST_IDLE: begin
					if(i_tick) begin
						reg_event<=i_event;flag_event<=i_event_valid;cnt_scan<=0;cnt_cycles<=0;
						flag_match<=0;flag_free<=0;flag_release<=0;reg_quietest<=18'h3ffff;
						reg_oldest_age<=0;enc_oldest<=0;
					end
				end
				ST_SCAN: begin
					if(cnt_scan<reg_limit) begin
						if((reg_stage[cnt_scan]!=0 && reg_id[cnt_scan]==reg_event[47:40]) || (flag_pending[cnt_scan] && reg_pending_id[cnt_scan]==reg_event[47:40])) begin
							flag_match<=1;enc_match<=cnt_scan;
						end
						if(reg_stage[cnt_scan]==0 && !flag_pending[cnt_scan] && !flag_free) begin flag_free<=1;enc_free<=cnt_scan; end
						if(reg_stage[cnt_scan]==4 && (!flag_release || reg_level[cnt_scan]<reg_quietest)) begin
							flag_release<=1;enc_release<=cnt_scan;reg_quietest<=reg_level[cnt_scan];
						end
						if(reg_age[cnt_scan]>reg_oldest_age) begin reg_oldest_age<=reg_age[cnt_scan];enc_oldest<=cnt_scan; end
					end
					cnt_scan<=cnt_scan+1'b1;
				end
				ST_APPLY: begin if(flag_event && reg_event[55:48]==5) begin flag_status_o<=1; end end
				ST_BEGIN: begin cnt_voice<=0;reg_accumulator<=0;cnt_active<=0;cnt_osc<=0;reg_tone_phase<=reg_tone_phase+32'd44739243; end
				ST_LOAD: begin
					reg_read_phase_a<=flag_tone ? reg_tone_phase : reg_phase_a[cnt_voice];reg_read_phase_b<=reg_phase_b[cnt_voice];
					reg_read_level<=reg_level[cnt_voice];reg_read_stage<=reg_stage[cnt_voice];reg_read_velocity<=reg_velocity[cnt_voice];
                    reg_read_fraction<=reg_level_fraction[cnt_voice];
                    reg_read_profile<=reg_active_profile[cnt_voice];flag_read_perkey<=flag_perkey[cnt_voice];
                    reg_read_position<=reg_active_position[cnt_voice];
                    reg_read_mod_level<=reg_mod_level[cnt_voice];reg_read_mod_stage<=reg_mod_stage[cnt_voice];
                    reg_read_mod_fraction<=reg_mod_fraction[cnt_voice];
				end
                ST_WAVE: begin reg_sensitivity_product<=reg_read_velocity*reg_read_profile[230:224];
                    reg_pcm_next<=reg_read_phase_a+reg_increment_a[cnt_voice];end
                ST_MOD_ENV: begin
                    reg_pcm_first<=reg_pcm_read;
                    if(reg_pcm_next>={1'b0,i_pcm_loop_end,16'd0})
                        reg_pcm_next<=reg_pcm_next-({1'b0,i_pcm_loop_end,16'd0}-{1'b0,i_pcm_loop_start,16'd0});
                    reg_velocity_factor<=9'd128-{2'd0,reg_read_profile[230:224]}+
                        (reg_sensitivity_product>>7);
                end
                ST_DEPTH: begin reg_pcm_second<=reg_pcm_read;reg_depth_product<=reg_read_profile[79:64]*reg_next_mod_level;end
                ST_DEPTH_VEL: begin reg_pcm_product<=pcm_difference*$signed({1'b0,reg_read_phase_a[15:0]});reg_depth_velocity<=(reg_depth_product>>14)*reg_velocity_factor;end
                ST_MOD_PRODUCT: begin
                    reg_pcm_interpolated<=$signed(reg_pcm_first)+(reg_pcm_product>>>16);
                    reg_effective_depth<=reg_depth_velocity[24:7];
                    reg_mod_product<=wire_wave_b*$signed({1'b0,reg_depth_velocity[24:7]});
                end
                ST_PHASE: begin
                    if(wire_mode==1) reg_read_phase_a<=reg_read_phase_a+(reg_mod_product>>>1);
                    if(wire_mode==2) reg_am_gain<=18'sd65536-$signed({1'b0,reg_effective_depth[17:1]})+(reg_mod_product>>>18);
                    else reg_am_gain<=18'sd65536-$signed(reg_effective_depth)+(reg_mod_product>>>17);
                end
				ST_GAIN: begin
					reg_product_a<=((wire_mode==4) ? pcm_audio : wire_wave_a)*$signed({1'b0,wire_gain_a});
					reg_product_b<=wire_wave_b*$signed({1'b0,wire_gain_b});
				end
				ST_SUM: begin
                    if(wire_mode==0) reg_osc_sum<=$signed(reg_product_a[36:18])+$signed(reg_product_b[36:18]);
                    else reg_osc_sum<=$signed(reg_product_a[36:18]);
                    reg_am_product<=$signed(reg_product_a[36:18])*reg_am_gain;
                end
                ST_AM: begin if(wire_mode==2||wire_mode==3) reg_osc_sum<=reg_am_product>>>16;end
				ST_ENV: begin reg_env_product<=reg_osc_sum*$signed({1'b0,enc_next_level}); end
				ST_VEL: begin reg_velocity_product<=($signed(reg_env_product)>>>18)*$signed({1'b0,reg_read_velocity}); end
				ST_ACC: begin
					if(flag_tone) begin
						if(cnt_voice==0) begin reg_accumulator<=$signed(wire_wave_a); end
					end else if(cnt_voice<reg_limit) begin reg_accumulator<=reg_accumulator+($signed(reg_velocity_product)>>>7); end
					if(enc_next_stage!=0 && cnt_voice<reg_limit) begin cnt_active<=cnt_active+1'b1;cnt_osc<=cnt_osc+((wire_mode==4) ? 1 : (wire_mode!=0) ? 2 : ((wire_gain_a!=0)+{1'b0,(wire_gain_b!=0)}));end
					cnt_voice<=cnt_voice+1'b1;
				end
				ST_MASTER: begin
					reg_normalized<=enc_mix_scaled[24:0];
				end
				ST_ROUND: begin reg_master_product<=reg_normalized*$signed({1'b0,reg_master}); end
				ST_DONE: begin
					// 先在组合式扩展位宽内四舍五入，再由下一空闲周期提交。
					if(reg_master_product<0) begin reg_rounded<=-((-$signed({reg_master_product[43],reg_master_product})+45'sd131072)>>>18); end
					else begin reg_rounded<=($signed({reg_master_product[43],reg_master_product})+45'sd131072)>>>18; end
					reg_active_o<=cnt_active;
					reg_oscillators_o<=cnt_osc;
					if(cnt_cycles>reg_max_cycles_o) begin reg_max_cycles_o<=cnt_cycles; end
					reg_samples_o<=reg_samples_o+1'b1;
				end
				default: begin end
			endcase
			// 延迟一拍提交舍入值，确保播放缓冲从不看到半更新样本。
			if(state_current==ST_IDLE && cnt_cycles!=0) begin
				flag_valid_o<=1;cnt_cycles<=0;
				if(reg_rounded>8388607) begin reg_sample_o<=24'sh7fffff;reg_clips_o<=reg_clips_o+1'b1; end
				else if(reg_rounded< -8388608) begin reg_sample_o<=24'sh800000;reg_clips_o<=reg_clips_o+1'b1; end
				else begin reg_sample_o<=reg_rounded[23:0]; end
			end
		end
	end
endmodule
