`timescale 1ns/1ps
// AXI4 slave BFM: independent channels, bursts, errors, snapshots, queue pressure.
module tb_axi_synth_engine(output o_done);
    reg completed = 0;
    assign o_done = completed; // 外层仿真夹具可观察所有检查完成。
    reg clk = 0;
    reg rstn = 0;
    reg [3:0] awid = 0;
    reg [15:0] awaddr = 0;
    reg [7:0] awlen = 0;
    reg [2:0] awsize = 0;
    reg [1:0] awburst = 0;
    reg awlock = 0;
    reg awvalid = 0;
    wire awready;
    reg [3:0] arid = 0;
    reg [15:0] araddr = 0;
    reg [7:0] arlen = 0;
    reg [2:0] arsize = 0;
    reg [1:0] arburst = 0;
    reg arlock = 0;
    reg arvalid = 0;
    wire arready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wlast = 0;
    reg wvalid = 0;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    wire [3:0] rid;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    reg rready = 0;
    reg pcm_ready=1;
    wire pcm_valid;
    wire [63:0] pcm_data;
    wire [31:0] pcm_frame;
    reg [95:0] held_pcm,snapshot_expected;
    reg was_stalled=0;
    integer nonzero_pcm=0,pcm_count=0,engine_seq=0,engine_tag=0;
    reg [319:0] core_rows[0:5],eg_rows[0:5];
    reg [127:0] control_result;
    always #10 clk = !clk;
    always @(posedge clk) begin
        if(!rstn) was_stalled=0;
        else begin
            if(was_stalled && (!pcm_valid || {pcm_frame,pcm_data}!==held_pcm)) $fatal(1,"PCM changed under backpressure");
            was_stalled=pcm_valid&&!pcm_ready;
            held_pcm={pcm_frame,pcm_data};
            if(pcm_valid&&pcm_ready) begin
                pcm_count=pcm_count+1;
                if(pcm_data!=0) nonzero_pcm=nonzero_pcm+1;
            end
        end
    end
    AxiVoiceEndpoint Dut(
        .i_axi_aclk(clk),
        .i_axi_arstn(rstn),
        .i_s_axi_awid(awid),
        .i_s_axi_awaddr(awaddr),
        .i_s_axi_awlen(awlen),
        .i_s_axi_awsize(awsize),
        .i_s_axi_awburst(awburst),
        .i_s_axi_awlock(awlock),
        .i_s_axi_awvalid(awvalid),
        .o_s_axi_awready(awready),
        .i_s_axi_arid(arid),
        .i_s_axi_araddr(araddr),
        .i_s_axi_arlen(arlen),
        .i_s_axi_arsize(arsize),
        .i_s_axi_arburst(arburst),
        .i_s_axi_arlock(arlock),
        .i_s_axi_arvalid(arvalid),
        .o_s_axi_arready(arready),
        .i_s_axi_wdata(wdata),
        .i_s_axi_wstrb(wstrb),
        .i_s_axi_wlast(wlast),
        .i_s_axi_wvalid(wvalid),
        .o_s_axi_wready(wready),
        .o_s_axi_bid(bid),
        .o_s_axi_bresp(bresp),
        .o_s_axi_bvalid(bvalid),
        .i_s_axi_bready(bready),
        .o_s_axi_rid(rid),
        .o_s_axi_rdata(rdata),
        .o_s_axi_rresp(rresp),
        .o_s_axi_rlast(rlast),
        .o_s_axi_rvalid(rvalid),
        .i_s_axi_rready(rready),
        .i_pcm_ready(pcm_ready),.o_pcm_valid(pcm_valid),.o_pcm_data(pcm_data),.o_pcm_frame(pcm_frame)
    );

    reg [31:0] wr [0:255], rd [0:255];
    reg [1:0] rr [0:255];
    reg [319:0] fp [0:1827], ep [0:7391];
    reg [127:0] fx [0:1827];
    reg [63:0] ex [0:7391];
    reg [7:0] op [0:1827];
    reg ends [0:1827], wanted [0:1827];
    reg [1:0] response;
    reg [31:0] rng = 32'hf153a902;
    reg [319:0] payload;
    reg [63:0] state_result = 0;
    reg [5:0] prev_b;
    reg [38:0] prev_r;
    reg held_b = 0, held_r = 0;
    integer b_stalls = 0, r_stalls = 0, writes = 0, reads = 0, dsp = 0;
    integer n, j, fd, code, tag_file, accepted, errors, before_count;
    reg [3:0] read_id = 0;

    task address_write;
        input [15:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        input [3:0] identity;
        begin
            @(negedge clk);
            awaddr=address; awlen=length; awsize=size; awburst=burst; awlock=locked; awid=identity; awvalid=1;
            @(posedge clk);
            while(!awready) @(posedge clk);
            @(negedge clk); awvalid=0;
        end
    endtask

    task get_write_response;
        input [3:0] identity;
        begin
            // Deliberately leave B blocked before accepting it.
            repeat(4) @(negedge clk);
            @(posedge clk);
            while(!bvalid) @(posedge clk);
            if(bid!==identity) $fatal(1,"BID mismatch");
            response=bresp;
            @(negedge clk); bready=1;
            @(posedge clk);
            if(!bvalid) $fatal(1,"BVALID withdrawn");
            @(negedge clk); bready=0;
            writes=writes+1;
        end
    endtask

    task write_burst;
        input [15:0] address;
        input [7:0] length;
        input integer beats;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        input [3:0] strobe;
        input [3:0] identity;
        input early_w;
        integer k;
        begin
            if(early_w) begin
                @(negedge clk); wdata=wr[0]; wstrb=strobe; wlast=beats==1; wvalid=1;
                repeat(3) begin @(posedge clk); if(wready || bvalid) $fatal(1,"W accepted without AW"); end
            end
            address_write(address,length,size,burst,locked,identity);
            for(k=0;k<beats;k=k+1) begin
                if(!(early_w && k==0)) begin
                    repeat((k%3)+1) @(negedge clk);
                    wdata=wr[k]; wstrb=strobe; wlast=k==beats-1; wvalid=1;
                end
                @(posedge clk);
                while(!wready) @(posedge clk);
                @(negedge clk); wvalid=0;
            end
            get_write_response(identity);
        end
    endtask

    task write_word;
        input [15:0] address;
        input [31:0] value;
        begin
            wr[0]=value;
            write_burst(address,0,1,2,1,0,15,4'h9,0);
        end
    endtask

    task expect_b;
        input [1:0] expected;
        begin if(response!==expected) $fatal(1,"BRESP expected=%h got=%h address=%h",expected,response,awaddr); end
    endtask

    task begin_read;
        input [15:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        input [3:0] identity;
        begin
            @(negedge clk);
            araddr=address; arlen=length; arsize=size; arburst=burst; arlock=locked; arid=identity; arvalid=1;
            @(posedge clk);
            while(!arready) @(posedge clk);
            @(negedge clk); arvalid=0;
            read_id=identity;
        end
    endtask

    task finish_read;
        input integer beats;
        integer k;
        begin
            for(k=0;k<beats;k=k+1) begin
                repeat((k%4)+2) @(negedge clk);
                rready=1;
                @(posedge clk);
                while(!rvalid) @(posedge clk);
                if(rid!==read_id || rlast!==(k==beats-1)) $fatal(1,"RID/RLAST mismatch beat=%0d",k);
                rd[k]=rdata; rr[k]=rresp;
                @(negedge clk); rready=0;
            end
            reads=reads+1;
        end
    endtask

    task read_burst;
        input [15:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        input locked;
        begin
            begin_read(address,length,size,burst,locked,4'hd);
            finish_read(length+1);
        end
    endtask

    task check_word;
        input [15:0] address;
        input [31:0] expected;
        input [1:0] status;
        begin
            read_burst(address,0,2,1,0);
            if(rr[0]!==status || rd[0]!==expected) $fatal(1,"read %h got=%h/%h expected=%h/%h",address,rd[0],rr[0],expected,status);
        end
    endtask

    task stage;
        input [7:0] operation;
        input [31:0] tag;
        input [319:0] raw;
        integer k;
        begin
            for(k=0;k<10;k=k+1) wr[k]=raw[k*32+:32];
            wr[10]={24'd0,operation}; wr[11]=tag;
            write_burst(16'h100,11,12,2,1,0,15,4'h3,0); expect_b(0);
        end
    endtask

    task wait_completion;
        integer tries;
        begin
            tries=0;
            read_burst(16'h8,0,2,1,0);
            while(rd[0][6:4]==0 && tries<100) begin
                read_burst(16'h8,0,2,1,0); tries=tries+1;
            end
            if(tries==100 || rr[0]!=0) $fatal(1,"completion timeout");
        end
    endtask

    task verify_completion;
        input [127:0] expected;
        input [31:0] tag;
        input [7:0] operation;
        integer k;
        begin
            for(k=0;k<6;k=k+1) if(rr[k]!==0) $fatal(1,"completion read error");
            if({rd[3],rd[2],rd[1],rd[0]}!==expected || rd[4]!==tag || rd[5]!=={24'd0,operation})
                $fatal(1,"completion got=%h tag=%h op=%h expected=%h tag=%h op=%h",{rd[3],rd[2],rd[1],rd[0]},rd[4],rd[5],expected,tag,operation);
            dsp=dsp+1;
        end
    endtask

    task consume;
        input [127:0] expected;
        input [31:0] tag;
        input [7:0] operation;
        begin
            wait_completion;
            read_burst(16'h200,5,2,1,0);
            verify_completion(expected,tag,operation);
            state_result={rd[1],rd[0]};
            write_word(16'h218,1); expect_b(0);
        end
    endtask

    always @(posedge clk) begin
        if(!rstn) begin held_b=0; held_r=0; end
        else begin
            if(held_b && (!bvalid || {bid,bresp}!==prev_b)) $fatal(1,"B response changed during stall");
            if(held_r && (!rvalid || {rid,rdata,rresp,rlast}!==prev_r)) $fatal(1,"R response changed during stall");
            held_b=bvalid&&!bready; prev_b={bid,bresp};
            held_r=rvalid&&!rready; prev_r={rid,rdata,rresp,rlast};
            if(held_b) b_stalls=b_stalls+1;
            if(held_r) r_stalls=r_stalls+1;
        end
    end

    initial begin #30000000; $fatal(1,"AXI timeout writes=%0d reads=%0d dsp=%0d",writes,reads,dsp); end
    task control;
        input [7:0] operation,address;
        input [319:0] image;
        input [7:0] status;
        begin
            stage(operation,engine_tag,image);
            write_word(16'h134,{24'd55,address}); expect_b(0);
            write_word(16'h138,engine_seq); expect_b(0);
            write_word(16'h130,1); expect_b(0);
            wait_completion;
            read_burst(16'h200,5,2,1,0);
            control_result={rd[3],rd[2],rd[1],rd[0]};
            if(control_result[71:64]!==status || rd[4]!==engine_tag || rd[5]!==operation) $fatal(1,"control result %h",control_result);
            write_word(16'h218,1); expect_b(0);
            engine_seq=engine_seq+1; engine_tag=engine_tag+1;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rstn=1;
        check_word(4,32'h00010005,0); check_word(16'h34,32'h0008063f,0);
        fd=$fopen("vectors/engine_patch.txt","r");
        for(n=0;n<6;n=n+1) begin
            code=$fscanf(fd,"%h %h\n",core_rows[n],eg_rows[n]); if(code!=2) $fatal(1,"patch vectors");
        end
        control(8'ha0,0,1,0);
        for(n=0;n<6;n=n+1) begin control(8'ha1,n,core_rows[n],0); control(8'ha2,n,eg_rows[n],0); end
        control(8'ha3,0,0,0);
        control(8'ha7,0,{256'd0,32'd67108864,32'd1},0);
        control(8'ha4,0,{192'd0,32'd33554432,32'd67108864,32'd38654706,32'd900},0);
        repeat(1024*32) @(negedge clk);
        if(nonzero_pcm<25) $fatal(1,"AXI note did not produce continuous PCM");
        check_word(16'h38,1,0); check_word(16'h3c,0,0);
        // PCM output stalls do not stop rendering or overwrite the held head.
        @(negedge clk); pcm_ready=0;
        repeat(1024*10) @(negedge clk);
        read_burst(16'h44,0,2,1,0); if(rd[0]<5) $fatal(1,"missing PCM overflow telemetry");
        begin_read(16'h300,3,2,1,0,4'ha);
        @(negedge clk); snapshot_expected={pcm_frame,pcm_data}; pcm_ready=1;
        finish_read(4);
        if({rd[2],rd[1],rd[0]}!==snapshot_expected || rd[3]!==1) $fatal(1,"PCM snapshot torn while FIFO drained");
        engine_seq=engine_seq-1;
        control(8'ha4,0,{192'd0,32'd33554432,32'd67108864,32'd38654706,32'd900},0);
        if(!control_result[72]) $fatal(1,"AXI retry not cached");
        check_word(16'h38,1,0);
        stage(0,32'h12345678,320'h0000000300000001);
        write_word(16'h130,1); expect_b(0);
        consume(128'h0000000400000004,32'h12345678,0);
        // New parameter bank can be loaded while the existing voice plays.
        control(8'ha0,0,2,0);
        for(n=0;n<6;n=n+1) begin
            core_rows[n][63:32]=0;
            control(8'ha1,n,core_rows[n],0); control(8'ha2,n,eg_rows[n],0);
        end
        control(8'ha3,0,0,0);
        repeat(1024*6) @(negedge clk);
        before_count=nonzero_pcm;
        repeat(1024*6) @(negedge clk);
        if(nonzero_pcm!=before_count) $fatal(1,"committed zero gains not applied");
        control(8'ha5,0,900,0);
        repeat(1024*20) @(negedge clk);
        check_word(16'h38,0,0); check_word(16'h3c,0,0);
        control(8'ha7,0,{256'd0,32'd67108864,32'd4},0);
        completed=1;
        $display("PASS axi_synth_engine control_commands=%0d pcm_consumed=%0d nonzero_pcm=%0d snapshot/replay/live_commit/legacy/overflow=PASS",engine_tag,pcm_count,nonzero_pcm);
        $finish;
    end
endmodule
