`timescale 1ns / 1ps
// HeadphoneMute: shut down the analog amplifier only after a completed tail.
// 静音后关闭功放；唤醒期间通过反压保留首个音符，不裁剪包络尾音。
module HeadphoneMute #(
    parameter C_SETTLE_FRAMES = 2048,
    parameter C_IDLE_FRAMES = 9600,
    parameter C_OFF_FRAMES = 16
)(
    input i_clk,
    input i_rstn,
    input i_tick,
    input i_note_pending,
    input i_silent,
    output o_ready,
    output o_shutdown
);
    // 96 kHz 下分别等待约 21.33 ms、100 ms 和 167 us。
    localparam ST_OFF = 2'd0, ST_SETTLE = 2'd1, ST_PLAY = 2'd2;
    reg [1:0] state_current;
    reg [1:0] state_next;
    reg [13:0] cnt_frames;
    // 功放关断电平保持超过 100 us，避免短脉冲被解释为工作模式切换。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) state_current <= ST_OFF;
        else state_current <= state_next;
    end
    always @(*) begin
        state_next = state_current;
        case (state_current)
            ST_OFF: if (i_note_pending && cnt_frames >= C_OFF_FRAMES) state_next = ST_SETTLE;
            ST_SETTLE: if (cnt_frames >= C_SETTLE_FRAMES) state_next = ST_PLAY;
            ST_PLAY: if (i_silent && !i_note_pending && cnt_frames >= C_IDLE_FRAMES) state_next = ST_OFF;
            default: state_next = ST_OFF;
        endcase
    end
    // 所有等待均以音频帧计数；零交越不算静音，必须同时没有活动声部。
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) cnt_frames <= 0;
        else if (state_current != state_next) cnt_frames <= 0;
        else begin
            case (state_current)
                ST_OFF: if (i_tick && cnt_frames < C_OFF_FRAMES) cnt_frames <= cnt_frames + 1'b1;
                ST_SETTLE: if (i_tick && cnt_frames < C_SETTLE_FRAMES) cnt_frames <= cnt_frames + 1'b1;
                ST_PLAY: begin
                    if (!i_silent || i_note_pending) cnt_frames <= 0;
                    else if (i_tick && cnt_frames < C_IDLE_FRAMES) cnt_frames <= cnt_frames + 1'b1;
                end
                default: cnt_frames <= 0;
            endcase
        end
    end
    assign o_ready = (state_current == ST_PLAY);
    assign o_shutdown = !i_rstn || (state_current == ST_OFF);
endmodule
