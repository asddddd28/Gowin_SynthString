`timescale 1ns / 1ps
// Shared effects command domain / 共享效果命令域. Contract: spec/AxisFxEngine_spec.md.
// AXI-MM endpoint adapts C0..C4 commands to this private ready-valid interface.
module AxisFxEngine #(parameter C_DELAY_ADDR_BITS=15)(
    input i_axis_aclk,
    input i_axis_arstn,
    input [383:0] i_s_axis_tdata,
    input [31:0] i_s_axis_tuser,
    input [7:0] i_s_axis_tdest,
    input i_s_axis_tvalid,
    output o_s_axis_tready,
    output [127:0] o_m_axis_tdata,
    output [31:0] o_m_axis_tuser,
    output [7:0] o_m_axis_tdest,
    output o_m_axis_tvalid,
    input i_m_axis_tready,
    input [63:0] i_audio_data,
    input [31:0] i_audio_frame,
    input i_audio_valid,
    output o_audio_ready,
    output [63:0] o_audio_data,
    output [31:0] o_audio_frame,
    output o_audio_valid,
    input i_audio_ready,
    output [31:0] o_frames,
    output [31:0] o_clipped_frames,
    output [31:0] o_cycles
);
    reg [159:0] reg_delay_draft;
    reg [159:0] reg_delay_active;
    reg [127:0] reg_reverb_draft;
    reg [127:0] reg_reverb_active;
    reg [31:0] cnt_revision;
    reg flag_session;
    reg [23:0] reg_epoch;
    reg [31:0] reg_sequence;
    reg [335:0] reg_signature;
    reg [127:0] reg_cached;
    reg [127:0] reg_completion;
    reg [31:0] reg_tag;
    reg [7:0] reg_opcode;
    reg flag_completion;
    reg [7:0] dec_status;
    reg [127:0] dec_result;
    reg flag_replay;
    reg flag_eligible;
    reg flag_packet_decoded;
    reg [20:0] reg_signature_equal;
    reg [9:0] reg_payload_zero;
    integer signature_chunk, payload_chunk;
    reg flag_audio_busy;
    reg flag_delay_clip;
    reg [31:0] cnt_cycles;
    reg [31:0] reg_cycles;
    reg [31:0] cnt_frames;
    reg [31:0] cnt_clipped;
    wire [7:0] wire_address=i_s_axis_tdata[327:320];
    wire [23:0] wire_epoch=i_s_axis_tdata[351:328];
    wire [31:0] wire_sequence=i_s_axis_tdata[383:352];
    wire [335:0] wire_signature={i_s_axis_tdest,wire_address,i_s_axis_tdata[319:0]};
    wire flag_accept=i_s_axis_tvalid && o_s_axis_tready;
    wire flag_apply=flag_accept && flag_eligible && dec_status==0;
    wire flag_clear_delay=flag_apply && i_s_axis_tdest==8'hc3 && i_s_axis_tdata[0];
    wire flag_clear_reverb=flag_apply && i_s_axis_tdest==8'hc3 && i_s_axis_tdata[1];
    wire flag_delay_ready;
    wire flag_delay_valid;
    wire flag_reverb_ready;
    wire flag_delay_clipped;
    wire flag_reverb_clipped;
    wire [63:0] wire_delay_data;
    wire [31:0] wire_delay_frame;
    assign o_s_axis_tready=i_axis_arstn && flag_packet_decoded && !flag_audio_busy && !i_audio_valid && (!flag_completion || i_m_axis_tready);
    assign o_m_axis_tvalid=flag_completion;
    assign o_m_axis_tdata=reg_completion;
    assign o_m_axis_tuser=reg_tag;
    assign o_m_axis_tdest=reg_opcode;
    assign o_audio_ready=!flag_audio_busy && flag_delay_ready;
    assign o_frames=cnt_frames;
    assign o_clipped_frames=cnt_clipped;
    assign o_cycles=reg_cycles;

    // Chunked comparisons keep wide packet equality out of a single carry chain.
    // Audio always takes priority, invalidating a control snapshot before use.
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) begin
            flag_packet_decoded<=0;reg_signature_equal<=0;reg_payload_zero<=0;
        end else if (flag_audio_busy || i_audio_valid || !i_s_axis_tvalid || flag_accept) begin
            flag_packet_decoded<=0;
        end else if (!flag_packet_decoded) begin
            flag_packet_decoded<=1;
            for (signature_chunk=0;signature_chunk<21;signature_chunk=signature_chunk+1)
                reg_signature_equal[signature_chunk]<=wire_signature[signature_chunk*16+:16]==reg_signature[signature_chunk*16+:16];
            for (payload_chunk=0;payload_chunk<10;payload_chunk=payload_chunk+1)
                reg_payload_zero[payload_chunk]<=i_s_axis_tdata[payload_chunk*32+:32]==0;
        end
    end

    // Transport identity is separate from audio frame identity and note lifetime.
    always @(*) begin
        dec_status=0;
        dec_result=0;
        flag_replay=0;
        flag_eligible=0;
        if (flag_session && wire_epoch!=reg_epoch) dec_status=4;
        else if (flag_session && wire_sequence==reg_sequence) begin
            if (&reg_signature_equal) flag_replay=1;
            else dec_status=5;
        end else if (flag_session && wire_sequence<reg_sequence) dec_status=6;
        else if (wire_sequence!=(flag_session ? reg_sequence+32'd1 : 32'd0)) dec_status=7;
        else begin
            flag_eligible=1;
            case (i_s_axis_tdest)
                8'hc0: begin
                    if (wire_address!=0 || !(&reg_payload_zero[9:5]) || i_s_axis_tdata[159:130]!=0 ||
                        i_s_axis_tdata[31:0]<65536 || i_s_axis_tdata[31:0]>((32'd1<<C_DELAY_ADDR_BITS)<<16)-1 ||
                        i_s_axis_tdata[63:32]<65536 || i_s_axis_tdata[63:32]>((32'd1<<C_DELAY_ADDR_BITS)<<16)-1 ||
                        $signed(i_s_axis_tdata[95:64])>32'sd63753420 || $signed(i_s_axis_tdata[95:64])< -32'sd63753420 ||
                        i_s_axis_tdata[127:96]>67108864) dec_status=8;
                end
                8'hc1: begin
                    if (wire_address!=0 || !(&reg_payload_zero[9:4]) || i_s_axis_tdata[127:97]!=0 ||
                        i_s_axis_tdata[31:0]>60397977 || i_s_axis_tdata[63:32]>63753420 ||
                        i_s_axis_tdata[95:64]>67108864) dec_status=8;
                end
                8'hc2: begin
                    if (wire_address!=0 || !(&reg_payload_zero)) dec_status=8;
                    else dec_result[31:0]=cnt_revision+1'b1;
                end
                8'hc3: if (wire_address!=0 || !(&reg_payload_zero[9:1]) || i_s_axis_tdata[31:2]!=0 || i_s_axis_tdata[1:0]==0) dec_status=8;
                8'hc4: begin
                    if (wire_address>3 || !(&reg_payload_zero)) dec_status=8;
                    else begin
                    case (wire_address[1:0])
                        0: begin dec_result[63:0]={cnt_clipped,cnt_frames}; dec_result[127:96]=reg_cycles; end
                        1: begin dec_result[63:0]=reg_delay_active[63:0]; dec_result[127:96]=reg_delay_active[159:128]; end
                        2: begin dec_result[63:0]={reg_delay_active[95:64],reg_delay_active[127:96]}; dec_result[127:96]=reg_reverb_active[95:64]; end
                        3: begin dec_result[63:0]=reg_reverb_active[63:0]; dec_result[127:96]=cnt_revision; end
                        default: dec_status=8;
                    endcase
                    end
                end
                default: dec_status=1;
            endcase
        end
        if (flag_replay) begin
            dec_result=reg_cached;
            dec_result[72]=1;
        end else dec_result[71:64]=dec_status;
    end
    always @(posedge i_axis_aclk or negedge i_axis_arstn) begin
        if (!i_axis_arstn) begin
            reg_delay_draft<=160'h00000000_00000000_00000000_00010000_00010000;
            reg_delay_active<=160'h00000000_00000000_00000000_00010000_00010000;
            reg_reverb_draft<=0;
            reg_reverb_active<=0;
            cnt_revision<=0;
            flag_session<=0;
            reg_epoch<=0;
            reg_sequence<=0;
            reg_signature<=0;
            reg_cached<=0;
            reg_completion<=0;
            reg_tag<=0;
            reg_opcode<=0;
            flag_completion<=0;
            flag_audio_busy<=0;
            flag_delay_clip<=0;
            cnt_cycles<=0;
            reg_cycles<=0;
            cnt_frames<=0;
            cnt_clipped<=0;
        end else begin
            if (flag_completion && i_m_axis_tready) flag_completion<=0;
            if (flag_accept) begin
                flag_completion<=1;
                reg_completion<=dec_result;
                reg_tag<=i_s_axis_tuser;
                reg_opcode<=i_s_axis_tdest;
                if (flag_eligible) begin
                    flag_session<=1;
                    reg_epoch<=wire_epoch;
                    reg_sequence<=wire_sequence;
                    reg_signature<=wire_signature;
                    reg_cached<=dec_result;
                end
                if (flag_apply) begin
                case (i_s_axis_tdest)
                    8'hc0: reg_delay_draft<=i_s_axis_tdata[159:0];
                    8'hc1: reg_reverb_draft<=i_s_axis_tdata[127:0];
                    8'hc2: begin
                        reg_delay_active<=reg_delay_draft;
                        reg_reverb_active<=reg_reverb_draft;
                        cnt_revision<=cnt_revision+1'b1;
                    end
                    default: cnt_revision<=cnt_revision;
                endcase
                end
            end
            if (i_audio_valid && o_audio_ready) begin
                flag_audio_busy<=1;
                flag_delay_clip<=0;
                cnt_cycles<=1;
            end else if (flag_audio_busy && !o_audio_valid) cnt_cycles<=cnt_cycles+1'b1;
            if (flag_delay_valid && flag_reverb_ready) flag_delay_clip<=flag_delay_clipped;
            if (o_audio_valid && i_audio_ready) begin
                flag_audio_busy<=0;
                reg_cycles<=cnt_cycles;
                cnt_frames<=cnt_frames+1'b1;
                if (flag_delay_clip || flag_reverb_clipped) cnt_clipped<=cnt_clipped+1'b1;
            end
        end
    end
    AxisStereoDelay #(.C_DELAY_ADDR_BITS(C_DELAY_ADDR_BITS)) Delay_Inst(
        .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),
        .i_s_axis_tdata(i_audio_data),.i_s_axis_tuser(i_audio_frame),
        .i_s_axis_tvalid(i_audio_valid && !flag_audio_busy),.o_s_axis_tready(flag_delay_ready),
        .o_m_axis_tdata(wire_delay_data),.o_m_axis_tuser(wire_delay_frame),
        .o_m_axis_tvalid(flag_delay_valid),.i_m_axis_tready(flag_reverb_ready),
        .i_config(reg_delay_active),.i_clear(flag_clear_delay),.o_clipped(flag_delay_clipped)
    );
    AxisSchroederReverb Reverb_Inst(
        .i_axis_aclk(i_axis_aclk),.i_axis_arstn(i_axis_arstn),
        .i_s_axis_tdata(wire_delay_data),.i_s_axis_tuser(wire_delay_frame),
        .i_s_axis_tvalid(flag_delay_valid),.o_s_axis_tready(flag_reverb_ready),
        .o_m_axis_tdata(o_audio_data),.o_m_axis_tuser(o_audio_frame),
        .o_m_axis_tvalid(o_audio_valid),.i_m_axis_tready(i_audio_ready),
        .i_config(reg_reverb_active),.i_clear(flag_clear_reverb),.o_clipped(flag_reverb_clipped)
    );
endmodule
