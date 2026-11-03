`timescale 1ns / 1ps
// Musical event recorder / 四拍截断、事件叠录与独立回放请求源。
// Contract: ../spec/SynthSequencer_spec.md. PCM sampling never waits for this unit.
module SynthSequencer #(
    parameter C_DEBOUNCE=250000,
    parameter C_US_CYCLES=50,
    parameter C_PHASE_LIMIT=1000000,
    parameter C_PPQ=960,
    parameter C_ADDRESS_BITS=10,
    parameter C_ARCHIVE_TIMEOUT=2147483647,
    parameter C_EARLY_WINDOW=1
)(
    input i_clk,
    input i_rstn,
    input i_enabled,
    input i_silent,
    input [5:0] i_buttons,
    input i_capture,
    input [4:0] i_key,
    input [391:0] i_event,
    output [391:0] o_request,
    output o_request_valid,
    input i_request_ready,
    input [135:0] i_response,
    input i_response_valid,
    output o_response_ready,
    input i_local_request,
    input [7:0] i_opcode,
    input [7:0] i_argument,
    input [63:0] i_words,
    output o_local_valid,
    output [135:0] o_local_response,
    output [3:0] o_patch_lock,
    output o_click,
    output o_accent,
    output o_recording,
    output [8:0] o_bpm,
    output [31:0] o_status
);
    localparam C_CAPACITY=1<<C_ADDRESS_BITS;
    localparam C_EPOCH_BITS=28-C_ADDRESS_BITS;
    localparam P_WAIT=0,P_BEGIN=1,P_READ=2,P_COLLECT=3,P_CHECK=4;
    localparam P_SEND=5,P_REPLY=6,P_NEXT=7,P_CLEAN=8,P_CLEAN_SEND=9,P_CLEAN_REPLY=10;

    // Independent button filters preserve the tested hardware pin semantics.
    wire [5:0] wire_buttons;
    reg [5:0] reg_buttons_previous;
    wire [5:0] wire_press=wire_buttons & ~reg_buttons_previous;
    genvar button;
    generate for(button=0;button<6;button=button+1)begin:gen_buttons
        TactileInput #(.C_STABLE_CYCLES(C_DEBOUNCE)) Button_Inst(
            .i_clk(i_clk),.i_rstn(i_rstn),.i_switch(i_buttons[button]),
            .o_pressed(wire_buttons[button]),.o_raw(),.o_presses(),.o_releases(),.o_edges());
    end endgenerate
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_buttons_previous<=0;
        else reg_buttons_previous<=wire_buttons;
    end

    // Musical time is independent of AXI completion latency.
    reg [8:0] reg_bpm;
    reg [5:0] cnt_microsecond;
    reg [19:0] reg_phase;
    reg flag_tick;
    wire [20:0] wire_phase_sum={1'b0,reg_phase}+{8'd0,reg_bpm,4'd0};
    reg [9:0] cnt_subbeat;
    reg [1:0] reg_beat;
    reg [19:0] reg_position,reg_length,reg_cut_position;
    reg [C_EPOCH_BITS-1:0] cnt_epoch;
    reg flag_recording,flag_playing,flag_finalizing,flag_full,flag_fault;
    reg flag_click_o,flag_accent_o;
    reg [5:0] reg_finish_key;
    reg [C_ADDRESS_BITS:0] cnt_write,cnt_saved,cnt_checkpoint;
    reg [31:0] reg_record_held,reg_checkpoint_held;
    reg flag_record_started,flag_bar_has_sound;
    reg [6:0] reg_take_lead;
    wire [6:0] wire_lead;
    // 20ms * BPM * 16 ticks/s = floor(BPM*8/25). Iterative subtraction
    // costs at most98 clocks, no divider/DSP. Freeze this offset per take.
    generate if(C_EARLY_WINDOW)begin:gen_early_window
        reg [8:0] reg_lead_bpm;
        reg [11:0] reg_numerator;
        reg [6:0] cnt_quotient,reg_lead;
        reg flag_dividing;
        assign wire_lead=reg_lead;
        always @(posedge i_clk or negedge i_rstn)begin
            if(!i_rstn)begin
                reg_lead_bpm<=120;reg_numerator<=0;cnt_quotient<=0;reg_lead<=38;flag_dividing<=0;
            end else if(reg_lead_bpm!=reg_bpm)begin
                reg_lead_bpm<=reg_bpm;reg_numerator<={reg_bpm,3'd0};cnt_quotient<=0;flag_dividing<=1;
            end else if(flag_dividing)begin
                if(reg_numerator>=25)begin reg_numerator<=reg_numerator-12'd25;cnt_quotient<=cnt_quotient+1'b1;end
                else begin reg_lead<=cnt_quotient;flag_dividing<=0;end
            end
        end
    end else begin:gen_exact_window
        assign wire_lead=0;
    end endgenerate
    reg [C_ADDRESS_BITS-1:0] mem_anchor [0:31];
    reg [C_ADDRESS_BITS-1:0] mem_checkpoint_anchor [0:31];
    reg [3:0] reg_saved_slots,reg_draft_slots,reg_checkpoint_slots;
    reg flag_local_valid_o;
    reg [135:0] reg_local_response_o;
    reg [89:0] reg_entry;
    reg [3:0] reg_state,next_state;
    reg [7:0] reg_held;
    // Archive leases reuse the playback RAM port only after playback drains.
    reg [1:0] reg_archive_mode;
    reg [30:0] cnt_archive_idle;
    reg [31:0] cnt_generation;
    reg [63:0] reg_archive_low;
    reg flag_archive_low;
    reg [C_ADDRESS_BITS:0] cnt_import;
    wire [10:0] wire_import_count=cnt_import;
    reg [19:0] reg_import_latest;
    reg [3:0] reg_import_slots;
    reg [C_ADDRESS_BITS-1:0] reg_archive_address;
    reg [1:0] reg_archive_read;
    wire flag_archive_command=i_local_request && i_argument==0 && i_opcode>=8'h43 && i_opcode<=8'h48;
    wire flag_archive_begin=i_local_request && i_argument==0 && i_opcode==8'h45 && (i_words==1 || i_words==2);
    wire flag_archive_guard=reg_archive_mode!=0 || flag_archive_begin;
    wire [89:0] wire_import_entry={i_words[25:0],reg_archive_low};
    wire flag_import_write=flag_archive_command && i_opcode==8'h47 && reg_archive_mode==2 && flag_archive_low &&
        i_words[63:32]==cnt_import && cnt_import<C_CAPACITY && i_words[31:21]==0 &&
        (i_words[14] ? reg_archive_low[29:20]==cnt_import : reg_archive_low[29:20]<cnt_import);
    // 960 PPQ: 3840 ticks/bar = 4096 - 256; no DSP for file length checks.
    wire [31:0] wire_import_length;
    generate if(C_PPQ==960)begin:gen_bar_length
        assign wire_import_length={11'd0,i_words[40:32],12'd0}-{15'd0,i_words[40:32],8'd0};
    end else begin:gen_other_ppq
        assign wire_import_length=i_words[40:32]*(C_PPQ*4);
    end endgenerate
    // Monotonic button counters survive host polling gaps; holds never repeat.
    reg [15:0] cnt_save_button,cnt_previous_button,cnt_next_button;
    wire flag_import_commit=flag_archive_command && i_opcode==8'h48 && reg_archive_mode==2 &&
        i_words[15:0]==cnt_import && i_words[31:16]>=20 && i_words[31:16]<=300 &&
        i_words[63:41]==0 && wire_import_length<1048576 &&
        ((cnt_import==0 && i_words[63:32]==0) || (i_words[63:32]!=0 && reg_import_latest<wire_import_length));
    integer key_index;

    wire flag_control=i_local_request && i_opcode==8'h42 && i_argument==0;
    wire flag_control_valid=flag_control && i_words[31:3]==0 &&
        ((i_words[2:0]>=1 && i_words[2:0]<=3 && i_words[63:32]==0) ||
         (i_words[2:0]==4 && i_words[63:32]>=20 && i_words[63:32]<=300));
    wire flag_record_button=i_enabled && !i_silent && !flag_finalizing && !flag_archive_guard &&
        (wire_press[0] || (flag_control_valid && i_words[2:0]==1));
    wire flag_clear_button=!flag_archive_guard && (wire_press[1] || (flag_control_valid && i_words[2:0]==2));
    wire flag_play_button=i_enabled && !i_silent && !flag_recording && !flag_finalizing && !flag_archive_guard &&
        (wire_press[3] || (flag_control_valid && i_words[2:0]==3));
    wire flag_stop_record=flag_recording && (flag_record_button || i_silent ||
        cnt_write>=C_CAPACITY-32 || (flag_record_started && reg_position==20'hffffe));
    wire flag_bar=flag_tick && cnt_subbeat==C_PPQ-1 && reg_beat==3;
    wire flag_wrap=flag_tick && flag_playing && reg_position+1'b1>=reg_length;
    reg [11:0] dec_beat_base;
    always @(*)begin
        case(reg_beat)
            0:dec_beat_base=0;
            1:dec_beat_base=C_PPQ;
            2:dec_beat_base=C_PPQ*2;
            default:dec_beat_base=C_PPQ*3;
        endcase
    end
    wire [12:0] wire_window_sum={1'b0,dec_beat_base}+{3'd0,cnt_subbeat}+{6'd0,reg_take_lead}+flag_tick;
    wire [12:0] wire_window_phase=wire_window_sum>=C_PPQ*4 ? wire_window_sum-C_PPQ*4 : wire_window_sum;
    wire flag_window_boundary=reg_length==0 ? flag_tick && wire_window_phase==0 : flag_bar;
    wire flag_checkpoint=flag_window_boundary && (reg_length!=0 || (flag_record_started && flag_bar_has_sound));
    wire [C_ADDRESS_BITS:0] wire_stop_count=flag_checkpoint ? cnt_write : cnt_checkpoint;
    wire [19:0] wire_stop_position=flag_checkpoint ? (flag_wrap ? 20'd0 : reg_position+1'b1) : reg_cut_position;
    wire [31:0] wire_capacity=C_CAPACITY;
    wire [31:0] wire_ppq=C_PPQ;
    wire [10:0] wire_saved_count=cnt_saved;
    wire flag_note_on=i_event[327:320]==8'ha4;
    wire flag_note_off=i_event[327:320]==8'ha5;
    wire flag_capture=flag_recording && !flag_stop_record && !flag_clear_button && i_capture &&
        ((flag_note_on && !reg_record_held[i_key]) || (flag_note_off && reg_record_held[i_key]));
    wire flag_first_note=flag_capture && flag_note_on && reg_length==0 && !flag_record_started;
    wire [19:0] wire_capture_position=flag_first_note ? {7'd0,wire_window_phase} :
        (reg_length==0 && flag_tick ? reg_position+1'b1 : reg_position);
    wire flag_finish_write=flag_finalizing && !flag_clear_button && reg_finish_key<32 &&
        reg_checkpoint_held[reg_finish_key[4:0]] && reg_cut_position!=0 && reg_cut_position<reg_length;
    wire [9:0] wire_anchor=flag_note_on ? cnt_write[C_ADDRESS_BITS-1:0] : mem_anchor[i_key];
    wire [9:0] wire_finish_anchor=mem_checkpoint_anchor[reg_finish_key[4:0]];
    wire [89:0] wire_capture_entry={5'd0,i_key,(i_event[95:64]!=32'd67108864),flag_note_on,
        i_event[329:328],i_event[134:128],i_event[141:135],i_event[63:32],wire_anchor,wire_capture_position};
    wire [89:0] wire_write_entry=flag_finish_write ? {60'd0,wire_finish_anchor,reg_cut_position} : wire_capture_entry;
    wire flag_write=flag_capture || flag_finish_write;

    assign o_patch_lock=reg_archive_mode!=0 ? 4'hf : reg_saved_slots | ((flag_recording || flag_finalizing) ? reg_draft_slots : 4'd0);
    assign o_click=flag_click_o;
    assign o_accent=flag_accent_o;
    assign o_recording=flag_recording;
    assign o_bpm=reg_bpm;
    assign o_status={10'd0,wire_buttons,4'd0,o_patch_lock,1'b0,
        (flag_recording && reg_length==0 && !flag_record_started),
        (reg_archive_mode!=0),flag_fault,flag_full,flag_finalizing,flag_playing,flag_recording};
    assign o_local_valid=flag_local_valid_o;
    assign o_local_response=reg_local_response_o;

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin cnt_microsecond<=0;reg_phase<=0;flag_tick<=0;end
        else begin
            flag_tick<=0;
            if(!flag_recording && !flag_playing) begin cnt_microsecond<=0;reg_phase<=0;end
            else if(cnt_microsecond==C_US_CYCLES-1) begin
                cnt_microsecond<=0;
                if(wire_phase_sum>=C_PHASE_LIMIT) begin reg_phase<=wire_phase_sum-C_PHASE_LIMIT;flag_tick<=1;end
                else reg_phase<=wire_phase_sum[19:0];
            end else cnt_microsecond<=cnt_microsecond+1'b1;
        end
    end

    // Journal publication is atomic: incomplete bars never enter cnt_saved.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_bpm<=120;cnt_subbeat<=0;reg_beat<=0;reg_position<=0;reg_length<=0;reg_cut_position<=0;cnt_epoch<=0;
            flag_recording<=0;flag_playing<=0;flag_finalizing<=0;flag_full<=0;flag_click_o<=0;flag_accent_o<=0;
            reg_finish_key<=0;cnt_write<=0;cnt_saved<=0;cnt_checkpoint<=0;reg_record_held<=0;reg_checkpoint_held<=0;
            flag_record_started<=0;flag_bar_has_sound<=0;reg_take_lead<=0;
            reg_saved_slots<=0;reg_draft_slots<=0;reg_checkpoint_slots<=0;
            flag_local_valid_o<=0;reg_local_response_o<=0;
            reg_archive_mode<=0;cnt_archive_idle<=0;cnt_generation<=0;reg_archive_low<=0;flag_archive_low<=0;
            cnt_import<=0;reg_import_latest<=0;reg_import_slots<=0;reg_archive_address<=0;reg_archive_read<=0;
            cnt_save_button<=0;cnt_previous_button<=0;cnt_next_button<=0;
            for(key_index=0;key_index<32;key_index=key_index+1)begin mem_anchor[key_index]<=0;mem_checkpoint_anchor[key_index]<=0;end
        end else begin
            flag_click_o<=0;flag_local_valid_o<=0;
            if(flag_recording && reg_record_held!=0)flag_bar_has_sound<=1;
            if(flag_window_boundary)flag_bar_has_sound<=0;
            if(flag_capture && flag_note_on)flag_bar_has_sound<=1;
            if(!flag_archive_guard)begin
                if(flag_control_valid && i_words[2:0]==4)reg_bpm<=i_words[40:32];
            end
            if(i_enabled && !i_silent && !flag_recording && !flag_finalizing && !flag_archive_guard)begin
                if(wire_press[2] && reg_length!=0)cnt_save_button<=cnt_save_button+1'b1;
                if(wire_press[4] && !wire_press[5])cnt_previous_button<=cnt_previous_button+1'b1;
                if(wire_press[5] && !wire_press[4])cnt_next_button<=cnt_next_button+1'b1;
            end
            if(reg_archive_mode==0 || flag_archive_command)cnt_archive_idle<=0;
            else if(cnt_archive_idle==C_ARCHIVE_TIMEOUT-1)begin
                reg_archive_mode<=0;flag_archive_low<=0;cnt_import<=0;
            end else cnt_archive_idle<=cnt_archive_idle+1'b1;
            if(reg_archive_read!=0)begin
                reg_archive_read<=reg_archive_read-1'b1;
                if(reg_archive_read==1)begin
                    flag_local_valid_o<=1;
                    reg_local_response_o<={8'd0,cnt_generation,6'd0,reg_entry};
                end
            end
            if(i_local_request)begin
                flag_local_valid_o<=1;reg_local_response_o<=0;
                if(i_argument!=0)reg_local_response_o[135:128]<=5;
                else case(i_opcode)
                    8'h40:if(i_words!=0)reg_local_response_o[135:128]<=5;
                        else reg_local_response_o<={8'd0,wire_ppq,wire_capacity,32'd3,32'h53455131};
                    8'h41:if(i_words!=0)reg_local_response_o[135:128]<=5;
                        // Saved dependencies remain visible while the archive lease locks all four slots.
                        else reg_local_response_o<={8'd0,reg_saved_slots,8'd0,reg_position,12'd0,reg_length,
                            5'd0,wire_saved_count,7'd0,reg_bpm,o_status};
                    8'h42:if(!flag_control_valid)reg_local_response_o[135:128]<=5;
                        else if(flag_archive_guard)reg_local_response_o[135:128]<=10;
                        else if((flag_finalizing || !i_enabled || i_silent) && i_words[2:0]!=2 && i_words[2:0]!=4)reg_local_response_o[135:128]<=10;
                    8'h43:if(i_words!=0)reg_local_response_o[135:128]<=5;
                        else reg_local_response_o<={8'd0,32'd90,21'd0,wire_import_count,30'd0,reg_archive_mode,32'h41524331};
                    8'h44:begin
                        if(i_words[63:32]!=0 || i_words[31:0]>=cnt_saved)reg_local_response_o[135:128]<=5;
                        else if(reg_archive_mode!=1)reg_local_response_o[135:128]<=10;
                        else begin
                            reg_archive_address<=i_words[C_ADDRESS_BITS-1:0];reg_archive_read<=2;flag_local_valid_o<=0;
                        end
                    end
                    8'h45:begin
                        if(i_words==0)begin reg_archive_mode<=0;flag_archive_low<=0;cnt_import<=0;end
                        else if(i_words!=1 && i_words!=2)reg_local_response_o[135:128]<=5;
                        else if(reg_archive_mode!=0 || flag_recording || flag_playing || flag_finalizing || reg_state!=P_WAIT || reg_held!=0 || !i_enabled || i_silent)
                            reg_local_response_o[135:128]<=10;
                        else if(i_words==2 && (cnt_saved!=0 || reg_length!=0))reg_local_response_o[135:128]<=10;
                        else begin
                            reg_archive_mode<=i_words[1:0];cnt_import<=0;reg_import_latest<=0;reg_import_slots<=0;flag_archive_low<=0;
                        end
                    end
                    8'h46:if(reg_archive_mode!=2)reg_local_response_o[135:128]<=10;
                        else begin reg_archive_low<=i_words;flag_archive_low<=1;end
                    8'h47:if(!flag_import_write)reg_local_response_o[135:128]<=5;
                        else begin
                            cnt_import<=cnt_import+1'b1;flag_archive_low<=0;
                            if(reg_archive_low[19:0]>reg_import_latest)reg_import_latest<=reg_archive_low[19:0];
                            if(i_words[14])reg_import_slots[i_words[13:12]]<=1;
                        end
                    8'h48:if(!flag_import_commit)reg_local_response_o[135:128]<=5;
                        else begin
                            cnt_saved<=cnt_import;cnt_write<=cnt_import;cnt_checkpoint<=cnt_import;
                            reg_length<=wire_import_length[19:0];reg_bpm<=i_words[24:16];
                            reg_saved_slots<=reg_import_slots;reg_draft_slots<=reg_import_slots;reg_checkpoint_slots<=reg_import_slots;
                            reg_archive_mode<=0;flag_archive_low<=0;cnt_generation<=cnt_generation+1'b1;
                        end
                    8'h49:if(i_words!=0)reg_local_response_o[135:128]<=5;
                        else reg_local_response_o<={8'd0,cnt_generation,16'd0,cnt_next_button,
                            16'd0,cnt_previous_button,16'd0,cnt_save_button};
                    default:reg_local_response_o[135:128]<=5;
                endcase
            end
            if(flag_tick && (flag_recording || flag_playing))begin
                reg_position<=flag_wrap ? 20'd0 : reg_position+1'b1;
                if(flag_wrap)cnt_epoch<=cnt_epoch+1'b1;
                if(cnt_subbeat==C_PPQ-1)begin
                    cnt_subbeat<=0;reg_beat<=reg_beat+1'b1;
                    if(flag_recording)begin flag_click_o<=1;flag_accent_o<=reg_beat==3;end
                end else cnt_subbeat<=cnt_subbeat+1'b1;
                if(flag_checkpoint && flag_recording)begin
                    cnt_checkpoint<=cnt_write+(reg_length!=0 && flag_capture);reg_cut_position<=flag_wrap ? 20'd0 : reg_position+1'b1;
                    reg_checkpoint_held<=reg_record_held;reg_checkpoint_slots<=reg_draft_slots;
                    for(key_index=0;key_index<32;key_index=key_index+1)mem_checkpoint_anchor[key_index]<=mem_anchor[key_index];
                    // First-take windows are half-open: a boundary capture is
                    // in the new window. Existing overdub timing is unchanged.
                    if(flag_capture && reg_length!=0)begin
                        reg_checkpoint_held[i_key]<=flag_note_on;
                        if(flag_note_on)begin
                            mem_checkpoint_anchor[i_key]<=cnt_write[C_ADDRESS_BITS-1:0];
                            reg_checkpoint_slots[i_event[329:328]]<=1;
                        end
                    end
                end
            end
            if(flag_capture)begin
                cnt_write<=cnt_write+1'b1;reg_record_held[i_key]<=flag_note_on;
                if(flag_note_on)begin mem_anchor[i_key]<=cnt_write[C_ADDRESS_BITS-1:0];reg_draft_slots[i_event[329:328]]<=1;end
            end
            if(flag_first_note)begin
                flag_record_started<=1;reg_position<={7'd0,wire_window_phase};reg_cut_position<=0;
            end
            if(flag_record_button && !flag_recording)begin
                flag_recording<=1;flag_full<=0;cnt_write<=cnt_saved;cnt_checkpoint<=cnt_saved;
                reg_record_held<=0;reg_checkpoint_held<=0;reg_draft_slots<=reg_saved_slots;reg_checkpoint_slots<=reg_saved_slots;
                reg_cut_position<=0;
                flag_record_started<=0;flag_bar_has_sound<=0;reg_take_lead<=wire_lead;
                if(reg_length==0)begin reg_position<=0;cnt_subbeat<=0;reg_beat<=0;flag_click_o<=1;flag_accent_o<=1;end
                else if(!flag_playing)begin flag_playing<=1;reg_position<=0;cnt_subbeat<=0;reg_beat<=0;cnt_epoch<=cnt_epoch+1'b1;flag_click_o<=1;flag_accent_o<=1;end
            end
            if(flag_stop_record)begin
                flag_recording<=0;flag_click_o<=0;flag_finalizing<=1;reg_finish_key<=0;
                cnt_write<=wire_stop_count;reg_draft_slots<=flag_checkpoint ? reg_draft_slots : reg_checkpoint_slots;
                if(reg_length==0)begin reg_length<=wire_stop_position;reg_position<=0;cnt_subbeat<=0;reg_beat<=0;end
                if(cnt_write>=C_CAPACITY-32 || reg_position==20'hffffe)flag_full<=1;
            end
            if(flag_finalizing)begin
                if(reg_finish_key==32)begin
                    cnt_generation<=cnt_generation+1'b1;
                    cnt_saved<=cnt_write;reg_saved_slots<=reg_checkpoint_slots;flag_finalizing<=0;
                    if(reg_length!=0 && !flag_playing)begin flag_playing<=1;cnt_epoch<=cnt_epoch+1'b1;end
                end else begin
                    reg_finish_key<=reg_finish_key+1'b1;
                    if(flag_finish_write)cnt_write<=cnt_write+1'b1;
                end
            end
            if(flag_play_button && reg_length!=0)begin flag_playing<=!flag_playing;reg_position<=0;cnt_subbeat<=0;reg_beat<=0;cnt_epoch<=cnt_epoch+1'b1;end
            if(i_silent)flag_playing<=0;
            if(flag_clear_button)begin
                cnt_generation<=cnt_generation+1'b1;
                flag_recording<=0;flag_playing<=0;flag_finalizing<=0;flag_full<=0;flag_click_o<=0;
                reg_length<=0;reg_position<=0;reg_cut_position<=0;cnt_subbeat<=0;reg_beat<=0;cnt_epoch<=cnt_epoch+1'b1;
                cnt_write<=0;cnt_saved<=0;cnt_checkpoint<=0;reg_record_held<=0;reg_checkpoint_held<=0;
                flag_record_started<=0;flag_bar_has_sound<=0;
                reg_saved_slots<=0;reg_draft_slots<=0;reg_checkpoint_slots<=0;
            end
        end
    end

    // Five narrow true independent-address memories keep write capture off the playback bus.
    (* syn_ramstyle="block_ram" *)reg [17:0] mem_event_a [0:C_CAPACITY-1];
    (* syn_ramstyle="block_ram" *)reg [17:0] mem_event_b [0:C_CAPACITY-1];
    (* syn_ramstyle="block_ram" *)reg [17:0] mem_event_c [0:C_CAPACITY-1];
    (* syn_ramstyle="block_ram" *)reg [17:0] mem_event_d [0:C_CAPACITY-1];
    (* syn_ramstyle="block_ram" *)reg [17:0] mem_event_e [0:C_CAPACITY-1];
    reg [C_ADDRESS_BITS-1:0] reg_read_address;
    wire [C_ADDRESS_BITS-1:0] wire_memory_write_address=flag_import_write ? cnt_import[C_ADDRESS_BITS-1:0] : cnt_write[C_ADDRESS_BITS-1:0];
    wire [89:0] wire_memory_write_entry=flag_import_write ? wire_import_entry : wire_write_entry;
    wire [C_ADDRESS_BITS-1:0] wire_memory_read_address=reg_archive_mode!=0 ? reg_archive_address : reg_read_address;
    always @(posedge i_clk)begin
        if(flag_write || flag_import_write)begin
            mem_event_a[wire_memory_write_address]<=wire_memory_write_entry[17:0];
            mem_event_b[wire_memory_write_address]<=wire_memory_write_entry[35:18];
            mem_event_c[wire_memory_write_address]<=wire_memory_write_entry[53:36];
            mem_event_d[wire_memory_write_address]<=wire_memory_write_entry[71:54];
            mem_event_e[wire_memory_write_address]<=wire_memory_write_entry[89:72];
        end
        reg_entry<={mem_event_e[wire_memory_read_address],mem_event_d[wire_memory_read_address],mem_event_c[wire_memory_read_address],mem_event_b[wire_memory_read_address],mem_event_a[wire_memory_read_address]};
    end

    // Replay scans timestamp windows, so AXI stalls defer events rather than silently dropping ticks.
    reg [C_ADDRESS_BITS:0] reg_scan_index,reg_scan_count;
    reg [19:0] reg_lower,reg_upper,reg_last;
    reg [C_EPOCH_BITS-1:0] reg_play_epoch;
    reg flag_initialized,flag_first,flag_clean_wrap;
    reg [3:0] reg_clean_voice;
    reg [31:0] mem_play_identity [0:7];
    reg [391:0] reg_request;
    reg [31:0] cnt_requests;
    wire [31:0] wire_identity={4'h4,reg_play_epoch,reg_entry[20+:C_ADDRESS_BITS]};
    wire flag_due=reg_entry[19:0]<=reg_upper && (flag_first || reg_entry[19:0]>reg_lower);
    wire flag_reply_bad=i_response[135:128]!=0 || i_response[71:64]!=0;
    integer voice;
    assign o_request=reg_request;
    assign o_request_valid=reg_state==P_SEND || reg_state==P_CLEAN_SEND;
    assign o_response_ready=reg_state==P_REPLY || reg_state==P_CLEAN_REPLY;

    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)reg_state<=P_WAIT;
        else reg_state<=next_state;
    end
    always @(*)begin
        next_state=reg_state;
        case(reg_state)
            P_WAIT:if(!flag_playing || flag_fault)begin if(reg_held!=0)next_state=P_CLEAN;end
                else if(!flag_initialized || reg_play_epoch!=cnt_epoch || reg_last!=reg_position)next_state=P_BEGIN;
            P_BEGIN:next_state=cnt_saved==0 ? P_NEXT : P_READ;
            P_READ:next_state=P_COLLECT;
            P_COLLECT:next_state=P_CHECK;
            P_CHECK:next_state=flag_due ? P_SEND : P_NEXT;
            P_SEND:if(i_request_ready)next_state=P_REPLY;
            P_REPLY:if(i_response_valid)next_state=P_NEXT;
            P_NEXT:if(!flag_playing || flag_fault || reg_scan_index+1'b1>=reg_scan_count)begin
                if(flag_playing && !flag_fault && reg_play_epoch!=cnt_epoch)next_state=P_CLEAN;
                else next_state=P_WAIT;
            end else next_state=P_READ;
            P_CLEAN:if(reg_clean_voice==8)next_state=P_WAIT;
                else if(reg_held[reg_clean_voice[2:0]])next_state=P_CLEAN_SEND;
            P_CLEAN_SEND:if(i_request_ready)next_state=P_CLEAN_REPLY;
            P_CLEAN_REPLY:if(i_response_valid)next_state=P_CLEAN;
            default:next_state=P_WAIT;
        endcase
        if((!flag_playing || flag_clear_button || i_silent || (flag_play_button && flag_playing)) &&
            (reg_state==P_BEGIN || reg_state==P_READ || reg_state==P_COLLECT || reg_state==P_CHECK || reg_state==P_NEXT))next_state=P_WAIT;
    end
    always @(posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            reg_scan_index<=0;reg_scan_count<=0;reg_lower<=0;reg_upper<=0;reg_last<=0;reg_play_epoch<=0;
            flag_initialized<=0;flag_first<=1;flag_clean_wrap<=0;reg_clean_voice<=0;reg_held<=0;
            reg_request<=0;cnt_requests<=0;reg_read_address<=0;flag_fault<=0;
            for(voice=0;voice<8;voice=voice+1)mem_play_identity[voice]<=0;
        end else begin
            case(reg_state)
                P_WAIT:begin
                    reg_clean_voice<=0;
                    if(!flag_playing || flag_fault)begin flag_initialized<=0;flag_first<=1;flag_clean_wrap<=0;end
                end
                P_BEGIN:begin
                    reg_scan_index<=0;reg_scan_count<=cnt_saved;reg_lower<=reg_last;
                    if(!flag_initialized)begin reg_play_epoch<=cnt_epoch;reg_upper<=reg_position;flag_initialized<=1;flag_first<=1;end
                    else reg_upper<=reg_play_epoch!=cnt_epoch ? reg_length-1'b1 : reg_position;
                end
                P_READ:reg_read_address<=reg_scan_index[C_ADDRESS_BITS-1:0];
                P_CHECK:if(flag_due)begin
                    reg_request<=0;reg_request[391:360]<=cnt_requests;cnt_requests<=cnt_requests+1'b1;
                    reg_request[327:320]<=reg_entry[78] ? 8'ha4 : 8'ha5;
                    reg_request[31:0]<=wire_identity;
                    if(reg_entry[78])begin
                        reg_request[329:328]<=reg_entry[77:76];reg_request[63:32]<=reg_entry[61:30];
                        reg_request[95:64]<=reg_entry[79] ? ({25'd0,reg_entry[68:62]}+1'b1)<<19 : 32'd67108864;
                        reg_request[127:96]<=32'd33554432;
                        reg_request[159:128]<={1'b1,17'd0,reg_entry[68:62],reg_entry[75:69]};
                    end
                end
                P_REPLY:if(i_response_valid)begin
                    if(flag_reply_bad)flag_fault<=1;
                    else if(reg_request[327:320]==8'ha4)begin
                        mem_play_identity[i_response[2:0]]<=reg_request[31:0];reg_held[i_response[2:0]]<=1;
                    end else for(voice=0;voice<8;voice=voice+1)if(mem_play_identity[voice]==reg_request[31:0])reg_held[voice]<=0;
                end
                P_NEXT:begin
                    reg_scan_index<=reg_scan_index+1'b1;
                    if(next_state==P_WAIT || next_state==P_CLEAN)begin reg_last<=reg_upper;flag_first<=0;end
                    if(next_state==P_CLEAN)begin reg_clean_voice<=0;flag_clean_wrap<=1;end
                end
                P_CLEAN:begin
                    if(reg_clean_voice==8)begin
                        if(flag_clean_wrap && flag_playing && !flag_fault)begin reg_play_epoch<=reg_play_epoch+1'b1;flag_first<=1;reg_last<=20'hfffff;end
                        else begin flag_initialized<=0;flag_first<=1;end
                    end else if(reg_held[reg_clean_voice[2:0]])begin
                        reg_request<=0;reg_request[327:320]<=8'ha5;reg_request[31:0]<=mem_play_identity[reg_clean_voice[2:0]];
                        reg_request[391:360]<=cnt_requests;cnt_requests<=cnt_requests+1'b1;
                    end else reg_clean_voice<=reg_clean_voice+1'b1;
                end
                P_CLEAN_REPLY:if(i_response_valid)begin
                    reg_held[reg_clean_voice[2:0]]<=0;reg_clean_voice<=reg_clean_voice+1'b1;
                    if(flag_reply_bad)flag_fault<=1;
                end
                default:begin end
            endcase
            if(flag_clear_button)flag_fault<=0;
        end
    end
endmodule
