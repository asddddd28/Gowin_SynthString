`timescale 1ns / 1ps
// DashboardTelemetry / 显示遥测：只观察本 FPGA 已发出的串口，不驱动控制通路。
// Contract: ../spec/DashboardTelemetry_spec.md. Clock: pixel; reset: active low.
// Line length, delimiter and numeric fields are checked. CRC is trusted at this
// internal observer boundary; this module is NOT an external command parser.
module DashboardTelemetry #(
    parameter integer C_CLOCK_HZ = 73333333
)(
    input i_clk, input i_rstn, input [7:0] i_byte, input i_valid, input i_error,
    output [383:0] o_keys, output [79:0] o_encoders, output [4:0] o_joystick,
    output [23:0] o_touch, output [1:0] o_touch_ok,
    output [31:0] o_pressed, output o_configured, output [3:0] o_effect,
    output o_live, output o_key_sample, output [11:0] o_key_value
);
    reg [7:0] reg_line [0:99]; // complete line staging, stable until LF commit
    reg [6:0] cnt_length;
    reg flag_overflow;
    reg [383:0] reg_keys_o;
    reg [79:0] reg_encoders_o;
    reg [4:0] reg_joystick_o;
    reg [23:0] reg_touch_o;
    reg [1:0] reg_touch_ok_o;
    reg [31:0] reg_pressed_o;
    reg flag_configured_o;
    reg [3:0] reg_effect_o;
    reg [26:0] cnt_age;
    reg flag_key_sample_o;
    reg [11:0] reg_key_value_o;
    reg flag_key_commit;
    reg [4:0] reg_key_address;
    reg [11:0] reg_key_pending;
    integer idx_reset;
    genvar idx_key;
    wire [5:0] dec_key_number = (reg_line[1]-8'd48)*6'd10 + (reg_line[2]-8'd48);
    wire [11:0] dec_key_value = {hex_value(reg_line[4]),hex_value(reg_line[5]),hex_value(reg_line[6])};
    assign o_keys=reg_keys_o;
    assign o_encoders=reg_encoders_o;
    assign o_joystick=reg_joystick_o;
    assign o_touch=reg_touch_o;
    assign o_touch_ok=reg_touch_ok_o;
    assign o_pressed=reg_pressed_o;
    assign o_configured=flag_configured_o;
    assign o_effect=reg_effect_o;
    assign o_live=(cnt_age < C_CLOCK_HZ);
    assign o_key_sample=flag_key_sample_o;
    assign o_key_value=reg_key_value_o;

    function [3:0] hex_value;
        input [7:0] character;
        begin
            if(character >= "0" && character <= "9") hex_value=character-8'd48;
            else hex_value=character-8'd55;
        end
    endfunction
    function is_hex;
        input [7:0] character;
        begin is_hex=(character >= "0" && character <= "9") || (character >= "A" && character <= "F"); end
    endfunction

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            cnt_length<=0; flag_overflow<=0;
            reg_encoders_o<=0; reg_joystick_o<=5'b10101;
            reg_touch_o<=0; reg_touch_ok_o<=0; reg_pressed_o<=0;
            flag_configured_o<=0; reg_effect_o<=0;
            cnt_age<=C_CLOCK_HZ; flag_key_sample_o<=0; reg_key_value_o<=0;
            flag_key_commit<=0; reg_key_address<=0; reg_key_pending<=0;
            for(idx_reset=0;idx_reset<100;idx_reset=idx_reset+1) reg_line[idx_reset]<=0;
        end else begin
            flag_key_sample_o<=0;
            flag_key_commit<=0;
            if(cnt_age<C_CLOCK_HZ) cnt_age<=cnt_age+1'b1;
            if(i_error) begin cnt_length<=0; flag_overflow<=1; end
            else if(i_valid) begin
                if(i_byte==8'd10) begin
                    cnt_length<=0; flag_overflow<=0;
                    if(!flag_overflow) begin
                        if(cnt_length==8 && reg_line[0]=="K" && reg_line[3]==":" && reg_line[7]==13
                            && reg_line[1]>="0" && reg_line[1]<="3" && reg_line[2]>="0" && reg_line[2]<="9"
                            && dec_key_number>=1 && dec_key_number<=32
                            && is_hex(reg_line[4]) && is_hex(reg_line[5]) && is_hex(reg_line[6])) begin
                            flag_key_commit<=1;
                            reg_key_address<=dec_key_number-1'b1;
                            reg_key_pending<=dec_key_value;
                            cnt_age<=0;
                            if(dec_key_number==1) begin flag_key_sample_o<=1; reg_key_value_o<=dec_key_value; end
                        end
                        if(cnt_length==33 && reg_line[0]=="E" && reg_line[1]>="1" && reg_line[1]<="5"
                            && reg_line[9]=="Q" && reg_line[32]==13
                            && is_hex(reg_line[10]) && is_hex(reg_line[11]) && is_hex(reg_line[12]) && is_hex(reg_line[13])) begin
                            reg_encoders_o[(reg_line[1]-8'd49)*16 +: 16] <=
                                {hex_value(reg_line[10]),hex_value(reg_line[11]),hex_value(reg_line[12]),hex_value(reg_line[13])};
                            cnt_age<=0;
                        end
                        if(cnt_length==20 && reg_line[0]=="J" && reg_line[10]=="F" && reg_line[19]==13
                            && (reg_line[11]=="0" || reg_line[11]=="1") && is_hex(reg_line[12])) begin
                            reg_joystick_o<={reg_line[11][0],hex_value(reg_line[12])}; cnt_age<=0;
                        end
                        if(cnt_length==22 && reg_line[0]=="@" && reg_line[19]=="*"
                            && is_hex(reg_line[6]) && is_hex(reg_line[7])
                            && is_hex(reg_line[11]) && is_hex(reg_line[12]) && is_hex(reg_line[13]) && is_hex(reg_line[14])
                            && is_hex(reg_line[15]) && is_hex(reg_line[16]) && is_hex(reg_line[17]) && is_hex(reg_line[18])) begin
                            flag_configured_o<=reg_line[6]=="1";
                            reg_effect_o<=hex_value(reg_line[7]);
                            reg_pressed_o<={hex_value(reg_line[11]),hex_value(reg_line[12]),hex_value(reg_line[13]),hex_value(reg_line[14]),
                                hex_value(reg_line[15]),hex_value(reg_line[16]),hex_value(reg_line[17]),hex_value(reg_line[18])};
                            cnt_age<=0;
                        end
                        if(cnt_length==99 && reg_line[0]=="T" && (reg_line[1]=="1" || reg_line[1]=="2")
                            && reg_line[95]=="*" && reg_line[98]==13
                            && is_hex(reg_line[11]) && is_hex(reg_line[12]) && is_hex(reg_line[13]) && is_hex(reg_line[14])) begin
                            // MPR121 touch mask is little endian. Transpose occurs in renderer geometry.
                            reg_touch_o[(reg_line[1]-8'd49)*12 +: 12] <=
                                {hex_value(reg_line[14]),hex_value(reg_line[11]),hex_value(reg_line[12])};
                            reg_touch_ok_o[reg_line[1]-8'd49] <= reg_line[8]=="0" && reg_line[9]=="0"
                                && reg_line[13]=="0" && reg_line[15]=="0" && reg_line[16]=="0";
                            cnt_age<=0;
                        end
                    end
                end else if(cnt_length<100 && !flag_overflow) begin
                    reg_line[cnt_length]<=i_byte; cnt_length<=cnt_length+1'b1;
                end else flag_overflow<=1;
            end
        end
    end
    // Register the parsed address before the 32-way write enables. This removes
    // decimal conversion and variable packed-write selection from one cycle.
    generate
        for(idx_key=0;idx_key<32;idx_key=idx_key+1) begin: gen_key_bank
            always @(posedge i_clk or negedge i_rstn) begin
                if(!i_rstn) reg_keys_o[idx_key*12 +: 12]<=0;
                else if(flag_key_commit && reg_key_address==idx_key)
                    reg_keys_o[idx_key*12 +: 12]<=reg_key_pending;
            end
        end
    endgenerate
endmodule
