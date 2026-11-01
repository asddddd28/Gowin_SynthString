`timescale 1ns / 1ps
// I2cRegister：单寄存器写或连续寄存器读；底层复用 OpenCores 字节控制器。
module I2cRegister #(
    parameter [15:0] C_DIVIDER = 16'd99,
    parameter integer C_TIMEOUT = 2000000
)(
    input i_clk,
    input i_rstn,
    input i_start,
    input i_read,
    input [6:0] i_address,
    input [7:0] i_register,
    input [7:0] i_write,
    input [5:0] i_count,
    output o_done,
    output [1:0] o_error,
    output o_valid,
    output [5:0] o_index,
    output [7:0] o_data,
    inout io_scl,
    inout io_sda
);
localparam [2:0] S_IDLE=0, S_COMMAND=1, S_DROP=2, S_STOP=3, S_RESET=4, S_DONE=5;
reg [2:0] state, next_state;
reg [5:0] phase, read_index, read_count;
reg read_mode;
reg [6:0] address;
reg [7:0] register_address, write_value;
reg [31:0] timeout_count;
reg [1:0] error_o;
reg done_o, valid_o;
reg [7:0] data_o;
reg [5:0] index_o;
reg cmd_start, cmd_stop, cmd_read, cmd_write, cmd_nack;
reg [7:0] cmd_data;
wire cmd_ack, nack, arbitration, scl_release, sda_release;
wire [7:0] received;
wire timed_out = timeout_count == C_TIMEOUT;
wire last_phase = read_mode ? (phase == 3 && read_index == read_count-1'b1) : phase == 2;
wire failed_ack = phase < 3 && nack;
assign io_scl = scl_release ? 1'bz : 1'b0;
assign io_sda = sda_release ? 1'bz : 1'b0;
assign o_done=done_o;
assign o_error=error_o;
assign o_valid=valid_o;
assign o_index=index_o;
assign o_data=data_o;
i2c_master_byte_ctrl byte_engine (
    .clk(i_clk), .rst(state==S_RESET), .nReset(i_rstn), .ena(1'b1), .clk_cnt(C_DIVIDER),
    .start(cmd_start), .stop(cmd_stop), .read(cmd_read), .write(cmd_write),
    .ack_in(cmd_nack), .din(cmd_data), .cmd_ack(cmd_ack), .ack_out(nack), .dout(received),
    .i2c_busy(), .i2c_al(arbitration), .scl_i(io_scl), .scl_o(), .scl_oen(scl_release),
    .sda_i(io_sda), .sda_o(), .sda_oen(sda_release)
);
// 状态寄存器：复位与超时都释放总线；没有无限等待从机的路径。
always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) state <= S_IDLE;
    else state <= next_state;
end
always @(*) begin
    next_state=state;
    case(state)
        S_IDLE: if(i_start) next_state=S_COMMAND;
        S_COMMAND: if(timed_out || arbitration) next_state=S_RESET;
                   else if(cmd_ack) next_state=S_DROP;
        S_DROP: if(error_o != 0) next_state=S_STOP;
                else if(last_phase) next_state=S_DONE;
                else next_state=S_COMMAND;
        S_STOP: if(timed_out || arbitration) next_state=S_RESET;
                else if(cmd_ack) next_state=S_DONE;
        S_RESET: next_state=S_DONE;
        S_DONE: next_state=S_IDLE;
        default: next_state=S_RESET;
    endcase
end
// 命令在 COMMAND 状态保持到字节确认；DROP 提供一拍清除握手。
always @(*) begin
    cmd_start=0; cmd_stop=0; cmd_read=0; cmd_write=0; cmd_nack=0; cmd_data=0;
    if(state==S_COMMAND) begin
        cmd_start=(phase==0 || (phase==2 && read_mode));
        cmd_stop=last_phase;
        cmd_read=(phase==3);
        cmd_write=(phase!=3);
        cmd_nack=last_phase;
        case(phase)
            0: cmd_data={address,1'b0};
            1: cmd_data=register_address;
            2: cmd_data=read_mode ? {address,1'b1} : write_value;
            default: cmd_data=0;
        endcase
    end else if(state==S_STOP) cmd_stop=1;
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        phase<=0; read_index<=0; read_count<=1; read_mode<=0; address<=0;
        register_address<=0; write_value<=0; timeout_count<=0; error_o<=0;
        done_o<=0; valid_o<=0; data_o<=0; index_o<=0;
    end else begin
        done_o<=0; valid_o<=0;
        if(state==S_IDLE) begin
            timeout_count<=0;
            if(i_start) begin
                address<=i_address; register_address<=i_register; write_value<=i_write;
                read_mode<=i_read; read_count<=i_count; read_index<=0; phase<=0; error_o<=0;
            end
        end else if(!timed_out) timeout_count<=timeout_count+1'b1;
        if(state==S_COMMAND && cmd_ack) begin
            if(failed_ack) error_o<=1;
            if(phase==3) begin valid_o<=1; data_o<=received; index_o<=read_index; end
        end
        if(state==S_DROP && error_o==0 && !last_phase) begin
            if(phase==3) read_index<=read_index+1'b1;
            else phase<=phase+1'b1;
        end
        if(next_state==S_RESET) error_o<=2;
        if(state==S_DONE) done_o<=1;
    end
end
endmodule
