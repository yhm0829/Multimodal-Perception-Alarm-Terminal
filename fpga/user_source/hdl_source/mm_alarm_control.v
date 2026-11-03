`timescale 1ns/1ps
// 告警状态与交互控制。本模块与FFT/音频同在25MHz，tick_ms是时钟使能，不是新时钟。
// MS_CYCLES表示1ms包含的输入时钟周期数；reasons[0]记录音频告警，reasons[1]记录光敏告警。
// 原因位锁存到上挥清除；tone_level范围0..7，只控制告警声幅度，不改变正常音频。
// 500ms节拍内安排两段短音，持续提示的同时保留静音间隔。
module mm_alarm_control #(parameter integer MS_CYCLES=25000)(
 input wire clk,rst,audio_alarm,flash_trigger,gesture_event,
 input wire [3:0] gesture_code,
 output reg tick_ms,output wire active,output reg [1:0] reasons,
 output reg [2:0] tone_level,output wire blink,output wire beep_on,
 output reg clear_pulse,output reg [1:0] report_event,output reg [31:0] uptime_ms);
 localparam CW=(MS_CYCLES<2)?1:$clog2(MS_CYCLES);
 reg [CW-1:0] divider;
 reg [8:0] cadence;
 reg audio_last;
 assign active=|reasons;
 assign blink=(cadence<250);
 assign beep_on=active && (cadence<125 || (cadence>=200 && cadence<325));
 // 两声短音后停175ms；音量0..7，只影响告警声，不改正常音频。
 always @(posedge clk or posedge rst)begin
  if(rst)begin divider<=0;tick_ms<=0;uptime_ms<=0;cadence<=0;reasons<=0;
   tone_level<=4;clear_pulse<=0;report_event<=0;audio_last<=0;end
  else begin
   tick_ms<=0;clear_pulse<=0;report_event<=0;audio_last<=audio_alarm;
   if(divider==MS_CYCLES-1)begin divider<=0;tick_ms<=1;uptime_ms<=uptime_ms+1'b1;end
   else divider<=divider+1'b1;
   if(!active)cadence<=0;
   else if(tick_ms)begin if(cadence==499)cadence<=0;else cadence<=cadence+1'b1;end
   if(audio_alarm && !audio_last && !reasons[0])begin reasons[0]<=1;report_event[0]<=1;end
   if(flash_trigger && !reasons[1])begin reasons[1]<=1;report_event[1]<=1;end
   // 系统内部手势码：上=1、右=3、左=4、顺时针=7、逆时针=8。
   if(gesture_event)begin
    if(gesture_code==1)begin reasons<=0;report_event<=0;clear_pulse<=1;end  // 上挥解除告警
    else if(active && gesture_code==8 && tone_level!=0)tone_level<=tone_level-1'b1; // 逆时针减音量
    else if(active && gesture_code==7 && tone_level!=7)tone_level<=tone_level+1'b1; // 顺时针加音量
   end
  end
 end
endmodule
