`timescale 1ns/1ps
// Synchronous voice RAM reads are overlapped with task execution.
// Reservations include the two in-flight formatter registers and all queued tasks.
module SynthTaskPrefetch #(parameter C_VOICES=32,parameter C_QUEUE_BITS=3)(
 input i_clk,input i_rstn,input i_begin,input i_run,input [2:0] i_stage,input [15:0] i_epoch,
 output [4:0] o_read_voice,input [511:0] i_profile,input [383:0] i_state,
 output o_valid,input i_ready,output [351:0] o_data,output [20:0] o_user
);
 localparam C_DEPTH=1<<C_QUEUE_BITS;
 reg [5:0] cnt_fetch;
 reg [C_QUEUE_BITS:0] cnt_reserved,cnt_queued;
 reg [C_QUEUE_BITS-1:0] reg_write,reg_read;
 reg flag_read,flag_pack;
 reg [20:0] reg_read_user,reg_pack_user;
 reg [351:0] reg_pack_data;
 reg [49:0] reg_depth_product;
 reg [351:0] mem_data[0:C_DEPTH-1];
 reg [20:0] mem_user[0:C_DEPTH-1];
 reg [351:0] enc_task,enc_final;
 wire flag_fetch=i_run&&(cnt_fetch<C_VOICES)&&(cnt_reserved<C_DEPTH)&&!i_begin;
 wire flag_issue=o_valid&&i_ready;
 wire [53:0] wire_query={i_profile[192:177],i_profile[195:193],(i_stage==1?i_profile[173:171]:i_profile[176:174]),(i_stage==1?i_state[31:0]:i_state[63:32])};
 wire [31:0] wire_depth=i_stage==2?i_profile[95:64]:i_profile[227:196];
 assign o_read_voice=cnt_fetch[4:0];
 assign o_valid=i_run&&(cnt_queued!=0)&&!i_begin;
 assign o_data=mem_data[reg_read];assign o_user=mem_user[reg_read];
 always @(*)begin
  enc_task=0;
  case(i_stage)
   0:enc_task={224'd0,64'd0,i_profile[31:0],i_state[31:0]};
   1,3:enc_task={298'd0,wire_query};
   2:enc_task={224'd0,32'd0,i_state[284:253],i_profile[63:32],i_state[63:32]};
   4:enc_task={240'd0,2'd0,i_profile[170:169],i_profile[168:96],i_state[98:64]};
   5:enc_task={216'd0,5'd0,i_profile[480:449],i_profile[481],i_profile[229:228],32'd0,i_state[284:253],i_state[316:285]};
   6:enc_task={7'd0,i_profile[367:361],i_state[95:78],2'd0,1'b0,
    (i_profile[368]?i_profile[360:358]:3'd1),
    (i_profile[368]?i_profile[357:326]:32'd268435456),
    (i_profile[368]?i_profile[325:294]:32'd5368709),
    (i_profile[368]?i_profile[293:262]:32'd268435456),
    (i_profile[368]?i_profile[261:230]:32'd13421773),i_state[252:99],(i_profile[368]?i_state[348:317]:32'd0)};
   7:enc_task={240'd0,2'd0,i_profile[170:169],i_profile[448:376],i_state[383:349]};
   default:enc_task=0;
  endcase
 end
 always @(*)begin
  enc_final=reg_pack_data;
  if(i_stage==2)enc_final[127:96]=reg_depth_product[49:18];
  if(i_stage==5)enc_final[95:64]=reg_depth_product[49:18];
 end
 always @(posedge i_clk)begin
  if(flag_pack&&!i_begin)begin mem_data[reg_write]<=enc_final;mem_user[reg_write]<=reg_pack_user;end
 end
 always @(posedge i_clk or negedge i_rstn)begin
  if(!i_rstn)begin
   cnt_fetch<=0;cnt_reserved<=0;cnt_queued<=0;reg_write<=0;reg_read<=0;
   flag_read<=0;flag_pack<=0;reg_read_user<=0;reg_pack_user<=0;reg_pack_data<=0;reg_depth_product<=0;
  end else if(i_begin)begin
   cnt_fetch<=0;cnt_reserved<=0;cnt_queued<=0;reg_write<=0;reg_read<=0;flag_read<=0;flag_pack<=0;
  end else begin
   flag_read<=flag_fetch;flag_pack<=flag_read;
   if(flag_fetch)begin cnt_fetch<=cnt_fetch+1'b1;reg_read_user<={i_epoch,cnt_fetch[4:0]};end
   if(flag_read)begin reg_pack_data<=enc_task;reg_depth_product<=wire_depth*i_state[380:363];reg_pack_user<=reg_read_user;end
   if(flag_pack)reg_write<=reg_write+1'b1;
   if(flag_issue)reg_read<=reg_read+1'b1;
   case({flag_fetch,flag_issue})
    2'b10:cnt_reserved<=cnt_reserved+1'b1;
    2'b01:cnt_reserved<=cnt_reserved-1'b1;
    default:begin end
   endcase
   case({flag_pack,flag_issue})
    2'b10:cnt_queued<=cnt_queued+1'b1;
    2'b01:cnt_queued<=cnt_queued-1'b1;
    default:begin end
   endcase
  end
 end
endmodule
