`timescale 1ns / 1ps
// MprScanner：单个 MPR121 的地址探测、配置回读与原子采样。
module MprScanner #(
    parameter [15:0] C_DIVIDER=99,
    parameter [7:0] C_SAMPLE_BASE=0,
    parameter integer C_BOOT=2500000, C_RETRY=50000000,
    parameter integer C_RESET_WAIT=250000, C_POLL=0, C_TIMEOUT=2000000
)(
    input i_clk, input i_rstn,
    inout io_scl, inout io_sda,
    output [335:0] o_raw,
    output [15:0] o_sequence,
    output [6:0] o_address,
    output [7:0] o_error
);
localparam [2:0] S_DELAY=0,S_SETUP=1,S_LAUNCH=2,S_WAIT=3,S_RESULT=4;
localparam [1:0] OP_PROBE=0,OP_CONFIG=1,OP_VERIFY=2,OP_SAMPLE=3;
reg [2:0] state,next_state;
reg [1:0] operation;
reg [31:0] delay_count;
reg [5:0] config_index;
reg [6:0] verify_interval;
reg [15:0] config_word;
reg [6:0] address_o;
reg [7:0] error_o;
reg [15:0] sequence_o;
reg [335:0] raw_o, staging;
reg [23:0] verification;
reg request_read;
reg [7:0] request_register, request_write;
reg [5:0] request_count;
wire done,valid;
wire [1:0] error;
wire [5:0] index;
wire [7:0] data;
assign o_raw=raw_o;
assign o_sequence=sequence_o;
assign o_address=address_o;
assign o_error=error_o;
I2cRegister #(.C_DIVIDER(C_DIVIDER),.C_TIMEOUT(C_TIMEOUT)) transaction (
    .i_clk(i_clk),.i_rstn(i_rstn),.i_start(state==S_LAUNCH),
    .i_read(request_read),.i_address(address_o),.i_register(request_register),
    .i_write(request_write),.i_count(request_count),.o_done(done),.o_error(error),
    .o_valid(valid),.o_index(index),.o_data(data),.io_scl(io_scl),.io_sda(io_sda)
);
// 配置查表来自 spec/model.py；触发 12、释放 6，固定充电参数；自动配置关闭，用于排查全零采样。
always @(*) begin
    config_word=16'h5e00;
    case(config_index)
        6'd0: config_word=16'h8063;
        6'd1: config_word=16'h5e00;
        6'd2: config_word=16'h2b01;
        6'd3: config_word=16'h2c01;
        6'd4: config_word=16'h2d0e;
        6'd5: config_word=16'h2e00;
        6'd6: config_word=16'h2f01;
        6'd7: config_word=16'h3005;
        6'd8: config_word=16'h3101;
        6'd9: config_word=16'h3200;
        6'd10: config_word=16'h3300;
        6'd11: config_word=16'h3400;
        6'd12: config_word=16'h3500;
        6'd13: config_word=16'h410c;
        6'd14: config_word=16'h4206;
        6'd15: config_word=16'h430c;
        6'd16: config_word=16'h4406;
        6'd17: config_word=16'h450c;
        6'd18: config_word=16'h4606;
        6'd19: config_word=16'h470c;
        6'd20: config_word=16'h4806;
        6'd21: config_word=16'h490c;
        6'd22: config_word=16'h4a06;
        6'd23: config_word=16'h4b0c;
        6'd24: config_word=16'h4c06;
        6'd25: config_word=16'h4d0c;
        6'd26: config_word=16'h4e06;
        6'd27: config_word=16'h4f0c;
        6'd28: config_word=16'h5006;
        6'd29: config_word=16'h510c;
        6'd30: config_word=16'h5206;
        6'd31: config_word=16'h530c;
        6'd32: config_word=16'h5406;
        6'd33: config_word=16'h550c;
        6'd34: config_word=16'h5606;
        6'd35: config_word=16'h570c;
        6'd36: config_word=16'h5806;
        6'd37: config_word=16'h5b00;
        6'd38: config_word=16'h5c10;
        6'd39: config_word=16'h5d20;
        6'd40: config_word=16'h7b00;
        6'd41: config_word=16'h7c00;
        6'd42: config_word=16'h7dc9;
        6'd43: config_word=16'h7e83;
        6'd44: config_word=16'h7fb5;
        6'd45: config_word=16'h5e8c;
        default: config_word=16'h5e00;
    endcase
end
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) state<=S_DELAY;
    else state<=next_state;
end
always @(*) begin
    next_state=state;
    case(state)
        S_DELAY: if(delay_count==0) next_state=S_SETUP;
        S_SETUP: next_state=S_LAUNCH;
        S_LAUNCH: next_state=S_WAIT;
        S_WAIT: if(done) next_state=S_RESULT;
        S_RESULT: next_state=S_DELAY;
        default: next_state=S_DELAY;
    endcase
end
// 只在完整读事务成功后替换 raw，失败时保留旧值并明确标记无效。
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        operation<=OP_PROBE; delay_count<=C_BOOT; config_index<=0; verify_interval<=0;
        address_o<=7'h5a; error_o<=8'h01; sequence_o<=0; raw_o<=0; staging<=0;
        verification<=0; request_read<=1; request_register<=0; request_write<=0; request_count<=1;
    end else begin
        if(state==S_DELAY && delay_count!=0) delay_count<=delay_count-1'b1;
        if(valid) begin
            if(operation==OP_VERIFY) verification<={verification[15:0],data};
            if(operation==OP_SAMPLE) staging<={staging[327:0],data};
        end
        if(state==S_SETUP) begin
            request_read<=(operation!=OP_CONFIG);
            request_register<= operation==OP_CONFIG ? config_word[15:8] :
                               operation==OP_VERIFY ? 8'h5c : operation==OP_PROBE ? 8'h5d : C_SAMPLE_BASE;
            request_write<=config_word[7:0];
            request_count<=operation==OP_SAMPLE ? 6'd42 : operation==OP_VERIFY ? 6'd3 : 6'd1;
        end
        if(state==S_RESULT) begin
            delay_count<=0;
            if(error!=0) begin
                error_o<=error==2 ? 8'd2 : operation==OP_PROBE ? 8'd1 : operation==OP_SAMPLE ? 8'd5 : 8'd3;
                operation<=OP_PROBE;
                if(operation==OP_PROBE && address_o!=7'h5d) address_o<=address_o+1'b1;
                else begin address_o<=7'h5a; delay_count<=C_RETRY; end
            end else case(operation)
                OP_PROBE: begin operation<=OP_CONFIG; config_index<=0; error_o<=7; end
                OP_CONFIG: begin
                    if(config_index==0) delay_count<=C_RESET_WAIT;
                    if(config_index==45) operation<=OP_VERIFY;
                    else config_index<=config_index+1'b1;
                end
                OP_VERIFY: begin
                    if(verification==24'h10208c) begin operation<=OP_SAMPLE; delay_count<=C_POLL; verify_interval<=0; end
                    else begin error_o<=4; operation<=OP_PROBE; delay_count<=C_RETRY; end
                end
                OP_SAMPLE: begin
                    raw_o<=staging; sequence_o<=sequence_o+1'b1; delay_count<=C_POLL;
                    verify_interval<=verify_interval+1'b1;
                    if(verify_interval==127) operation<=OP_VERIFY;
                    error_o<=(C_SAMPLE_BASE==0 && staging[327]) ? 8'd6 : 8'd0;
                    if(C_SAMPLE_BASE==0 && staging[327]) begin operation<=OP_PROBE; delay_count<=C_RETRY; end
                end
                default: begin operation<=OP_PROBE; delay_count<=C_RETRY; end
            endcase
        end
    end
end
endmodule
