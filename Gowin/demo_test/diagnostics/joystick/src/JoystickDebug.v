`timescale 1ns / 1ps
// JoystickDebug：读取四路比较器和按压开关，每20ms报告原始、去抖状态。
// 输入按位编号为 XH、XL、YH、YL、SW；本模块不驱动任何摇杆信号。
module JoystickDebug #(
	parameter [31:0] C_FILTER_CYCLES = 32'd250000, // 每位独立稳定5ms
	parameter [31:0] C_REPORT_CYCLES = 32'd1000000, // 一轮遥测间隔20ms
	parameter [15:0] C_BAUD_CYCLES = 16'd434 // 50MHz对应115200近似值
)(
	input i_clk, // 板载50MHz时钟
	input i_rstn, // 板载低有效复位
	input [4:0] i_joystick, // 五路异步数字电平，SW为bit4
	output o_uart_tx // 板载DEBUG串口发送端
);
	localparam [2:0] ST_IDLE = 3'd0, ST_LATCH = 3'd1, ST_SEND = 3'd2,
		ST_ACCEPT = 3'd3, ST_WAIT = 3'd4, ST_ADVANCE = 3'd5;
	reg [1:0] reg_reset_release; // 两拍释放下游复位
	wire flag_reset_n; // 本时钟域复位
	reg [4:0] reg_meta; // 亚稳态捕获级
	reg [4:0] reg_sync; // 同步后的原始状态
	reg [4:0] reg_filtered; // 每位稳定窗口后的状态
	reg [31:0] cnt_stable [0:4]; // 每路独立计时，避免按压影响方向
	reg flag_previous_switch; // 上一拍去抖开关电平
	reg flag_armed; // 首次报告后允许累计按压，排除上电假事件
	reg [15:0] cnt_press; // 按下沿累计，65535后回绕
	reg [31:0] cnt_report; // 固定报告节拍
	reg [15:0] cnt_sequence; // 每次快照递增的序号
	reg [2:0] state_current; // 报告发送状态
	reg [2:0] state_next; // 组合计算的下一状态
	reg [4:0] cnt_character; // 一行21字节的位置
	reg [4:0] reg_raw_snapshot; // 一行锁存的原始状态
	reg [4:0] reg_filter_snapshot; // 一行锁存的去抖状态
	reg [15:0] reg_press_snapshot; // 一行锁存的按压次数
	reg [15:0] reg_sequence_snapshot; // 一行锁存的报告序号
	reg [3:0] enc_nibble; // 当前十六进制半字节
	wire [7:0] enc_hex; // 半字节对应的ASCII字符
	reg [7:0] enc_character; // UART当前字符
	wire flag_uart_busy; // UART停止位完成前为高
	wire flag_uart_start; // 提交一个待发字符
	genvar idx_input; // 独立五路去抖展开索引

	assign flag_reset_n = reg_reset_release[1];
	assign flag_uart_start = (state_current == ST_SEND);
	assign enc_hex = enc_nibble < 4'd10 ? 8'd48 + {4'd0, enc_nibble} : 8'd55 + {4'd0, enc_nibble};

	// 复位立即生效，外部释放后经过两拍才启动采样。
	always @(posedge i_clk or negedge i_rstn) begin
		if (!i_rstn) begin
			reg_reset_release <= 2'b00;
		end else begin
			reg_reset_release <= {reg_reset_release[0], 1'b1};
		end
	end

	// 异步端口只进入第一同步级；同步结果才参与计时。
	always @(posedge i_clk or negedge flag_reset_n) begin
		if (!flag_reset_n) begin
			reg_meta <= 5'b10000;
			reg_sync <= 5'b10000;
		end else begin
			reg_meta <= i_joystick;
			reg_sync <= reg_meta;
		end
	end

	// 连续稳定满阈值才翻转单个位；相同电平立即清除候选计时。
	generate
		for (idx_input = 0; idx_input < 5; idx_input = idx_input + 1) begin: gen_filter
			always @(posedge i_clk or negedge flag_reset_n) begin
				if (!flag_reset_n) begin
					reg_filtered[idx_input] <= (idx_input == 4);
					cnt_stable[idx_input] <= 32'd0;
				end else if (reg_sync[idx_input] == reg_filtered[idx_input]) begin
					cnt_stable[idx_input] <= 32'd0;
				end else if (cnt_stable[idx_input] == C_FILTER_CYCLES - 32'd1) begin
					reg_filtered[idx_input] <= reg_sync[idx_input];
					cnt_stable[idx_input] <= 32'd0;
				end else begin
					cnt_stable[idx_input] <= cnt_stable[idx_input] + 32'd1;
				end
			end
		end
	endgenerate

	// 按住不重复累计，第一次稳定报告之前的状态仅作为基线。
	always @(posedge i_clk or negedge flag_reset_n) begin
		if (!flag_reset_n) begin
			flag_previous_switch <= 1'b1;
			flag_armed <= 1'b0;
			cnt_press <= 16'd0;
		end else begin
			flag_previous_switch <= reg_filtered[4];
			if (state_current == ST_LATCH) begin
				flag_armed <= 1'b1;
			end
			if (flag_armed && flag_previous_switch && !reg_filtered[4]) begin
				cnt_press <= cnt_press + 16'd1;
			end
		end
	end

	// 固定周期触发，发送忙时跳过节拍而不覆盖正在发送的快照。
	always @(posedge i_clk or negedge flag_reset_n) begin
		if (!flag_reset_n) begin
			cnt_report <= 32'd0;
		end else if (cnt_report == C_REPORT_CYCLES - 32'd1) begin
			cnt_report <= 32'd0;
		end else begin
			cnt_report <= cnt_report + 32'd1;
		end
	end

	// 状态寄存器仅保存组合逻辑选择的状态。
	always @(posedge i_clk or negedge flag_reset_n) begin
		if (!flag_reset_n) begin
			state_current <= ST_IDLE;
		end else begin
			state_current <= state_next;
		end
	end

	// 发送前后分别等待UART忙标志拉高和拉低，保证一字节只提交一次。
	always @(*) begin
		state_next = state_current;
		case (state_current)
			ST_IDLE: begin
				if (cnt_report == C_REPORT_CYCLES - 32'd1) begin
					state_next = ST_LATCH;
				end
			end
			ST_LATCH: begin state_next = ST_SEND; end
			ST_SEND: begin state_next = ST_ACCEPT; end
			ST_ACCEPT: begin
				if (flag_uart_busy) begin state_next = ST_WAIT; end
			end
			ST_WAIT: begin
				if (!flag_uart_busy) begin state_next = ST_ADVANCE; end
			end
			ST_ADVANCE: begin
				if (cnt_character == 5'd20) begin state_next = ST_IDLE; end
				else begin state_next = ST_SEND; end
			end
			default: begin state_next = ST_IDLE; end
		endcase
	end

	// 报告字段同时锁存，防止字节发送过程中出现跨时刻拼接。
	always @(posedge i_clk or negedge flag_reset_n) begin
		if (!flag_reset_n) begin
			cnt_character <= 5'd0;
			cnt_sequence <= 16'd0;
			reg_sequence_snapshot <= 16'd0;
			reg_raw_snapshot <= 5'd16;
			reg_filter_snapshot <= 5'd16;
			reg_press_snapshot <= 16'd0;
		end else if (state_current == ST_LATCH) begin
			cnt_character <= 5'd0;
			cnt_sequence <= cnt_sequence + 16'd1;
			reg_sequence_snapshot <= cnt_sequence;
			reg_raw_snapshot <= reg_sync;
			reg_filter_snapshot <= reg_filtered;
			reg_press_snapshot <= cnt_press;
		end else if (state_current == ST_ADVANCE) begin
			cnt_character <= cnt_character + 5'd1;
		end
	end

	// 数值字段大端十六进制，原始电平保持物理极性不在FPGA猜方向。
	always @(*) begin
		enc_nibble = 4'd0;
		case (cnt_character)
			5'd1: begin enc_nibble = reg_sequence_snapshot[15:12]; end
			5'd2: begin enc_nibble = reg_sequence_snapshot[11:8]; end
			5'd3: begin enc_nibble = reg_sequence_snapshot[7:4]; end
			5'd4: begin enc_nibble = reg_sequence_snapshot[3:0]; end
			5'd7: begin enc_nibble = {3'd0, reg_raw_snapshot[4]}; end
			5'd8: begin enc_nibble = reg_raw_snapshot[3:0]; end
			5'd11: begin enc_nibble = {3'd0, reg_filter_snapshot[4]}; end
			5'd12: begin enc_nibble = reg_filter_snapshot[3:0]; end
			5'd15: begin enc_nibble = reg_press_snapshot[15:12]; end
			5'd16: begin enc_nibble = reg_press_snapshot[11:8]; end
			5'd17: begin enc_nibble = reg_press_snapshot[7:4]; end
			5'd18: begin enc_nibble = reg_press_snapshot[3:0]; end
			default: begin enc_nibble = 4'd0; end
		endcase
	end

	// Jssss Rrr Fff Ppppp后接回车换行，固定21字节。
	always @(*) begin
		enc_character = enc_hex;
		case (cnt_character)
			5'd0: begin enc_character = "J"; end
			5'd5, 5'd9, 5'd13: begin enc_character = 8'd32; end
			5'd6: begin enc_character = "R"; end
			5'd10: begin enc_character = "F"; end
			5'd14: begin enc_character = "P"; end
			5'd19: begin enc_character = 8'd13; end
			5'd20: begin enc_character = 8'd10; end
			default: begin enc_character = enc_hex; end
		endcase
	end

	// 复用已在编码器实板验证过的8N1发送器，输入引脚始终为高阻。
	EncoderUartTx #(.C_BAUD_CYCLES(C_BAUD_CYCLES)) u_uart (
		.i_clk(i_clk), .i_rstn(flag_reset_n), .i_start(flag_uart_start),
		.i_data(enc_character), .o_busy(flag_uart_busy), .o_tx(o_uart_tx)
	);
endmodule
