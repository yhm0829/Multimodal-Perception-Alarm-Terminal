`timescale 1ns/1ps
// 1024点定点基2 FFT音频分析器。
// 信号链：左右声道混合 -> 64级Hann窗ROM -> 1024点FFT -> |Re|+|Im|
// -> 近似对数电平 -> 32个对数频段。加窗和蝶形运算复用一个18x18有符号乘法器，
// 以运算周期换DSP资源；25MHz时钟、48kHz采样率下约每秒更新42帧。
// 参数DATA_W决定输入位宽，FFT_W决定内部定点精度，FFT_N固定为1024时与旋转因子MIF对应。
// 调试记录：低电平频谱若过早截位会使告警分类器失去弱信号，因此先保留内部保护位，
// 仅在显示输出处压缩到8位；频段边界按48kHz采样率取整，不把直流bin计入首个有效频段。
module mm_audio_spectrum_1024 #(
    parameter integer DB_FLOOR = 24,
    parameter [7:0] SILENCE_GATE = 8'd1
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    sample_valid,
    input  wire signed [23:0]      sample_left,
    input  wire signed [23:0]      sample_right,
    output reg  [255:0]            bars,
    output reg  [7:0]              volume,
    output wire [31:0] alarm_energy,
    output wire [29:0] alarm_low200,
    output wire [31:0] alarm_low1k,
    output wire [30:0] alarm_high2k8k,
    output wire [4:0] alarm_wide_bins,
    output wire frame_valid
);
    localparam ST_CAPTURE   = 4'd0;
    localparam ST_LOAD_A    = 4'd1;
    localparam ST_GET_A     = 4'd2;
    localparam ST_LOAD_B    = 4'd3;
    localparam ST_GET_B     = 4'd4;
    localparam ST_MUL0      = 4'd5;
    localparam ST_MUL1      = 4'd6;
    localparam ST_MUL2      = 4'd7;
    localparam ST_MUL3      = 4'd8;
    localparam ST_WRITE_A   = 4'd9;
    localparam ST_WRITE_B   = 4'd10;
    localparam ST_SCAN_INIT = 4'd11;
    localparam ST_SCAN_REQ  = 4'd12;
    localparam ST_SCAN_EVAL = 4'd13;
    localparam ST_PUBLISH   = 4'd14;

    // 仅告警特征复用原乘法器；不新增DSP/BRAM、不改变频谱柱高定义。
    localparam ST_POWER_RE=4'd15;
    reg [31:0] energy_acc;
    reg [29:0] low_acc;
    reg [31:0] low1k_acc;
    reg [30:0] high_acc;
    reg [4:0] wide_acc;
    reg [9:0] last_power_bin;
    assign alarm_energy=energy_acc;
    assign alarm_low200=low_acc;
    assign alarm_low1k=low1k_acc;
    assign alarm_high2k8k=high_acc;
    assign alarm_wide_bins=wide_acc;
    reg [3:0] state;
    reg publish_d;
    always @(posedge clk or posedge rst)
      if(rst)publish_d<=0;else publish_d<=(state==ST_PUBLISH);
    assign frame_valid=publish_d;
    reg [9:0] capture_count;
    reg [3:0] stage;
    reg [9:0] butterfly;
    reg [4:0] scan_band;
    reg [9:0] scan_bin;
    reg [7:0] band_max;
    reg [7:0] capture_peak;
    reg [255:0] next_bars;

    reg [9:0] idx_a, idx_b;
    reg [8:0] tw_idx;
    integer half_size;
    integer group_no;
    integer within_group;
    always @(*) begin
        half_size = (1 << stage);
        group_no = butterfly >> stage;
        within_group = butterfly & (half_size - 1);
        idx_a = (group_no << (stage + 1)) + within_group;
        idx_b = idx_a + half_size;
        tw_idx = within_group << (9 - stage);
    end

    function [9:0] bit_reverse10;
        input [9:0] value;
        begin bit_reverse10={value[0],value[1],value[2],value[3],value[4],
                             value[5],value[6],value[7],value[8],value[9]}; end
    endfunction

    function signed [15:0] hann_q15;
        input [5:0] index;
        begin
            case(index)
                6'd0: hann_q15=16'sd20;
                6'd1: hann_q15=16'sd178;
                6'd2: hann_q15=16'sd492;
                6'd3: hann_q15=16'sd960;
                6'd4: hann_q15=16'sd1576;
                6'd5: hann_q15=16'sd2335;
                6'd6: hann_q15=16'sd3230;
                6'd7: hann_q15=16'sd4252;
                6'd8: hann_q15=16'sd5391;
                6'd9: hann_q15=16'sd6636;
                6'd10: hann_q15=16'sd7975;
                6'd11: hann_q15=16'sd9395;
                6'd12: hann_q15=16'sd10883;
                6'd13: hann_q15=16'sd12423;
                6'd14: hann_q15=16'sd14002;
                6'd15: hann_q15=16'sd15604;
                6'd16: hann_q15=16'sd17213;
                6'd17: hann_q15=16'sd18815;
                6'd18: hann_q15=16'sd20393;
                6'd19: hann_q15=16'sd21932;
                6'd20: hann_q15=16'sd23417;
                6'd21: hann_q15=16'sd24835;
                6'd22: hann_q15=16'sd26172;
                6'd23: hann_q15=16'sd27413;
                6'd24: hann_q15=16'sd28549;
                6'd25: hann_q15=16'sd29567;
                6'd26: hann_q15=16'sd30457;
                6'd27: hann_q15=16'sd31212;
                6'd28: hann_q15=16'sd31824;
                6'd29: hann_q15=16'sd32287;
                6'd30: hann_q15=16'sd32597;
                6'd31: hann_q15=16'sd32750;
                6'd32: hann_q15=16'sd32745;
                6'd33: hann_q15=16'sd32582;
                6'd34: hann_q15=16'sd32263;
                6'd35: hann_q15=16'sd31790;
                6'd36: hann_q15=16'sd31169;
                6'd37: hann_q15=16'sd30406;
                6'd38: hann_q15=16'sd29507;
                6'd39: hann_q15=16'sd28481;
                6'd40: hann_q15=16'sd27339;
                6'd41: hann_q15=16'sd26091;
                6'd42: hann_q15=16'sd24749;
                6'd43: hann_q15=16'sd23326;
                6'd44: hann_q15=16'sd21837;
                6'd45: hann_q15=16'sd20295;
                6'd46: hann_q15=16'sd18715;
                6'd47: hann_q15=16'sd17113;
                6'd48: hann_q15=16'sd15503;
                6'd49: hann_q15=16'sd13903;
                6'd50: hann_q15=16'sd12326;
                6'd51: hann_q15=16'sd10788;
                6'd52: hann_q15=16'sd9304;
                6'd53: hann_q15=16'sd7889;
                6'd54: hann_q15=16'sd6555;
                6'd55: hann_q15=16'sd5317;
                6'd56: hann_q15=16'sd4185;
                6'd57: hann_q15=16'sd3170;
                6'd58: hann_q15=16'sd2284;
                6'd59: hann_q15=16'sd1533;
                6'd60: hann_q15=16'sd926;
                6'd61: hann_q15=16'sd468;
                6'd62: hann_q15=16'sd163;
                6'd63: hann_q15=16'sd15;
                default: hann_q15=16'sd0;
            endcase
        end
    endfunction

    // Twiddle factors are stored in the dedicated BRAM instance below.

    // Fs=48kHz时，单个bin宽46.875Hz。20Hz以下没有独立可分辨bin，
    // 因此前几个显示频段共用bin1，频段边界统一向可用整数bin取整。
    function [9:0] band_start;
        input [4:0] band;
        begin
            case(band)
                5'd0: band_start = 10'd1;
                5'd1: band_start = 10'd1;
                5'd2: band_start = 10'd1;
                5'd3: band_start = 10'd1;
                5'd4: band_start = 10'd2;
                5'd5: band_start = 10'd2;
                5'd6: band_start = 10'd2;
                5'd7: band_start = 10'd2;
                5'd8: band_start = 10'd3;
                5'd9: band_start = 10'd3;
                5'd10: band_start = 10'd4;
                5'd11: band_start = 10'd5;
                5'd12: band_start = 10'd6;
                5'd13: band_start = 10'd8;
                5'd14: band_start = 10'd9;
                5'd15: band_start = 10'd11;
                5'd16: band_start = 10'd14;
                5'd17: band_start = 10'd17;
                5'd18: band_start = 10'd21;
                5'd19: band_start = 10'd26;
                5'd20: band_start = 10'd32;
                5'd21: band_start = 10'd40;
                5'd22: band_start = 10'd50;
                5'd23: band_start = 10'd62;
                5'd24: band_start = 10'd76;
                5'd25: band_start = 10'd95;
                5'd26: band_start = 10'd117;
                5'd27: band_start = 10'd145;
                5'd28: band_start = 10'd180;
                5'd29: band_start = 10'd224;
                5'd30: band_start = 10'd278;
                5'd31: band_start = 10'd344;
                default: band_start=10'd1;
            endcase
        end
    endfunction
    function [9:0] band_end;
        input [4:0] band;
        begin
            case(band)
                5'd0: band_end = 10'd1;
                5'd1: band_end = 10'd1;
                5'd2: band_end = 10'd1;
                5'd3: band_end = 10'd1;
                5'd4: band_end = 10'd2;
                5'd5: band_end = 10'd2;
                5'd6: band_end = 10'd2;
                5'd7: band_end = 10'd2;
                5'd8: band_end = 10'd3;
                5'd9: band_end = 10'd3;
                5'd10: band_end = 10'd4;
                5'd11: band_end = 10'd5;
                5'd12: band_end = 10'd7;
                5'd13: band_end = 10'd8;
                5'd14: band_end = 10'd10;
                5'd15: band_end = 10'd13;
                5'd16: band_end = 10'd16;
                5'd17: band_end = 10'd20;
                5'd18: band_end = 10'd25;
                5'd19: band_end = 10'd31;
                5'd20: band_end = 10'd39;
                5'd21: band_end = 10'd49;
                5'd22: band_end = 10'd61;
                5'd23: band_end = 10'd75;
                5'd24: band_end = 10'd94;
                5'd25: band_end = 10'd116;
                5'd26: band_end = 10'd144;
                5'd27: band_end = 10'd179;
                5'd28: band_end = 10'd223;
                5'd29: band_end = 10'd277;
                5'd30: band_end = 10'd343;
                5'd31: band_end = 10'd426;
                default: band_end=10'd426;
            endcase
        end
    endfunction

    function [4:0] leading_one20;
        input [19:0] value;
        integer p;
        begin
            leading_one20=0;
            for(p=0;p<20;p=p+1)
                if(value[p]) leading_one20=p[4:0];
        end
    endfunction

    // 幅度每翻倍约增加6.02dB；取最高有效位及其后两位近似小数部分，
    // 避免在FPGA中实现对数器或除法器。
    function [7:0] magnitude_to_level;
        input [19:0] magnitude;
        reg [4:0] msb;
        reg [7:0] db_code;
        reg [1:0] frac;
        integer shifted;
        begin
            if(magnitude==0) magnitude_to_level=0;
            else begin
                msb=leading_one20(magnitude);
                shifted=magnitude >> ((msb>1)?(msb-2):0);
                frac=shifted[1:0];
                db_code=(msb*6)+(frac+1);
                if(db_code<=DB_FLOOR) magnitude_to_level=0;
                else if((db_code-DB_FLOOR)>=63) magnitude_to_level=8'd63;
                else magnitude_to_level=db_code-DB_FLOOR;
            end
        end
    endfunction

    wire signed [24:0] stereo_sum =
        ($signed(sample_left) >>> 1) + ($signed(sample_right) >>> 1);
    wire signed [15:0] mixed_sample = stereo_sum >>> 8;
    wire [23:0] mixed_abs24 = stereo_sum[24] ? -stereo_sum[23:0] : stereo_sum[23:0];
    wire [7:0] mixed_level = (mixed_abs24[23]) ? 8'hff : mixed_abs24[22:15];

    reg signed [17:0] ar, ai, br, bi, wr, wi;
    wire [35:0] twiddle_word;
    mm_twiddle_rom_1024 u_twiddle_rom(
        .clk(clk), .rst(rst), .addr(tw_idx), .data(twiddle_word)
    );
    reg signed [35:0] product0, product1, product2, product3;
    reg signed [17:0] mult_lhs, mult_rhs;
    wire signed [35:0] shared_product = mult_lhs * mult_rhs;
    wire signed [15:0] hann_value = hann_q15(capture_count[9:4]);
    reg [9:0] fft_addr;
    reg signed [17:0] fft_re_d, fft_im_d;
    reg fft_we;
    wire signed [17:0] fft_re_q, fft_im_q;
    mm_fft_ram_1024 u_fft_ram(
        .clk(clk), .addr(fft_addr), .we(fft_we),
        .re_d(fft_re_d), .im_d(fft_im_d), .re_q(fft_re_q), .im_q(fft_im_q)
    );
    // 非负平方和按固定比例量化；不是对数bars求和。每个FFT bin只累计一次。
    // 频段求和前保留低电平能量；18位FFT的两个保护位作为小数精度使用。
    wire [32:0] bin_power={1'b0,product0[35:4]}+{1'b0,shared_product[35:4]};
    reg [18:0] abs_re, abs_im;
    reg [19:0] magnitude;
    reg [7:0] scan_level;
    integer i;

    always @(*) begin
        abs_re = fft_re_q[17] ? -fft_re_q : fft_re_q;
        abs_im = fft_im_q[17] ? -fft_im_q : fft_im_q;
        // Keep the original display scale; only classifier precision changes.
        magnitude = (abs_re + abs_im) >> 2;
        scan_level = magnitude_to_level(magnitude);
        mult_lhs=18'sd0; mult_rhs=18'sd0;
        case(state)
            ST_CAPTURE: begin
                mult_lhs={mixed_sample,2'b00};
                mult_rhs={{2{hann_value[15]}},hann_value};
            end
            ST_POWER_RE: begin mult_lhs=fft_re_q; mult_rhs=fft_re_q; end
            ST_SCAN_EVAL: begin mult_lhs=fft_im_q; mult_rhs=fft_im_q; end
            ST_MUL0: begin mult_lhs=br; mult_rhs=wr; end
            ST_MUL1: begin mult_lhs=bi; mult_rhs=wi; end
            ST_MUL2: begin mult_lhs=br; mult_rhs=wi; end
            ST_MUL3: begin mult_lhs=bi; mult_rhs=wr; end
            default: begin mult_lhs=18'sd0; mult_rhs=18'sd0; end
        endcase
    end

    // 工作缓存显式映射到单口BRAM，避免36kbit数据展开成寄存器和LUT多路器。
    always @(*) begin
        fft_addr=10'd0; fft_re_d=18'sd0; fft_im_d=18'sd0; fft_we=1'b0;
        case(state)
            ST_CAPTURE: begin
                fft_addr=bit_reverse10(capture_count);
                fft_re_d=shared_product>>>15; fft_im_d=18'sd0;
                fft_we=sample_valid;
            end
            ST_LOAD_A,ST_GET_A: fft_addr=idx_a;
            ST_LOAD_B,ST_GET_B: fft_addr=idx_b;
            ST_WRITE_A: begin
                fft_addr=idx_a; fft_we=1'b1;
                fft_re_d=($signed(ar)+$signed((product0-product1)>>>15))>>>1;
                fft_im_d=($signed(ai)+$signed((product2+product3)>>>15))>>>1;
            end
            ST_WRITE_B: begin
                fft_addr=idx_b; fft_we=1'b1;
                fft_re_d=($signed(ar)-$signed((product0-product1)>>>15))>>>1;
                fft_im_d=($signed(ai)-$signed((product2+product3)>>>15))>>>1;
            end
            ST_SCAN_REQ,ST_POWER_RE,ST_SCAN_EVAL: fft_addr=scan_bin;
            default: ;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            energy_acc<=0;low_acc<=0;low1k_acc<=0;high_acc<=0;wide_acc<=0;last_power_bin<=0;
            state<=ST_CAPTURE; capture_count<=0; stage<=0; butterfly<=0;
            scan_band<=0; scan_bin<=0; band_max<=0; capture_peak<=0;
            bars<=0; next_bars<=0; volume<=0;
            ar<=0; ai<=0; br<=0; bi<=0; wr<=0; wi<=0;
            product0<=0; product1<=0; product2<=0; product3<=0;
        end else begin
            case(state)
                ST_CAPTURE: if(sample_valid) begin
                    if(mixed_level>capture_peak) capture_peak<=mixed_level;
                    if(capture_count==10'd1023) begin
                        capture_count<=0; stage<=0; butterfly<=0;
                        state<=ST_LOAD_A;
                    end else capture_count<=capture_count+1'b1;
                end
                ST_LOAD_A: state<=ST_GET_A;
                ST_GET_A: begin
                    ar<=fft_re_q; ai<=fft_im_q; state<=ST_LOAD_B;
                end
                ST_LOAD_B: state<=ST_GET_B;
                ST_GET_B: begin
                    br<=fft_re_q; bi<=fft_im_q;
                    wr<=twiddle_word[35:18]; wi<=twiddle_word[17:0];
                    state<=ST_MUL0;
                end
                ST_MUL0: begin product0<=shared_product; state<=ST_MUL1; end
                ST_MUL1: begin product1<=shared_product; state<=ST_MUL2; end
                ST_MUL2: begin product2<=shared_product; state<=ST_MUL3; end
                ST_MUL3: begin product3<=shared_product; state<=ST_WRITE_A; end
                ST_WRITE_A: begin
                    state<=ST_WRITE_B;
                end
                ST_WRITE_B: begin
                    if(butterfly==10'd511) begin
                        butterfly<=0;
                        if(stage==4'd9) state<=ST_SCAN_INIT;
                        else begin stage<=stage+1'b1; state<=ST_LOAD_A; end
                    end else begin butterfly<=butterfly+1'b1; state<=ST_LOAD_A; end
                end
                ST_SCAN_INIT: begin
                    energy_acc<=0;low_acc<=0;low1k_acc<=0;high_acc<=0;wide_acc<=0;last_power_bin<=0;
                    scan_band<=0; scan_bin<=band_start(0); band_max<=0;
                    next_bars<=0; state<=ST_SCAN_REQ;
                end
                ST_SCAN_REQ: state<=ST_POWER_RE;
                ST_POWER_RE: begin product0<=shared_product; state<=ST_SCAN_EVAL; end
                ST_SCAN_EVAL: begin
                    if(scan_bin!=last_power_bin) begin
                        last_power_bin<=scan_bin;
                        energy_acc<=energy_acc+bin_power;
                        if(scan_bin<=21)low1k_acc<=low1k_acc+bin_power; // 46.875..984.375Hz
                        if(scan_bin<=4)low_acc<=low_acc+bin_power; // 46.875..187.5Hz
                        if(scan_bin>=43 && scan_bin<=170)begin // 2015.625..7968.75Hz
                            high_acc<=high_acc+bin_power;
                            if(bin_power>=32768 && wide_acc<31)wide_acc<=wide_acc+1'b1;
                        end
                    end
                    if(scan_level>band_max) band_max<=scan_level;
                    if(scan_bin>=band_end(scan_band)) begin
                        next_bars[(scan_band*8)+:8] <=
                            (scan_level>band_max)?scan_level:band_max;
                        band_max<=0;
                        if(scan_band==5'd31) state<=ST_PUBLISH;
                        else begin
                            scan_band<=scan_band+1'b1;
                            scan_bin<=band_start(scan_band+1'b1);
                            state<=ST_SCAN_REQ;
                        end
                    end else begin scan_bin<=scan_bin+1'b1; state<=ST_SCAN_REQ; end
                end
                ST_PUBLISH: begin
                    bars <= (capture_peak<SILENCE_GATE) ? 256'd0 : next_bars;
                    volume <= capture_peak;
                    capture_peak<=0;
                    state<=ST_CAPTURE;
                end
                default: state<=ST_CAPTURE;
            endcase
        end
    end
endmodule

// Two 18x1024 single-port work RAMs hold the complex FFT vector.
module mm_fft_ram_1024(
    input  wire               clk,
    input  wire [9:0]         addr,
    input  wire               we,
    input  wire signed [17:0] re_d,
    input  wire signed [17:0] im_d,
    output wire signed [17:0] re_q,
    output wire signed [17:0] im_q
);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(18), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("SP"), .REGMODE_A("NOREG"), .WRITEMODE_A("NORMAL"),
        .IMPLEMENT("32K"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) re_ram (
        .dia(re_d), .dib(18'd0), .addra(addr), .addrb(10'd0),
        .cea(1'b1), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0),
        .clka(clk), .clkb(1'b0), .wea(we), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(re_q), .dob()
    );
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(18), .ADDR_WIDTH_A(10), .DATA_DEPTH_A(1024),
        .DATA_WIDTH_B(18), .ADDR_WIDTH_B(10), .DATA_DEPTH_B(1024),
        .MODE("SP"), .REGMODE_A("NOREG"), .WRITEMODE_A("NORMAL"),
        .IMPLEMENT("32K"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) im_ram (
        .dia(im_d), .dib(18'd0), .addra(addr), .addrb(10'd0),
        .cea(1'b1), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0),
        .clka(clk), .clkb(1'b0), .wea(we), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .doa(im_q), .dob()
    );
endmodule

// 厂商 BRAM ROM，由 MIF 初始化，TD 在综合/生成位流阶段加载。
module mm_twiddle_rom_1024(
    input  wire        clk,
    input  wire        rst,
    input  wire [8:0]  addr,
    output wire [35:0] data
);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(36), .ADDR_WIDTH_A(9), .DATA_DEPTH_A(512),
        .DATA_WIDTH_B(36), .ADDR_WIDTH_B(9), .DATA_DEPTH_B(512),
        .MODE("SP"), .REGMODE_A("OUTREG"), .IMPLEMENT("32K"),
        .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .INIT_FILE("../../td_project/al_ip/mm_twiddle_1024.mif"),
        .FILL_ALL("NONE")
    ) inst (
        .dia(36'd0), .dib(36'd0), .addra(addr), .addrb(9'd0),
        .cea(1'b1), .ceb(1'b0), .ocea(1'b1), .oceb(1'b0),
        .clka(clk), .clkb(1'b0), .wea(1'b0), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(rst), .rstb(1'b0),
        .doa(data), .dob()
    );
endmodule

