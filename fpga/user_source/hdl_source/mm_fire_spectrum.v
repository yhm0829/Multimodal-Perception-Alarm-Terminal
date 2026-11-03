`timescale 1ns/1ps
// 32 frequency knots span ALL 640 columns. Smoothstep interpolation has zero
// slope at knots; Q4 vertical coverage softens the silhouette without noise
// in the pixel boundary. No video registers are inserted by this module.
module mm_fire_spectrum(
    input wire clk,rst,frame_tick,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [255:0] bars,
    input wire [7:0] phase,
    input wire [1:0] style,
    output reg [23:0] color,
    output reg [2:0] coverage,
    output reg peak_on,spark_on
);
    reg [5:0] level [0:31];
    reg [5:0] peak [0:31];
    reg [1:0] fall_count;
    integer i;
    function [5:0] bounded;
        input [7:0] value;
        // Fixed visual gain expands real FFT energy into the 126-pixel area.
        // Saturation is intentional; zero energy still produces zero height.
        begin bounded=(value>31)?6'd63:{value[4:0],1'b0}; end
    endfunction
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            fall_count<=0;
            for(i=0;i<32;i=i+1) begin level[i]<=0;peak[i]<=0;end
        end else if(frame_tick) begin
            fall_count<=(fall_count==2)?0:fall_count+1'b1;
            for(i=0;i<32;i=i+1) begin
                if(bounded(bars[i*8+:8])>level[i]) begin
                    if({1'b0,bounded(bars[i*8+:8])}>{1'b0,level[i]}+7'd8)
                        level[i]<=level[i]+6'd8;
                    else level[i]<=bounded(bars[i*8+:8]);
                end else if(bounded(bars[i*8+:8])<level[i]) level[i]<=level[i]-1'b1;
                if(bounded(bars[i*8+:8])>=peak[i]) peak[i]<=bounded(bars[i*8+:8]);
                else if(fall_count==2 && peak[i]!=0) peak[i]<=peak[i]-1'b1;
            end
        end
    end
    // ceil(4096/20)=205 gives exact floor(x/20) for x=0..639.
    wire [18:0] scaled_x=x*19'd205;
    wire [4:0] band=(scaled_x[18:12]>31)?5'd31:scaled_x[16:12];
    wire [4:0] next_band=(band==31)?5'd31:band+1'b1;
    wire [10:0] fraction_wide=x-band*11'd20;
    wire [4:0] fraction=fraction_wide[4:0];
    function [7:0] smooth_weight;
        input [4:0] pos;
        begin
            case(pos)
                0:smooth_weight=0; 1:smooth_weight=2; 2:smooth_weight=7;
                3:smooth_weight=16; 4:smooth_weight=27; 5:smooth_weight=40;
                6:smooth_weight=55; 7:smooth_weight=72; 8:smooth_weight=90;
                9:smooth_weight=109;10:smooth_weight=128;11:smooth_weight=147;
                12:smooth_weight=166;13:smooth_weight=184;14:smooth_weight=201;
                15:smooth_weight=216;16:smooth_weight=229;17:smooth_weight=240;
                18:smooth_weight=249;19:smooth_weight=254;
                default:smooth_weight=0;
            endcase
        end
    endfunction
    wire [7:0] weight=smooth_weight(fraction);
    wire signed [6:0] level_delta=$signed({1'b0,level[next_band]})-$signed({1'b0,level[band]});
    wire signed [6:0] peak_delta=$signed({1'b0,peak[next_band]})-$signed({1'b0,peak[band]});
    wire signed [15:0] level_product=level_delta*$signed({1'b0,weight});
    wire signed [15:0] peak_product=peak_delta*$signed({1'b0,weight});
    wire signed [16:0] level_q8=$signed({3'b0,level[band],8'd0})+$signed({level_product[15],level_product});
    wire signed [16:0] peak_q8=$signed({3'b0,peak[band],8'd0})+$signed({peak_product[15],peak_product});
    wire [10:0] height_q4=level_q8[13:3];
    wire [10:0] peak_q4=peak_q8[13:3];
    wire [9:0] y_from_base=10'd443-y;
    wire signed [12:0] edge_distance=$signed({2'b0,height_q4})-$signed({y_from_base[8:0],4'b0});
    wire signed [12:0] peak_distance=$signed({2'b0,peak_q4})-$signed({y_from_base[8:0],4'b0});
    wire [8:0] red_sum=9'd88+{1'b0,height_q4[10:4],1'b0}+{2'b0,y_from_base[6:0]};
    wire [7:0] green_base=8'd4+{1'b0,height_q4[10:4]}+{2'b0,y_from_base[6:1]};
    wire [5:0] spark_lift=6'd3+{2'b0,(phase[3:0]^band[3:0])};
    wire [4:0] spark_pos=5'd3+{2'b0,phase[2:0]};
    always @(*) begin
        color=24'd0;coverage=0;peak_on=0;spark_on=0;
        if(x<640 && y>=292 && y<=443) begin
            if(height_q4!=0 && y_from_base<128 && edge_distance>0) begin
                coverage=(edge_distance>=16)?3'd4:((edge_distance+13'sd3)>>>2);
                color[23:16]=red_sum[8]?8'd255:red_sum[7:0];
                // All modes remain warm red/orange; inner depth supplies a
                // bright core rather than checkerboards or per-pixel height cuts.
                case(style)
                    0:color[15:8]=green_base>>1;
                    1:color[15:8]=green_base;
                    2:color[15:8]=(green_base>>1)+(green_base>>2);
                    3:color[15:8]=green_base>>2;
                endcase
                color[7:0]=(y_from_base<height_q4[10:5])?8'd4:8'd0;
            end
            if(peak_q4!=0 && peak_distance>=0 && peak_distance<16) peak_on=1;
            if(peak_q4>11'd320 && y_from_base<152 &&
               y_from_base>peak_q4[10:4] &&
               y_from_base<=({3'b0,peak_q4[10:4]}+spark_lift) &&
               y_from_base+2>=({3'b0,peak_q4[10:4]}+spark_lift) &&
               fraction>=spark_pos && fraction<=spark_pos+1) spark_on=1;
        end
    end
endmodule
