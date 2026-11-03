`timescale 1ns/1ps
// ADC threshold crossing timestamps / ADC阈值穿越时刻插值。
// Contract: keyboard/VELOCITY_PRECISION.md; spec/KeyboardCrossingTime_spec.md.
module KeyboardCrossingTime(
    input i_clk,input i_rstn,input i_start,
    input [4:0] i_key,input [11:0] i_raw,input [31:0] i_time,
    input [11:0] i_release,input [11:0] i_press,input i_falling,
    output o_done,output [31:0] o_release_time,output [31:0] o_press_time,
    output [31:0] o_interval,output o_release_estimated,output o_press_estimated
);
    localparam IDLE=0,READ=1,DELTA=2,SELECT=3,MULTIPLY=4,LOAD=5,DIVIDE=6,STORE=7,NEXT=8,DONE=9;
    reg [3:0] reg_state,next_state;
    (* syn_ramstyle="block_ram" *) reg [43:0] mem_history [0:31];
    reg [31:0] reg_valid;
    reg [43:0] reg_history;
    reg [4:0] reg_key;
    reg [11:0] reg_raw,reg_release,reg_press;
    reg [31:0] reg_time,reg_interval,reg_release_time,reg_press_time;
    reg [11:0] reg_distance,reg_overshoot;
    reg flag_falling,flag_previous,flag_motion,flag_threshold,flag_release_estimated,flag_press_estimated,flag_interpolate;
    reg [27:0] reg_product,reg_numerator,reg_quotient;
    reg [12:0] reg_remainder;
    reg [4:0] cnt_bit;
    wire [11:0] wire_threshold=flag_threshold ? reg_press : reg_release;
    wire [12:0] wire_shifted={reg_remainder[11:0],reg_numerator[27]};
    wire [12:0] wire_divisor={1'b0,reg_distance};
    wire flag_subtract=wire_shifted>=wire_divisor;
    wire flag_bracket=flag_falling ? (reg_history[11:0]>=wire_threshold && reg_raw<=wire_threshold) : (reg_history[11:0]<=wire_threshold && reg_raw>=wire_threshold);
    assign o_done=reg_state==DONE;
    assign o_release_time=reg_release_time;
    assign o_press_time=reg_press_time;
    assign o_interval=reg_interval;
    assign o_release_estimated=flag_release_estimated;
    assign o_press_estimated=flag_press_estimated;
    always @(posedge i_clk) begin
        if(reg_state==READ) reg_history<=mem_history[reg_key];
        if(reg_state==DELTA) mem_history[reg_key]<={reg_time,reg_raw};
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) reg_state<=IDLE;else reg_state<=next_state;
    end
    always @(*) begin
        next_state=reg_state;
        case(reg_state)
            IDLE: if(i_start) next_state=READ;
            READ: next_state=DELTA;
            DELTA: next_state=SELECT;
            SELECT: next_state=MULTIPLY;
            MULTIPLY: next_state=flag_interpolate ? LOAD : NEXT;
            LOAD: next_state=DIVIDE;
            DIVIDE: if(cnt_bit==27) next_state=STORE;
            STORE: next_state=NEXT;
            NEXT: next_state=flag_threshold ? DONE : SELECT;
            DONE: next_state=IDLE;
            default: next_state=IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_valid<=0;reg_key<=0;reg_raw<=0;reg_release<=0;reg_press<=0;reg_time<=0;reg_interval<=0;
            reg_release_time<=0;reg_press_time<=0;reg_distance<=0;reg_overshoot<=0;
            flag_falling<=0;flag_previous<=0;flag_motion<=0;flag_threshold<=0;
            flag_release_estimated<=0;flag_press_estimated<=0;flag_interpolate<=0;
            reg_product<=0;reg_numerator<=0;reg_quotient<=0;reg_remainder<=0;cnt_bit<=0;
        end else case(reg_state)
            IDLE: if(i_start) begin
                reg_key<=i_key;reg_raw<=i_raw;reg_time<=i_time;reg_release<=i_release;reg_press<=i_press;flag_falling<=i_falling;
                flag_previous<=reg_valid[i_key];flag_threshold<=0;flag_release_estimated<=0;flag_press_estimated<=0;
                reg_release_time<=i_time;reg_press_time<=i_time;
            end
            DELTA: begin
                reg_valid[reg_key]<=1;reg_interval<=reg_time-reg_history[43:12];
                reg_distance<=flag_falling ? reg_history[11:0]-reg_raw : reg_raw-reg_history[11:0];
                flag_motion<=flag_falling ? reg_history[11:0]>reg_raw : reg_raw>reg_history[11:0];
            end
            SELECT: begin
                flag_interpolate<=flag_previous && flag_motion && flag_bracket && reg_interval!=0 && reg_interval<=65535;
                reg_overshoot<=flag_falling ? wire_threshold-reg_raw : reg_raw-wire_threshold;
            end
            MULTIPLY: reg_product<=reg_interval[15:0]*reg_overshoot;
            LOAD: begin reg_numerator<=reg_product;reg_quotient<=0;reg_remainder<=0;cnt_bit<=0;end
            DIVIDE: begin
                reg_numerator<={reg_numerator[26:0],1'b0};
                reg_quotient<={reg_quotient[26:0],flag_subtract};
                reg_remainder<=flag_subtract ? wire_shifted-wire_divisor : wire_shifted;
                cnt_bit<=cnt_bit+1'b1;
            end
            STORE: begin
                if(flag_threshold) begin reg_press_time<=reg_time-{4'd0,reg_quotient};flag_press_estimated<=1;end
                else begin reg_release_time<=reg_time-{4'd0,reg_quotient};flag_release_estimated<=1;end
            end
            NEXT: flag_threshold<=1;
            default: begin end
        endcase
    end
endmodule
