`timescale 1ns / 1ps
// GuitarEventQueue：每板独立16项队列，同时弹出/写入不丢事件。
module GuitarEventQueue (
    input i_clk,
    input i_rstn,
    input i_push,
    input [95:0] i_data,
    input i_pop,
    output o_empty,
    output [95:0] o_data,
    output [15:0] o_dropped
);
reg [95:0] memory [0:15];
reg [3:0] write_pointer,read_pointer;
reg [4:0] occupancy;
reg [15:0] dropped_o;
wire pop = i_pop && occupancy!=0;
wire push = i_push && (occupancy<16 || pop);
assign o_empty=occupancy==0;
assign o_data=memory[read_pointer];
assign o_dropped=dropped_o;
always @(posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        write_pointer<=0; read_pointer<=0; occupancy<=0; dropped_o<=0;
    end else begin
        if(push) begin memory[write_pointer]<=i_data; write_pointer<=write_pointer+1'b1; end
        if(pop) read_pointer<=read_pointer+1'b1;
        case({push,pop})
            2'b10: occupancy<=occupancy+1'b1;
            2'b01: occupancy<=occupancy-1'b1;
            default: begin end
        endcase
        if(i_push && !push && dropped_o!=16'hffff) dropped_o<=dropped_o+1'b1;
    end
end
endmodule
