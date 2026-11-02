`timescale 1ns / 1ps
// Contract: spec/SynthCommandArbiter_spec.md.
module SynthCommandArbiter(
    input i_clk,
    input i_rstn,
    output [391:0] o_request,
    output o_request_valid,
    input i_request_ready,
    input [135:0] i_response,
    input i_response_valid,
    output o_response_ready,
    input i_boot_done,
    input [391:0] i_boot_request,
    input i_boot_request_valid,
    output o_boot_request_ready,
    output [135:0] o_boot_response,
    output o_boot_response_valid,
    input i_boot_response_ready,
    input [391:0] i_key_request,
    input i_key_request_valid,
    output o_key_request_ready,
    output [135:0] o_key_response,
    output o_key_response_valid,
    input i_key_response_ready,
    input [391:0] i_host_request,
    input i_host_request_valid,
    output o_host_request_ready,
    output [135:0] o_host_response,
    output o_host_response_valid,
    input i_host_response_ready
);

    reg flag_owned,flag_prefer_host,flag_offered;
    reg [1:0] reg_owner,reg_offer_owner;
    reg [391:0] reg_offer;
    wire [1:0] wire_choice=!i_boot_done ? 2'd0 :
        (i_host_request_valid && (!i_key_request_valid || flag_prefer_host) ? 2'd2 : 2'd1);
    wire flag_offer=!flag_owned && !flag_offered && (wire_choice==0 ? i_boot_request_valid : wire_choice==1 ? i_key_request_valid : i_host_request_valid);
    assign o_request=reg_offer;
    assign o_request_valid=flag_offered;
    assign o_boot_request_ready=!flag_owned && !flag_offered && wire_choice==0;
    assign o_key_request_ready=!flag_owned && !flag_offered && wire_choice==1;
    assign o_host_request_ready=!flag_owned && !flag_offered && wire_choice==2;
    assign o_boot_response=i_response;
    assign o_key_response=i_response;
    assign o_host_response=i_response;
    assign o_boot_response_valid=flag_owned && reg_owner==0 && i_response_valid;
    assign o_key_response_valid=flag_owned && reg_owner==1 && i_response_valid;
    assign o_host_response_valid=flag_owned && reg_owner==2 && i_response_valid;
    assign o_response_ready=flag_owned && (reg_owner==0 ? i_boot_response_ready : reg_owner==1 ? i_key_response_ready : i_host_response_ready);
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin flag_owned<=0;reg_owner<=0;flag_prefer_host<=0;flag_offered<=0;reg_offer_owner<=0;reg_offer<=0;end
        else begin
            if (flag_offer) begin
                reg_offer<=wire_choice==0 ? i_boot_request : wire_choice==1 ? i_key_request : i_host_request;
                reg_offer_owner<=wire_choice;flag_offered<=1;
                if (wire_choice!=0) flag_prefer_host<=wire_choice==1;
            end
            if (o_request_valid && i_request_ready) begin
                flag_owned<=1;reg_owner<=reg_offer_owner;flag_offered<=0;
            end
            if (i_response_valid && o_response_ready) flag_owned<=0;
        end
    end
endmodule
