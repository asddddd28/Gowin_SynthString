`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Unspecified
// Engineer:        Codex
//
// Create Date:     2026/10/27 22:16:18
// Design Name:     AxisFixedCore
// Module Name:     AxisFixedCore
// Description:     description/AxisFixedCore_Design.pdf
// Simulations:     testbench/vivado/2021.1/AxisFixedCore
//
// Referrences:     None
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/10/27 22:16:18
// History:
// Time             Version     Revised by        Contents
// 2026/10/27       V1.0        Codex              Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        Unspecified
// 开发人员:        Codex
//
// 创建日期:        2026年10月27日
// 设计名称:        AxisFixedCore
// 模块名称:        AxisFixedCore
// 模块说明:        Description/AxisFixedCore_Design.pdf
// 仿真工程:        TestBench/Vivado/2021.1/AxisFixedCore
//
// 参考资料:        None
//
// 依赖文件:        None
//
// 当前版本:        V1.0
// 修订日期:        2026年10月27日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年10月27日   V1.0        Codex              创建文件

module AxisFixedCore
#(
	parameter C_INPUT_WIDTH = 32,               // 单次发射的完整快照位数
	parameter C_OUTPUT_WIDTH = 32,              // 每个结果槽容纳的有效位数
	parameter C_USER_WIDTH = 21,                // 原样保留的事务身份宽度
	parameter C_ADDR_WIDTH = 6                  // 返回槽地址宽度，支持一至八位
)
(
	//-----------------全局信号-----------------//
	input i_axis_aclk,                          // 核心和存储共享的时钟
	input i_axis_arstn,                         // 低有效复位撤销所有在途任务

	//-------------AXI-Stream总线S--------------//
	//数据通道
	input [C_INPUT_WIDTH - 1:0]i_s_axis_tdata,  // 当前等待接纳的操作快照
	input [C_USER_WIDTH - 1:0]i_s_axis_tuser,   // 与快照同时锁定的身份

	//控制通道
	input i_s_axis_tvalid,                      // 源端持有一份完整输入
	output o_s_axis_tready,                     // 尚有未分配的返回位置

	//-------------AXI-Stream总线M--------------//
	//数据通道
	output [C_OUTPUT_WIDTH - 1:0]o_m_axis_tdata, // 最早未消费的计算结果
	output [C_USER_WIDTH - 1:0]o_m_axis_tuser,  // 队首结果的原始身份

	//控制通道
	input i_m_axis_tready,                      // 消费端接收当前队首
	output o_m_axis_tvalid,                     // 队首槽已有完整返回

	//-----------------CORE接口-----------------//

	//CORE接口
	output o_core_valid,                        // 已接受任务的核心发射脉冲
	output [C_INPUT_WIDTH - 1:0]o_core_data,    // 发射沿送入核心的字段
	input i_core_valid,                         // 核心有序产生一个完成结果
	input [C_OUTPUT_WIDTH - 1:0]i_core_data     // 当前完成任务的全部返回字段
);

	//---------------配置参数区域---------------//
	localparam DEPTH = 32'd1 << C_ADDR_WIDTH;   // 环形存储的总槽数

	//-----------------计数信号-----------------//
	reg [C_ADDR_WIDTH:0]cnt_outstanding = 0;    // 已发射但尚未被消费的任务总量
	reg [C_ADDR_WIDTH:0]cnt_completed = 0;      // 已完成且尚未消费的结果数

	//----------------寄存器信号----------------//
	reg [C_USER_WIDTH - 1:0]reg_identity[0:DEPTH-1]; // 分配时登记标签，直到消费才可覆盖
	reg [C_OUTPUT_WIDTH - 1:0]reg_result[0:DEPTH-1]; // 完成时写入对应的预留位置
	reg [C_ADDR_WIDTH - 1:0]reg_allocate = 0;   // 下一次接纳所占用的位置
	reg [C_ADDR_WIDTH - 1:0]reg_complete = 0;   // 下一次有序完成的写地址
	reg [C_ADDR_WIDTH - 1:0]reg_retire = 0;     // 当前最早未消费的地址

	//-----------------标志信号-----------------//
	wire flag_accept;                           // 输入握手唯一决定一次新发射
	wire flag_retire;                           // 输出握手唯一释放一个已用槽

	//-----------------输出信号-----------------//
	//AXI-Stream总线S--控制通道
	wire s_axis_tready_o;                       // 环形信用未耗尽时允许接纳

	//AXI-Stream总线M--数据通道
	wire [C_OUTPUT_WIDTH - 1:0]m_axis_tdata_o;  // 读指针停顿期间保持同一结果
	wire [C_USER_WIDTH - 1:0]m_axis_tuser_o;    // 与读指针绑定的同行身份

	//AXI-Stream总线M--控制通道
	wire m_axis_tvalid_o;                       // 存在已完成队首时声明有效

	//CORE接口
	wire core_valid_o;                          // 向不可反压核心交付的资格
	wire [C_INPUT_WIDTH - 1:0]core_data_o;      // 核心入口使用当前完整数据字

	//---------------其他信号连线---------------//
	//其他信号连线
	assign s_axis_tready_o = i_axis_arstn && (cnt_outstanding < DEPTH); // 复位期间关闭入口
	assign m_axis_tvalid_o = i_axis_arstn && (cnt_completed != 0); // 未完成的内存不能被读取为有效
	assign flag_accept = i_s_axis_tvalid && s_axis_tready_o; // 源和适配器共同确认所有权转移
	assign flag_retire = m_axis_tvalid_o && i_m_axis_tready; // 只有实际消费才返还信用
	assign m_axis_tdata_o = reg_result[reg_retire]; // 输出阻塞时地址及已写槽都不变化
	assign m_axis_tuser_o = reg_identity[reg_retire]; // 不从活动参数重新生成标签
	assign core_valid_o = flag_accept;          // 每次输入握手恰好发射一次
	assign core_data_o = i_s_axis_tdata;        // 所有运算字段在同一发射沿采样

	//---------------输出信号连线---------------//
	//AXI-Stream总线S--控制通道
	assign o_s_axis_tready = s_axis_tready_o;   // 告知源端是否可移交

	//AXI-Stream总线M--数据通道
	assign o_m_axis_tdata = m_axis_tdata_o;     // 暴露整包结果供下游采样
	assign o_m_axis_tuser = m_axis_tuser_o;     // 输出原请求的拥有者

	//AXI-Stream总线M--控制通道
	assign o_m_axis_tvalid = m_axis_tvalid_o;   // 发布已完成队首的资格

	//CORE接口
	assign o_core_valid = core_valid_o;         // 固定流水只接收有效发射
	assign o_core_data = core_data_o;           // 把原子快照送到数值核心

	//-------------主要任务处理区域-------------//
	// 标签无需逐槽复位，清空信用即可撤销旧内容。
	always@(posedge i_axis_aclk)begin
		if(i_axis_arstn == 1'b0)begin
			// 复位只禁止写入；槽有效性由独立信用计数决定。
		end else if(flag_accept == 1'b1)begin
			reg_identity[reg_allocate] <= i_s_axis_tuser; // 入口握手沿锁定同行身份
		end
	end

	// 每个完成都有对应预留位置，因此这里不需要反压核心。
	always@(posedge i_axis_aclk)begin
		if(i_axis_arstn == 1'b0)begin
			// 不复位数据阵列，避免把返回存储强制展开成带复位触发器。
		end else if(i_core_valid == 1'b1)begin
			reg_result[reg_complete] <= i_core_data; // 按发射顺序写入完整返回
		end
	end

	// 分配游标仅随新任务前进。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_allocate <= 0;                  // 下一轮从槽零分配
		end else if(flag_accept == 1'b1)begin
			reg_allocate <= reg_allocate + 1'b1; // 自然截断形成环形地址
		end
	end

	// 完成游标跟随不可暂停核心的返回次序。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_complete <= 0;                  // 复位后首个结果对应槽零
		end else if(i_core_valid == 1'b1)begin
			reg_complete <= reg_complete + 1'b1; // 每个返回占据下一个预留槽
		end
	end

	// 消费游标不受计算完成速度影响。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			reg_retire <= 0;                    // 清除旧队首位置
		end else if(flag_retire == 1'b1)begin
			reg_retire <= reg_retire + 1'b1;    // 消费后才允许访问后继项
		end
	end

	// 在途数量包含核心中的任务和队列中的已完成任务。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			cnt_outstanding <= 0;               // 全部信用回到空闲池
		end else begin
			case({flag_accept, flag_retire})
				2'b10:begin
					cnt_outstanding <= cnt_outstanding + 1'b1; // 新发射占用一个信用
				end
				2'b01:begin
					cnt_outstanding <= cnt_outstanding - 1'b1; // 消费释放一个信用
				end
				default:begin
					cnt_outstanding <= cnt_outstanding; // 同进同出或都不发生时保持
				end
			endcase
		end
	end

	// 已完成计数限定输出有效范围，不使用未初始化内存。
	always@(posedge i_axis_aclk or negedge i_axis_arstn)begin
		if(i_axis_arstn == 1'b0)begin
			cnt_completed <= 0;                 // 无可交付的旧结果
		end else begin
			case({i_core_valid, flag_retire})
				2'b10:begin
					cnt_completed <= cnt_completed + 1'b1; // 新完成结果进入可读区
				end
				2'b01:begin
					cnt_completed <= cnt_completed - 1'b1; // 队首被下游取走
				end
				default:begin
					cnt_completed <= cnt_completed; // 同时写读保持结果总量
				end
			endcase
		end
	end

endmodule
