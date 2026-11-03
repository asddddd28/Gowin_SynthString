`timescale 1ns/1ps
// Shared wave RAM / 共用波表存储
// Explicit write-through DPB avoids unsupported inferred read-before-write mode.
module SynthWaveRam(
    input i_clk,input i_write,input [9:0] i_address_a,input [31:0] i_data,
    input [9:0] i_address_b,output [31:0] o_data_a,output [31:0] o_data_b
);
`ifdef SYNTHESIS
    genvar part;
    generate for(part=0;part<2;part=part+1)begin:gen_half
        DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b01),.WRITE_MODE1(2'b00),
            .BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC"),
            .INIT_RAM_00(part==0 ? 256'h1d62db40984654821005cadd851a3eccf802b0cb69372156d93790e9487c0000 : 256'h005e00570051004b0045003e00380032002b0025001f00190012000c00060000),
            .INIT_RAM_01(part==0 ? 256'h9b376ecf409810a2defcabb676de408308b7cf86950259391c3bde179edd5e9b : 256'h00c100bb00b500af00a800a2009c0096009000890083007d00770070006a0064),
            .INIT_RAM_02(part==0 ? 256'h3bbb34442a0d1d260d9dfb81e6e1cfccb6519a7f7c665c1339971501ee60c5c2 : 256'h0123011d01170111010b010400fe00f800f200ec00e600e000da00d400cd00c7),
            .INIT_RAM_03(part==0 ? 256'h0e3b3a9363418853a9d8c7dee273f9a70d881e242b8a35c93cf0410c422e4063 : 256'h0182017c01760170016a0164015e01580153014d01470141013b0135012f0129),
            .INIT_RAM_04(part==0 ? 256'h28f19776016f66eac7f5249e7cf2d10120d76c83b412f794371672a6aa53de2a : 256'h01dd01d701d201cc01c601c101bb01b501b001aa01a4019e01990193018d0187),
            .INIT_RAM_05(part==0 ? 256'hab4169ac22b6d66b84d72e0ad20f70f30ac59f912f65ba4e4059c1953e0fb5d4 : 256'h0233022e02290223021e02190213020e0209020301fe01f801f301ed01e801e2),
            .INIT_RAM_06(part==0 ? 256'hbfe3db2af047ff4508310b160802ff00f01cdb65c0e5a0aa7abf4f331e11e767 : 256'h0284027f027a02750271026c02670261025c02570252024d02480243023e0238),
            .INIT_RAM_07(part==0 ? 256'h9ef12325a07416eb8693ef7851a5ad27020750529814d9571429489376a39e65 : 256'h02cf02cb02c602c202bd02b802b402af02ab02a602a1029c02980293028e0289),
            .INIT_RAM_08(part==0 ? 256'h8fd3880278a361c143661d9cf06ebbe4800b3cecf292a1074856e88b81ae13cd : 256'h0313030f030b0307030302ff02fa02f602f202ee02e902e502e102dc02d802d4),
            .INIT_RAM_09(part==0 ? 256'heb0a6123cf1934f492bde87e363f7c09b9e6efdf1dfd444962ce799488a6900d : 256'h034f034c034803450341033d033a03360332032e032b03270323031f031b0317),
            .INIT_RAM_0A(part==0 ? 256'h1bc818850c9cf816daf9b54d871a50691140c9a879a9214bc0975794e64b6cc5 : 256'h03840381037e037a037703740371036e036b036703640361035d035a03560353),
            .INIT_RAM_0B(part==0 ? 256'ha1602c2eadea269a9644fcef5aa0af5ffb313e1e782da964d1caf1670840165e : 256'h03af03ad03aa03a803a503a203a0039d039a039803950392038f038c038a0387),
            .INIT_RAM_0C(part==0 ? 256'h10872f7544fb511e53e14d493d5d24210199d5cca0bf62771af9ca4c70750d7a : 256'h03d203d003ce03cc03ca03c803c603c403c203bf03bd03bb03b903b603b403b2),
            .INIT_RAM_0D(part==0 ? 256'h1456cc077a111e76b9394a5fd1ea4fdfc4422f14905ce81d365a7b19b65de82b : 256'h03eb03e903e803e703e503e403e203e103df03de03dc03da03d903d703d503d3),
            .INIT_RAM_0E(part==0 ? 256'h6f23c2c00c8e4c8e82c3af2ed1d2eab0f9cbff25fac0ec9fd4c5b33487f052fa : 256'h03fa03f903f903f803f703f603f503f403f303f203f103f003ef03ee03ed03ec),
            .INIT_RAM_0F(part==0 ? 256'hfb11ec43d397b10c84a44e5e0e3bc43c706212adab1e39b6be763960aa7411b4 : 256'h03ff03ff03ff03ff03ff03ff03ff03fe03fe03fe03fd03fd03fc03fc03fb03fb),
            .INIT_RAM_10(part==0 ? 256'haa743960be7639b6ab1e12ad7062c43c0e3b4e5e84a4b10cd397ec43fb110000 : 256'h03fb03fc03fc03fd03fd03fe03fe03fe03ff03ff03ff03ff03ff03ff03ff0400),
            .INIT_RAM_11(part==0 ? 256'h87f0b334d4c5ec9ffac0ff25f9cbeab0d1d2af2e82c34c8e0c8ec2c06f2311b4 : 256'h03ed03ee03ef03f003f103f203f303f403f503f603f703f803f903f903fa03fb),
            .INIT_RAM_12(part==0 ? 256'hb65d7b19365ae81d905c2f14c4424fdfd1ea4a5fb9391e767a11cc07145652fa : 256'h03d503d703d903da03dc03de03df03e103e203e403e503e703e803e903eb03ec),
            .INIT_RAM_13(part==0 ? 256'h7075ca4c1af96277a0bfd5cc019924213d5d4d4953e1511e44fb2f751087e82b : 256'h03b403b603b903bb03bd03bf03c203c403c603c803ca03cc03ce03d003d203d3),
            .INIT_RAM_14(part==0 ? 256'h0840f167d1caa964782d3e1efb31af5f5aa0fcef9644269aadea2c2ea1600d7a : 256'h038a038c038f039203950398039a039d03a003a203a503a803aa03ad03af03b2),
            .INIT_RAM_15(part==0 ? 256'he64b5794c097214b79a9c9a811405069871ab54ddaf9f8160c9c18851bc8165e : 256'h0356035a035d036103640367036b036e037103740377037a037e038103840387),
            .INIT_RAM_16(part==0 ? 256'h88a6799462ce44491dfdefdfb9e67c09363fe87e92bd34f4cf196123eb0a6cc5 : 256'h031b031f03230327032b032e03320336033a033d034103450348034c034f0353),
            .INIT_RAM_17(part==0 ? 256'h81aee88b4856a107f2923cec800bbbe4f06e1d9c436661c178a388028fd3900d : 256'h02d802dc02e102e502e902ee02f202f602fa02ff03030307030b030f03130317),
            .INIT_RAM_18(part==0 ? 256'h76a348931429d957981450520207ad2751a5ef78869316eba07423259ef113cd : 256'h028e02930298029c02a102a602ab02af02b402b802bd02c202c602cb02cf02d4),
            .INIT_RAM_19(part==0 ? 256'h1e114f337abfa0aac0e5db65f01cff0008020b160831ff45f047db2abfe39e65 : 256'h023e02430248024d02520257025c02610267026c02710275027a027f02840289),
            .INIT_RAM_1A(part==0 ? 256'h3e0fc1954059ba4e2f659f910ac570f3d20f2e0a84d7d66b22b669acab41e767 : 256'h01e801ed01f301f801fe02030209020e02130219021e02230229022e02330238),
            .INIT_RAM_1B(part==0 ? 256'haa5372a63716f794b4126c8320d7d1017cf2249ec7f566ea016f977628f1b5d4 : 256'h018d01930199019e01a401aa01b001b501bb01c101c601cc01d201d701dd01e2),
            .INIT_RAM_1C(part==0 ? 256'h422e410c3cf035c92b8a1e240d88f9a7e273c7dea9d8885363413a930e3bde2a : 256'h012f0135013b01410147014d01530158015e0164016a01700176017c01820187),
            .INIT_RAM_1D(part==0 ? 256'hee60150139975c137c669a7fb651cfcce6e1fb810d9d1d262a0d34443bbb4063 : 256'h00cd00d400da00e000e600ec00f200f800fe0104010b01110117011d01230129),
            .INIT_RAM_1E(part==0 ? 256'h9eddde171c3b59399502cf8608b7408376deabb6defc10a240986ecf9b37c5c2 : 256'h006a00700077007d0083008900900096009c00a200a800af00b500bb00c100c7),
            .INIT_RAM_1F(part==0 ? 256'h487c90e9d93721566937b0cbf8023ecc851acadd100554829846db401d625e9b : 256'h0006000c00120019001f0025002b00320038003e0045004b00510057005e0064),
            .INIT_RAM_20(part==0 ? 256'he29e24c067baab7eeffb35237ae6c13407fe4f3596c9deaa26c96f17b7840000 : 256'hffa1ffa8ffaeffb4ffbaffc1ffc7ffcdffd4ffdaffe0ffe6ffedfff3fff90000),
            .INIT_RAM_21(part==0 ? 256'h64c99131bf68ef5e2104544a8922bf7df749307a6afea6c7e3c521e96123a165 : 256'hff3eff44ff4aff50ff57ff5dff63ff69ff6fff76ff7cff82ff88ff8fff95ff9b),
            .INIT_RAM_22(part==0 ? 256'hc445cbbcd5f3e2daf263047f191f303449af6581839aa3edc669eaff11a03a3e : 256'hfedcfee2fee8feeefef4fefbff01ff07ff0dff13ff19ff1fff25ff2bff32ff38),
            .INIT_RAM_23(part==0 ? 256'hf1c5c56d9cbf77ad562838221d8d0659f278e1dcd476ca37c310bef4bdd2bf9d : 256'hfe7dfe83fe89fe8ffe95fe9bfea1fea7feacfeb2feb8febefec4fecafed0fed6),
            .INIT_RAM_24(part==0 ? 256'hd70f688afe919916380bdb62830e2effdf29937d4bee086cc8ea8d5a55ad21d6 : 256'hfe22fe28fe2dfe33fe39fe3efe44fe4afe4ffe55fe5bfe61fe66fe6cfe72fe78),
            .INIT_RAM_25(part==0 ? 256'h54bf9654dd4a29957b29d1f62df18f0df53b606fd09b45b2bfa73e6bc1f14a2c : 256'hfdccfdd1fdd6fddcfde1fde6fdecfdf1fdf6fdfcfe01fe07fe0cfe12fe17fe1d),
            .INIT_RAM_26(part==0 ? 256'h401d24d60fb900bbf7cff4eaf7fe01000fe4249b3f1b5f568541b0cde1ef1899 : 256'hfd7bfd80fd85fd8afd8efd93fd98fd9efda3fda8fdadfdb2fdb7fdbcfdc1fdc7),
            .INIT_RAM_27(part==0 ? 256'h610fdcdb5f8ce915796d1088ae5b52d9fdf9afae67ec26a9ebd7b76d895d619b : 256'hfd30fd34fd39fd3dfd42fd47fd4bfd50fd54fd59fd5efd63fd67fd6cfd71fd76),
            .INIT_RAM_28(part==0 ? 256'h702d77fe875d9e3fbc9ae2640f92441c7ff5c3140d6e5ef9b7aa17757e52ec33 : 256'hfcecfcf0fcf4fcf8fcfcfd00fd05fd09fd0dfd11fd16fd1afd1efd23fd27fd2b),
            .INIT_RAM_29(part==0 ? 256'h14f69edd30e7cb0c6d431782c9c183f7461a1021e203bbb79d32866c775a6ff3 : 256'hfcb0fcb3fcb7fcbafcbefcc2fcc5fcc9fccdfcd1fcd4fcd8fcdcfce0fce4fce8),
            .INIT_RAM_2A(part==0 ? 256'he438e77bf36407ea25074ab378e6af97eec036588657deb53f69a86c19b5933b : 256'hfc7bfc7efc81fc85fc88fc8bfc8efc91fc94fc98fc9bfc9efca2fca5fca9fcac),
            .INIT_RAM_2B(part==0 ? 256'h5ea0d3d25216d96669bc0311a56050a104cfc1e287d3569c2e360e99f7c0e9a2 : 256'hfc50fc52fc55fc57fc5afc5dfc5ffc62fc65fc67fc6afc6dfc70fc73fc75fc78),
            .INIT_RAM_2C(part==0 ? 256'hef79d08bbb05aee2ac1fb2b7c2a3dbdffe672a345f419d89e50735b48f8bf286 : 256'hfc2dfc2ffc31fc33fc35fc37fc39fc3bfc3dfc40fc42fc44fc46fc49fc4bfc4d),
            .INIT_RAM_2D(part==0 ? 256'hebaa33f985efe18a46c7b5a12e16b0213bbed0ec6fa417e3c9a684e749a317d5 : 256'hfc14fc16fc17fc18fc1afc1bfc1dfc1efc20fc21fc23fc25fc26fc28fc2afc2c),
            .INIT_RAM_2E(part==0 ? 256'h90dd3d40f372b3727d3d50d22e2e1550063500db054013612b3b4ccc7810ad06 : 256'hfc05fc06fc06fc07fc08fc09fc0afc0bfc0cfc0dfc0efc0ffc10fc11fc12fc13),
            .INIT_RAM_2F(part==0 ? 256'h04ef13bd2c694ef47b5cb1a2f1c53bc48f9eed5354e2c64a418ac6a0558cee4c : 256'hfc00fc00fc00fc00fc00fc00fc00fc01fc01fc01fc02fc02fc03fc03fc04fc04),
            .INIT_RAM_30(part==0 ? 256'h558cc6a0418ac64a54e2ed538f9e3bc4f1c5b1a27b5c4ef42c6913bd04ef0000 : 256'hfc04fc03fc03fc02fc02fc01fc01fc01fc00fc00fc00fc00fc00fc00fc00fc00),
            .INIT_RAM_31(part==0 ? 256'h78104ccc2b3b1361054000db063515502e2e50d27d3db372f3723d4090ddee4c : 256'hfc12fc11fc10fc0ffc0efc0dfc0cfc0bfc0afc09fc08fc07fc06fc06fc05fc04),
            .INIT_RAM_32(part==0 ? 256'h49a384e7c9a617e36fa4d0ec3bbeb0212e16b5a146c7e18a85ef33f9ebaaad06 : 256'hfc2afc28fc26fc25fc23fc21fc20fc1efc1dfc1bfc1afc18fc17fc16fc14fc13),
            .INIT_RAM_33(part==0 ? 256'h8f8b35b4e5079d895f412a34fe67dbdfc2a3b2b7ac1faee2bb05d08bef7917d5 : 256'hfc4bfc49fc46fc44fc42fc40fc3dfc3bfc39fc37fc35fc33fc31fc2ffc2dfc2c),
            .INIT_RAM_34(part==0 ? 256'hf7c00e992e36569c87d3c1e204cf50a1a560031169bcd9665216d3d25ea0f286 : 256'hfc75fc73fc70fc6dfc6afc67fc65fc62fc5ffc5dfc5afc57fc55fc52fc50fc4d),
            .INIT_RAM_35(part==0 ? 256'h19b5a86c3f69deb586573658eec0af9778e64ab3250707eaf364e77be438e9a2 : 256'hfca9fca5fca2fc9efc9bfc98fc94fc91fc8efc8bfc88fc85fc81fc7efc7bfc78),
            .INIT_RAM_36(part==0 ? 256'h775a866c9d32bbb7e2031021461a83f7c9c117826d43cb0c30e79edd14f6933b : 256'hfce4fce0fcdcfcd8fcd4fcd1fccdfcc9fcc5fcc2fcbefcbafcb7fcb3fcb0fcac),
            .INIT_RAM_37(part==0 ? 256'h7e521775b7aa5ef90d6ec3147ff5441c0f92e264bc9a9e3f875d77fe702d6ff3 : 256'hfd27fd23fd1efd1afd16fd11fd0dfd09fd05fd00fcfcfcf8fcf4fcf0fcecfce8),
            .INIT_RAM_38(part==0 ? 256'h895db76debd726a967ecafaefdf952d9ae5b1088796de9155f8cdcdb610fec33 : 256'hfd71fd6cfd67fd63fd5efd59fd54fd50fd4bfd47fd42fd3dfd39fd34fd30fd2b),
            .INIT_RAM_39(part==0 ? 256'he1efb0cd85415f563f1b249b0fe40100f7fef4eaf7cf00bb0fb924d6401d619b : 256'hfdc1fdbcfdb7fdb2fdadfda8fda3fd9efd98fd93fd8efd8afd85fd80fd7bfd76),
            .INIT_RAM_3A(part==0 ? 256'hc1f13e6bbfa745b2d09b606ff53b8f0d2df1d1f67b292995dd4a965454bf1899 : 256'hfe17fe12fe0cfe07fe01fdfcfdf6fdf1fdecfde6fde1fddcfdd6fdd1fdccfdc7),
            .INIT_RAM_3B(part==0 ? 256'h55ad8d5ac8ea086c4bee937ddf292eff830edb62380b9916fe91688ad70f4a2c : 256'hfe72fe6cfe66fe61fe5bfe55fe4ffe4afe44fe3efe39fe33fe2dfe28fe22fe1d),
            .INIT_RAM_3C(part==0 ? 256'hbdd2bef4c310ca37d476e1dcf27806591d8d3822562877ad9cbfc56df1c521d6 : 256'hfed0fecafec4febefeb8feb2feacfea7fea1fe9bfe95fe8ffe89fe83fe7dfe78),
            .INIT_RAM_3D(part==0 ? 256'h11a0eaffc669a3ed839a658149af3034191f047ff263e2dad5f3cbbcc445bf9d : 256'hff32ff2bff25ff1fff19ff13ff0dff07ff01fefbfef4feeefee8fee2fedcfed6),
            .INIT_RAM_3E(part==0 ? 256'h612321e9e3c5a6c76afe307af749bf7d8922544a2104ef5ebf68913164c93a3e : 256'hff95ff8fff88ff82ff7cff76ff6fff69ff63ff5dff57ff50ff4aff44ff3eff38),
            .INIT_RAM_3F(part==0 ? 256'hb7846f1726c9deaa96c94f3507fec1347ae63523effbab7e67ba24c0e29ea165 : 256'hfff9fff3ffedffe6ffe0ffdaffd4ffcdffc7ffc1ffbaffb4ffaeffa8ffa1ff9b)
        ) Memory_Inst(
            .CLKA(i_clk),.CEA(1'b1),.OCEA(1'b1),.RESETA(1'b0),.WREA(i_write),
            .ADA({i_address_a,4'b0011}),.DIA(i_data[part*16+:16]),.DOA(o_data_a[part*16+:16]),.BLKSELA(3'b000),
            .CLKB(i_clk),.CEB(1'b1),.OCEB(1'b1),.RESETB(1'b0),.WREB(1'b0),
            .ADB({i_address_b,4'b0000}),.DIB(16'd0),.DOB(o_data_b[part*16+:16]),.BLKSELB(3'b000));
    end endgenerate
`else
    reg [31:0] mem_wave[0:1023];
    reg [31:0] reg_data_a_o,reg_data_b_o;
    assign o_data_a=reg_data_a_o;
    assign o_data_b=reg_data_b_o;
    initial $readmemh("rom/sine_q26.hex",mem_wave);
    always @(posedge i_clk)begin
        reg_data_a_o<=i_write ? i_data : mem_wave[i_address_a];
        reg_data_b_o<=mem_wave[i_address_b];
        if(i_write)mem_wave[i_address_a]<=i_data;
    end
`endif
endmodule
