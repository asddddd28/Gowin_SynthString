`timescale 1ns / 1ps
// WavetableRom: six-cycle periodic interpolation, preserving elementary shapes.
// 奇偶点分存，使每个自定义 RAM 只有一个读口和一个写口。
// 邻点在同一活动银行内回绕；整数相位点与原表一致，RAM 不做复位。
module WavetableRom(
    input i_clk,
    input i_rstn,
    input [31:0] i_phase,
    input [2:0] i_wave,
    input i_table_write,
    input [10:0] i_table_address,
    input [15:0] i_table_data,
    input i_table_bank,
    input i_table_available,
    output signed [17:0] o_sample
);
    reg signed [17:0] reg_sine [0:1023];
    reg signed [17:0] reg_sine_sample,reg_sine_next,reg_shape;
    reg signed [15:0] reg_even [0:1023];
    reg signed [15:0] reg_odd [0:1023];
    reg signed [15:0] reg_even_sample,reg_odd_sample;
    reg signed [17:0] reg_normal_first,reg_normal_second;
    reg signed [17:0] reg_custom_first,reg_custom_second;
    reg signed [17:0] reg_selected_first,reg_selected_second;
    reg [15:0] reg_fraction,reg_fraction_delayed,reg_selected_fraction;
    reg flag_sine,flag_custom,flag_custom_delayed,flag_odd;
    wire [9:0] enc_next_address;
    wire [8:0] enc_even_index;
    wire [17:0] enc_triangle;
    assign enc_next_address=i_phase[31:22]+10'd1;
    // 奇数起点的偶邻点位于下一对，九位加法只在同一银行内回绕。
    assign enc_even_index=i_phase[31:23]+{8'd0,i_phase[22]};
    assign enc_triangle=i_phase[30] ? ~i_phase[29:12] : i_phase[29:12];
    initial $readmemb("rtl/synth/sine.mem",reg_sine);
    // 逻辑地址最低位选奇偶 RAM，其余十位包含银行和周期内索引。
    // 上传只写不活动银行；不定义活动银行同地址读写时的音频结果。
    always @(posedge i_clk) begin
        if(i_table_write&&!i_table_address[0]) reg_even[i_table_address[10:1]]<=i_table_data;
        reg_even_sample<=reg_even[{i_table_bank,enc_even_index}];
    end
    always @(posedge i_clk) begin
        if(i_table_write&&i_table_address[0]) reg_odd[i_table_address[10:1]]<=i_table_data;
        reg_odd_sample<=reg_odd[{i_table_bank,i_phase[31:23]}];
    end
    // 同拍保存奇偶选择，下一拍恢复逻辑起点和邻点顺序。
    always @(posedge i_clk) begin
        reg_sine_sample<=reg_sine[i_phase[31:22]];
        reg_sine_next<=reg_sine[enc_next_address];
        flag_sine<=(i_wave==0)||(i_wave==4&&!i_table_available);
        flag_custom<=(i_wave==4)&&i_table_available;
        flag_odd<=i_phase[22];
        reg_fraction<=((i_wave==0)||(i_wave==4)) ? i_phase[21:6] : 16'd0;
        case(i_wave)
            3'd0: begin reg_shape<=0;end
            3'd1: begin reg_shape<=i_phase[31] ? -18'sd131071 : 18'sd131071;end
            3'd2: begin reg_shape<={~i_phase[31],i_phase[30:14]};end
            default: begin reg_shape<=i_phase[31] ? -$signed({1'b0,enc_triangle[17:1]}) : $signed({1'b0,enc_triangle[17:1]});end
        endcase
    end
    // 第二区间先准备基础波形，避免三个波形来源形成长组合路径。
    always @(posedge i_clk) begin
        reg_normal_first<=flag_sine ? reg_sine_sample : reg_shape;
        reg_normal_second<=flag_sine ? reg_sine_next : reg_shape;
        reg_custom_first<=flag_odd ? {reg_odd_sample,2'b00} : {reg_even_sample,2'b00};
        reg_custom_second<=flag_odd ? {reg_even_sample,2'b00} : {reg_odd_sample,2'b00};
        flag_custom_delayed<=flag_custom;
        reg_fraction_delayed<=reg_fraction;
    end
    // 第三区间只在基础样值和自定义样值之间二选一，并对齐小数。
    always @(posedge i_clk) begin
        reg_selected_first<=flag_custom_delayed ? reg_custom_first : reg_normal_first;
        reg_selected_second<=flag_custom_delayed ? reg_custom_second : reg_normal_second;
        reg_selected_fraction<=reg_fraction_delayed;
    end
    WavetableInterpolator Interpolate_Inst(
        .i_clk(i_clk),.i_rstn(i_rstn),.i_first(reg_selected_first),
        .i_second(reg_selected_second),.i_fraction(reg_selected_fraction),.o_sample(o_sample)
    );
endmodule
