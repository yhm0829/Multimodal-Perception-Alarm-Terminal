`timescale 1ns/1ps
// Valid framed external PCM wins even when silent. No generated display bars.
module mm_audio_source #(parameter integer TIMEOUT=250000, QUALIFY=8)(
 input wire clk,rst,external_valid,input wire [23:0] external_left,external_right,
 output reg valid,output reg [23:0] left,right,output reg demo_active, output wire sample_tick);
 reg [18:0] age;reg [3:0] good;
 reg [24:0] sample_acc;
 // Sample-clocked modulo-64 phase accumulator: steps1/2 give750/1500Hz.
 reg [5:0] phase;reg [15:0] sample_count;
 wire demo_tick=(sample_acc>=25000000-48000);
 assign sample_tick=demo_tick; // 既有48kHz使能，告警音不依赖外部I2S继续送帧。
 wire [4:0] sin_addr=phase[4]? (5'd0-phase[4:0]):phase[4:0];
 reg [15:0] sine_abs;
 wire signed [16:0] sine_value=phase[5]?-$signed({1'b0,sine_abs}):$signed({1'b0,sine_abs});
 wire [3:0] envelope=sample_count[15] ? ~sample_count[14:11] : sample_count[14:11];
 wire signed [21:0] modulated=sine_value * $signed({1'b0,envelope}+6'sd4);
 wire signed [23:0] tone=$signed(modulated) <<< 2;
 always @(*) case(sin_addr)
 5'd0:sine_abs=16'd0;
 5'd1:sine_abs=16'd1960;
 5'd2:sine_abs=16'd3902;
 5'd3:sine_abs=16'd5806;
 5'd4:sine_abs=16'd7654;
 5'd5:sine_abs=16'd9428;
 5'd6:sine_abs=16'd11111;
 5'd7:sine_abs=16'd12688;
 5'd8:sine_abs=16'd14142;
 5'd9:sine_abs=16'd15460;
 5'd10:sine_abs=16'd16629;
 5'd11:sine_abs=16'd17638;
 5'd12:sine_abs=16'd18478;
 5'd13:sine_abs=16'd19139;
 5'd14:sine_abs=16'd19616;
 5'd15:sine_abs=16'd19904;
 5'd16:sine_abs=16'd20000;
 default:sine_abs=0;
 endcase
 always @(posedge clk or posedge rst) begin
  if(rst) begin age<=TIMEOUT;good<=0;sample_acc<=0;phase<=0;sample_count<=0;
   valid<=0;left<=0;right<=0;demo_active<=1;end
  else begin
   valid<=0;
   if(demo_tick) begin sample_acc<=sample_acc+48000-25000000;
    sample_count<=sample_count+1'b1;
    phase<=phase+(sample_count[15]?6'd2:6'd1);
   end else sample_acc<=sample_acc+48000;
   if(external_valid) begin
    age<=0;
    if(good<QUALIFY) good<=good+1'b1;
    if(good>=QUALIFY-1) demo_active<=0;
   end else if(age<TIMEOUT) age<=age+1'b1;
   else begin good<=0;demo_active<=1;end
   if(!demo_active && external_valid) begin valid<=1;left<=external_left;right<=external_right;end
   else if(demo_active && demo_tick) begin valid<=1;left<=tone;right<=tone;end
  end
 end
endmodule
