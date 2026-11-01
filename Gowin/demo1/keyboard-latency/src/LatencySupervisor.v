`timescale 1ns / 1ps
// Observe the digital onset path without applying backpressure to audio.
// Physical timing starts at the FIRST qualifying ADC sample, including debounce.
// DAC timing ends at the left PT8211 word latch, not an acoustic measurement.
module LatencySupervisor #(
    parameter C_TIMEOUT_CYCLES = 50000000,
    parameter C_BUDGET_CYCLES = 500000,
    parameter C_INITIAL_TICK = 0
)(
    input i_clk,
    input i_rstn,
    input i_clear,
    input i_initialized,
    input i_sample_valid,
    input [4:0] i_sample_key,
    input i_candidate,
    input i_confirm,
    input i_cancel,
    input [31:0] i_physical,
    input [31:0] i_effective,
    input i_commit,
    input [4:0] i_commit_key,
    input i_result_valid,
    input [4:0] i_result_key,
    input [31:0] i_result_sample,
    input i_pcm_valid,
    input i_pcm_nonzero,
    input i_frame_load,
    input i_dac_left_latch,
    output [879:0] o_payload
);
    reg [31:0] cnt_tick;
    // Registered observation boundary: timestamps travel with all events.
    reg [31:0] reg_tap_tick;
    reg reg_tap_initialized;
    reg reg_tap_sample_valid;
    reg [4:0] reg_tap_sample_key;
    reg reg_tap_candidate;
    reg reg_tap_confirm;
    reg reg_tap_cancel;
    reg [31:0] reg_tap_physical;
    reg [31:0] reg_tap_effective;
    reg reg_tap_commit;
    reg [4:0] reg_tap_commit_key;
    reg reg_tap_result_valid;
    reg [4:0] reg_tap_result_key;
    reg [31:0] reg_tap_result_sample;
    reg reg_tap_pcm_valid;
    reg reg_tap_pcm_nonzero;
    reg reg_tap_frame_load;
    reg reg_tap_dac_left_latch;
    reg reg_tap_clear;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_tap_tick <= C_INITIAL_TICK;
            reg_tap_initialized <= 0;
            reg_tap_sample_valid <= 0;
            reg_tap_sample_key <= 0;
            reg_tap_candidate <= 0;
            reg_tap_confirm <= 0;
            reg_tap_cancel <= 0;
            reg_tap_physical <= 0;
            reg_tap_effective <= 0;
            reg_tap_commit <= 0;
            reg_tap_commit_key <= 0;
            reg_tap_result_valid <= 0;
            reg_tap_result_key <= 0;
            reg_tap_result_sample <= 0;
            reg_tap_pcm_valid <= 0;
            reg_tap_pcm_nonzero <= 0;
            reg_tap_frame_load <= 0;
            reg_tap_dac_left_latch <= 0;
            reg_tap_clear <= 0;
        end else begin
            reg_tap_tick <= cnt_tick;
            reg_tap_initialized <= i_initialized;
            reg_tap_sample_valid <= i_sample_valid;
            reg_tap_sample_key <= i_sample_key;
            reg_tap_candidate <= i_candidate;
            reg_tap_confirm <= i_confirm;
            reg_tap_cancel <= i_cancel;
            reg_tap_physical <= i_physical;
            reg_tap_effective <= i_effective;
            reg_tap_commit <= i_commit;
            reg_tap_commit_key <= i_commit_key;
            reg_tap_result_valid <= i_result_valid;
            reg_tap_result_key <= i_result_key;
            reg_tap_result_sample <= i_result_sample;
            reg_tap_pcm_valid <= i_pcm_valid;
            reg_tap_pcm_nonzero <= i_pcm_nonzero;
            reg_tap_frame_load <= i_frame_load;
            reg_tap_dac_left_latch <= i_dac_left_latch;
            reg_tap_clear <= i_clear;
        end
    end

    localparam [2:0] C_IDLE=0, C_QUALIFY=1, C_DETECTED=2, C_VOICE=3;
    localparam [2:0] C_PCM=4, C_LOAD=5, C_PLAY=6, C_DONE=7;
    localparam [31:0] C_BUDGET_WORD = C_BUDGET_CYCLES;

    reg [31:0] reg_previous;
    reg [2:0] mem_stage [0:31];
    reg [7:0] mem_generation [0:31];
    reg [7:0] mem_losses [0:31];
    reg mem_physical [0:31];
    reg mem_sample_seen [0:31];
    reg mem_result_seen [0:31];
    reg [31:0] mem_sample_time [0:31];
    reg [31:0] mem_start [0:31];
    reg [31:0] mem_detect [0:31];
    reg [31:0] mem_commit [0:31];
    reg [31:0] mem_first [0:31];
    reg [31:0] mem_voice [0:31];
    reg [31:0] mem_interval [0:31];
    wire [31:0] flag_pending;
    wire [31:0] flag_remote = reg_tap_effective & ~reg_previous & ~reg_tap_physical;

    // A shared reporting pipeline drains simultaneous completions in <= 36 clocks.
    reg [4:0] cnt_scan, reg_read_key, reg_calc_key;
    reg [7:0] reg_read_generation, reg_calc_generation;
    reg [7:0] reg_read_losses, reg_calc_losses;
    reg [2:0] reg_read_stage;
    reg flag_read_valid, flag_calc_valid, flag_calc_done, flag_calc_timeout;
    reg flag_read_physical, flag_calc_physical;
    reg [31:0] reg_read_start, reg_read_detect, reg_read_commit, reg_read_first;
    reg [31:0] reg_read_voice, reg_read_pcm, reg_read_dac, reg_read_interval;
    reg [31:0] reg_calc_start, reg_calc_dac, reg_calc_interval;
    reg [31:0] reg_calc_total, reg_calc_qualify, reg_calc_queue, reg_calc_compute;
    reg [31:0] reg_calc_output, reg_calc_mix, reg_calc_onset;
    wire flag_same = mem_generation[reg_calc_key] == reg_calc_generation;
    wire flag_report = flag_calc_valid && flag_calc_done && flag_same && (mem_stage[reg_calc_key] == C_DONE);
    wire flag_timeout = flag_calc_valid && flag_calc_timeout && flag_same &&
                        (mem_stage[reg_calc_key] != C_IDLE) && (mem_stage[reg_calc_key] != C_DONE);

    reg [31:0] cnt_records, cnt_late, cnt_timeouts, cnt_losses, cnt_canceled;
    reg [31:0] cnt_physical, cnt_remote;
    reg [63:0] reg_total_sum;
    reg [31:0] reg_min, reg_max;
    reg [4:0] reg_last_key;
    reg [7:0] reg_last_flags;
    reg [31:0] reg_last_total, reg_last_qualify, reg_last_queue, reg_last_compute;
    reg [31:0] reg_last_output, reg_last_mix, reg_last_interval, reg_last_onset;
    reg [31:0] reg_last_start, reg_last_dac;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) cnt_tick <= C_INITIAL_TICK;
        else cnt_tick <= cnt_tick + 1'b1;
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_previous <= 0;
        else reg_previous <= reg_tap_effective;
    end

    // One ADC sample per clock permits one shared interval datapath.
    wire [31:0] wire_scan_interval = reg_tap_tick - mem_sample_time[reg_tap_sample_key];
    always @(posedge i_clk) begin
        if (i_rstn && !reg_tap_clear && reg_tap_sample_valid) begin
            mem_sample_time[reg_tap_sample_key] <= reg_tap_tick;
            if (reg_tap_candidate && !reg_tap_effective[reg_tap_sample_key])
                mem_interval[reg_tap_sample_key] <= mem_sample_seen[reg_tap_sample_key] ? wire_scan_interval : 0;
        end
    end

    // All completed keys belong to the same DAC frame. Reporting drains in
    // <=36 clocks, much sooner than the next 1024-clock PT8211 left latch.
    reg [31:0] reg_pending_pcm, reg_play_pcm, reg_completed_pcm, reg_completed_dac;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_pending_pcm <= 0; reg_play_pcm <= 0;
            reg_completed_pcm <= 0; reg_completed_dac <= 0;
        end else begin
            if (reg_tap_pcm_valid) reg_pending_pcm <= reg_tap_tick;
            if (reg_tap_frame_load) reg_play_pcm <= reg_tap_pcm_valid ? reg_tap_tick : reg_pending_pcm;
            if (reg_tap_dac_left_latch) begin
                reg_completed_pcm <= reg_play_pcm;
                reg_completed_dac <= reg_tap_tick;
            end
        end
    end

    genvar key;
    generate for (key=0; key<32; key=key+1) begin:VoiceTiming
        wire flag_sample = reg_tap_sample_valid && (reg_tap_sample_key == key);
        wire flag_physical_start = reg_tap_candidate && flag_sample && !reg_tap_effective[key];
        wire flag_begin = reg_tap_initialized && (flag_physical_start || flag_remote[key]);
        wire flag_replaced = (mem_stage[key] != C_IDLE) && !((flag_report || flag_timeout) && reg_calc_key == key);
        reg [2:0] state_next;
        assign flag_pending[key] = mem_stage[key] != C_IDLE;

        always @(*) begin
            state_next = mem_stage[key];
            if (flag_begin) state_next = flag_physical_start ? C_QUALIFY : C_DETECTED;
            else if (reg_tap_cancel && flag_sample && mem_stage[key] == C_QUALIFY) state_next = C_IDLE;
            else if ((flag_report || flag_timeout) && reg_calc_key == key) state_next = C_IDLE;
            else case (mem_stage[key])
                C_QUALIFY: if (reg_tap_confirm && flag_sample) state_next = C_DETECTED;
                C_DETECTED: if (reg_tap_commit && reg_tap_commit_key == key) state_next = C_VOICE;
                C_VOICE: if (reg_tap_result_valid && reg_tap_result_key == key && reg_tap_result_sample != 0) state_next = C_PCM;
                C_PCM: if (reg_tap_pcm_valid) state_next = reg_tap_pcm_nonzero ? C_LOAD : C_VOICE;
                C_LOAD: if (reg_tap_frame_load) state_next = C_PLAY;
                C_PLAY: if (reg_tap_dac_left_latch) state_next = C_DONE;
                default: begin end
            endcase
        end

        always @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) mem_stage[key] <= C_IDLE;
            else if (reg_tap_clear) mem_stage[key] <= C_IDLE;
            else mem_stage[key] <= state_next;
        end

        always @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                mem_generation[key] <= 0;
                mem_losses[key] <= 0;
                mem_sample_seen[key] <= 0;
                mem_result_seen[key] <= 0;
                mem_physical[key] <= 0;
            end else if (reg_tap_clear) begin
                mem_generation[key] <= 0;
                mem_losses[key] <= 0;
                mem_sample_seen[key] <= 0;
                mem_result_seen[key] <= 0;
                mem_physical[key] <= 0;
            end else begin
                if (flag_sample) mem_sample_seen[key] <= 1;
                // At most one aggregate loss read per key every 32 clocks.
                if (cnt_scan == key) mem_losses[key] <= 0;
                if (flag_begin) begin
                    mem_generation[key] <= mem_generation[key] + 1'b1;
                    mem_start[key] <= reg_tap_tick;
                    mem_detect[key] <= reg_tap_tick;
                    mem_physical[key] <= flag_physical_start;
                    mem_result_seen[key] <= 0;
                    if (flag_replaced) begin
                        if (cnt_scan == key) mem_losses[key] <= 1;
                        else if (mem_losses[key] != 255) mem_losses[key] <= mem_losses[key] + 1'b1;
                    end
                end else if (reg_tap_cancel && flag_sample && mem_stage[key] == C_QUALIFY) begin
                end else if ((flag_report || flag_timeout) && reg_calc_key == key) begin
                end else begin
                    case (mem_stage[key])
                        C_QUALIFY: if (reg_tap_confirm && flag_sample) begin
                            mem_detect[key] <= reg_tap_tick;
                        end
                        C_DETECTED: if (reg_tap_commit && reg_tap_commit_key == key) begin
                            mem_commit[key] <= reg_tap_tick;
                        end
                        C_VOICE: if (reg_tap_result_valid && reg_tap_result_key == key) begin
                            if (!mem_result_seen[key]) begin
                                mem_first[key] <= reg_tap_tick;
                                mem_result_seen[key] <= 1;
                            end
                            if (reg_tap_result_sample != 0) begin
                                mem_voice[key] <= reg_tap_tick;
                            end
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end endgenerate

    // Snapshot registers isolate the large voice-selection mux from arithmetic.
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt_scan <= 0;
            flag_read_valid <= 0;
            flag_calc_valid <= 0;
        end else if (reg_tap_clear) begin
            cnt_scan <= 0;
            flag_read_valid <= 0;
            flag_calc_valid <= 0;
        end else begin
            cnt_scan <= cnt_scan + 1'b1;
            flag_read_valid <= 1;
            reg_read_key <= cnt_scan;
            reg_read_generation <= mem_generation[cnt_scan];
            reg_read_stage <= mem_stage[cnt_scan];
            reg_read_losses <= mem_losses[cnt_scan];
            flag_read_physical <= mem_physical[cnt_scan];
            reg_read_start <= mem_start[cnt_scan];
            reg_read_detect <= mem_detect[cnt_scan];
            reg_read_commit <= mem_commit[cnt_scan];
            reg_read_first <= mem_first[cnt_scan];
            reg_read_voice <= mem_voice[cnt_scan];
            reg_read_pcm <= reg_completed_pcm;
            reg_read_dac <= reg_completed_dac;
            reg_read_interval <= mem_physical[cnt_scan] ? mem_interval[cnt_scan] : 0;

            flag_calc_valid <= flag_read_valid;
            reg_calc_key <= reg_read_key;
            reg_calc_generation <= reg_read_generation;
            reg_calc_losses <= reg_read_losses;
            flag_calc_physical <= flag_read_physical;
            flag_calc_done <= reg_read_stage == C_DONE;
            flag_calc_timeout <= (reg_read_stage != C_IDLE) && (reg_read_stage != C_DONE) &&
                                 ((cnt_tick - reg_read_start) >= C_TIMEOUT_CYCLES);
            reg_calc_start <= reg_read_start;
            reg_calc_dac <= reg_read_dac;
            reg_calc_interval <= reg_read_interval;
            reg_calc_total <= reg_read_dac - reg_read_start;
            reg_calc_qualify <= reg_read_detect - reg_read_start;
            reg_calc_queue <= reg_read_commit - reg_read_detect;
            reg_calc_compute <= reg_read_first - reg_read_commit;
            reg_calc_onset <= reg_read_voice - reg_read_first;
            reg_calc_output <= reg_read_dac - reg_read_voice;
            reg_calc_mix <= reg_read_pcm - reg_read_voice;
        end
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt_records <= 0; cnt_late <= 0; cnt_timeouts <= 0; cnt_losses <= 0; cnt_canceled <= 0;
            cnt_physical <= 0; cnt_remote <= 0; reg_total_sum <= 0;
            reg_min <= 32'hffffffff; reg_max <= 0;
            reg_last_key <= 0; reg_last_flags <= 0;
            reg_last_total <= 0; reg_last_qualify <= 0; reg_last_queue <= 0; reg_last_compute <= 0;
            reg_last_output <= 0; reg_last_mix <= 0; reg_last_interval <= 0; reg_last_onset <= 0;
            reg_last_start <= 0; reg_last_dac <= 0;
        end else if (reg_tap_clear) begin
            cnt_records <= 0; cnt_late <= 0; cnt_timeouts <= 0; cnt_losses <= 0; cnt_canceled <= 0;
            cnt_physical <= 0; cnt_remote <= 0; reg_total_sum <= 0;
            reg_min <= 32'hffffffff; reg_max <= 0;
            reg_last_key <= 0; reg_last_flags <= 0;
            reg_last_total <= 0; reg_last_qualify <= 0; reg_last_queue <= 0; reg_last_compute <= 0;
            reg_last_output <= 0; reg_last_mix <= 0; reg_last_interval <= 0; reg_last_onset <= 0;
            reg_last_start <= 0; reg_last_dac <= 0;
        end else begin
            if (flag_calc_valid) cnt_losses <= cnt_losses + reg_calc_losses;
            if (flag_timeout) cnt_timeouts <= cnt_timeouts + 1'b1;
            if (reg_tap_cancel && reg_tap_sample_valid && mem_stage[reg_tap_sample_key] == C_QUALIFY) cnt_canceled <= cnt_canceled + 1'b1;
            if (flag_report) begin
                // Freeze the sum/count pair at saturation, preserving a valid mean.
                if (cnt_records != 32'hffffffff) begin
                    cnt_records <= cnt_records + 1'b1;
                    reg_total_sum <= reg_total_sum + reg_calc_total;
                end
                if (flag_calc_physical) cnt_physical <= cnt_physical + 1'b1;
                else cnt_remote <= cnt_remote + 1'b1;
                if (reg_calc_total > C_BUDGET_CYCLES) cnt_late <= cnt_late + 1'b1;
                if (reg_calc_total < reg_min) reg_min <= reg_calc_total;
                if (reg_calc_total > reg_max) reg_max <= reg_calc_total;
                reg_last_key <= reg_calc_key;
                reg_last_flags <= {4'd0,(reg_calc_total > C_BUDGET_CYCLES),2'b11,flag_calc_physical};
                reg_last_total <= reg_calc_total;
                reg_last_qualify <= reg_calc_qualify;
                reg_last_queue <= reg_calc_queue;
                reg_last_compute <= reg_calc_compute;
                reg_last_output <= reg_calc_output;
                reg_last_mix <= reg_calc_mix;
                reg_last_interval <= reg_calc_interval;
                reg_last_onset <= reg_calc_onset;
                reg_last_start <= reg_calc_start;
                reg_last_dac <= reg_calc_dac;
            end
        end
    end

    // Extension occupies telemetry bytes 80..189, little-endian integers.
    assign o_payload = {16'd0,64'd0,cnt_canceled,reg_last_onset,flag_pending,C_BUDGET_WORD,
                        reg_last_dac,reg_last_start,cnt_tick,cnt_remote,cnt_physical,reg_last_interval,
                        cnt_losses,cnt_timeouts,cnt_late,reg_total_sum,reg_max,reg_min,
                        reg_last_mix,reg_last_output,reg_last_compute,reg_last_queue,reg_last_qualify,
                        reg_last_total,16'd0,reg_last_flags,3'd0,reg_last_key,cnt_records};
endmodule
