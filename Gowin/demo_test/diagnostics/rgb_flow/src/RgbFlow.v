`timescale 1ns / 1ps
// RgbFlow: four-row, left-to-right color comet for the keyboard LED chain.
// 键盘彩色流水灯：50MHz，32颗GRB灯珠，四行同步向右移动。
module RgbFlow #(
	parameter integer C_FRAME_CYCLES = 1000000 // 相邻帧起点间隔，默认20ms
)(
	input i_clk,                             // 板载50MHz时钟
	input i_rstn,                            // 异步低有效复位
	output o_data                            // 接至首颗灯珠DIN
);
localparam [3:0] ST_WAIT = 4'd0, ST_DISTANCE = 4'd1,
	ST_WEIGHT = 4'd2, ST_COLOR = 4'd3, ST_SCALE = 4'd4,
	ST_LOAD = 4'd5, ST_SEND = 4'd6, ST_NEXT = 4'd7, ST_DONE = 4'd8;
reg [1:0] reg_reset_release;                // 将复位释放同步到主时钟
wire flag_reset_n;                        // 驱动所有灯效状态的内部复位
reg [3:0] state_current, state_next;       // 像素准备与位发送阶段
reg [31:0] cnt_frame;                     // 周期帧调度计数
reg [4:0] cnt_pixel;                      // 当前串联灯珠编号，从零开始
reg [4:0] cnt_bit;                        // 当前像素已发送位数
reg [5:0] cnt_slot;                       // 一个灯珠数据位内的时钟数
reg [6:0] reg_motion;                     // 八列乘以十六级子位置
reg [7:0] reg_hue;                        // 六段色环，每段三十二级
reg [2:0] reg_distance;                   // 当前列到光带头部的环形距离
reg [5:0] reg_weight;                     // 拖尾亮度系数，零至三十二
reg [5:0] reg_red, reg_green, reg_blue;    // 当前帧色环分量
reg [11:0] reg_red_product;               // 红色乘以拖尾亮度
reg [11:0] reg_green_product;             // 绿色乘以拖尾亮度
reg [11:0] reg_blue_product;              // 蓝色乘以拖尾亮度
reg [23:0] reg_shift;                     // 按GRB排列并从最高位发送
reg reg_data_o;                          // 注册后的单线脉冲输出
wire flag_frame_end;                     // 新帧调度时刻
wire flag_slot_end;                      // 当前位已满63拍
wire flag_word_end;                      // 当前位为像素的末位
wire flag_chain_end;                     // 当前像素为灯串末端

assign flag_reset_n = reg_reset_release[1];
assign flag_frame_end = cnt_frame == C_FRAME_CYCLES - 1;
assign flag_slot_end = cnt_slot == 6'd62;
assign flag_word_end = cnt_bit == 5'd23;
assign flag_chain_end = cnt_pixel == 5'd31;
assign o_data = reg_data_o;

// 复位立即关闭数据脉冲；解除时留两拍同步裕量。
always@(posedge i_clk or negedge i_rstn)begin
	if(!i_rstn)begin
		reg_reset_release <= 2'b00;
	end else begin
		reg_reset_release <= {reg_reset_release[0], 1'b1};
	end
end

// 帧调度独立于像素发送，保证正常配置下刷新间隔恒定。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin
		cnt_frame <= 32'd0;
	end else if(flag_frame_end)begin
		cnt_frame <= 32'd0;
	end else begin
		cnt_frame <= cnt_frame + 1'b1;
	end
end

// 每个像素先计算亮度和颜色，随后完整发送二十四位。
always@(*)begin
	state_next = state_current;
	case(state_current)
		ST_WAIT:begin
			if(flag_frame_end)begin state_next = ST_DISTANCE; end
		end
		ST_DISTANCE:begin state_next = ST_WEIGHT; end
		ST_WEIGHT:begin state_next = ST_COLOR; end
		ST_COLOR:begin state_next = ST_SCALE; end
		ST_SCALE:begin state_next = ST_LOAD; end
		ST_LOAD:begin state_next = ST_SEND; end
		ST_SEND:begin
			if(flag_slot_end && flag_word_end)begin state_next = ST_NEXT; end
		end
		ST_NEXT:begin
			if(flag_chain_end)begin state_next = ST_DONE; end
			else begin state_next = ST_DISTANCE; end
		end
		ST_DONE:begin state_next = ST_WAIT; end
		default:begin state_next = ST_WAIT; end
	endcase
end

// 非法状态由组合默认分支恢复到低电平等待。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin state_current <= ST_WAIT; end
	else begin state_current <= state_next; end
end

// 一个完整灯串结束后才推进动画，避免同帧不同灯珠使用不同色相。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_motion <= 7'd0; end
	else if(state_current == ST_DONE)begin reg_motion <= reg_motion + 1'b1; end
end

// 色环在红、黄、绿、青、蓝、紫之间渐变。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_hue <= 8'd0; end
	else if(state_current == ST_DONE)begin
		if(reg_hue == 8'd191)begin reg_hue <= 8'd0; end
		else begin reg_hue <= reg_hue + 1'b1; end
	end
end

// 三位减法自然模八，使四行相同列同时点亮。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_distance <= 3'd0; end
	else if(state_current == ST_DISTANCE)begin reg_distance <= reg_motion[6:4] - cnt_pixel[2:0]; end
end

// 前沿逐渐亮起，尾部逐列衰减，跨列时保持近似连续。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_weight <= 6'd0; end
	else if(state_current == ST_WEIGHT)begin
		case(reg_distance)
			3'd0:begin reg_weight <= 6'd32 - {2'b00, reg_motion[3:0]}; end
			3'd1:begin reg_weight <= 6'd16 - {3'b000, reg_motion[3:1]}; end
			3'd2:begin reg_weight <= 6'd8 - {4'b0000, reg_motion[3:2]}; end
			3'd3:begin reg_weight <= 6'd4 - {4'b0000, reg_motion[3:2]}; end
			3'd7:begin reg_weight <= {1'b0, reg_motion[3:0], 1'b0}; end
			default:begin reg_weight <= 6'd0; end
		endcase
	end
end

// 三个通道上限均为32，便于首次接板观察。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin
		reg_red <= 6'd0; reg_green <= 6'd0; reg_blue <= 6'd0;
	end else if(state_current == ST_COLOR)begin
		case(reg_hue[7:5])
			3'd0:begin reg_red <= 6'd32; reg_green <= {1'b0, reg_hue[4:0]}; reg_blue <= 6'd0; end
			3'd1:begin reg_red <= 6'd32 - {1'b0, reg_hue[4:0]}; reg_green <= 6'd32; reg_blue <= 6'd0; end
			3'd2:begin reg_red <= 6'd0; reg_green <= 6'd32; reg_blue <= {1'b0, reg_hue[4:0]}; end
			3'd3:begin reg_red <= 6'd0; reg_green <= 6'd32 - {1'b0, reg_hue[4:0]}; reg_blue <= 6'd32; end
			3'd4:begin reg_red <= {1'b0, reg_hue[4:0]}; reg_green <= 6'd0; reg_blue <= 6'd32; end
			default:begin reg_red <= 6'd32; reg_green <= 6'd0; reg_blue <= 6'd32 - {1'b0, reg_hue[4:0]}; end
		endcase
	end
end

// 乘法结果单独寄存，下一拍除以32后装入发送移位寄存器。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_red_product <= 12'd0; end
	else if(state_current == ST_SCALE)begin reg_red_product <= reg_red * reg_weight; end
end

// 绿色缩放路径与红蓝通道保持相同延迟。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_green_product <= 12'd0; end
	else if(state_current == ST_SCALE)begin reg_green_product <= reg_green * reg_weight; end
end

// 蓝色缩放不改变前沿的空间位置。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_blue_product <= 12'd0; end
	else if(state_current == ST_SCALE)begin reg_blue_product <= reg_blue * reg_weight; end
end

// 像素间插入准备周期，但远短于灯珠复位所需的80us。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin cnt_pixel <= 5'd0; end
	else if(state_current == ST_WAIT)begin cnt_pixel <= 5'd0; end
	else if(state_current == ST_NEXT)begin cnt_pixel <= cnt_pixel + 1'b1; end
end

// 每位占63拍，即1.26us，只有发送阶段累加。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin cnt_slot <= 6'd0; end
	else if(state_current != ST_SEND || flag_slot_end)begin cnt_slot <= 6'd0; end
	else begin cnt_slot <= cnt_slot + 1'b1; end
end

// 完整二十四位后才允许切换下一颗灯。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin cnt_bit <= 5'd0; end
	else if(state_current != ST_SEND)begin cnt_bit <= 5'd0; end
	else if(flag_slot_end)begin cnt_bit <= cnt_bit + 1'b1; end
end

// 发送格式为G7..G0、R7..R0、B7..B0，保持一位期间数据不变。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_shift <= 24'd0; end
	else if(state_current == ST_LOAD)begin
		reg_shift <= {1'b0, reg_green_product[11:5], 1'b0, reg_red_product[11:5], 1'b0, reg_blue_product[11:5]};
	end else if(state_current == ST_SEND && flag_slot_end)begin
		reg_shift <= {reg_shift[22:0], 1'b0};
	end
end

// 注册输出消除组合毛刺；零高0.30us，一高0.84us，其他阶段保持低。
always@(posedge i_clk or negedge flag_reset_n)begin
	if(!flag_reset_n)begin reg_data_o <= 1'b0; end
	else if(state_current != ST_SEND)begin reg_data_o <= 1'b0; end
	else if(reg_shift[23])begin reg_data_o <= cnt_slot < 6'd42; end
	else begin reg_data_o <= cnt_slot < 6'd15; end
end
endmodule
