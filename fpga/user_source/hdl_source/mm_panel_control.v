`timescale 1ns/1ps
// 面板模式译码与按键消抖。SW1为bit0，有效模式如下：
// 0000基础控制，0001亮度，0010对比度，0100缩放，0111九宫格ROI，
// 1000图像轮廓，1100字幕选择；其他组合保持上一次有效模式。
// DEBOUNCE_CYCLES是输入稳定时间，PULSE_CYCLES是兼容原按键接口的低脉冲宽度。
// 调试记录：模式切换后必须先松开按键再重新武装，防止拨码过程中误触发一次操作。
module mm_panel_control #(parameter integer DEBOUNCE_CYCLES=1000000,
 parameter integer PULSE_CYCLES=1750000)(
 input wire clk, rst, input wire [3:0] sw, input wire [3:0] keys_n,
 output reg [3:0] mode, output reg [3:0] press,
 output wire next_n, auto_n, output reg reset_request);
 reg [3:0] sw_m,sw_s,sw_candidate,key_m,key_s,key_stable,armed;
 reg [19:0] sw_count;
 reg [19:0] key_count[0:3];
 reg [20:0] next_count,auto_count;
 wire candidate_valid=(sw_candidate==0 || sw_candidate==1 || sw_candidate==2 ||
                       sw_candidate==4 || sw_candidate==8 || sw_candidate==12 || sw_candidate==7);
 wire mode_settled=(sw_s==sw_candidate && sw_count>=DEBOUNCE_CYCLES);
 // 非法组合不更新mode；按键松开后才允许下一次触发。

 integer i;
 assign next_n=(next_count==0);
 assign auto_n=(auto_count==0);
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   sw_m<=0;sw_s<=0;sw_candidate<=0;mode<=0;sw_count<=0;
   key_m<=15;key_s<=15;key_stable<=15;armed<=0;
   press<=0;reset_request<=0;next_count<=0;auto_count<=0;
   for(i=0;i<4;i=i+1) key_count[i]<=0;
  end else begin
   sw_m<=sw;sw_s<=sw_m;key_m<=keys_n;key_s<=key_m;
   press<=0;reset_request<=0;
   if(next_count!=0) next_count<=next_count-1'b1;
   if(auto_count!=0) auto_count<=auto_count-1'b1;
   if(sw_s!=sw_candidate) begin sw_candidate<=sw_s;sw_count<=0;armed<=0; end
   else if(sw_count<DEBOUNCE_CYCLES) sw_count<=sw_count+1'b1;
   else if(candidate_valid && mode!=sw_candidate) begin mode<=sw_candidate;armed<=0; end
   for(i=0;i<4;i=i+1) begin
    if(key_s[i]==key_stable[i]) begin
     key_count[i]<=0;
     if(key_s[i] && mode_settled) armed[i]<=1;
    end else if(key_count[i]==DEBOUNCE_CYCLES-1) begin
     key_count[i]<=0;key_stable[i]<=key_s[i];
     if(!key_s[i]) begin
      armed[i]<=0;
      if(armed[i] && mode_settled) begin
       case(mode)
        0: begin
         if(i==0) next_count<=PULSE_CYCLES;
         if(i==1) auto_count<=PULSE_CYCLES;
         if(i==2) press[i]<=1;
         if(i==3) reset_request<=1;
        end
        1,2,4,7,8,12:press[i]<=1;
        default:;
       endcase
      end
     end
    end else key_count[i]<=key_count[i]+1'b1;
   end
  end
 end
endmodule
