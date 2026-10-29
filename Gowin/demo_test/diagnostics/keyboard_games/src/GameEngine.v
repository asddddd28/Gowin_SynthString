`timescale 1ns / 1ps
// Autonomous 4x8 games. All timing and decisions stay inside the FPGA.
// 板上游戏引擎：50Hz帧节拍、校准后的按键边沿；串口断开不影响运行。
module GameEngine (
    input i_clk,
    input i_rstn,
    input i_start,
    input i_stop,
    input [1:0] i_game,
    input i_frame_tick,
    input [31:0] i_press,
    input [31:0] i_pressed,
    output [63:0] o_pixels,
    output [127:0] o_status
);
localparam [2:0] ST_IDLE=0, ST_COUNTDOWN=1, ST_RUNNING=2, ST_FINISHED=3, ST_WIN=4;
localparam [31:0] C_CONTROLS=32'hE0400000;
reg [2:0] state_current, state_next;
reg [1:0] reg_game;
reg [7:0] reg_seconds, reg_reason, reg_misses, reg_epoch;
reg [15:0] reg_score, reg_random;
reg [5:0] cnt_second;
reg [6:0] cnt_result;
reg [4:0] mem_body[0:31];
reg [31:0] reg_occupied;
reg [5:0] reg_length, cnt_move, reg_move_limit;
reg [1:0] reg_direction, reg_turn;
reg flag_turn;
reg [4:0] reg_apple, reg_probe;
reg flag_apple, flag_spawn;
reg [1:0] mem_target[0:31];
reg [6:0] mem_life[0:31];
reg [4:0] cnt_spawn;
reg [2:0] mem_note[0:3];
reg [6:0] cnt_piano;
reg [63:0] reg_pixels_o;
reg [1:0] enc_request, enc_direction;
reg flag_request, flag_boundary;
reg [4:0] enc_head;
wire [15:0] enc_points;
wire [7:0] enc_expired;
wire [9:0] net_points_tree[1:63];
wire [5:0] net_expiry_tree[1:63];
reg [6:0] enc_piano_limit;
wire flag_move, flag_grow, flag_self, flag_blocked, flag_mole_end;
wire flag_piano_press, flag_piano_correct, flag_piano_wrong, flag_piano_timeout;
wire [7:0] enc_bottom_mask;
wire [2:0] enc_new_note;
wire [1:0] enc_new_color;
integer init_index, pixel_index;
genvar node_index;

assign o_pixels=reg_pixels_o;
assign o_status={{6'b0,reg_game},{5'b0,state_current},reg_seconds,reg_reason,
                 reg_score,reg_misses,reg_epoch,reg_pixels_o};
assign flag_move=i_frame_tick && cnt_move==reg_move_limit-1'b1;
assign flag_grow=flag_apple && enc_head==reg_apple;
assign flag_self=reg_occupied[enc_head] && (flag_grow || enc_head!=mem_body[reg_length-1'b1]);
assign flag_blocked=flag_boundary || C_CONTROLS[enc_head];
assign flag_mole_end=i_frame_tick && cnt_second==49 && reg_seconds==1;
assign enc_bottom_mask=8'b1<<mem_note[3];
assign flag_piano_press=|i_press[31:24];
assign flag_piano_correct=i_press[31:24]==enc_bottom_mask;
assign flag_piano_wrong=flag_piano_press && !flag_piano_correct;
assign flag_piano_timeout=i_frame_tick && cnt_piano>=enc_piano_limit-1'b1 && !flag_piano_correct;
assign enc_new_note=reg_random[2:0]==mem_note[0] ? reg_random[2:0]+3'd1 : reg_random[2:0];
assign enc_new_color=reg_random[1:0]==0 ? 2'd1 : reg_random[1:0];
assign enc_points={6'b0,net_points_tree[1]};
assign enc_expired={2'b0,net_expiry_tree[1]};

// Balanced reduction avoids a32-key serial adder chain on the score path.
generate
    for(node_index=0;node_index<32;node_index=node_index+1) begin: HitLeaves
        assign net_points_tree[32+node_index]=!i_press[node_index] ? 10'd0 :
            mem_target[node_index]==1 ? 10'd10 : mem_target[node_index]==2 ? 10'd30 :
            mem_target[node_index]==3 ? 10'd20 : 10'd0;
        assign net_expiry_tree[32+node_index]=!i_press[node_index] && mem_target[node_index]!=0 && mem_life[node_index]==1;
    end
    for(node_index=1;node_index<32;node_index=node_index+1) begin: HitBranches
        assign net_points_tree[node_index]=net_points_tree[node_index*2]+net_points_tree[node_index*2+1];
        assign net_expiry_tree[node_index]=net_expiry_tree[node_index*2]+net_expiry_tree[node_index*2+1];
    end
endgenerate

// Only one legal turn may be queued per movement; direct reversal is ignored.
always @(*) begin
    flag_request=0;
    enc_request=reg_direction;
    if(i_press[22]) begin flag_request=1; enc_request=0; end
    else if(i_press[30]) begin flag_request=1; enc_request=1; end
    else if(i_press[29]) begin flag_request=1; enc_request=2; end
    else if(i_press[31]) begin flag_request=1; enc_request=3; end
    if(enc_request==(reg_direction^2'b01)) begin flag_request=0; end
    enc_direction=flag_turn ? reg_turn : reg_direction;
    flag_boundary=0;
    enc_head=mem_body[0];
    case(enc_direction)
        0:begin enc_head=mem_body[0]-5'd8; flag_boundary=mem_body[0][4:3]==0; end
        1:begin enc_head=mem_body[0]+5'd8; flag_boundary=mem_body[0][4:3]==3; end
        2:begin enc_head=mem_body[0]-5'd1; flag_boundary=mem_body[0][2:0]==0; end
        3:begin enc_head=mem_body[0]+5'd1; flag_boundary=mem_body[0][2:0]==7; end
    endcase
end

// Integer frame deadline, with a500ms floor after130 successful notes.
always @(*) begin
    enc_piano_limit=reg_score>=130 ? 7'd25 : 7'd90-reg_score[7:1];
end

always @(*) begin
    state_next=state_current;
    case(state_current)
        ST_IDLE:begin end
        ST_COUNTDOWN:begin
            if(i_frame_tick && cnt_second==49 && reg_seconds==1) begin state_next=ST_RUNNING; end
        end
        ST_RUNNING:begin
            if(reg_game==1 && flag_move) begin
                if(flag_blocked || flag_self) begin state_next=ST_FINISHED; end
                else if(flag_grow && reg_length==27) begin state_next=ST_WIN; end
            end
            if(reg_game==2 && flag_mole_end) begin state_next=ST_FINISHED; end
            if(reg_game==3 && (flag_piano_wrong || flag_piano_timeout)) begin state_next=ST_FINISHED; end
        end
        ST_FINISHED:begin end
        ST_WIN:begin end
        default:begin state_next=ST_IDLE; end
    endcase
    if(i_start) begin state_next=ST_COUNTDOWN; end
    if(i_stop) begin state_next=ST_IDLE; end
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin state_current<=ST_IDLE; end
    else begin state_current<=state_next; end
end

// Free-running PRNG affects spawn positions only, never game timing or scoring.
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin reg_random<=16'hACE1; end
    else begin reg_random<={reg_random[14:0],reg_random[15]^reg_random[13]^reg_random[12]^reg_random[10]}; end
end

always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        reg_game<=0; reg_seconds<=0; reg_reason<=0; reg_misses<=0; reg_epoch<=0; reg_score<=0;
        cnt_second<=0; cnt_result<=0; reg_occupied<=0; reg_length<=3;
        cnt_move<=0; reg_move_limit<=25; reg_direction<=3; reg_turn<=3; flag_turn<=0;
        reg_apple<=0; reg_probe<=0; flag_apple<=0; flag_spawn<=0; cnt_spawn<=0; cnt_piano<=0;
        for(init_index=0;init_index<32;init_index=init_index+1) begin
            mem_body[init_index]<=0; mem_target[init_index]<=0; mem_life[init_index]<=0;
        end
        for(init_index=0;init_index<4;init_index=init_index+1) begin mem_note[init_index]<=0; end
    end else if(i_stop) begin
        reg_reason<=5; flag_spawn<=0;
    end else if(i_start) begin
        reg_game<=i_game; reg_seconds<=3; reg_reason<=0; reg_misses<=0; reg_epoch<=reg_epoch+1'b1; reg_score<=0;
        cnt_second<=0; cnt_result<=0; cnt_move<=0; cnt_piano<=0; cnt_spawn<=0;
        reg_move_limit<=25; reg_length<=3; reg_direction<=3; reg_turn<=3; flag_turn<=0;
        reg_occupied<=32'h00000700; flag_apple<=0; flag_spawn<=i_game==1; reg_probe<=reg_random[4:0];
        for(init_index=0;init_index<32;init_index=init_index+1) begin
            mem_body[init_index]<=0; mem_target[init_index]<=0; mem_life[init_index]<=0;
        end
        mem_body[0]<=10; mem_body[1]<=9; mem_body[2]<=8;
        mem_note[0]<=reg_random[2:0]; mem_note[1]<=reg_random[2:0]+3'd3;
        mem_note[2]<=reg_random[2:0]+3'd5; mem_note[3]<=reg_random[2:0]+3'd2;
    end else begin
        if(state_current==ST_COUNTDOWN && i_frame_tick) begin
            if(cnt_second==49) begin
                cnt_second<=0;
                if(reg_seconds==1) begin
                    reg_seconds<=reg_game==2 ? 8'd60 : 8'd0;
                    if(reg_game==2) begin flag_spawn<=1; reg_probe<=reg_random[4:0]; end
                end else begin reg_seconds<=reg_seconds-1'b1; end
            end else begin cnt_second<=cnt_second+1'b1; end
        end
        if(state_current==ST_RUNNING) begin
            if(i_frame_tick) begin
                if(cnt_second==49) begin
                    cnt_second<=0;
                    if(reg_game==2) begin reg_seconds<=reg_seconds-1'b1; end
                    else if(reg_seconds!=255) begin reg_seconds<=reg_seconds+1'b1; end
                end else begin cnt_second<=cnt_second+1'b1; end
            end
            if(reg_game==1) begin
                if(flag_move) begin
                    cnt_move<=0; flag_turn<=0; reg_direction<=enc_direction;
                    // A direction arriving on this exact edge queues for the next step.
                    if(!flag_turn && flag_request) begin reg_turn<=enc_request; flag_turn<=1; end
                    if(flag_blocked) begin reg_reason<=1; end
                    else if(flag_self) begin reg_reason<=2; end
                    else begin
                        for(init_index=31;init_index>0;init_index=init_index-1) begin mem_body[init_index]<=mem_body[init_index-1]; end
                        mem_body[0]<=enc_head;
                        if(flag_grow) begin
                            reg_occupied<=reg_occupied | (32'b1<<enc_head);
                            reg_length<=reg_length+1'b1; reg_score<=reg_score+16'd10;
                            flag_apple<=0; flag_spawn<=reg_length!=27; reg_probe<=reg_random[4:0];
                            if(reg_move_limit>9) begin reg_move_limit<=reg_move_limit-1'b1; end
                            if(reg_length==27) begin reg_reason<=6; end
                        end else begin
                            reg_occupied<=(reg_occupied & ~(32'b1<<mem_body[reg_length-1'b1])) | (32'b1<<enc_head);
                        end
                    end
                end else begin
                    if(i_frame_tick) begin cnt_move<=cnt_move+1'b1; end
                    if(!flag_turn && flag_request) begin reg_turn<=enc_request; flag_turn<=1; end
                end
            end
            if(reg_game==2 && !flag_mole_end) begin
                reg_score<=reg_score+enc_points;
                if(i_frame_tick) begin
                    reg_misses<=reg_misses+enc_expired;
                    if(cnt_spawn==29) begin cnt_spawn<=0; flag_spawn<=1; reg_probe<=reg_random[4:0]; end
                    else begin cnt_spawn<=cnt_spawn+1'b1; end
                end
                for(init_index=0;init_index<32;init_index=init_index+1) begin
                    if(i_press[init_index]) begin mem_target[init_index]<=0; mem_life[init_index]<=0; end
                    else if(i_frame_tick && mem_target[init_index]!=0) begin
                        mem_life[init_index]<=mem_life[init_index]-1'b1;
                        if(mem_life[init_index]==1) begin mem_target[init_index]<=0; end
                    end
                end
            end
            if(reg_game==3) begin
                if(flag_piano_wrong) begin reg_reason<=3; end
                else if(flag_piano_correct) begin
                    reg_score<=reg_score+1'b1; cnt_piano<=0;
                    mem_note[3]<=mem_note[2]; mem_note[2]<=mem_note[1]; mem_note[1]<=mem_note[0]; mem_note[0]<=enc_new_note;
                end else if(flag_piano_timeout) begin reg_reason<=4; end
                else if(i_frame_tick) begin cnt_piano<=cnt_piano+1'b1; end
            end
        end
        // Probe one cell per clock, avoiding a long combinational search path.
        if(flag_spawn && (state_current==ST_COUNTDOWN || state_current==ST_RUNNING)) begin
            if(reg_game==1) begin
                if(!reg_occupied[reg_probe] && !C_CONTROLS[reg_probe]) begin
                    reg_apple<=reg_probe; flag_apple<=1; flag_spawn<=0;
                end else begin reg_probe<=reg_probe+1'b1; end
            end else if(reg_game==2 && state_current==ST_RUNNING && !flag_mole_end) begin
                if(mem_target[reg_probe]==0 && !i_pressed[reg_probe]) begin
                    mem_target[reg_probe]<=enc_new_color;
                    case(enc_new_color)
                        1:mem_life[reg_probe]<=80;
                        2:mem_life[reg_probe]<=45;
                        default:mem_life[reg_probe]<=60;
                    endcase
                    flag_spawn<=0;
                end else begin reg_probe<=reg_probe+1'b1; end
            end
        end
        if(state_current==ST_FINISHED || state_current==ST_WIN) begin
            if(i_frame_tick && cnt_result<100) begin cnt_result<=cnt_result+1'b1; end
        end else begin cnt_result<=0; end
    end
end

always @(*) begin
    reg_pixels_o=0;
    if(state_current==ST_COUNTDOWN || state_current==ST_RUNNING) begin
        for(pixel_index=0;pixel_index<32;pixel_index=pixel_index+1) begin
            case(reg_game)
                1:begin
                    if(C_CONTROLS[pixel_index]) begin reg_pixels_o[pixel_index*2+:2]=3; end
                    else if(reg_occupied[pixel_index]) begin reg_pixels_o[pixel_index*2+:2]=1; end
                    else if(flag_apple && reg_apple==pixel_index) begin reg_pixels_o[pixel_index*2+:2]=2; end
                end
                2:begin reg_pixels_o[pixel_index*2+:2]=mem_target[pixel_index]; end
                3:begin
                    if(mem_note[pixel_index/8]==pixel_index%8) begin reg_pixels_o[pixel_index*2+:2]=pixel_index>=24 ? 1 : 3; end
                end
                default:begin end
            endcase
        end
    end else if((state_current==ST_FINISHED || state_current==ST_WIN) && cnt_result<100 && cnt_result%20<10) begin
        reg_pixels_o=(state_current==ST_WIN || reg_reason==0) ? 64'h5555555555555555 : 64'hAAAAAAAAAAAAAAAA;
    end
end
endmodule
