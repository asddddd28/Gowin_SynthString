`timescale 1ns / 1ps
// Passive PCM analyser / 旁路音频分析器。Contract: SynthDisplayAudio_spec.md.
// A held publication bank is never overwritten. Missing a display frame drops
// observation samples only; there is no ready signal back to the audio engine.
module SynthDisplayAudio(
    input i_clk,
    input i_rstn,
    input i_sample_valid,
    input signed [15:0] i_sample,
    input i_pixel_clk,
    input i_pixel_rstn,
    input i_blank_start,
    input [7:0] i_wave_address,
    input [5:0] i_spectrum_address,
    output [7:0] o_wave,
    output [6:0] o_spectrum,
    output o_available,
    output o_publish
);
    localparam IDLE=0, READ=1, MULTIPLY=2, SUM=3, STORE=4, MAGNITUDE=5, ADVANCE=6, WAIT_BANK=7, TRIGGER=8;
    reg [3:0] reg_state, dec_next_state;
    reg flag_trigger_armed;
    reg [10:0] cnt_trigger_wait;
    reg [7:0] reg_sample_index, reg_phase;
    reg [5:0] reg_band;
    reg signed [15:0] reg_sample;
    (* syn_ramstyle="block_ram" *) reg [31:0] mem_coefficient [0:255];
    (* syn_ramstyle="block_ram" *) reg [47:0] mem_accumulator [0:63];
    (* syn_ramstyle="block_ram" *) reg [15:0] mem_wave [0:511];
    (* syn_ramstyle="block_ram" *) reg [6:0] mem_spectrum [0:127];
    reg [31:0] reg_coefficient;
    reg [47:0] reg_accumulator;
    reg signed [31:0] reg_product_real, reg_product_imag;
    reg signed [23:0] reg_sum_real, reg_sum_imag;
    reg [23:0] reg_abs_real, reg_abs_imag;
    wire [24:0] wire_magnitude={1'b0,reg_abs_real}+{1'b0,reg_abs_imag};
    reg flag_bank, flag_request;
    reg [1:0] reg_ack_sync;
    reg [1:0] reg_request_sync;
    reg flag_ack, flag_display_bank, flag_available_o, flag_publish_o;
    reg [15:0] reg_wave_read;
    reg [15:0] reg_peak;
    wire [15:0] wire_trigger_level=reg_peak[15:4]<12'd4 ? 16'd4 : {4'd0,reg_peak[15:4]};
    wire flag_trigger_crossing=flag_trigger_armed && !i_sample[15];
    wire flag_trigger_capture=flag_trigger_crossing || cnt_trigger_wait==11'd2047;
    wire flag_sample_accept=i_sample_valid && (reg_state==IDLE || (reg_state==TRIGGER && flag_trigger_capture));
    reg [2:0] reg_hold_shift,reg_display_shift;
    reg [2:0] dec_shift;
    reg [6:0] dec_log_magnitude;
    wire [15:0] wire_absolute=i_sample[15] ? -i_sample : i_sample;
    wire [15:0] wire_wave_scaled=reg_wave_read<<reg_display_shift;
    reg [6:0] reg_spectrum_o;
    initial $readmemh("hdmi/dft.hex",mem_coefficient);
    assign o_wave=wire_wave_scaled[15:8]^8'h80;
    assign o_spectrum=reg_spectrum_o;
    assign o_available=flag_available_o;
    assign o_publish=flag_publish_o;

    // Only toggles cross synchronizers; all published sample memory is held.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_ack_sync<=0;
        else reg_ack_sync<={reg_ack_sync[0],flag_ack};
    end
    always @(posedge i_pixel_clk or negedge i_pixel_rstn) begin
        if(!i_pixel_rstn) begin
            reg_request_sync<=0;flag_ack<=0;flag_display_bank<=0;
            flag_available_o<=0;flag_publish_o<=0;reg_display_shift<=0;
        end else begin
            reg_request_sync<={reg_request_sync[0],flag_request};flag_publish_o<=0;
            if(i_blank_start && reg_request_sync[1]!=flag_ack) begin
                flag_ack<=reg_request_sync[1];flag_display_bank<=reg_request_sync[1];
                flag_available_o<=1;flag_publish_o<=1;
                reg_display_shift<=reg_hold_shift;
            end
        end
    end
    // True dual-clock RAM ports. The producer writes only the undisplayed bank.
    always @(posedge i_pixel_clk) begin
        reg_wave_read<=mem_wave[{flag_display_bank,i_wave_address}];
        reg_spectrum_o<=mem_spectrum[{flag_display_bank,i_spectrum_address}];
    end
    always @(posedge i_clk) begin
        if(flag_sample_accept) mem_wave[{flag_bank,reg_sample_index}]<=i_sample;
        if(reg_state==READ) begin
            reg_coefficient<=mem_coefficient[reg_phase];
            reg_accumulator<=mem_accumulator[reg_band];
        end
        if(reg_state==STORE) mem_accumulator[reg_band]<={reg_sum_imag,reg_sum_real};
        if(reg_state==MAGNITUDE && reg_sample_index==255)
            mem_spectrum[{flag_bank,reg_band}]<=dec_log_magnitude;
    end
    // Display gain is derived from the same frozen waveform, so a loud attack
    // cannot clip using a quiet previous frame's gain. Below64 PCM counts the
    // viewer keeps unity scale rather than magnifying digital silence/noise.
    always @(*) begin
        dec_shift=0;
        if(reg_peak>=64) begin
            if(reg_peak<256) dec_shift=7;
            else if(reg_peak<512) dec_shift=6;
            else if(reg_peak<1024) dec_shift=5;
            else if(reg_peak<2048) dec_shift=4;
            else if(reg_peak<4096) dec_shift=3;
            else if(reg_peak<8192) dec_shift=2;
            else if(reg_peak<16384) dec_shift=1;
        end
        // Piecewise log2 magnitude: ten display pixels per octave of amplitude,
        // approximately6dB. DC/silence remains zero; no visual gain enters audio.
        dec_log_magnitude=0;
        if(|wire_magnitude[24:22]) dec_log_magnitude=127;
        else if(wire_magnitude[21]) dec_log_magnitude=118+{4'd0,wire_magnitude[20:18]};
        else if(wire_magnitude[20]) dec_log_magnitude=108+{4'd0,wire_magnitude[19:17]};
        else if(wire_magnitude[19]) dec_log_magnitude=98+{4'd0,wire_magnitude[18:16]};
        else if(wire_magnitude[18]) dec_log_magnitude=88+{4'd0,wire_magnitude[17:15]};
        else if(wire_magnitude[17]) dec_log_magnitude=78+{4'd0,wire_magnitude[16:14]};
        else if(wire_magnitude[16]) dec_log_magnitude=68+{4'd0,wire_magnitude[15:13]};
        else if(wire_magnitude[15]) dec_log_magnitude=58+{4'd0,wire_magnitude[14:12]};
        else if(wire_magnitude[14]) dec_log_magnitude=48+{4'd0,wire_magnitude[13:11]};
        else if(wire_magnitude[13]) dec_log_magnitude=38+{4'd0,wire_magnitude[12:10]};
        else if(wire_magnitude[12]) dec_log_magnitude=28+{4'd0,wire_magnitude[11:9]};
        else if(wire_magnitude[11]) dec_log_magnitude=18+{4'd0,wire_magnitude[10:8]};
        else if(wire_magnitude[10]) dec_log_magnitude=8+{4'd0,wire_magnitude[9:7]};
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_state<=TRIGGER;
        else reg_state<=dec_next_state;
    end
    always @(*) begin
        dec_next_state=reg_state;
        case(reg_state)
            TRIGGER: if(i_sample_valid && flag_trigger_capture) dec_next_state=READ;
            IDLE: if(i_sample_valid) dec_next_state=READ;
            READ: dec_next_state=MULTIPLY;
            MULTIPLY: dec_next_state=SUM;
            SUM: dec_next_state=STORE;
            STORE: dec_next_state=MAGNITUDE;
            MAGNITUDE: dec_next_state=ADVANCE;
            ADVANCE: if(reg_band!=63) dec_next_state=READ;
                else dec_next_state=reg_sample_index==255 ? WAIT_BANK : IDLE;
            WAIT_BANK: if(reg_ack_sync[1]==flag_request) dec_next_state=TRIGGER;
            default: dec_next_state=TRIGGER;
        endcase
    end
    // Two pipelined 16x16 products and two shared 24-bit accumulators service
    // 64 frequency bins in 448 core clocks, below the 1024-clock sample period.
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_sample_index<=0;reg_phase<=0;reg_band<=0;reg_sample<=0;
            reg_product_real<=0;reg_product_imag<=0;reg_sum_real<=0;reg_sum_imag<=0;
            reg_abs_real<=0;reg_abs_imag<=0;flag_bank<=1;flag_request<=0;
            reg_peak<=0;reg_hold_shift<=0;flag_trigger_armed<=0;cnt_trigger_wait<=0;
        end else begin
            // Hysteresis suppresses near-zero chatter. A capture starts at the
            // rising zero crossing, then stores256 consecutive real samples.
            // Auto-trigger after2048 observed samples keeps DC/silence fresh;
            // this wait never enters the main synthesis or DAC audio path.
            if(reg_state==TRIGGER && i_sample_valid) begin
                cnt_trigger_wait<=cnt_trigger_wait+1'b1;
                if(i_sample<=-$signed(wire_trigger_level)) flag_trigger_armed<=1;
            end
            if(flag_sample_accept) begin
                reg_sample<=i_sample;reg_phase<=reg_sample_index;reg_band<=0;
                if(reg_sample_index==0 || wire_absolute>reg_peak) reg_peak<=wire_absolute;
            end
            case(reg_state)
                MULTIPLY: begin
                    reg_product_real<=reg_sample*$signed(reg_coefficient[15:0]);
                    reg_product_imag<=reg_sample*$signed(reg_coefficient[31:16]);
                end
                SUM: begin
                    reg_sum_real<=(reg_sample_index==0 ? 24'sd0 : $signed(reg_accumulator[23:0]))+($signed(reg_product_real)>>>15);
                    reg_sum_imag<=(reg_sample_index==0 ? 24'sd0 : $signed(reg_accumulator[47:24]))+($signed(reg_product_imag)>>>15);
                end
                STORE: begin
                    reg_abs_real<=reg_sum_real[23] ? -reg_sum_real : reg_sum_real;
                    reg_abs_imag<=reg_sum_imag[23] ? -reg_sum_imag : reg_sum_imag;
                end
                ADVANCE: if(reg_band==63) begin
                    reg_sample_index<=reg_sample_index+1'b1;
                    if(reg_sample_index==255) begin flag_request<=~flag_request;reg_hold_shift<=dec_shift;end
                end else begin reg_band<=reg_band+1'b1;reg_phase<=reg_phase+reg_sample_index;end
                WAIT_BANK: if(reg_ack_sync[1]==flag_request) begin
                    flag_bank<=~flag_bank;flag_trigger_armed<=0;cnt_trigger_wait<=0;
                end
                default: begin end
            endcase
        end
    end
endmodule
