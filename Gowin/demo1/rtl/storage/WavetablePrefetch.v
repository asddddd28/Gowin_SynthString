`timescale 1ns / 1ps
// Background coherent frame-pair fetch; memory backend must flush cancelled responses.
// 后台预取：调用者提供已验证目录的帧CRC，并独占未使用银行写口。
module WavetablePrefetch #(parameter C_TIMEOUT_CYCLES=245765000)(
    input i_clk,
    input i_rstn,
    input i_request_valid,
    input [31:0] i_resource_id,
    input [31:0] i_revision,
    input [9:0] i_frame_count,
    input [8:0] i_first_frame,
    input [8:0] i_second_frame,
    input [15:0] i_fraction,
    input [31:0] i_payload_base,
    input [31:0] i_first_crc,
    input [31:0] i_second_crc,
    input i_active_bank,
    input i_cancel,
    input i_memory_request_ready,
    input i_memory_valid,
    input [7:0] i_memory_data,
    input i_memory_last,
    input i_memory_error,
    input i_commit_ready,
    output o_request_ready,
    output o_busy,
    output o_memory_request_valid,
    output [31:0] o_memory_address,
    output [11:0] o_memory_length,
    output o_memory_ready,
    output o_memory_cancel,
    output o_table_write,
    output [10:0] o_table_address,
    output o_table_frame,
    output [15:0] o_table_data,
    output o_commit_valid,
    output o_commit_bank,
    output [31:0] o_resource_id,
    output [31:0] o_revision,
    output [8:0] o_first_frame,
    output [8:0] o_second_frame,
    output [15:0] o_fraction,
    output o_done,
    output [7:0] o_error
);
    localparam ST_IDLE=0, ST_COUNT=1, ST_RANGE=2, ST_FIRST=3, ST_SECOND=4;
    localparam ST_ADJ_CALC=5, ST_ADJ_CHECK=6, ST_FRACTION=7, ST_ADDRESS_FIRST=8;
    localparam ST_REQUEST_FIRST=9, ST_RECEIVE=10, ST_CRC=11, ST_CHECK=12;
    localparam ST_CHECK_CRC=13, ST_ADDRESS_SECOND=14, ST_REQUEST_SECOND=15;
    localparam ST_COMMIT=16, ST_DONE=17, ST_BAD_ARGUMENT=18, ST_BAD_LENGTH=19;
    localparam ST_BAD_CRC=20, ST_MEMORY_ERROR=21, ST_TIMEOUT=22, ST_CANCEL=23;
    reg [4:0] state_current;
    reg [4:0] state_next;
    reg [31:0] reg_resource_id;
    reg [31:0] reg_revision;
    reg [9:0] reg_frame_count;
    reg [8:0] reg_first_frame;
    reg [8:0] reg_second_frame;
    reg [15:0] reg_fraction;
    reg [31:0] reg_payload_base;
    reg [31:0] reg_first_crc;
    reg [31:0] reg_second_crc;
    reg [32:0] reg_resource_end;
    reg [8:0] reg_last_frame;
    reg [8:0] reg_expected_second;
    reg [31:0] reg_expected_crc;
    reg [31:0] reg_crc;
    reg [7:0] reg_low_byte;
    reg [11:0] cnt_bytes;
    reg [2:0] cnt_crc_bits;
    reg [31:0] cnt_timeout;
    reg flag_bad_last;
    reg flag_bank;
    reg flag_frame;
    reg flag_busy_o;
    reg flag_memory_request_o;
    reg [31:0] reg_memory_address_o;
    reg flag_memory_ready_o;
    reg flag_memory_cancel_o;
    reg flag_table_write_o;
    reg [10:0] reg_table_address_o;
    reg [15:0] reg_table_data_o;
    reg flag_commit_o;
    reg flag_done_o;
    reg [7:0] reg_error_o;
    wire flag_active;
    wire flag_timeout;
    wire flag_fatal;
    wire flag_request_ready;

    assign flag_active=(state_current!=ST_IDLE)&&(state_current<ST_DONE);
    assign flag_timeout=cnt_timeout>=C_TIMEOUT_CYCLES;
    assign flag_fatal=i_cancel|i_memory_error|flag_timeout;
    assign flag_request_ready=(state_current==ST_IDLE)&&!i_cancel;
    assign o_request_ready=flag_request_ready;
    assign o_busy=flag_busy_o;
    assign o_memory_request_valid=flag_memory_request_o&&!flag_fatal;
    assign o_memory_address=reg_memory_address_o;
    assign o_memory_length=12'd2048;
    assign o_memory_ready=flag_memory_ready_o&&!flag_fatal;
    assign o_memory_cancel=flag_memory_cancel_o;
    assign o_table_write=flag_table_write_o;
    assign o_table_address=reg_table_address_o;
    assign o_table_frame=flag_frame;
    assign o_table_data=reg_table_data_o;
    assign o_commit_valid=flag_commit_o&&!flag_fatal;
    assign o_commit_bank=flag_bank;
    assign o_resource_id=reg_resource_id;
    assign o_revision=reg_revision;
    assign o_first_frame=reg_first_frame;
    assign o_second_frame=reg_second_frame;
    assign o_fraction=reg_fraction;
    assign o_done=flag_done_o;
    assign o_error=reg_error_o;

    // 状态寄存器与异步复位独立，控制不会访问任何波表RAM。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) state_current<=ST_IDLE;
        else state_current<=state_next;
    end

    // 三进程FSM：输入只在对应握手状态消费，异常优先于提交。
    always @(*) begin
        state_next=state_current;
        case(state_current)
            ST_IDLE: if(i_request_valid&&!i_cancel) state_next=ST_COUNT;
            ST_COUNT: begin
                if(reg_frame_count==0||reg_frame_count>512) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_RANGE;
            end
            ST_RANGE: begin
                if(reg_payload_base[0]||reg_resource_end>33'h100000000) state_next=ST_BAD_ARGUMENT;
                else if(reg_resource_id==0||reg_revision==0) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_FIRST;
            end
            ST_FIRST: begin
                if({1'b0,reg_first_frame}>=reg_frame_count) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_SECOND;
            end
            ST_SECOND: begin
                if({1'b0,reg_second_frame}>=reg_frame_count) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_ADJ_CALC;
            end
            ST_ADJ_CALC: state_next=ST_ADJ_CHECK;
            ST_ADJ_CHECK: begin
                if(reg_second_frame!=reg_expected_second) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_FRACTION;
            end
            ST_FRACTION: begin
                if(reg_first_frame==reg_last_frame&&reg_fraction!=0) state_next=ST_BAD_ARGUMENT;
                else state_next=ST_ADDRESS_FIRST;
            end
            ST_ADDRESS_FIRST: state_next=ST_REQUEST_FIRST;
            ST_REQUEST_FIRST: if(i_memory_request_ready) state_next=ST_RECEIVE;
            ST_RECEIVE: if(i_memory_valid) state_next=ST_CRC;
            ST_CRC: if(cnt_crc_bits==7) state_next=ST_CHECK;
            ST_CHECK: begin
                if(flag_bad_last) state_next=ST_BAD_LENGTH;
                else if(cnt_bytes==2048) state_next=ST_CHECK_CRC;
                else state_next=ST_RECEIVE;
            end
            ST_CHECK_CRC: begin
                if((~reg_crc)!=reg_expected_crc) state_next=ST_BAD_CRC;
                else if(flag_frame) state_next=ST_COMMIT;
                else state_next=ST_ADDRESS_SECOND;
            end
            ST_ADDRESS_SECOND: state_next=ST_REQUEST_SECOND;
            ST_REQUEST_SECOND: if(i_memory_request_ready) state_next=ST_RECEIVE;
            ST_COMMIT: if(i_commit_ready) state_next=ST_DONE;
            ST_DONE,ST_BAD_ARGUMENT,ST_BAD_LENGTH,ST_BAD_CRC,ST_MEMORY_ERROR,ST_TIMEOUT,ST_CANCEL: state_next=ST_IDLE;
            default: state_next=ST_IDLE;
        endcase
        if(flag_active) begin
            if(i_cancel) state_next=ST_CANCEL;
            else if(i_memory_error) state_next=ST_MEMORY_ERROR;
            else if(flag_timeout) state_next=ST_TIMEOUT;
        end
    end

    // 单事务快照、低字节拼接、串行CRC和输出脉冲。
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            reg_resource_id<=0;reg_revision<=0;reg_frame_count<=0;
            reg_first_frame<=0;reg_second_frame<=0;reg_fraction<=0;
            reg_payload_base<=0;reg_first_crc<=0;reg_second_crc<=0;
            reg_resource_end<=0;reg_last_frame<=0;reg_expected_second<=0;
            reg_expected_crc<=0;reg_crc<=32'hffffffff;reg_low_byte<=0;
            cnt_bytes<=0;cnt_crc_bits<=0;cnt_timeout<=0;
            flag_bad_last<=0;flag_bank<=0;flag_frame<=0;
            flag_busy_o<=0;flag_memory_request_o<=0;reg_memory_address_o<=0;
            flag_memory_ready_o<=0;flag_memory_cancel_o<=0;
            flag_table_write_o<=0;reg_table_address_o<=0;reg_table_data_o<=0;
            flag_commit_o<=0;flag_done_o<=0;reg_error_o<=0;
        end else begin
            flag_done_o<=0;flag_memory_cancel_o<=0;flag_table_write_o<=0;
            if(flag_active) cnt_timeout<=cnt_timeout+1'b1;
            else cnt_timeout<=0;
            // 即使COMMIT ready同时有效，fatal组合门也阻止对外握手。
            if(flag_active&&flag_fatal) begin
                flag_memory_request_o<=0;flag_memory_ready_o<=0;flag_commit_o<=0;
            end else begin
                case(state_current)
                    ST_IDLE: begin
                        flag_busy_o<=0;
                        if(i_request_valid&&!i_cancel) begin
                            reg_resource_id<=i_resource_id;reg_revision<=i_revision;
                            reg_frame_count<=i_frame_count;reg_first_frame<=i_first_frame;
                            reg_second_frame<=i_second_frame;reg_fraction<=i_fraction;
                            reg_payload_base<=i_payload_base;reg_first_crc<=i_first_crc;reg_second_crc<=i_second_crc;
                            flag_bank<=!i_active_bank;flag_frame<=0;flag_busy_o<=1;reg_error_o<=0;
                            flag_memory_request_o<=0;flag_memory_ready_o<=0;flag_commit_o<=0;
                        end
                    end
                    ST_COUNT: begin
                        reg_resource_end<={1'b0,reg_payload_base}+{12'd0,reg_frame_count,11'd0};
                        // 验证帧数为1..512后，9位减法在512时回绕为511。
                        reg_last_frame<=reg_frame_count[8:0]-9'd1;
                    end
                    ST_ADJ_CALC: begin
                        if(reg_first_frame==reg_last_frame) reg_expected_second<=reg_first_frame;
                        else reg_expected_second<=reg_first_frame+1'b1;
                    end
                    ST_ADDRESS_FIRST: begin
                        reg_memory_address_o<=reg_payload_base+{12'd0,reg_first_frame,11'd0};
                        reg_expected_crc<=reg_first_crc;flag_frame<=0;flag_memory_request_o<=1;
                    end
                    ST_ADDRESS_SECOND: begin
                        reg_memory_address_o<=reg_payload_base+{12'd0,reg_second_frame,11'd0};
                        reg_expected_crc<=reg_second_crc;flag_frame<=1;flag_memory_request_o<=1;
                    end
                    ST_REQUEST_FIRST,ST_REQUEST_SECOND: begin
                        if(i_memory_request_ready) begin
                            flag_memory_request_o<=0;flag_memory_ready_o<=1;
                            cnt_bytes<=0;reg_crc<=32'hffffffff;
                        end
                    end
                    ST_RECEIVE: begin
                        if(i_memory_valid) begin
                            flag_memory_ready_o<=0;
                            flag_bad_last<=(i_memory_last!=(cnt_bytes==2047));
                            reg_crc<=reg_crc^{24'd0,i_memory_data};cnt_crc_bits<=0;
                            if(cnt_bytes[0]) begin
                                reg_table_address_o<={flag_bank,cnt_bytes[10:1]};
                                reg_table_data_o<={i_memory_data,reg_low_byte};flag_table_write_o<=1;
                            end else reg_low_byte<=i_memory_data;
                            cnt_bytes<=cnt_bytes+1'b1;
                        end
                    end
                    ST_CRC: begin
                        if(reg_crc[0]) reg_crc<={1'b0,reg_crc[31:1]}^32'hedb88320;
                        else reg_crc<={1'b0,reg_crc[31:1]};
                        cnt_crc_bits<=cnt_crc_bits+1'b1;
                    end
                    ST_CHECK: if(!flag_bad_last&&cnt_bytes!=2048) flag_memory_ready_o<=1;
                    ST_CHECK_CRC: if((~reg_crc)==reg_expected_crc&&flag_frame) flag_commit_o<=1;
                    ST_COMMIT: if(i_commit_ready) flag_commit_o<=0;
                    ST_DONE: begin flag_done_o<=1;flag_busy_o<=0;end
                    ST_BAD_ARGUMENT,ST_BAD_LENGTH,ST_BAD_CRC,ST_MEMORY_ERROR,ST_TIMEOUT,ST_CANCEL: begin
                        flag_done_o<=1;flag_busy_o<=0;flag_memory_cancel_o<=1;
                        flag_memory_request_o<=0;flag_memory_ready_o<=0;flag_commit_o<=0;
                        case(state_current)
                            ST_BAD_ARGUMENT:reg_error_o<=1;
                            ST_BAD_LENGTH:reg_error_o<=2;
                            ST_BAD_CRC:reg_error_o<=3;
                            ST_MEMORY_ERROR:reg_error_o<=4;
                            ST_TIMEOUT:reg_error_o<=5;
                            ST_CANCEL:reg_error_o<=6;
                            default:reg_error_o<=4;
                        endcase
                    end
                    default: begin
                        // Unused states retain their registered outputs.
                    end
                endcase
            end
        end
    end
endmodule
