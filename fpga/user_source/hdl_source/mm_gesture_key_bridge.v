`timescale 1ns/1ps
// 手势事件桥接：把传感器事件转换为切图脉冲、ROI位置或告警控制码。
// PULSE_CYCLES决定低有效按键脉冲宽度，COOLDOWN_CYCLES限制连续触发，
// QUIET_CYCLES要求动作结束后出现完整静默窗口，防止一次挥动被识别为多次操作。
// 调试记录：仅等待gesture_event会受传感器内部冷却影响，因此同时观察原始活动和静默采样。
module mm_gesture_key_bridge #(
 parameter integer PULSE_CYCLES=1750000, COOLDOWN_CYCLES=25000000,
 parameter integer QUIET_CYCLES=40000000
)(input wire clk,rst,gesture_event,input wire [3:0] gesture_code,
 output wire next_n,auto_n,effect_n,prev_n,input wire quiet_event,
 input wire activity_event, input wire alarm_active, input wire roi_mode,
 output reg [3:0] roi_position,
 output reg accepted_toggle,output reg [3:0] accepted_code);
 localparam integer QW=$clog2(QUIET_CYCLES+1);
 reg [20:0] next_count,prev_count;
 reg [24:0] cooldown;
 reg [QW-1:0] quiet_count;
 reg armed, quiet_seen;
 assign next_n=(next_count==0);
 assign prev_n=(prev_count==0);
 assign auto_n=1'b1;
 assign effect_n=1'b1;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   next_count<=0;prev_count<=0;cooldown<=0;armed<=1;accepted_toggle<=0;accepted_code<=0;
   quiet_seen<=0;quiet_count<=0;roi_position<=4;
  end else begin
   if(next_count!=0)next_count<=next_count-1'b1;
   if(prev_count!=0)prev_count<=prev_count-1'b1;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   if(activity_event || gesture_event) begin
    quiet_seen<=0;quiet_count<=0;
   end else begin
    if(quiet_event)quiet_seen<=1;
    if(quiet_seen && quiet_count<QUIET_CYCLES)quiet_count<=quiet_count+1'b1;
    // 仅由新的静默采样重新武装，不能沿用上一次遗留的静默电平。
    if(quiet_event && quiet_seen && quiet_count>=QUIET_CYCLES && cooldown==0)
     armed<=1;
   end
   // 内部手势码：上=1、下=2、标准右挥=3、标准左挥=4、顺时针=7、逆时针=8。
   // ROI模式只接收左右挥，避免上挥清警和旋转调音量在选区过程中误触发。
   if(gesture_event && armed && cooldown==0 && (gesture_code==3 || gesture_code==4 || (alarm_active && (gesture_code==1 || gesture_code==7 || gesture_code==8)))) begin
    armed<=0;quiet_seen<=0;quiet_count<=0;cooldown<=COOLDOWN_CYCLES;
    if(roi_mode) begin
     if(gesture_code==3) roi_position <= (roi_position==8)?0:roi_position+1'b1;
     if(gesture_code==4) roi_position <= (roi_position==0)?8:roi_position-1'b1;
    end else begin accepted_toggle<=~accepted_toggle;accepted_code<=gesture_code; end
    if(!roi_mode && !alarm_active && gesture_code==3)next_count<=PULSE_CYCLES; // 传感器标准右挥 -> 下一张
    if(!roi_mode && !alarm_active && gesture_code==4)prev_count<=PULSE_CYCLES; // 传感器标准左挥 -> 上一张
   end
  end
 end
endmodule
