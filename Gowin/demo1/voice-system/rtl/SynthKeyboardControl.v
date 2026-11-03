`timescale 1ns / 1ps
// Keyboard calibration/velocity frontend / 键盘校准与力度采集。
// Contract: keyboard/CONTRACT.md and spec/SynthKeyboardControl_spec.md.
module SynthKeyboardControl #(parameter C_MS_CYCLES=50000,parameter C_US_CYCLES=50,parameter C_TIMEOUT_MS=5000)(
    input i_clk,input i_rstn,
    input [4:0] i_key,input [11:0] i_raw,input i_valid,
    output [31:0] o_pressed,output o_calibrating,output o_velocity_enabled,
    input [4:0] i_velocity_key,output [6:0] o_velocity,
    input i_request,input [7:0] i_opcode,input [7:0] i_argument,input [63:0] i_words,
    output o_response_valid,output [135:0] o_response
);
    localparam IDLE=0,EXECUTE=1,READ_WAIT=2,READ_COLLECT=3,CURVE_WRITE=4,RESPOND=5;
    reg [2:0] reg_state,next_state;
    reg [3:0] reg_sample_stage;
    (* syn_ramstyle="block_ram" *) reg [24:0] mem_threshold [0:63];
    (* syn_ramstyle="block_ram" *) reg [11:0] mem_raw [0:31];
    (* syn_ramstyle="block_ram" *) reg [31:0] mem_start [0:31];
    (* syn_ramstyle="block_ram" *) reg [6:0] mem_velocity [0:31];
    (* syn_ramstyle="block_ram" *) reg [6:0] mem_curve [0:255];
    reg [31:0] reg_pressed,reg_qualified,reg_tracking,reg_armed;
    reg [31:0] cnt_us,cnt_scans,reg_start,reg_elapsed,reg_revision,reg_sample_time;
    reg [31:0] reg_start_estimated;
    reg flag_measure_estimated,flag_last_estimated;
    reg [31:0] reg_measure_interval,reg_last_interval;
    reg [5:0] cnt_microsecond;
    reg [15:0] cnt_divider,cnt_watchdog;
    reg flag_bank,flag_velocity;
    reg [1:0] reg_mode;
    reg [4:0] reg_key,reg_last_key;
    reg [11:0] reg_raw,reg_host_raw;
    reg [24:0] reg_threshold,reg_host_threshold;
    reg flag_press_crossed,flag_release_crossed;
    reg [6:0] reg_curve_address,reg_curve_value,reg_velocity_o,reg_last_velocity;
    reg [31:0] reg_travel,reg_last_travel;
    reg [7:0] reg_opcode,reg_argument;
    reg [63:0] reg_words;
    reg [2:0] reg_lane;
    reg [31:0] reg_written;
    reg [15:0] reg_curve_written;
    reg [135:0] reg_response;
    wire flag_tick=cnt_divider==C_MS_CYCLES-1;
    wire flag_expired=reg_mode!=0 && cnt_watchdog==C_TIMEOUT_MS-1 && flag_tick;
    wire flag_commit=reg_state==EXECUTE && reg_opcode==8'h24 && reg_mode!=0 && &reg_written && &reg_curve_written && reg_words[31:1]==0;
    wire flag_crossing_done,flag_release_estimated,flag_press_estimated;
    wire [31:0] wire_release_time,wire_press_time,wire_interval;
    KeyboardCrossingTime Crossing_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_start(reg_sample_stage==2),.i_key(reg_key),.i_raw(reg_raw),.i_time(reg_sample_time),
        .i_release(reg_threshold[23:12]),.i_press(reg_threshold[11:0]),.i_falling(reg_threshold[24]),
        .o_done(flag_crossing_done),.o_release_time(wire_release_time),.o_press_time(wire_press_time),.o_interval(wire_interval),
        .o_release_estimated(flag_release_estimated),.o_press_estimated(flag_press_estimated));
    integer index;
    initial begin
        $readmemh("rom/keyboard_threshold_banks.hex",mem_threshold);
        for(index=0;index<32;index=index+1) begin mem_raw[index]=0;mem_start[index]=0;mem_velocity[index]=100;end
        for(index=0;index<256;index=index+1) mem_curve[index]=127;
    end
    assign o_pressed=reg_pressed;
    assign o_calibrating=reg_mode==1;
    assign o_velocity_enabled=flag_velocity;
    assign o_velocity=reg_velocity_o;
    assign o_response=reg_response;
    assign o_response_valid=reg_state==RESPOND;
    // Independent read ports keep note dispatch and UART observations off the ADC path.
    always @(posedge i_clk) begin
        if(i_valid) mem_raw[i_key]<=i_raw;
        reg_host_raw<=mem_raw[{reg_argument[1:0],reg_lane}];
        reg_host_threshold<=mem_threshold[{flag_bank,reg_argument[4:0]}];
        reg_velocity_o<=mem_velocity[i_velocity_key];
        if(reg_sample_stage==1) begin
            reg_threshold<=mem_threshold[{flag_bank,reg_key}];
            reg_start<=mem_start[reg_key];
        end
        reg_curve_value<=mem_curve[{flag_bank,reg_curve_address}];
        if(reg_sample_stage==4 && reg_mode==0 && !reg_pressed[reg_key] && reg_armed[reg_key] && !flag_release_crossed && !reg_tracking[reg_key])
            mem_start[reg_key]<=wire_release_time;
        if(reg_sample_stage==8) mem_velocity[reg_key]<=reg_curve_value;
        if(reg_state==EXECUTE && reg_opcode==8'h23 && reg_mode!=0 && reg_argument<32 && reg_words[63:25]==0)
            mem_threshold[{!flag_bank,reg_argument[4:0]}]<=reg_words[24:0];
        if(reg_state==CURVE_WRITE) mem_curve[{!flag_bank,reg_argument[3:0],reg_lane}]<=reg_words[reg_lane*8+:7];
    end
    // Interpolation is bounded to fewer than96 core clocks per conversion.
    // It improves the estimate inside a scan interval, not the physical scan cadence.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_sample_stage<=0;reg_pressed<=0;reg_qualified<=0;reg_tracking<=0;reg_armed<=0;reg_start_estimated<=0;
            reg_key<=0;reg_raw<=0;reg_sample_time<=0;flag_press_crossed<=0;flag_release_crossed<=0;
            reg_elapsed<=0;reg_curve_address<=0;reg_travel<=0;
            reg_last_key<=0;reg_last_velocity<=100;reg_last_travel<=0;
            flag_measure_estimated<=0;flag_last_estimated<=0;reg_measure_interval<=0;reg_last_interval<=0;
        end else begin
            case(reg_sample_stage)
                0: if(i_valid) begin reg_key<=i_key;reg_raw<=i_raw;reg_sample_time<=cnt_us;reg_sample_stage<=1;end
                1: reg_sample_stage<=2;
                2: begin
                    flag_press_crossed<=reg_threshold[24] ? reg_raw<=reg_threshold[11:0] : reg_raw>=reg_threshold[11:0];
                    flag_release_crossed<=reg_threshold[24] ? reg_raw>=reg_threshold[23:12] : reg_raw<=reg_threshold[23:12];
                    reg_sample_stage<=3;
                end
                3: if(flag_crossing_done) begin
                    reg_elapsed<=wire_press_time-(reg_tracking[reg_key] ? reg_start : wire_release_time);
                    flag_measure_estimated<=flag_press_estimated && (reg_tracking[reg_key] ? reg_start_estimated[reg_key] : flag_release_estimated);
                    reg_measure_interval<=wire_interval;reg_sample_stage<=4;
                end
                4: begin
                    reg_sample_stage<=0;
                    if(reg_pressed[reg_key]) begin
                        if(flag_release_crossed) begin
                            if(reg_qualified[reg_key]) begin reg_pressed[reg_key]<=0;reg_qualified[reg_key]<=0;reg_tracking[reg_key]<=0;end
                            else reg_qualified[reg_key]<=1;
                        end else reg_qualified[reg_key]<=0;
                    end else if(flag_release_crossed) begin
                        reg_armed[reg_key]<=1;reg_tracking[reg_key]<=0;reg_qualified[reg_key]<=0;
                    end else if(reg_armed[reg_key]) begin
                        reg_tracking[reg_key]<=1;
                        if(!reg_tracking[reg_key]) reg_start_estimated[reg_key]<=flag_release_estimated;
                        if(flag_press_crossed) begin
                            if(reg_qualified[reg_key]) begin reg_pressed[reg_key]<=1;reg_qualified[reg_key]<=0;end
                            else begin
                                reg_qualified[reg_key]<=1;reg_sample_stage<=5;reg_travel<=reg_elapsed;
                            end
                        end else reg_qualified[reg_key]<=0;
                    end
                end
                5: begin
                    //32 fine bins, then16 bins/octave. Slow tail saturates to minimum velocity.
                    if(reg_travel<4096) reg_curve_address<=reg_travel[13:7];
                    else if(reg_travel<8192) reg_curve_address<={3'd2,reg_travel[11:8]};
                    else if(reg_travel<16384) reg_curve_address<={3'd3,reg_travel[12:9]};
                    else if(reg_travel<32768) reg_curve_address<={3'd4,reg_travel[13:10]};
                    else if(reg_travel<65536) reg_curve_address<={3'd5,reg_travel[14:11]};
                    else if(reg_travel<131072) reg_curve_address<={3'd6,reg_travel[15:12]};
                    else if(reg_travel<262144) reg_curve_address<={3'd7,reg_travel[16:13]};
                    else reg_curve_address<=127;
                    reg_sample_stage<=6;
                end
                6: reg_sample_stage<=7;
                7: reg_sample_stage<=8;
                8: begin
                    reg_last_key<=reg_key;reg_last_velocity<=reg_curve_value;reg_last_travel<=reg_travel;
                    flag_last_estimated<=flag_measure_estimated;reg_last_interval<=reg_measure_interval;reg_sample_stage<=0;
                end
                default: reg_sample_stage<=0;
            endcase
            if(reg_mode!=0 || flag_commit || flag_expired) begin
                reg_pressed<=0;reg_qualified<=0;reg_tracking<=0;reg_armed<=0;reg_start_estimated<=0;
            end
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_divider<=0;cnt_us<=0;cnt_microsecond<=0;cnt_scans<=0;cnt_watchdog<=0;end
        else begin
            if(flag_tick) cnt_divider<=0;
            else cnt_divider<=cnt_divider+1'b1;
            if(cnt_microsecond==C_US_CYCLES-1) begin cnt_microsecond<=0;cnt_us<=cnt_us+1'b1;end
            else cnt_microsecond<=cnt_microsecond+1'b1;
            if(i_valid && i_key==31) cnt_scans<=cnt_scans+1'b1;
            if(i_request || reg_mode==0) cnt_watchdog<=0;
            else if(flag_tick) cnt_watchdog<=cnt_watchdog+1'b1;
        end
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_state<=IDLE;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case(reg_state)
            IDLE: if(i_request) next_state=EXECUTE;
            EXECUTE: begin
                next_state=RESPOND;
                if((reg_opcode==8'h21 && reg_argument<4) || (reg_opcode==8'h26 && reg_argument<32)) next_state=READ_WAIT;
                if(reg_opcode==8'h27 && reg_mode!=0 && reg_argument<16 && (reg_words & 64'h8080808080808080)==0) next_state=CURVE_WRITE;
            end
            READ_WAIT: next_state=READ_COLLECT;
            READ_COLLECT: if(reg_opcode==8'h26 || reg_lane==7) next_state=RESPOND;else next_state=READ_WAIT;
            CURVE_WRITE: if(reg_lane==7) next_state=RESPOND;
            RESPOND: next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_opcode<=0;reg_argument<=0;reg_words<=0;reg_lane<=0;reg_response<=0;
            flag_bank<=0;flag_velocity<=0;reg_mode<=0;reg_written<=0;reg_curve_written<=0;reg_revision<=0;
        end else begin
            case(reg_state)
                IDLE: if(i_request) begin reg_opcode<=i_opcode;reg_argument<=i_argument;reg_words<=i_words;reg_response<=0;reg_lane<=0;end
                EXECUTE: case(reg_opcode)
                    8'h20: begin
                        reg_response[31:0]<=32'h4b424432;reg_response[63:32]<=reg_revision;
                        reg_response[95:64]<={reg_last_travel[15:0],2'd0,reg_mode==1,flag_velocity,reg_last_velocity,reg_last_key};
                        reg_response[127:96]<=cnt_scans;
                    end
                    8'h28: begin
                        reg_response[31:0]<=reg_last_travel;reg_response[63:32]<=reg_last_interval;
                        reg_response[95:64]<={19'd0,flag_last_estimated,reg_last_velocity,reg_last_key};reg_response[127:96]<=1;
                    end
                    8'h21: if(reg_argument>=4) reg_response[135:128]<=1;
                    8'h22: begin
                        if(reg_argument>2) reg_response[135:128]<=1;
                        else begin reg_mode<=reg_argument[1:0];reg_written<=0;reg_curve_written<=0;end
                    end
                    8'h23: begin
                        if(reg_mode==0) reg_response[135:128]<=10;
                        else if(reg_argument>=32 || reg_words[63:25]!=0) reg_response[135:128]<=1;
                        else reg_written[reg_argument[4:0]]<=1;
                    end
                    8'h24: begin
                        if(flag_commit) begin flag_bank<=!flag_bank;flag_velocity<=reg_words[0];reg_revision<=reg_words[63:32];reg_mode<=0;end
                        else reg_response[135:128]<=10;
                    end
                    8'h25: begin reg_response[31:0]<={30'd0,reg_mode};reg_response[63:32]<=reg_revision;reg_response[95:64]<=reg_written;reg_response[127:96]<={16'd0,reg_curve_written};end
                    8'h26: if(reg_argument>=32) reg_response[135:128]<=1;
                    8'h27: begin
                        if(reg_mode==0) reg_response[135:128]<=10;
                        else if(reg_argument>=16 || (reg_words & 64'h8080808080808080)!=0) reg_response[135:128]<=1;
                        else reg_curve_written[reg_argument[3:0]]<=1;
                    end
                    default: reg_response[135:128]<=1;
                endcase
                READ_COLLECT: begin
                    if(reg_opcode==8'h26) reg_response[31:0]<={7'd0,reg_host_threshold};
                    else reg_response[reg_lane*16+:16]<={4'd0,reg_host_raw};
                    reg_lane<=reg_lane+1'b1;
                end
                CURVE_WRITE: reg_lane<=reg_lane+1'b1;
                default: begin end
            endcase
            if(flag_expired) begin reg_mode<=0;reg_written<=0;reg_curve_written<=0;end
        end
    end
endmodule
