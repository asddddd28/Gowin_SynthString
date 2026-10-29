`timescale 1ns/1ps
// KeyboardDebug: Tang Mega NEO 60K Hall keyboard acquisition diagnostic.
// 键盘原始采集调试：50MHz，ADC 4.166MHz，115200 8N1，K01:ABC\r\n。
// Reference: ADC124S051 serial interface; project pin spreadsheet.
module KeyboardDebug #(
    parameter integer C_SETTLE_CYCLES = 10000, // 每个键切换后等待200us
    parameter integer C_HALF_CYCLES = 6,       // SPI半周期120ns
    parameter integer C_UART_CYCLES = 434      // 50MHz / 115200
)(
    input wire i_clk,             // 板载50MHz时钟
    input wire i_rstn,            // 板载低有效复位
    input wire i_adc_dout,        // 经电平转换后的ADC数据
    output wire [2:0] o_mux_sel,  // TMUX1208地址，低位为A0
    output wire o_mux_en,         // 模拟开关高有效使能
    output wire o_adc_cs_n,       // ADC低有效片选
    output wire o_adc_sclk,       // ADC串行时钟，空闲低
    output wire o_adc_din,        // 下一次转换通道命令
    output wire o_uart_tx,        // 板载USB串口发送
    output wire o_rgb             // 调试阶段关闭RGB数据
);
localparam [2:0] ST_SETTLE=0, ST_START=1, ST_SPI=2, ST_GAP=3,
                 ST_LOAD=4, ST_UART=5, ST_ADVANCE=6;
reg [2:0] state_current, state_next;
reg [1:0] reg_reset_release;
wire flag_reset_n;
reg [4:0] reg_key;
reg [31:0] cnt_wait;
reg [15:0] cnt_half;
reg [4:0] cnt_spi_bit;
reg reg_dummy;
reg reg_cs_n, reg_sclk;
reg [15:0] reg_command, reg_receive;
reg [11:0] reg_sample;
reg [3:0] cnt_character, cnt_uart_bit;
reg [15:0] cnt_baud;
reg [9:0] reg_uart_shift;
reg [7:0] enc_character;
reg [2:0] enc_mux;
wire [5:0] enc_key_number;
// 复位异步拉低、两拍同步释放；按住复位期间关闭模拟开关。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) reg_reset_release <= 2'b00;
    else reg_reset_release <= {reg_reset_release[0],1'b1};
end
assign flag_reset_n = reg_reset_release[1];
assign o_mux_sel = enc_mux;
assign o_mux_en = flag_reset_n;
assign o_adc_cs_n = reg_cs_n;
assign o_adc_sclk = reg_sclk;
assign o_adc_din = reg_command[15];
assign o_uart_tx = reg_uart_shift[0];
assign o_rgb = 1'b0;
assign enc_key_number = {1'b0,reg_key} + 6'd1;
// 物理列1..8对应开关S5,S6,S7,S8,S4,S3,S2,S1。
always @(*) begin
    case (reg_key[2:0])
        0: enc_mux=4; 1: enc_mux=5; 2: enc_mux=6; 3: enc_mux=7;
        4: enc_mux=3; 5: enc_mux=2; 6: enc_mux=1; default: enc_mux=0;
    endcase
end
function [7:0] hex_ascii;
    input [3:0] i_nibble;
    begin
        if(i_nibble < 10) hex_ascii = 8'h30 + {4'b0,i_nibble};
        else hex_ascii = 8'h41 + {4'b0,i_nibble} - 8'd10;
    end
endfunction
// 固定九字节行，十进制键号与十六进制采样值便于串口终端检查。
always @(*) begin
    case(cnt_character)
        0: enc_character=8'h4b;
        1: enc_character=8'h30 + (enc_key_number / 10);
        2: enc_character=8'h30 + (enc_key_number % 10);
        3: enc_character=8'h3a;
        4: enc_character=hex_ascii(reg_sample[11:8]);
        5: enc_character=hex_ascii(reg_sample[7:4]);
        6: enc_character=hex_ascii(reg_sample[3:0]);
        7: enc_character=8'h0d;
        default: enc_character=8'h0a;
    endcase
end
// 两次转换使用相同地址；第一次丢弃，第二次才属于请求通道。
always @(*) begin
    state_next=state_current;
    case(state_current)
        ST_SETTLE: if(cnt_wait == C_SETTLE_CYCLES-1) state_next=ST_START;
        ST_START: state_next=ST_SPI;
        ST_SPI: if(cnt_half == C_HALF_CYCLES-1 && reg_sclk && cnt_spi_bit == 15) state_next=ST_GAP;
        ST_GAP: if(cnt_wait == 15) begin
            if(reg_dummy) state_next=ST_START; else state_next=ST_LOAD;
        end
        ST_LOAD: state_next=ST_UART;
        ST_UART: if(cnt_baud == C_UART_CYCLES-1 && cnt_uart_bit == 9) begin
            if(cnt_character == 8) state_next=ST_ADVANCE; else state_next=ST_LOAD;
        end
        ST_ADVANCE: state_next=ST_SETTLE;
        default: state_next=ST_SETTLE;
    endcase
end
always @(posedge i_clk or negedge flag_reset_n) begin
    if(!flag_reset_n) state_current <= ST_SETTLE;
    else state_current <= state_next;
end
// 所有外设时序均由主时钟使能产生，不以输出SPI时钟驱动内部逻辑。
always @(posedge i_clk or negedge flag_reset_n) begin
    if(!flag_reset_n) begin
        reg_key<=0; cnt_wait<=0; cnt_half<=0; cnt_spi_bit<=0;
        reg_dummy<=1; reg_cs_n<=1; reg_sclk<=0;
        reg_command<=0; reg_receive<=0; reg_sample<=0;
        cnt_character<=0; cnt_uart_bit<=0; cnt_baud<=0;
        reg_uart_shift<=10'h3ff;
    end else begin
        case(state_current)
            ST_SETTLE: begin
                if(state_next==ST_START) cnt_wait<=0;
                else cnt_wait<=cnt_wait+1'b1;
            end
            ST_START: begin
                reg_cs_n<=0; reg_sclk<=0; cnt_half<=0; cnt_spi_bit<=0;
                reg_command<={3'b000,reg_key[4:3],11'b0};
                reg_receive<=0;
            end
            ST_SPI: begin
                if(cnt_half == C_HALF_CYCLES-1) begin
                    cnt_half<=0;
                    reg_sclk<=~reg_sclk;
                    if(!reg_sclk) reg_receive<={reg_receive[14:0],i_adc_dout};
                    else if(cnt_spi_bit==15) begin
                        reg_cs_n<=1; cnt_wait<=0;
                        if(!reg_dummy) reg_sample<=reg_receive[11:0];
                    end else begin
                        cnt_spi_bit<=cnt_spi_bit+1'b1;
                        reg_command<={reg_command[14:0],1'b0};
                    end
                end else cnt_half<=cnt_half+1'b1;
            end
            ST_GAP: begin
                if(cnt_wait==15) begin cnt_wait<=0; reg_dummy<=0; end
                else cnt_wait<=cnt_wait+1'b1;
            end
            ST_LOAD: begin
                reg_uart_shift<={1'b1,enc_character,1'b0};
                cnt_baud<=0; cnt_uart_bit<=0;
            end
            ST_UART: begin
                if(cnt_baud==C_UART_CYCLES-1) begin
                    cnt_baud<=0;
                    reg_uart_shift<={1'b1,reg_uart_shift[9:1]};
                    if(cnt_uart_bit==9) begin
                        if(cnt_character==8) cnt_character<=0;
                        else cnt_character<=cnt_character+1'b1;
                    end else cnt_uart_bit<=cnt_uart_bit+1'b1;
                end else cnt_baud<=cnt_baud+1'b1;
            end
            ST_ADVANCE: begin reg_key<=reg_key+1'b1; reg_dummy<=1; end
            default: begin reg_cs_n<=1; reg_sclk<=0; cnt_wait<=0; end
        endcase
    end
end
endmodule
