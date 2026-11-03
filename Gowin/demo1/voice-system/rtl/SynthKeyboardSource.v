`timescale 1ns / 1ps
// Edge-to-note source / 按键事件源. Contract: spec/SynthKeyboardSource_spec.md.
module SynthKeyboardSource(
    input i_clk,input i_rstn,
    output [391:0] o_request,output o_request_valid,input i_request_ready,
    input [135:0] i_response,input i_response_valid,output o_response_ready,
    input i_enabled,input [31:0] i_pressed,output o_idle,
    output [4:0] o_velocity_key,input [6:0] i_velocity,input i_velocity_enabled,output [31:0] o_delivered,
    output [31:0] o_events,output o_fault,
    input i_config_write,input [4:0] i_config_key,input [47:0] i_config_data,output [47:0] o_config_data,
    output o_event_start,output o_event_finish,output o_event_failed,output [4:0] o_event_key,output [31:0] o_event_frame
);
    localparam SCAN=0,PREPARE=1,SEND=2,WAIT_REPLY=3;
    reg [1:0] reg_state,next_state;
    reg [31:0] mem_note_id[0:31];
    (* syn_ramstyle = "block_ram" *) reg [47:0] mem_mapping[0:31];
    reg [47:0] reg_mapping,reg_config_read;
    reg [31:0] reg_delivered,cnt_events,cnt_identity;
    reg [4:0] reg_key;
    reg flag_press,flag_fault;
    reg [391:0] reg_request;
    integer index;
    initial $readmemh("rom/keyboard_mapping.hex",mem_mapping);
    wire [6:0] wire_note_velocity=i_velocity_enabled ? i_velocity : reg_mapping[47:41];
    wire [7:0] wire_velocity_gain={1'b0,i_velocity}+1'b1;
    assign o_idle=reg_state==SCAN;
    assign o_velocity_key=reg_key;
    assign o_config_data=reg_config_read;
    assign o_event_start=reg_state==PREPARE && flag_press;
    assign o_event_finish=reg_state==WAIT_REPLY && i_response_valid && flag_press;
    assign o_event_failed=i_response[135:128]!=0 || i_response[71:64]!=0;
    assign o_event_key=reg_key;
    assign o_event_frame=i_response[63:32];
    assign o_request=reg_request;
    assign o_request_valid=reg_state==SEND;
    assign o_response_ready=reg_state==WAIT_REPLY;
    assign o_delivered=reg_delivered;
    assign o_events=cnt_events;
    assign o_fault=flag_fault;
    always @(posedge i_clk) begin
        if (reg_state==SCAN) reg_mapping<=mem_mapping[reg_key];
        if (i_config_write) mem_mapping[i_config_key]<=i_config_data;
        else reg_config_read<=mem_mapping[i_config_key];
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) reg_state<=SCAN;
        else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case (reg_state)
            SCAN: if (i_enabled && !flag_fault && i_pressed[reg_key]!=reg_delivered[reg_key]) next_state=PREPARE;
            PREPARE: next_state=SEND;
            SEND: if (i_request_ready) next_state=WAIT_REPLY;
            WAIT_REPLY: if (i_response_valid) next_state=SCAN;
            default: next_state=SCAN;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            reg_delivered<=0;cnt_events<=0;cnt_identity<=0;reg_key<=0;flag_press<=0;flag_fault<=0;reg_request<=0;
            for (index=0;index<32;index=index+1) mem_note_id[index]<=0;
        end else begin
            case (reg_state)
                SCAN: if (next_state==PREPARE) flag_press<=i_pressed[reg_key];
                    else reg_key<=reg_key+1'b1;
                PREPARE: begin
                    reg_request<=0;
                    reg_request[391:360]<=cnt_events;
                    if (flag_press) begin
                        cnt_identity<=cnt_identity+1'b1;
                        mem_note_id[reg_key]<=32'h80000000 | (cnt_identity+1'b1);
                        reg_request[335:328]<={6'd0,reg_mapping[33:32]};
                        reg_request[327:320]<=8'ha4;
                        reg_request[31:0]<=32'h80000000 | (cnt_identity+1'b1);
                        reg_request[63:32]<=reg_mapping[31:0];
                        reg_request[95:64]<=i_velocity_enabled ? {5'd0,wire_velocity_gain,19'd0} : 32'd67108864;
                        reg_request[127:96]<=33554432;
                        // Host mapping is latched before dispatch; Note-Off keeps the original identity.
                        reg_request[159:128]<={1'b1,17'd0,wire_note_velocity,reg_mapping[40:34]};
                    end else begin
                        reg_request[327:320]<=8'ha5;
                        reg_request[31:0]<=mem_note_id[reg_key];
                    end
                end
                WAIT_REPLY: if (i_response_valid) begin
                    if (i_response[135:128]!=0 || i_response[71:64]!=0) flag_fault<=1;
                    else begin reg_delivered[reg_key]<=flag_press;cnt_events<=cnt_events+1'b1;end
                    reg_key<=reg_key+1'b1;
                end
                default: reg_key<=reg_key;
            endcase
        end
    end
endmodule
