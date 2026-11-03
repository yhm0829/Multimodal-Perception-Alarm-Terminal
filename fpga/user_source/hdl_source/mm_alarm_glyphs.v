`timescale 1ns/1ps
// 告警字模为常量逻辑查表，不增加时钟/流水级或帧存储。
module mm_alarm_glyphs(input wire [10:0] x,input wire [9:0] y,
 input wire [31:0] timestamp_ms,input wire [1:0] reasons,input wire [7:0] darkness,input wire valid,output wire pixel);
 reg [4:0] glyph;
 reg [255:0] bitmap;
 reg [3:0] time_digit;
 wire row0=(y>=444 && y<460),row1=(y>=460 && y<476);
 wire [3:0] yy=row0?(y-444):(y-460);
 wire [5:0] column=x[10:4];
 always @(*)begin
  time_digit=0;
  glyph=0;
  if(row0)begin
   if(reasons[1])begin
    case(column)
     1:glyph=5'd1;
     2:glyph=5'd2;
     3:glyph=5'd3;
     4:glyph=5'd4;
     5:glyph=5'd5;
    endcase
   end else if(reasons[0])begin
    case(column)
     1:glyph=5'd6;
     2:glyph=5'd7;
     3:glyph=5'd4;
     4:glyph=5'd5;
    endcase
   end
   // T:Hxxxxxxxx MS：上电毫秒数，H表示十六进制；串口同样输出8位十六进制。
   if(column>=15 && column<=22)begin
    case(column)
     15:time_digit=timestamp_ms[31:28];
     16:time_digit=timestamp_ms[27:24];
     17:time_digit=timestamp_ms[23:20];
     18:time_digit=timestamp_ms[19:16];
     19:time_digit=timestamp_ms[15:12];
     20:time_digit=timestamp_ms[11:8];
     21:time_digit=timestamp_ms[7:4];
     22:time_digit=timestamp_ms[3:0];
    default:time_digit=0;endcase
    if(time_digit<10)glyph=12+time_digit;
    else case(time_digit)10:glyph=25;11:glyph=26;12:glyph=27;13:glyph=28;14:glyph=22;15:glyph=29;endcase
   end else case(column)
    12:glyph=10;13:glyph=11;14:glyph=24;24:glyph=30;25:glyph=31;
   endcase
  end else if(row1 && reasons==3)begin
   case(column)
    1:glyph=5'd6;
    2:glyph=5'd7;
    3:glyph=5'd4;
    4:glyph=5'd5;
   endcase
  end
 end
 always @(*)case(glyph)
  5'd0:bitmap=256'h0000000000000000000000000000000000000000000000000000000000000000;
  5'd1:bitmap=256'h200017fc00044004410441044104410442844244442448244004400440144008;
  5'd2:bitmap=256'h010021081108091009200100fffe0440044004400440084208421042203ec000;
  5'd3:bitmap=256'h0104f888085009fc0924792441fc4124412479fc082008200bfe082050202020;
  5'd4:bitmap=256'h2420ff20247e7ec482287a104a287ac60500fffe00003ff800003ff820083ff8;
  5'd5:bitmap=256'h0100110011001ff8210041000100fffe000000001ff01010101010101ff01010;
  5'd6:bitmap=256'h11fc110411fc150459fc508853fe908817fe108811242aaa247040a841248060;
  5'd7:bitmap=256'h11001100110015fe5a805280548090f810801080108028fc2480448040808080;
  5'd8:bitmap=256'h0e000400040004000400040004000400040004200fe000000000000000000000;
  5'd9:bitmap=256'h03c00440044008000800080008e0084004400440038000000000000000000000;
  5'd10:bitmap=256'h0fe0092001000100010001000100010001000100038000000000000000000000;
  5'd11:bitmap=256'h0180018000000000000000000180018000000000000000000000000000000000;
  5'd12:bitmap=256'h0180024004200420042004200420042004200240018000000000000000000000;
  5'd13:bitmap=256'h008003800080008000800080008000800080008003e000000000000000000000;
  5'd14:bitmap=256'h03c004200420042000200040008001000200042007e000000000000000000000;
  5'd15:bitmap=256'h03c004200420002000400180004000200420042003c000000000000000000000;
  5'd16:bitmap=256'h004000c000c0014002400240044007f00040004001f000000000000000000000;
  5'd17:bitmap=256'h07e0040004000400078004400020002004200440038000000000000000000000;
  5'd18:bitmap=256'h018002400400040005c00620042004200420022001c000000000000000000000;
  5'd19:bitmap=256'h07e0042000400040008000800100010001000100010000000000000000000000;
  5'd20:bitmap=256'h03c004200420042002400180024004200420042003c000000000000000000000;
  5'd21:bitmap=256'h03800440042004200420046003a0002000200240018000000000000000000000;
  5'd22:bitmap=256'h0fc00420048004800780048004800400042004200fc000000000000000000000;
  5'd23:bitmap=256'h0fc004200420042007c0048004800440044004200e3000000000000000000000;
  5'd24:bitmap=256'h000042004200420042007e007e00420042004200420042000000000000000000;
  5'd25:bitmap=256'h1800180018003c00240024007c00660042004200c30000000000000000000000;
  5'd26:bitmap=256'h00007c004600420042007c007c004200420042007e0078000000000000000000;
  5'd27:bitmap=256'h3c006600420042004000400042004200620036001c0000000000000000000000;
  5'd28:bitmap=256'h000078004c0046004200420042004200420046007c0070000000000000000000;
  5'd29:bitmap=256'h00007e0040004000400040007c00400040004000400040000000000000000000;
  5'd30:bitmap=256'h000066006600660066006e007a005a005a005a005a0052000000000000000000;
  5'd31:bitmap=256'h3c0066004600600030001c0006004200420066003c0000000000000000000000;
  default:bitmap=0;
 endcase
 assign pixel=(row0||row1) && bitmap[8'd255-{yy,x[3:0]}];
endmodule

// 64像素大字，仅告警覆盖；保持原RGB/同步流水线延迟。
module mm_alarm_headline(input wire [10:0] x,input wire [9:0] y,output wire pixel);
wire area=(x>=160 && x<480 && y>=160 && y<224);
wire [8:0] xx=x-160;wire [5:0] yy=y-160;
reg [15:0] row_bits;
always @(*)case({xx[8:6],yy[5:2]})
7'd0:row_bits=16'h0020;
7'd1:row_bits=16'h33fe;
7'd2:row_bits=16'h1820;
7'd3:row_bits=16'h03fc;
7'd4:row_bits=16'h0020;
7'd5:row_bits=16'h77fe;
7'd6:row_bits=16'h1000;
7'd7:row_bits=16'h11fc;
7'd8:row_bits=16'h1104;
7'd9:row_bits=16'h11fc;
7'd10:row_bits=16'h1504;
7'd11:row_bits=16'h19fc;
7'd12:row_bits=16'h3104;
7'd13:row_bits=16'h010c;
7'd14:row_bits=16'h0000;
7'd15:row_bits=16'h0000;
7'd16:row_bits=16'h1230;
7'd17:row_bits=16'h7fbe;
7'd18:row_bits=16'h1244;
7'd19:row_bits=16'h3fa8;
7'd20:row_bits=16'h7cb8;
7'd21:row_bits=16'h271c;
7'd22:row_bits=16'h3c66;
7'd23:row_bits=16'h7ffe;
7'd24:row_bits=16'h0000;
7'd25:row_bits=16'h1ff8;
7'd26:row_bits=16'h1ff8;
7'd27:row_bits=16'h0000;
7'd28:row_bits=16'h1ff8;
7'd29:row_bits=16'h1ff8;
7'd30:row_bits=16'h1008;
7'd31:row_bits=16'h0000;
7'd32:row_bits=16'h1000;
7'd33:row_bits=16'h11fc;
7'd34:row_bits=16'h1104;
7'd35:row_bits=16'h5dfc;
7'd36:row_bits=16'h5504;
7'd37:row_bits=16'h51fc;
7'd38:row_bits=16'h5080;
7'd39:row_bits=16'h51fe;
7'd40:row_bits=16'h134a;
7'd41:row_bits=16'h1252;
7'd42:row_bits=16'h1192;
7'd43:row_bits=16'h1322;
7'd44:row_bits=16'h1046;
7'd45:row_bits=16'h119c;
7'd46:row_bits=16'h0100;
7'd47:row_bits=16'h0000;
7'd48:row_bits=16'h0c00;
7'd49:row_bits=16'h0c00;
7'd50:row_bits=16'h0c00;
7'd51:row_bits=16'h0c00;
7'd52:row_bits=16'h0c00;
7'd53:row_bits=16'h0800;
7'd54:row_bits=16'h0800;
7'd55:row_bits=16'h0000;
7'd56:row_bits=16'h0000;
7'd57:row_bits=16'h0c00;
7'd58:row_bits=16'h0c00;
7'd59:row_bits=16'h0000;
7'd60:row_bits=16'h0000;
7'd61:row_bits=16'h0000;
7'd62:row_bits=16'h0000;
7'd63:row_bits=16'h0000;
7'd64:row_bits=16'h0c00;
7'd65:row_bits=16'h0c00;
7'd66:row_bits=16'h0c00;
7'd67:row_bits=16'h0c00;
7'd68:row_bits=16'h0c00;
7'd69:row_bits=16'h0800;
7'd70:row_bits=16'h0800;
7'd71:row_bits=16'h0000;
7'd72:row_bits=16'h0000;
7'd73:row_bits=16'h0c00;
7'd74:row_bits=16'h0c00;
7'd75:row_bits=16'h0000;
7'd76:row_bits=16'h0000;
7'd77:row_bits=16'h0000;
7'd78:row_bits=16'h0000;
7'd79:row_bits=16'h0000;
default:row_bits=0;endcase
assign pixel=area && row_bits[15-xx[5:2]];
endmodule

// 用户警告图片编译为64x60双色常量ROM；外部白底透明、内部白色保留；2倍显示。
module mm_alarm_icon(input wire[10:0] x,input wire[9:0] y,output wire[1:0] pixel);
wire area=x>=256 && x<384 && y>=144 && y<264;
wire[6:0] xx=x-256;wire[6:0] yy=y-144;
reg[63:0] red_bits;reg[5:0] lo,hi;reg row_valid;
always @(*)begin red_bits=0;lo=0;hi=0;row_valid=1;case(yy[6:1])
6'd8:begin red_bits=64'h00000001f0000000;lo=6'd31;hi=6'd35;end
6'd9:begin red_bits=64'h00000003f8000000;lo=6'd30;hi=6'd36;end
6'd10:begin red_bits=64'h00000007f8000000;lo=6'd29;hi=6'd36;end
6'd11:begin red_bits=64'h0000000ffc000000;lo=6'd28;hi=6'd37;end
6'd12:begin red_bits=64'h0000000e1e000000;lo=6'd28;hi=6'd38;end
6'd13:begin red_bits=64'h0000001c0e000000;lo=6'd27;hi=6'd38;end
6'd14:begin red_bits=64'h00000019e7000000;lo=6'd27;hi=6'd39;end
6'd15:begin red_bits=64'h0000003bf3000000;lo=6'd26;hi=6'd39;end
6'd16:begin red_bits=64'h00000073fb800000;lo=6'd25;hi=6'd40;end
6'd17:begin red_bits=64'h00000077f9800000;lo=6'd25;hi=6'd40;end
6'd18:begin red_bits=64'h000000e7fdc00000;lo=6'd24;hi=6'd41;end
6'd19:begin red_bits=64'h000000cffce00000;lo=6'd24;hi=6'd42;end
6'd20:begin red_bits=64'h000001dffee00000;lo=6'd23;hi=6'd42;end
6'd21:begin red_bits=64'h0000019ffe700000;lo=6'd23;hi=6'd43;end
6'd22:begin red_bits=64'h000003bfff300000;lo=6'd22;hi=6'd43;end
6'd23:begin red_bits=64'h0000073e0fb80000;lo=6'd21;hi=6'd44;end
6'd24:begin red_bits=64'h0000077c0f980000;lo=6'd21;hi=6'd44;end
6'd25:begin red_bits=64'h00000e7e0fdc0000;lo=6'd20;hi=6'd45;end
6'd26:begin red_bits=64'h00000cfe0fce0000;lo=6'd20;hi=6'd46;end
6'd27:begin red_bits=64'h00001dfe0fee0000;lo=6'd19;hi=6'd46;end
6'd28:begin red_bits=64'h000019fe0fe70000;lo=6'd19;hi=6'd47;end
6'd29:begin red_bits=64'h00003bfe1ff30000;lo=6'd18;hi=6'd47;end
6'd30:begin red_bits=64'h000073fe1ffb8000;lo=6'd17;hi=6'd48;end
6'd31:begin red_bits=64'h000077fe1ff98000;lo=6'd17;hi=6'd48;end
6'd32:begin red_bits=64'h0000e7fe1ffdc000;lo=6'd16;hi=6'd49;end
6'd33:begin red_bits=64'h0000cffe1ffce000;lo=6'd16;hi=6'd50;end
6'd34:begin red_bits=64'h0001dffe1ffee000;lo=6'd15;hi=6'd50;end
6'd35:begin red_bits=64'h00019ffe1ffe7000;lo=6'd15;hi=6'd51;end
6'd36:begin red_bits=64'h0003bffe1fff3000;lo=6'd14;hi=6'd51;end
6'd37:begin red_bits=64'h00073ffe1fffb800;lo=6'd13;hi=6'd52;end
6'd38:begin red_bits=64'h00077ffe1fff9800;lo=6'd13;hi=6'd52;end
6'd39:begin red_bits=64'h000e7ffe1fffdc00;lo=6'd12;hi=6'd53;end
6'd40:begin red_bits=64'h000cffff3fffce00;lo=6'd12;hi=6'd54;end
6'd41:begin red_bits=64'h001dffffffffee00;lo=6'd11;hi=6'd54;end
6'd42:begin red_bits=64'h0019ffffffffe700;lo=6'd11;hi=6'd55;end
6'd43:begin red_bits=64'h003bfffffffff300;lo=6'd10;hi=6'd55;end
6'd44:begin red_bits=64'h0073fffe1ffffb80;lo=6'd9;hi=6'd56;end
6'd45:begin red_bits=64'h0077fffe0ffff980;lo=6'd9;hi=6'd56;end
6'd46:begin red_bits=64'h00e7fffc0ffffdc0;lo=6'd8;hi=6'd57;end
6'd47:begin red_bits=64'h00cffffe1ffffce0;lo=6'd8;hi=6'd58;end
6'd48:begin red_bits=64'h01cfffff3ffffee0;lo=6'd7;hi=6'd58;end
6'd49:begin red_bits=64'h01cffffffffffe70;lo=6'd7;hi=6'd59;end
6'd50:begin red_bits=64'h03cffffffffffc70;lo=6'd6;hi=6'd59;end
6'd51:begin red_bits=64'h03c7fffffffff870;lo=6'd6;hi=6'd59;end
6'd52:begin red_bits=64'h03c00000000000f0;lo=6'd6;hi=6'd59;end
6'd53:begin red_bits=64'h01e00000000001e0;lo=6'd7;hi=6'd58;end
6'd54:begin red_bits=64'h00ffffffffffffe0;lo=6'd8;hi=6'd58;end
6'd55:begin red_bits=64'h007fffffffffff80;lo=6'd9;hi=6'd56;end
default:row_valid=0;endcase end
assign pixel=(!area || !row_valid || xx[6:1]<lo || xx[6:1]>hi)?2'd0:(red_bits[63-xx[6:1]]?2'd1:2'd2);
endmodule
