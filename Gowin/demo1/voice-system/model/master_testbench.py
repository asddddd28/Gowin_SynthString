"""Adversarial bus slave for the new mailbox master, independent of synth DSP."""
from contracts import PORTS,ROOT,publish


def generate():
    declarations=[]
    mapping=[]
    for direction,name,width in PORTS['SynthAxiMaster']:
        signal={'i_clk':'clk','i_rstn':'rstn'}.get(name,name[2:])
        mapping.append(f'        .{name}({signal})')
        if name in ('i_clk','i_rstn'):continue
        declarations.append('    '+('reg ' if direction=='input' else 'wire ')+(f'[{width-1}:0] ' if width>1 else '')+signal+('=0' if direction=='input' else '')+';')
    text='''`timescale 1ns / 1ps
// AXI stall/error verification / 主控总线异常验证. Contract: spec/tb_synth_master_spec.md.
module tb_synth_master(output o_done);
    reg clk=0,rstn=0,done=0;
    always #10 clk=~clk;
    assign o_done=done;
'''+ '\n'.join(declarations)+'\n    SynthAxiMaster #(.C_WATCHDOG(2048)) Dut(\n'+',\n'.join(mapping)+'\n    );\n'+r'''
    reg [31:0] random_state=32'h7391acb5;
    reg hold_aw=0,inject_b=0,inject_r=0,inject_identity=0;
    reg aw_pending=0,b_pending=0,r_pending=0,completion_present=0;
    reg [15:0] saved_aw;
    reg [31:0] staged[0:14];
    reg [31:0] saved_r;
    reg [1:0] saved_resp;
    reg [127:0] completion;
    reg [31:0] completion_tag,completion_opcode;
    reg [31:0] expected_voice=0,expected_fx=0;
    reg [391:0] gold_request;
    integer executions=0,pops=0,writes=0,reads=0,n,j,accepted=0,stalls=0;
    reg held_aw=0,held_w=0,held_ar=0,held_response=0;
    reg [15:0] previous_aw,previous_ar;
    reg [31:0] previous_w;
    reg [135:0] previous_response;
    reg [135:0] reply;
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        axi_awready=rstn && !hold_aw && !aw_pending && !b_pending && !axi_bvalid && random_state[0];
        axi_wready=rstn && aw_pending && !b_pending && !axi_bvalid && random_state[3];
        axi_arready=rstn && !r_pending && !axi_rvalid && random_state[6];
    end
    always @(posedge clk) begin
        if(!rstn) begin
            aw_pending<=0;b_pending<=0;r_pending<=0;completion_present<=0;
            axi_bvalid<=0;axi_bresp<=0;axi_rvalid<=0;axi_rdata<=0;axi_rresp<=0;axi_rlast<=1;
            expected_voice<=0;expected_fx<=0;executions<=0;pops<=0;
        end else begin
            if(request_valid && request_ready)gold_request=request;
            if(axi_awvalid && axi_awready)begin saved_aw<=axi_awaddr;aw_pending<=1;end
            if(axi_wvalid && axi_wready)begin
                aw_pending<=0;b_pending<=1;writes<=writes+1;
                if(saved_aw>=16'h100 && saved_aw<=16'h12c)staged[(saved_aw-16'h100)/4]<=axi_wdata;
                else if(saved_aw==16'h134)staged[12]<=axi_wdata;
                else if(saved_aw==16'h138)staged[13]<=axi_wdata;
                else if(saved_aw==16'h130)begin
                    if(axi_wdata!=1 || staged[10]!=={24'd0,gold_request[327:320]} || staged[11]!==gold_request[391:360] || staged[12]!=={24'd1,gold_request[335:328]})$fatal(1,"staged metadata mismatch");
                    for(j=0;j<10;j=j+1)if(staged[j]!==gold_request[j*32+:32])$fatal(1,"payload word %0d",j);
                    if(staged[10]==8'hc4)begin
                        if(staged[13]!==expected_fx)$fatal(1,"FX sequence");expected_fx<=expected_fx+1;
                    end else begin
                        if(staged[13]!==expected_voice)$fatal(1,"voice sequence");expected_voice<=expected_voice+1;
                    end
                    completion<={32'h12345678,32'd0,staged[11],staged[0]};
                    completion_tag<=staged[11]+inject_identity;completion_opcode<=staged[10];
                    completion_present<=1;executions<=executions+1;
                end else if(saved_aw==16'h218)begin
                    if(!completion_present || axi_wdata!=1)$fatal(1,"bad POP");
                    completion_present<=0;pops<=pops+1;
                end else $fatal(1,"unexpected write address");
            end
            if(b_pending && random_state[9])begin axi_bvalid<=1;axi_bresp<=inject_b ? 2'd2 : 2'd0;b_pending<=0;end
            if(axi_bvalid && axi_bready)axi_bvalid<=0;
            if(axi_arvalid && axi_arready)begin
                r_pending<=1;reads<=reads+1;saved_resp<=inject_r ? 2'd2 : 2'd0;
                case(axi_araddr)
                    16'h004:saved_r<=32'h00010005;
                    16'h008:saved_r<=completion_present ? 32'h10 : 32'd0;
                    16'h200:saved_r<=completion[31:0];
                    16'h204:saved_r<=completion[63:32];
                    16'h208:saved_r<=completion[95:64];
                    16'h20c:saved_r<=completion[127:96];
                    16'h210:saved_r<=completion_tag;
                    16'h214:saved_r<=completion_opcode;
                    default:begin saved_r<=0;saved_resp<=2;end
                endcase
            end
            if(r_pending && random_state[12])begin axi_rvalid<=1;axi_rdata<=saved_r;axi_rresp<=saved_resp;r_pending<=0;end
            if(axi_rvalid && axi_rready)axi_rvalid<=0;
        end
    end
    always @(posedge clk) begin
        if(!rstn)begin held_aw=0;held_w=0;held_ar=0;held_response=0;end
        else begin
            if(held_aw && (!axi_awvalid || axi_awaddr!==previous_aw))$fatal(1,"AW unstable");
            if(held_w && (!axi_wvalid || axi_wdata!==previous_w))$fatal(1,"W unstable");
            if(held_ar && (!axi_arvalid || axi_araddr!==previous_ar))$fatal(1,"AR unstable");
            if(held_response && (!response_valid || response!==previous_response))$fatal(1,"completion unstable");
            held_aw=axi_awvalid&&!axi_awready;previous_aw=axi_awaddr;
            held_w=axi_wvalid&&!axi_wready;previous_w=axi_wdata;
            held_ar=axi_arvalid&&!axi_arready;previous_ar=axi_araddr;
            held_response=response_valid&&!response_ready;previous_response=response;
            if(held_aw || held_w || held_ar || held_response)stalls=stalls+1;
        end
    end
    task reset_all;
        begin
            @(negedge clk);rstn=0;request_valid=0;response_ready=0;hold_aw=0;inject_b=0;inject_r=0;inject_identity=0;
            repeat(4)@(negedge clk);rstn=1;
        end
    endtask
    task submit;
        input [391:0] image;
        begin
            @(negedge clk);request=image;request_valid=1;
            @(posedge clk);while(!request_ready)@(posedge clk);
            @(negedge clk);request_valid=0;request=0;accepted=accepted+1;
        end
    endtask
    task receive;
        input [7:0] status;
        begin
            while(!response_valid)@(negedge clk);
            reply=response;
            repeat(9)@(negedge clk);
            if(reply[135:128]!=status)$fatal(1,"transport error got=%h expected=%h",reply,status);
            response_ready=1;@(negedge clk);response_ready=0;
        end
    endtask
    reg [391:0] image;
    integer before_exec;
    initial begin
        reset_all;
        for(n=0;n<96;n=n+1)begin
            image=0;
            image[327:320]=n%3==0 ? 8'hc4 : 8'ha9;
            image[335:328]=n;
            image[391:360]=32'h35000000+n;
            for(j=0;j<10;j=j+1)image[j*32+:32]=(n<<8)|j;
            submit(image);receive(0);
            if(reply[127:0]!=={32'h12345678,32'd0,32'h35000000+n,32'(n<<8)})$fatal(1,"readback result");
            if(n%4==0)begin
                image=0;image[336]=1;image[359:344]=4;
                before_exec=executions;submit(image);receive(0);
                if(reply[31:0]!=32'h00010005 || executions!=before_exec)$fatal(1,"read command executed write");
            end
        end
        if(executions!=96 || pops!=96 || fault)$fatal(1,"normal traffic totals");
        reset_all;hold_aw=1;image=0;image[327:320]=8'ha9;
        submit(image);repeat(2100)@(negedge clk);
        if(!fault || !axi_awvalid)$fatal(1,"watchdog withdrew VALID or failed to flag");
        hold_aw=0;receive(6);
        if(executions!=0 || request_ready)$fatal(1,"timed-out command executed or accepted new work");
        reset_all;inject_b=1;submit(image);receive(6);
        if(!fault || executions!=0)$fatal(1,"BRESP error not contained");
        reset_all;inject_r=1;image=0;image[336]=1;image[359:344]=4;submit(image);receive(6);
        if(!fault)$fatal(1,"RRESP error not contained");
        reset_all;inject_identity=1;image=0;image[327:320]=8'ha9;submit(image);receive(6);
        if(!fault || pops!=0)$fatal(1,"wrong completion owner was popped");
        reset_all;hold_aw=1;submit(image);repeat(12)@(negedge clk);reset_all;
        if(axi_awvalid || response_valid || fault)$fatal(1,"reset did not cancel");
        submit(image);receive(0);
        done=1;
        $display("PASS synth_master normal_commands=96 reads=24 requests=%0d stalled_cycles=%0d watchdog/BRESP/RRESP/identity/reset=PASS",accepted,stalls);
        $finish;
    end
    initial begin #30000000;$fatal(1,"master watchdog");end
endmodule
'''
    # Verilog-2001 avoids a SystemVerilog sized cast in the test expression.
    text=text.replace("32'(n<<8)","(n<<8)")
    (ROOT/'sim/tb_synth_master.v').write_text(text,encoding='utf-8')
    publish('tb_synth_master',[('output','o_done',1)],['Random AXI channel stalls, payload/sequence ownership, response pressure, errors, watchdog containment and reset cancellation.'],'sim/tb_synth_master.v')


if __name__=='__main__':generate()
