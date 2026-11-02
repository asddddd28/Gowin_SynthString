`timescale 1ns/1ps
// Reference-vector scoreboard: independent envelope lane and mixed private fabric.
// Input drivers change only after a recorded clock-edge handshake.
module tb_voice_fabric(output o_done);
    reg completed = 0;
    assign o_done = completed; // 外层仿真夹具可观察所有检查完成。
    reg clk = 0;
    always #10 clk = !clk;
    reg rstn = 0;
    reg run = 0;
    reg [319:0] ed = 0, fd = 0;
    reg [31:0] et = 0, ft = 0;
    reg [7:0] dest = 0;
    reg last = 1, ev = 0, fv = 0, er = 0, fr = 0;
    wire ei, fi, eo, fo, fl;
    wire [63:0] eq;
    wire [127:0] fq;
    wire [31:0] eut, fut;
    wire [7:0] fdt;
    AxisEnvelopeMulti Env(
        .i_axis_aclk(clk),.i_axis_arstn(rstn),
        .i_s_axis_tdata(ed),.i_s_axis_tuser(et),.i_s_axis_tvalid(ev),.o_s_axis_tready(ei),
        .o_m_axis_tdata(eq),.o_m_axis_tuser(eut),.o_m_axis_tvalid(eo),.i_m_axis_tready(er)
    );
    AxisVoiceFabric Fabric(
        .i_axis_aclk(clk),.i_axis_arstn(rstn),
        .i_s_axis_tdata(fd),.i_s_axis_tuser(ft),.i_s_axis_tdest(dest),.i_s_axis_tlast(last),
        .i_s_axis_tvalid(fv),.o_s_axis_tready(fi),
        .o_m_axis_tdata(fq),.o_m_axis_tuser(fut),.o_m_axis_tdest(fdt),.o_m_axis_tlast(fl),
        .o_m_axis_tvalid(fo),.i_m_axis_tready(fr)
    );
    reg [319:0] ep [0:7391];
    reg [63:0] ex [0:7391];
    reg [319:0] fp [0:1827];
    reg [127:0] fx [0:1827];
    reg [7:0] op [0:1827];
    reg ends [0:1827], wanted [0:1827], started [0:1827], seen [0:1827];
    integer arrival [0:7391];
    integer ec = 0, fc = 0, eg = 0, fg = 0, cycle = 0;
    integer min_latency = 99999, min_ii = 99999, last_accept = -99999;
    integer cancelled = 0, estalls = 0, fstalls = 0;
    integer file_e, file_f, n, code, tag_file, idx;
    reg eat = 0, fat = 0, held_e = 0, held_f = 0;
    reg [95:0] previous_e;
    reg [168:0] previous_f;
    reg [31:0] rng = 32'h12345678;
    initial begin
        file_e = $fopen("vectors/AxisEnvelopeMulti.txt", "r");
        file_f = $fopen("vectors/voice_fabric.txt", "r");
        if (!file_e || !file_f) $fatal(1,"missing vectors");
        for(n=0;n<7392;n=n+1) begin
            code = $fscanf(file_e,"%h %h\n",ep[n],ex[n]);
            if(code!=2) $fatal(1,"bad envelope vector %0d",n);
        end
        for(n=0;n<1828;n=n+1) begin
            code = $fscanf(file_f,"%h %h %h %h %h %h\n",op[n],ends[n],tag_file,fp[n],wanted[n],fx[n]);
            if(code!=6 || tag_file!=n) $fatal(1,"bad fabric vector %0d",n);
            started[n]=0; seen[n]=0;
        end
        $fclose(file_e); $fclose(file_f);
        repeat(3) @(negedge clk);
        rstn=1;
        // Fill blocked pipelines and then cancel them, including a malformed packet drain.
        repeat(30) @(negedge clk);
        rstn=0;
        repeat(3) @(negedge clk);
        run=1;
        @(negedge clk); rstn=1;
        wait(eg==7392 && fg==1800);
        repeat(100) @(negedge clk);
        if(ec!=7392 || fc!=1828 || min_latency!=6 || min_ii!=1 || cancelled==0 || estalls==0 || fstalls==0)
            $fatal(1,"coverage counts E=%0d F=%0d latency=%0d II=%0d reset=%0d stalls=%0d/%0d",ec,fc,min_latency,min_ii,cancelled,estalls,fstalls);
        for(n=0;n<1828;n=n+1) if(seen[n]!==wanted[n]) $fatal(1,"unresolved tag %0d",n);
        completed=1;
        $display("PASS voice_fabric envelopes=%0d beats=%0d completions=%0d min_latency=%0d min_ii=%0d cancelled=%0d stalls=%0d/%0d",eg,fc,fg,min_latency,min_ii,cancelled,estalls,fstalls);
        $finish;
    end
    initial begin #10000000; $fatal(1,"timeout ec=%0d eg=%0d fc=%0d fg=%0d",ec,eg,fc,fg); end
    always @(negedge clk) begin
        rng = {rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(!rstn) begin ev=0; fv=0; er=0; fr=0; end
        else if(!run) begin
            ev=1; ed=ep[0]; et=32'hdeadbeef; er=0;
            fv=1; fd=fp[0]; ft=32'hdeadbeef; dest=0; last=0; fr=0;
        end else begin
            // First window proves II=1; later random and long stalls exercise retention.
            er = cycle<120 || (rng[0] && cycle%211>65);
            fr = cycle<120 || (rng[3] && cycle%173>55);
            if(!ev || eat) begin
                ev = ec<7392 && (cycle<120 || rng[2]);
                if(ev) begin ed=ep[ec]; et=32'hb6000000|ec; end
            end
            if(!fv || fat) begin
                fv = fc<1828 && (cycle<120 || rng[4]);
                if(fv) begin fd=fp[fc]; ft=32'ha5000000|fc; dest=op[fc]; last=ends[fc]; end
            end
        end
    end
    always @(posedge clk) begin
        eat=ev&&ei; fat=fv&&fi;
        if(!rstn) begin
            ec=0; fc=0; eg=0; fg=0; cycle=0; held_e=0; held_f=0;
        end else if(!run) begin
            if(eat) cancelled=cancelled+1;
            if(fat) cancelled=cancelled+1;
        end else begin
            cycle=cycle+1;
            if(held_e && (!eo || {eut,eq}!==previous_e)) $fatal(1,"EG output changed while stalled");
            if(held_f && (!fo || {fl,fdt,fut,fq}!==previous_f)) $fatal(1,"fabric output changed while stalled");
            held_e=eo&&!er; previous_e={eut,eq};
            held_f=fo&&!fr; previous_f={fl,fdt,fut,fq};
            if(held_e) estalls=estalls+1;
            if(held_f) fstalls=fstalls+1;
            if(eat) begin
                arrival[ec]=cycle;
                if(ec>0 && cycle-last_accept<min_ii) min_ii=cycle-last_accept;
                last_accept=cycle; ec=ec+1;
            end
            if(fat) begin started[fc]=1; fc=fc+1; end
            if(eo&&er) begin
                if(eg>=ec || eut!==(32'hb6000000|eg) || eq!==ex[eg])
                    $fatal(1,"EG mismatch index=%0d tag=%h got=%h expected=%h",eg,eut,eq,ex[eg]);
                if(cycle-arrival[eg]<min_latency) min_latency=cycle-arrival[eg];
                eg=eg+1;
            end
            if(fo&&fr) begin
                idx=fut[23:0];
                if(fut[31:24]!==8'ha5 || idx>=1828) $fatal(1,"stale/invalid tag %h",fut);
                if(!started[idx] || seen[idx] || !wanted[idx] || fq!==fx[idx] || fdt!==op[idx] || !fl)
                    $fatal(1,"fabric mismatch tag=%h got=%h expected=%h opcode=%h expected=%h",fut,fq,fx[idx],fdt,op[idx]);
                seen[idx]=1; fg=fg+1;
            end
        end
    end
endmodule
