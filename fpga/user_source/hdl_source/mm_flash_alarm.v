`timescale 1ns/1ps
// One group is an observed LGT=0 followed later by LGT=10.
// Intermediate values retain progress; holding either endpoint cannot add groups.
module mm_flash_alarm #(
 parameter [7:0] BRIGHT_LEVEL=8'd0,
 parameter [7:0] DARK_LEVEL=8'd10,
 parameter integer SAMPLE_MS=100,
 parameter integer STABLE_SAMPLES=1,
 parameter integer WINDOW_MS=20000,
 parameter integer CYCLES=3
)(input wire clk,rst,tick_ms,clear,valid,
  input wire [7:0] darkness,output reg trigger);
 localparam SPW=(SAMPLE_MS<2)?1:$clog2(SAMPLE_MS);
 localparam STW=(STABLE_SAMPLES<2)?1:$clog2(STABLE_SAMPLES);
 localparam CYW=(CYCLES<2)?1:$clog2(CYCLES);
 localparam WIW=(WINDOW_MS<2)?1:$clog2(WINDOW_MS+1);
 reg have_zero;
 reg [SPW-1:0] sample_cnt;
 reg [STW-1:0] stable_cnt;
 reg [CYW-1:0] cycle_cnt;
 reg [WIW-1:0] window_cnt;
 wire endpoint=have_zero?(darkness==DARK_LEVEL):(darkness==BRIGHT_LEVEL);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   trigger<=0;have_zero<=0;sample_cnt<=0;stable_cnt<=0;cycle_cnt<=0;window_cnt<=0;
  end else begin
   trigger<=0;
   if(clear || !valid)begin
    have_zero<=0;sample_cnt<=0;stable_cnt<=0;cycle_cnt<=0;window_cnt<=0;
   end else if(tick_ms)begin
    // Optional window is measured from the first zero; timeout wins over sampling.
    if(WINDOW_MS>0 && (have_zero || cycle_cnt!=0) && window_cnt>=WINDOW_MS-1)begin
     have_zero<=0;sample_cnt<=0;stable_cnt<=0;cycle_cnt<=0;window_cnt<=0;
    end else begin
     if(WINDOW_MS>0 && (have_zero || cycle_cnt!=0))window_cnt<=window_cnt+1'b1;
     if(sample_cnt==SAMPLE_MS-1)begin
      sample_cnt<=0;
      if(endpoint)begin
       if(stable_cnt<STABLE_SAMPLES-1)stable_cnt<=stable_cnt+1'b1;
       else begin
        stable_cnt<=0;
        if(!have_zero)have_zero<=1;
        else begin
         have_zero<=0;
         if(cycle_cnt==CYCLES-1)begin trigger<=1;cycle_cnt<=0;window_cnt<=0;end
         else cycle_cnt<=cycle_cnt+1'b1;
        end
       end
      end else stable_cnt<=0;
     end else sample_cnt<=sample_cnt+1'b1;
    end
   end
  end
 end
endmodule
