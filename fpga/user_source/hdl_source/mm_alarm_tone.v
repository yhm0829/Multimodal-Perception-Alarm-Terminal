`timescale 1ns/1ps
// 与原音频sample_valid同步的750Hz查表音，告警之外逐位直通。
// 16点一周期，48kHz每4采样推进一点。幅度只做右移，不用乘法器。
module mm_alarm_tone(input wire clk,rst,active,beep_on,sample_valid,
 input wire [2:0] level,input wire [23:0] normal_left,normal_right,
 output wire [23:0] left,right);
 reg [5:0] phase;
 reg signed [21:0] sine;
 wire signed [23:0] amplitude=($signed({{2{sine[21]}},sine}) <<< 2) >>> (3'd7-level);
 // 最大约满量程1/2，默认5档约1/8；0档静音，避免24bit削顶及初次上板过响。
 wire [23:0] warning_sample=(beep_on && level!=0)?amplitude:24'd0;
 assign left=active?warning_sample:normal_left;
 assign right=active?warning_sample:normal_right;
 always @(posedge clk or posedge rst)
  if(rst)phase<=0;else if(!active)phase<=0;else if(sample_valid)phase<=phase+1'b1;
 always @(*)case(phase[5:2])
  0:sine=0;1:sine=401272;2:sine=741455;3:sine=968758;
  4:sine=1048575;5:sine=968758;6:sine=741455;7:sine=401272;
  8:sine=0;9:sine=-401272;10:sine=-741455;11:sine=-968758;
  12:sine=-1048575;13:sine=-968758;14:sine=-741455;15:sine=-401272;
 endcase
endmodule
