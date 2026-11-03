`timescale 1ns/1ps
// Optional standard I2S DAC, stereo 24-bit in 32-bit slots, 48kHz, 64fs.
// Eight-entry asynchronous FIFO preserves complete stereo pairs across clocks.
module mm_dac_output(input wire sample_clk,mclk,rst,sample_valid,
 input wire [23:0] left,right,output wire bclk,output reg lrck,dout,
 output reg overflow,underflow);
 (* async_reg="true" *) reg [1:0] reset_write_sync=2'b11,reset_read_sync=2'b11;
 always @(posedge sample_clk or posedge rst)
  if(rst)reset_write_sync<=2'b11;else reset_write_sync<={reset_write_sync[0],1'b0};
 always @(posedge mclk or posedge rst)
  if(rst)reset_read_sync<=2'b11;else reset_read_sync<={reset_read_sync[0],1'b0};
 wire wrst=reset_write_sync[1],rrst=reset_read_sync[1];
 reg [47:0] mem[0:7];
 reg [3:0] wp, wg, rp, rg;
 (* async_reg="true" *) reg [3:0] rm,rs,wm,ws;
 reg [7:0] phase;
 reg [47:0] pair_hold;
 reg running;
 wire [3:0] wn=wp+1'b1,rn=rp+1'b1;
 wire full=(wg=={~rs[3:2],rs[1:0]});
 wire empty=(rg==ws);
 wire [3:0] wbin={ws[3],^ws[3:2],^ws[3:1],^ws};
 wire [3:0] available=wbin-rp;
 assign bclk=phase[1];
 always @(posedge sample_clk or posedge wrst) begin
  if(wrst)begin wp<=0;wg<=0;rm<=0;rs<=0;overflow<=0;end
  else begin
   rm<=rg;rs<=rm;
   if(sample_valid)begin
    if(full)overflow<=1;
    else begin mem[wp[2:0]]<={left,right};wp<=wn;wg<=(wn>>1)^wn;end
   end
  end
 end
 always @(posedge mclk or posedge rrst) begin
  if(rrst)begin rp<=0;rg<=0;wm<=0;ws<=0;phase<=0;lrck<=0;dout<=0;pair_hold<=0;running<=0;underflow<=0;end
  else begin
   wm<=wg;ws<=wm;phase<=phase+1'b1;
   if(phase[1:0]==3)begin // all data changes on falling BCLK
    lrck<=phase[7];
    if(phase[7:2]==0)begin
     dout<=0;
     if((running && !empty) || (!running && available>=2))begin
      pair_hold<=mem[rp[2:0]];rp<=rn;rg<=(rn>>1)^rn;running<=1;
     end else begin
      pair_hold<=0;
      if(running)underflow<=1;
      running<=0;
     end
    end else if(phase[7:2]>=1 && phase[7:2]<=24)
     dout<=pair_hold[48-phase[7:2]];
    else if(phase[7:2]>=33 && phase[7:2]<=56)
     dout<=pair_hold[56-phase[7:2]];
    else dout<=0;
   end
  end
 end
endmodule
