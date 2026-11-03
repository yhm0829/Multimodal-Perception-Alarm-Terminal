`timescale 1ns/1ps
// PCM1808 master, FMT=0: 64 BCLK/frame, 24-bit two's complement.
// Oversample with 25 MHz; data/LRCK settle for half of a 3.072 MHz BCLK.
module I2S_receiver(input wire I_clk,I_rst,I_i2s_BCLK,I_i2s_LRCK,I_i2s_DOUT,
 output reg O_audio_valid,output reg [23:0] O_audio_left_data,O_audio_right_data);
 (* async_reg="true" *) reg [2:0] bclk_s,lrck_s,data_s;
 reg channel,started,left_good;
 reg [5:0] bit_count;
 reg [23:0] shift,left_hold;
 wire rise=bclk_s[1] && !bclk_s[2];
 always @(posedge I_clk or posedge I_rst) begin
  if(I_rst) begin
   bclk_s<=0;lrck_s<=0;data_s<=0;channel<=0;started<=0;left_good<=0;
   bit_count<=0;shift<=0;left_hold<=0;O_audio_valid<=0;
   O_audio_left_data<=0;O_audio_right_data<=0;
  end else begin
   bclk_s<={bclk_s[1:0],I_i2s_BCLK};lrck_s<={lrck_s[1:0],I_i2s_LRCK};
   data_s<={data_s[1:0],I_i2s_DOUT};O_audio_valid<=0;
   if(rise) begin
    if(lrck_s[2]!=channel) begin
     if(started && bit_count==31) begin
      if(!channel) begin left_hold<=shift;left_good<=1;end
      else if(left_good) begin
       O_audio_left_data<=left_hold;O_audio_right_data<=shift;O_audio_valid<=1;
       left_good<=0;
      end
     end else left_good<=0;
     channel<=lrck_s[2];started<=1;bit_count<=0;shift<=0;
     // This edge is the I2S one-bit delay, not the new channel MSB.
    end else if(started) begin
     if(bit_count<24) shift<={shift[22:0],data_s[2]};
     if(bit_count<63) bit_count<=bit_count+1'b1;
    end
   end
  end
 end
endmodule
