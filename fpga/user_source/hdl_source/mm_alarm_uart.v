`timescale 1ns/1ps
// Format and transmit in the same 25 MHz video clock domain.
// 25 MHz / 217 = 115207.37 baud (0.0064% high), 8N1.
module mm_alarm_uart #(parameter integer BAUD_DIV=217, STATUS_CYCLES=25000000)(
 input wire clk,rst,input wire [1:0] events,input wire [31:0] timestamp_ms,
 input wire [7:0] darkness,volume,input wire [5:0] brightness,
 input wire [2:0] tone_level,input wire [1:0] reasons,
 input wire sensor_ready,sensor_error,input wire [3:0] gesture,
 input wire [7:0] raw43,raw44,input wire [1:0] audio_class,input wire [3:0] audio_score,
 input wire [15:0] audio_latency_ms,input wire combined_event,decision_valid,
 input wire clear,tick_ms,pcm_valid,light_valid,input wire [15:0] pcm_sample,
 output reg tx);
 localparam BW=(BAUD_DIV<2)?1:$clog2(BAUD_DIV);
 localparam SW=(STATUS_CYCLES<2)?1:$clog2(STATUS_CYCLES);
 reg [SW-1:0] status_count;
 reg [3:0] pending;
 reg [121:0] audio_record,flash_record,clear_record,status_record,current;
 reg combined_seen;
 reg [15:0] pcm_last;
 reg [7:0] pcm_age;
 wire pcm_recent=(pcm_age<8'd250);
 wire [121:0] snapshot={pcm_last,pcm_recent,light_valid,timestamp_ms,darkness,volume,brightness,tone_level,reasons,
  sensor_ready,sensor_error,gesture,raw43,raw44,audio_class,audio_score,audio_latency_ms,((combined_seen|combined_event)&&!clear)};
 reg [1:0] kind,last_reasons;
 reg [2:0] last_tone;
 reg busy;reg [7:0] position;
 reg [7:0] byte_mailbox;
 reg byte_request,byte_wait,byte_ack;
 reg [9:0] tx_shift;
 reg [3:0] tx_bits;
 reg [BW-1:0] tx_count;
 reg tx_busy;
 reg [7:0] character;
 wire [7:0] ambient_brightness=current[104]?(8'hff-current[71:64]):8'd0;
 function [7:0] hexchar;input [3:0] v;begin hexchar=(v<10)?8'd48+v:8'd65+(v-10);end endfunction
 always @(*)begin
  character=32;
  case(position)
   8'd0:character=8'd76;
   8'd1:character=8'd79;
   8'd2:character=8'd71;
   8'd3:character=8'd32;
   8'd4:character=kind==0?8'd69:kind==1?8'd70:kind==2?8'd65:8'd83;
   8'd5:character=kind==0?8'd120:kind==1?8'd108:kind==2?8'd108:8'd116;
   8'd6:character=kind==0?8'd112:kind==1?8'd97:kind==2?8'd97:8'd97;
   8'd7:character=kind==0?8'd108:kind==1?8'd115:kind==2?8'd114:8'd116;
   8'd8:character=kind==0?8'd111:kind==1?8'd104:kind==2?8'd109:8'd117;
   8'd9:character=kind==0?8'd115:kind==1?8'd32:kind==2?8'd32:8'd115;
   8'd10:character=kind==0?8'd105:kind==1?8'd69:kind==2?8'd67:8'd32;
   8'd11:character=kind==0?8'd111:kind==1?8'd120:kind==2?8'd108:8'd32;
   8'd12:character=kind==0?8'd110:kind==1?8'd112:kind==2?8'd101:8'd32;
   8'd13:character=kind==0?8'd32:kind==1?8'd108:kind==2?8'd97:8'd32;
   8'd14:character=kind==0?8'd87:kind==1?8'd111:kind==2?8'd114:8'd32;
   8'd15:character=kind==0?8'd97:kind==1?8'd115:kind==2?8'd101:8'd32;
   8'd16:character=kind==0?8'd114:kind==1?8'd105:kind==2?8'd100:8'd32;
   8'd17:character=kind==0?8'd110:kind==1?8'd111:kind==2?8'd32:8'd32;
   8'd18:character=kind==0?8'd105:kind==1?8'd110:kind==2?8'd32:8'd32;
   8'd19:character=kind==0?8'd110:kind==1?8'd32:kind==2?8'd32:8'd32;
   8'd20:character=kind==0?8'd103:kind==1?8'd32:kind==2?8'd32:8'd32;
   8'd21:character=kind==0?8'd32:kind==1?8'd32:kind==2?8'd32:8'd32;
   8'd22:character=kind==0?8'd32:kind==1?8'd32:kind==2?8'd32:8'd32;
   8'd23:character=8'd32;
   8'd24:character=8'd76;
   8'd25:character=kind==0?"1":kind==1?"2":"0";
   8'd26:character=8'd32;
   8'd27:character=8'd77;
   8'd28:character=8'd83;
   8'd29:character=8'd61;
   8'd30:character=hexchar(current[103-:4]);
   8'd31:character=hexchar(current[99-:4]);
   8'd32:character=hexchar(current[95-:4]);
   8'd33:character=hexchar(current[91-:4]);
   8'd34:character=hexchar(current[87-:4]);
   8'd35:character=hexchar(current[83-:4]);
   8'd36:character=hexchar(current[79-:4]);
   8'd37:character=hexchar(current[75-:4]);
   8'd38:character=8'd32;
   8'd39:character=8'd76;
   8'd40:character=8'd73;
   8'd41:character=8'd71;
   8'd42:character=8'd72;
   8'd43:character=8'd84;
   8'd44:character=8'd61;
   8'd45:character=hexchar(current[71-:4]);
   8'd46:character=hexchar(current[67-:4]);
   8'd47:character=8'd32;
   8'd48:character=8'd86;
   8'd49:character=8'd79;
   8'd50:character=8'd76;
   8'd51:character=8'd61;
   8'd52:character=hexchar(current[63-:4]);
   8'd53:character=hexchar(current[59-:4]);
   8'd54:character=8'd32;
   8'd55:character=8'd66;
   8'd56:character=8'd82;
   8'd57:character=8'd73;
   8'd58:character=8'd71;
   8'd59:character=8'd72;
   8'd60:character=8'd84;
   8'd61:character=8'd61;
   8'd62:character=hexchar(ambient_brightness[7:4]);
   8'd63:character=hexchar(ambient_brightness[3:0]);
   8'd64:character=8'd32;
   8'd65:character=8'd84;
   8'd66:character=8'd79;
   8'd67:character=8'd78;
   8'd68:character=8'd69;
   8'd69:character=8'd61;
   // Report effective alarm volume; SET below retains the configured level.
   8'd70:character=hexchar((current[46:45]==0)?4'd0:{1'b0,current[49:47]});
   8'd71:character=8'd32;
   8'd72:character=8'd65;
   8'd73:character=8'd67;
   8'd74:character=8'd84;
   8'd75:character=8'd73;
   8'd76:character=8'd86;
   8'd77:character=8'd69;
   8'd78:character=8'd61;
   8'd79:character=hexchar({2'b0,current[46:45]});
   8'd80:character=8'd32;
   8'd81:character=8'd82;
   8'd82:character=8'd69;
   8'd83:character=8'd65;
   8'd84:character=8'd68;
   8'd85:character=8'd89;
   8'd86:character=8'd61;
   8'd87:character=hexchar({3'b0,current[44]});
   8'd88:character=8'd32;
   8'd89:character=8'd69;
   8'd90:character=8'd82;
   8'd91:character=8'd82;
   8'd92:character=8'd61;
   8'd93:character=hexchar({3'b0,current[43]});
   8'd94:character=8'd32;
   8'd95:character=8'd71;
   8'd96:character=8'd83;
   8'd97:character=8'd84;
   8'd98:character=8'd61;
   8'd99:character=hexchar(current[42:39]);
   8'd100:character=8'd32;
   8'd101:character=8'd82;
   8'd102:character=8'd65;
   8'd103:character=8'd87;
   8'd104:character=8'd61;
   8'd105:character=hexchar(current[38-:4]);
   8'd106:character=hexchar(current[34-:4]);
   8'd107:character=hexchar(current[30-:4]);
   8'd108:character=hexchar(current[26-:4]);
   8'd109:character=" "; 8'd110:character="C"; 8'd111:character="L"; 8'd112:character="S"; 8'd113:character="=";
   8'd114:character=hexchar({2'b0,current[22:21]});
   8'd115:character=" "; 8'd116:character="S"; 8'd117:character="C"; 8'd118:character="=";
   8'd119:character=hexchar(current[20:17]);
   8'd120:character=" "; 8'd121:character="L"; 8'd122:character="A"; 8'd123:character="T"; 8'd124:character="=";
   8'd125:character=hexchar(current[16:13]);8'd126:character=hexchar(current[12:9]);
   8'd127:character=hexchar(current[8:5]);8'd128:character=hexchar(current[4:1]);
   8'd129:character=" ";8'd130:character="C";8'd131:character="B";8'd132:character="=";
   // Combined source bitmap: 0=none, 1=audio, 2=flash, 3=both.
   8'd133:character=hexchar({2'b0,current[46:45]});
   8'd134:character=" ";8'd135:character="S";8'd136:character="E";8'd137:character="T";8'd138:character="=";
   8'd139:character=hexchar({1'b0,current[49:47]});
   8'd140:character=" ";8'd141:character="P";8'd142:character="C";8'd143:character="M";8'd144:character="=";
   8'd145:character=hexchar(current[121:118]);8'd146:character=hexchar(current[117:114]);
   8'd147:character=hexchar(current[113:110]);8'd148:character=hexchar(current[109:106]);
   8'd149:character=" ";8'd150:character="I";8'd151:character="2";8'd152:character="S";8'd153:character="=";
   8'd154:character=hexchar({3'b0,current[105]});
   8'd155:character=" ";8'd156:character="L";8'd157:character="V";8'd158:character="A";8'd159:character="L";8'd160:character="I";8'd161:character="D";8'd162:character="=";
   8'd163:character=hexchar({3'b0,current[104]});
   8'd164:character=" ";8'd165:character="A";8'd166:character="U";8'd167:character="D";8'd168:character="I";8'd169:character="O";8'd170:character="=";
   8'd171:character=hexchar({3'b0,current[45]});
   8'd172:character=" ";8'd173:character="F";8'd174:character="L";8'd175:character="A";8'd176:character="S";8'd177:character="H";8'd178:character="=";
   8'd179:character=hexchar({3'b0,current[46]});
   8'd180:character=" ";8'd181:character="B";8'd182:character="S";8'd183:character="E";8'd184:character="T";8'd185:character="=";
   8'd186:character=hexchar({2'b0,current[55:54]});8'd187:character=hexchar(current[53:50]);
   8'd188:character=" ";8'd189:character="F";8'd190:character="U";8'd191:character="S";8'd192:character="E";8'd193:character="D";8'd194:character="=";
   8'd195:character=hexchar({3'b0,current[0]});
   8'd196:character=8'd13;8'd197:character=8'd10;
  endcase
 end
  // The byte producer and serializer share clk, so no multi-bit CDC mailbox remains.
  always @(posedge clk or posedge rst)begin
   if(rst)begin
    byte_ack<=0;tx_shift<=10'h3ff;tx_bits<=0;
   tx_count<=0;tx_busy<=0;tx<=1'b1;
  end else begin
   tx<=tx_busy?tx_shift[0]:1'b1;
   if(!tx_busy)begin
     if(byte_request!=byte_ack)begin
     tx_shift<={1'b1,byte_mailbox,1'b0};tx_bits<=10;
     tx_count<=BAUD_DIV-1;tx_busy<=1;
    end
   end else if(tx_count!=0)tx_count<=tx_count-1'b1;
   else begin
    tx_shift<={1'b1,tx_shift[9:1]};tx_count<=BAUD_DIV-1;
    tx_bits<=tx_bits-1'b1;
     if(tx_bits==1)begin tx_busy<=0;byte_ack<=byte_request;end
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin combined_seen<=0;pcm_last<=0;pcm_age<=8'd250;end
  else begin
   if(clear)combined_seen<=0;
   else if(combined_event)combined_seen<=1;
   if(pcm_valid)begin pcm_last<=pcm_sample;pcm_age<=0;end
   else if(tick_ms && pcm_age<8'd250)pcm_age<=pcm_age+1'b1;
  end
 end
 always @(posedge clk or posedge rst)begin
   if(rst)begin pending<=0;audio_record<=0;flash_record<=0;clear_record<=0;status_record<=0;current<=0;
   kind<=0;last_reasons<=0;last_tone<=4;status_count<=0;busy<=0;position<=0;
    byte_mailbox<=0;byte_request<=0;byte_wait<=0;end
  else begin
   last_reasons<=reasons;last_tone<=tone_level;
   if(status_count==STATUS_CYCLES-1)status_count<=0;else status_count<=status_count+1'b1;
   if(!busy)begin
    if(pending!=0)begin busy<=1;position<=0;
     if(pending[0])begin current<=audio_record;kind<=0;pending[0]<=0;end
     else if(pending[1])begin current<=flash_record;kind<=1;pending[1]<=0;end
     else if(pending[2])begin current<=clear_record;kind<=2;pending[2]<=0;end
     else begin current<=status_record;kind<=3;pending[3]<=0;end
    end
   end else if(!byte_wait)begin
    byte_mailbox<=character;byte_request<=~byte_request;byte_wait<=1;
   end else if(byte_ack==byte_request)begin
    byte_wait<=0;
    if(position==197)busy<=0;else position<=position+1'b1;
   end
   if(events[0])begin pending[0]<=1;audio_record<=snapshot;end
   if(events[1])begin pending[1]<=1;flash_record<=snapshot;end
   if(last_reasons!=0 && reasons==0)begin pending[2]<=1;clear_record<=snapshot;end
   if(status_count==0 || last_reasons!=reasons || last_tone!=tone_level)begin pending[3]<=1;status_record<=snapshot;end
   if(decision_valid)begin pending[3]<=1;status_record<=snapshot;end
   // Capture a one-cycle fusion event even if it misses the heartbeat.
   if(combined_event)begin pending[3]<=1;status_record<=snapshot;end
  end
 end
endmodule

