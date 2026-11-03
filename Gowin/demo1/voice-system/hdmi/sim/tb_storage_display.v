`timescale 1ns/1ps
module tb_storage_display;
    reg clk=0,rstn=0;
    reg [2:0] page=6;
    wire write;wire [9:0] address;wire [7:0] data;wire [5:0] title_address;
    reg [7:0] text_ram[0:1023];integer i,writes=0;
    always #10 clk=~clk;
    SynthStorageDisplay Dut(.i_clk(clk),.i_rstn(rstn),.i_page(page),.i_slot(2'd2),.i_delete_mode(1'b0),
        .i_status(32'd3),.i_ready(1'b1),.i_busy(1'b0),.i_dirty(1'b0),.i_error(8'd0),
        .i_sequence(8'd12),.i_preset(8'd49),.i_sequence_count(8'd8),.i_preset_count(8'd49),
        .i_sequence_status(32'd2),.i_bpm(9'd120),.o_title_address(title_address),.i_title(title_address==0 ? 8'd80 : 8'd32),
        .o_write(write),.o_address(address),.o_data(data));
    always @(posedge clk)if(write)begin
        if(!((address>=128 && address<384) || (address>=512 && address<640) || (address>=832 && address<864)))$fatal(1,"out-of-page text write");
        text_ram[address]<=data;writes=writes+1;
    end
    task refresh;
        begin @(negedge clk);rstn=0;@(negedge clk);rstn=1;repeat(420)@(negedge clk);end
    endtask
    initial begin
        for(i=0;i<1024;i=i+1)text_ram[i]=0;
        refresh();
        if(writes!=416 || {text_ram[128],text_ram[129]}!="SD")$fatal(1,"ROM pipeline misaligned");
        if({text_ram[174],text_ram[175],text_ram[176]}!="012")$fatal(1,"sequence number");
        if({text_ram[198],text_ram[199],text_ram[200]}!="008" || text_ram[212]!="3")$fatal(1,"count / slot");
        if({text_ram[260],text_ram[261],text_ram[262]}!="120")$fatal(1,"BPM");
        page=7;refresh();
        if({text_ram[174],text_ram[175],text_ram[176]}!="049" || text_ram[224]!="P")$fatal(1,"preset metadata");
        page=0;writes=0;refresh();if(writes!=0)$fatal(1,"renderer overwrote sound page");
        $display("PASS storage display ROM, address/valid alignment, decimal fields and page isolation");$finish;
    end
endmodule
