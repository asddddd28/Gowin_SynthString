`timescale 1ns/1ps
// AXI4 slave BFM: independent channels, bursts, errors, snapshots, queue pressure.
module tb_axi_voice_endpoint(output o_done);
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
    always #10 clk = !clk;
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
        .i_pcm_ready(1'b1),.o_pcm_valid(),.o_pcm_data(),.o_pcm_frame()
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
    initial begin
        fd=$fopen("vectors/voice_fabric.txt","r");
        if(!fd) $fatal(1,"missing fabric vectors");
        for(n=0;n<1828;n=n+1) begin
            code=$fscanf(fd,"%h %h %h %h %h %h\n",op[n],ends[n],tag_file,fp[n],wanted[n],fx[n]);
            if(code!=6) $fatal(1,"vector format");
        end
        $fclose(fd);
        fd=$fopen("vectors/AxisEnvelopeMulti.txt","r");
        for(n=0;n<7392;n=n+1) code=$fscanf(fd,"%h %h\n",ep[n],ex[n]);
        $fclose(fd);
        repeat(3) @(negedge clk); rstn=1;
        check_word(0,32'h56534531,0); check_word(4,32'h00010006,0); check_word(12,31,0);
        check_word(16'h200,0,2); write_word(16'h218,1); expect_b(2);

        // W-before-AW, partial byte strobes, and no-op strobe.
        wr[0]=32'h12345678; write_burst(16'h100,0,1,2,1,0,15,4'h1,1); expect_b(0);
        wr[0]=32'habcd4321; write_burst(16'h100,0,1,2,1,0,5,4'h2,0); expect_b(0);
        check_word(16'h100,32'h12cd5621,0);
        wr[0]=0; write_burst(16'h100,0,1,2,1,0,0,4'h2,0); expect_b(0);
        check_word(16'h100,32'h12cd5621,0);

        // Valid FIXED length16, and invalid FIXED length17.
        for(j=0;j<17;j=j+1) wr[j]=j;
        write_burst(16'h100,15,16,2,0,0,15,4'hf,0); expect_b(0);
        check_word(16'h100,15,0);
        write_burst(16'h100,16,17,2,0,0,15,4'hf,0); expect_b(2);
        check_word(16'h100,15,0);
        read_burst(16'h100,15,2,0,0);
        for(j=0;j<16;j=j+1) if(rd[j]!==15 || rr[j]!==0) $fatal(1,"FIXED read");
        read_burst(16'h100,16,2,0,0);
        for(j=0;j<17;j=j+1) if(rr[j]!==2) $fatal(1,"invalid FIXED read");

        // Reject unsupported addressing and permissions, with no stage change.
        wr[0]=32'h87654321; wr[1]=32'hdeadbeef;
        write_burst(16'h100,0,1,1,1,0,15,4'h4,0); expect_b(2);
        write_burst(16'h102,0,1,2,1,0,15,4'h4,0); expect_b(2);
        write_burst(16'h100,0,1,2,2,0,15,4'h4,0); expect_b(2);
        write_burst(16'h100,0,1,2,1,1,15,4'h4,0); expect_b(2);
        write_burst(16'hffc,1,2,2,1,0,15,4'h4,0); expect_b(2);
        write_burst(16'h100,1,1,2,1,0,15,4'h4,0); expect_b(2); // Early WLAST.
        write_burst(16'h100,0,2,2,1,0,15,4'h4,0); expect_b(2); // Late WLAST.
        check_word(16'h100,15,0);
        write_word(0,1); expect_b(2);
        read_burst(16'h100,0,1,1,0); if(rr[0]!==2) $fatal(1,"SIZE accepted");
        read_burst(16'h102,0,2,1,0); if(rr[0]!==2) $fatal(1,"unaligned accepted");
        read_burst(16'h100,0,2,2,0); if(rr[0]!==2) $fatal(1,"WRAP accepted");
        read_burst(16'h100,0,2,1,1); if(rr[0]!==2) $fatal(1,"LOCK accepted");
        read_burst(16'hffc,1,2,1,0);
        if(rr[0]!==2 || rr[1]!==2) $fatal(1,"4KiB crossing accepted");
        read_burst(16'h400,255,2,1,0); // Legal max-length burst to unmapped range.
        for(j=0;j<256;j=j+1) if(rr[j]!==2 || rd[j]!==0) $fatal(1,"256 beat read error");
        for(j=0;j<256;j=j+1) wr[j]=j;
        write_burst(16'h400,255,256,2,1,0,15,4'h7,0); expect_b(2);
        check_word(16'h130,0,2);
        wr[0]=123; wr[1]=1;
        write_burst(16'h12c,1,2,2,1,0,15,4'h4,0); expect_b(2);
        check_word(16'h10,0,0); // Doorbell inside a burst must not submit.

        // Mixed operator results from independent Python semantics.
        for(n=1;n<1050;n=n+7) begin
            if(wanted[n] && ends[n]) begin
                stage(op[n],32'hc7000000|n,fp[n]);
                write_word(16'h130,1); expect_b(0);
                consume(fx[n],32'hc7000000|n,op[n]);
            end
        end

        // Feedback the actual hardware EG result into the next task for 192 samples.
        state_result=0;
        for(n=2784;n<2976;n=n+1) begin
            payload=ep[n];
            payload[31:0]=state_result[31:0];
            payload[34:32]=state_result[34:32];
            stage(4,32'he8000000|n,payload);
            write_word(16'h130,1); expect_b(0);
            consume({64'd0,ex[n]},32'he8000000|n,4);
        end

        // Snapshot at AR remains coherent while POP advances the live FIFO.
        stage(0,32'h11112222,320'h0000000300000000);
        write_word(16'h130,1); expect_b(0);
        stage(0,32'h33334444,320'h0000000700000000);
        write_word(16'h130,1); expect_b(0);
        wait_completion;
        begin_read(16'h200,5,2,1,0,4'h5);
        repeat(4) @(negedge clk); // RVALID now held against backpressure.
        write_word(16'h218,1); expect_b(0);
        finish_read(6);
        verify_completion(128'h00000000000000000000000300000003,32'h11112222,0);
        consume(128'h00000000000000000000000700000007,32'h33334444,0);

        // Fill completion FIFO, pipelines, head slot and command FIFO without POP.
        // Repeated commands are distinguishable by tag; rejected COMMIT is side-effect free.
        stage(0,0,320'h00000003ffffffff);
        accepted=0; errors=0;
        read_burst(16'h10,0,2,1,0); before_count=rd[0];
        while(errors<2 && accepted<64) begin
            write_word(16'h12c,32'hd9000000|accepted); expect_b(0);
            write_word(16'h130,1);
            if(response==0) accepted=accepted+1;
            else if(response==2) errors=errors+1;
            else $fatal(1,"invalid COMMIT response");
        end
        if(accepted==64 || accepted<8) $fatal(1,"queue saturation not reached %0d",accepted);
        check_word(16'h10,before_count+accepted,0);
        read_burst(16'h8,0,2,1,0);
        if(rd[0][2:0]!=4 || rd[0][6:4]!=4 || !rd[0][8]) $fatal(1,"full queue status %h",rd[0]);
        write_word(16'h100,32'hbadbad00); expect_b(0); // Cannot alter committed snapshots.
        for(n=0;n<accepted;n=n+1)
            consume(128'h00000000000000000000000200000002,32'hd9000000|n,0);
        read_burst(16'h8,0,2,1,0);
        if(rd[0]!==32'h200) $fatal(1,"drained queue status %h",rd[0]);
        write_word(16'h218,1); expect_b(2);
        check_word(16'h200,0,2);

        // Reset while an R burst and B response are both stalled, plus queued work.
        stage(0,32'hdeadbeef,320'd0); write_word(16'h130,1); expect_b(0);
        wait_completion;
        begin_read(16'h200,5,2,1,0,4'h2);
        address_write(16'h100,0,2,1,0,4'h8);
        @(negedge clk); wdata=1; wstrb=15; wlast=1; wvalid=1;
        @(posedge clk); while(!wready) @(posedge clk);
        @(negedge clk); wvalid=0;
        repeat(4) @(negedge clk);
        if(!rvalid || !bvalid) $fatal(1,"reset coverage not live");
        rstn=0;
        repeat(3) @(negedge clk);
        if(rvalid || bvalid || awready || arready || wready) $fatal(1,"reset interface not idle");
        rstn=1;
        check_word(16'h10,0,0); check_word(16'h14,0,0); check_word(16'h18,0,0);
        check_word(16'h8,32'h200,0); check_word(16'h200,0,2);
        // Cancel an accepted AW that has not received any W.
        address_write(16'h100,2,2,1,0,4'h8);
        @(negedge clk); rstn=0;
        repeat(3) @(negedge clk); rstn=1;
        repeat(3) @(negedge clk);
        if(wready || bvalid || rvalid) $fatal(1,"old transaction after reset");
        stage(0,32'hffffeeee,320'h0000000100000001);
        write_word(16'h130,1); expect_b(0);
        consume(128'h00000000000000000000000200000002,32'hffffeeee,0);
        check_word(16'h10,1,0); check_word(16'h14,1,0); check_word(16'h18,1,0);

        // Resident PM context, with a separate generation/sequence identity.
        check_word(16'h1c,7,0); check_word(16'h30,32,0);
        write_word(16'h134,32'h00000700); expect_b(0);
        wr[0]=2; write_burst(16'h134,0,1,2,1,0,1,4'h6,0); expect_b(0);
        check_word(16'h134,32'h00000702,0);
        write_word(16'h138,0); expect_b(0);
        stage(8'h80,32'haabc0001,320'h0000000300000001);
        write_word(16'h130,1); expect_b(0); consume(0,32'haabc0001,8'h80);
        stage(8'h90,32'haabc0002,320'd0);
        write_word(16'h130,1); expect_b(0);
        consume(128'h00000000000000000000000400000004,32'haabc0002,8'h90);
        // Same sequence but a new transport tag must replay, not integrate phase again.
        write_word(16'h12c,32'haabc0003); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume((128'd1<<72)|128'h0000000400000004,32'haabc0003,8'h90);
        check_word(16'h20,2,0); check_word(16'h24,1,0);
        // With unchanged live operands, each new tick only writes sequence/tag/COMMIT.
        write_word(16'h138,1); expect_b(0);
        write_word(16'h12c,32'haabc0004); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'h0000000700000007,32'haabc0004,8'h90);
        write_word(16'h100,1); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'd5<<64,32'haabc0004,8'h90); // Conflicting reuse of the same execution ID.
        write_word(16'h100,0); expect_b(0);
        write_word(16'h138,3); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'd7<<64,32'haabc0004,8'h90); // Missing sequence2 cannot be skipped.
        write_word(16'h138,0); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'd6<<64,32'haabc0004,8'h90); // Older replay window entry is rejected.
        write_word(16'h138,2); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'h0000000a0000000a,32'haabc0004,8'h90);
        // Exact BIND retry after state advanced cannot restart the oscillator.
        stage(8'h80,32'haabc0005,320'h0000000300000001);
        write_word(16'h130,1); expect_b(0); consume(128'd1<<72,32'haabc0005,8'h80);
        stage(8'h91,32'haabc0006,320'd0);
        write_word(16'h130,1); expect_b(0);
        consume((128'd2<<80)|(128'd1<<73)|128'd10,32'haabc0006,8'h91);
        stage(8'h80,32'haabc0007,320'h0000000300000002);
        write_word(16'h130,1); expect_b(0); consume(128'd5<<64,32'haabc0007,8'h80);
        // A newer owner reinitializes state; delayed commands from the old owner fail.
        write_word(16'h134,32'h802); expect_b(0);
        stage(8'h80,32'haabc0008,320'h0000000300000001);
        write_word(16'h130,1); expect_b(0); consume(0,32'haabc0008,8'h80);
        stage(8'h91,32'haabc0009,320'd0);
        write_word(16'h130,1); expect_b(0); consume(1,32'haabc0009,8'h91);
        write_word(16'h134,32'h702); expect_b(0);
        stage(8'h90,32'haabc000a,320'd0);
        write_word(16'h130,1); expect_b(0); consume(128'd4<<64,32'haabc000a,8'h90);
        write_word(16'h134,32'h802); expect_b(0);
        write_word(16'h138,0); expect_b(0);
        write_word(16'h130,1); expect_b(0);
        consume(128'h0000000400000004,32'haabc000a,8'h90);
        check_word(16'h20,5,0); check_word(16'h24,2,0);
        check_word(16'h28,5,0); check_word(16'h2c,2,0);
        @(negedge clk); rstn=0;
        repeat(3) @(negedge clk); rstn=1;
        check_word(16'h134,0,0); check_word(16'h138,0,0);
        write_word(16'h134,32'h802); expect_b(0);
        stage(8'h90,32'haabc000b,320'd0);
        write_word(16'h130,1); expect_b(0); consume(128'd3<<64,32'haabc000b,8'h90);
        check_word(16'h20,0,0); check_word(16'h24,0,0); check_word(16'h28,1,0);
        if(b_stalls==0 || r_stalls==0) $fatal(1,"missing backpressure");
        completed=1;
        $display("PASS axi_voice_endpoint writes=%0d reads=%0d checked_completions=%0d saturation_accepted=%0d full_rejected=%0d B_stalls=%0d R_stalls=%0d",writes,reads,dsp,accepted,errors,b_stalls,r_stalls);
        $finish;
    end
endmodule

