`timescale 1ns / 1ps
// ChordKeys: debounced eight-note chord and four-wave selection events.
// 板上 KEY1 控制八音和弦，KEY2 按下切换波形；事件等待握手，松开不漏发。
module ChordKeys #(parameter C_DEBOUNCE=960)(
    input i_clk, input i_rstn, input i_tick,
    input i_chord_n, input i_wave_n, input i_ready,
    output o_valid, output [55:0] o_event, output [1:0] o_wave
);
    localparam ST_IDLE=0, ST_CHORD=1, ST_WAVE=2;
    reg [1:0] state_current;
    reg [2:0] cnt_note;
    reg flag_pressed;
    reg [1:0] reg_wave;
    reg [7:0] enc_note;
    wire flag_chord, flag_wave;
    wire [55:0] wire_chord_event, wire_wave_event;
    wire flag_idle;
    assign flag_idle=(state_current==ST_IDLE);
    ButtonNote #(.C_DEBOUNCE(C_DEBOUNCE)) Chord_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_tick(i_tick),.i_key_n(i_chord_n),
        .i_ready(flag_idle),.o_valid(flag_chord),.o_event(wire_chord_event));
    ButtonNote #(.C_DEBOUNCE(C_DEBOUNCE)) Wave_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_tick(i_tick),.i_key_n(i_wave_n),
        .i_ready(flag_idle&&!flag_chord),.o_valid(flag_wave),.o_event(wire_wave_event));
    // C3/E3/G3/C4/E4/G4/C5/E5，独立 ID 0..7，保留混音余量。
    always @(*) begin
        case(cnt_note)
            0: enc_note=48;
            1: enc_note=52;
            2: enc_note=55;
            3: enc_note=60;
            4: enc_note=64;
            5: enc_note=67;
            6: enc_note=72;
            default: enc_note=76;
        endcase
    end
    assign o_valid=(state_current!=ST_IDLE);
    assign o_wave=reg_wave;
    assign o_event=(state_current==ST_WAVE)
        ? {8'd3,8'd5,16'd0,14'd0,reg_wave,8'd0}
        : {flag_pressed ? 8'd1 : 8'd2,5'd0,cnt_note,enc_note,8'd64,24'd0};
    // 忙时保留索引与事件数据；整组完成后再领取下一按键事件。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            state_current<=ST_IDLE;cnt_note<=0;flag_pressed<=0;reg_wave<=0;
        end else begin
            case(state_current)
                ST_IDLE: begin
                    if(flag_chord) begin
                        cnt_note<=0;flag_pressed<=(wire_chord_event[55:48]==1);
                        state_current<=ST_CHORD;
                    end else if(flag_wave && wire_wave_event[55:48]==1) begin
                        case(reg_wave)
                            0: reg_wave<=3;
                            3: reg_wave<=2;
                            2: reg_wave<=1;
                            default: reg_wave<=0;
                        endcase
                        state_current<=ST_WAVE;
                    end
                end
                ST_CHORD: begin
                    if(i_ready) begin
                        if(cnt_note==7) state_current<=ST_IDLE;
                        else cnt_note<=cnt_note+1'b1;
                    end
                end
                ST_WAVE: begin if(i_ready) state_current<=ST_IDLE; end
                default: begin state_current<=ST_IDLE; end
            endcase
        end
    end
endmodule
