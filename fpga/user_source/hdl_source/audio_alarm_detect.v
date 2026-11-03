`timescale 1ns/1ps
// 相对能量突增与归一化频谱序列分类器，逐帧决策，不存储音频模板。
// ENERGY_MIN屏蔽静音量化噪声，WARM_FRAMES用于建立环境能量基线；
// 低频主体和随后出现的高频尾部组成时序特征，减少单次敲击造成的误报。
// 调试记录：8位显示音量在安静输入下可能量化为0，分类器仍使用高精度energy，
// 因此不能用显示音量作为频谱判决的总使能。
module audio_alarm_detect #(
 parameter [7:0] VOLUME_ON=8'd1,parameter [31:0] ENERGY_MIN=32'd16,
 parameter integer WARM_FRAMES=32
)(input wire clk,rst,frame_valid,tick_ms,enable,clear,
 input wire [31:0] energy,input wire [29:0] low200,input wire [31:0] low1k,
 input wire [30:0] high2k8k,input wire [4:0] wide_bins,input wire [7:0] volume,
 output reg alarm,output reg suspect,output reg [1:0] class_code,
 output reg [3:0] score,output reg [15:0] decision_latency_ms,output reg decision_valid);
 reg [31:0] energy_floor;
 localparam WW=(WARM_FRAMES<2)?1:$clog2(WARM_FRAMES+1);
 reg [WW-1:0] warm;
 reg [2:0] pending,candidate_frames;
 wire [3:0] latency_frames={1'b0,candidate_frames}+1'b1;
 wire [15:0] latency_value=({12'd0,latency_frames}<<4)+({12'd0,latency_frames}<<3);
 reg signature_b,body_seen;
 // sounding直接由高精度energy判断，不受8位显示音量量化影响。
 wire sounding=(energy>=ENERGY_MIN);
 wire energy_jump={5'b0,energy}>=({5'b0,energy_floor}<<5);
 wire low87=(low1k>=(energy-(energy>>3)));
 wire bass50=({2'b0,low200}>=(energy>>1));
 wire type_a=low87&&bass50;
 wire type_b=(low1k>=(energy>>1))&&!low87&&
  ({2'b0,low200}>=(energy>>3))&&({2'b0,low200}<((energy>>1)+(energy>>3)))&&
  ({1'b0,high2k8k}>=(energy>>5))&&({1'b0,high2k8k}<=(energy>>2));
 wire onset=energy_jump&&(type_a||type_b);
 // onset已确认低频主体；高频尾部允许出现在后续FFT帧，此时200Hz以下能量可能已衰减。
 wire rumble=({1'b0,high2k8k}>=(energy>>2))&&
  (signature_b?body_seen:(low1k>=(energy>>2)));
 wire [31:0] floor_input=(energy==0)?32'd1:energy;
 wire [31:0] edown=(energy_floor-floor_input)>>2;
 wire [31:0] eup=(floor_input-energy_floor)>>5;
 wire unused=^{tick_ms,wide_bins,volume,VOLUME_ON};
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   energy_floor<=1;warm<=0;pending<=0;candidate_frames<=0;
   alarm<=0;suspect<=0;signature_b<=0;body_seen<=0;class_code<=0;score<=0;
   decision_latency_ms<=0;decision_valid<=0;
  end else begin
   decision_valid<=0;suspect<=0;
   if(clear||!enable)begin
    energy_floor<=1;warm<=0;pending<=0;candidate_frames<=0;
    alarm<=0;signature_b<=0;body_seen<=0;
    if(clear)begin class_code<=0;score<=0;decision_latency_ms<=0;end
   end else if(frame_valid)begin
    // 安静段继续更新基线，不因显示幅度取整为0而反复重新预热。
    if(warm==0)begin energy_floor<=floor_input;warm<=1;end
    else begin
     if(pending==0)begin
      if(floor_input<energy_floor)energy_floor<=energy_floor-((edown==0)?32'd1:edown);
      else if(floor_input>energy_floor)energy_floor<=energy_floor+((eup==0)?32'd1:eup);
     end
     if(warm<WARM_FRAMES)begin warm<=warm+1'b1;pending<=0;candidate_frames<=0;end
     else if(!alarm)begin
      if(!sounding)begin
     if(pending!=0)begin
      // 频谱主体形成前恢复静音时，按短脉冲处理，不进入持续告警。
      pending<=0;class_code<=2;score<=3;decision_latency_ms<=latency_value;
      decision_valid<=1;candidate_frames<=0;
     end
      end else begin
       if(pending!=0)begin
        candidate_frames<=candidate_frames+1'b1;
        if(rumble)begin
         alarm<=1;pending<=0;class_code<=1;score<=signature_b?4'd8:4'd9;
         decision_latency_ms<=latency_value;decision_valid<=1;
        end else if(pending==1)begin
         pending<=0;suspect<=body_seen;class_code<=body_seen?2'd2:2'd3;
         score<=body_seen?4'd5:4'd2;decision_latency_ms<=latency_value;
         decision_valid<=1;
        end else begin pending<=pending-1'b1;if(low87&&bass50)body_seen<=1;end
       end else if(onset)begin
        pending<=type_a?2:5;signature_b<=!type_a;body_seen<=0;candidate_frames<=0;
       end
      end
     end
    end
   end
  end
 end
endmodule

// 多模态融合保留音频和光敏两条独立告警；中等置信度音频特征仅在光敏事件时间窗内升级。
// WINDOW_MS定义两类事件允许互相印证的最大时间差。
module mm_multimodal_fusion #(parameter integer WINDOW_MS=2000)(
 input wire clk,rst,tick_ms,clear,audio_alarm,audio_suspect,flash_trigger,
 output wire fused_audio_alarm,output reg combined_event);
 localparam W=(WINDOW_MS<2)?1:$clog2(WINDOW_MS+1);
 reg [W-1:0] suspect_age,flash_age;reg suspect_recent,flash_recent;
 assign fused_audio_alarm=audio_alarm|combined_event;
 always @(posedge clk or posedge rst)begin
  if(rst)begin suspect_age<=0;flash_age<=0;suspect_recent<=0;flash_recent<=0;combined_event<=0;end
  else begin
   combined_event<=0;
   if(clear)begin suspect_age<=0;flash_age<=0;suspect_recent<=0;flash_recent<=0;end
   else begin
    if(audio_suspect)begin suspect_recent<=1;suspect_age<=0;if(flash_recent||flash_trigger)combined_event<=1;end
    if(flash_trigger)begin flash_recent<=1;flash_age<=0;if(suspect_recent||audio_suspect)combined_event<=1;end
    if(tick_ms)begin
     if(suspect_recent)begin if(suspect_age==WINDOW_MS-1)suspect_recent<=0;else suspect_age<=suspect_age+1'b1;end
     if(flash_recent)begin if(flash_age==WINDOW_MS-1)flash_recent<=0;else flash_age<=flash_age+1'b1;end
    end
   end
  end
 end
endmodule
