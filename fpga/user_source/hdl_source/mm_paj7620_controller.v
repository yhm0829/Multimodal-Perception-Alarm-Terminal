`timescale 1ns/1ps

// PAJ7620U2初始化与50Hz手势读取控制器。
// WAIT_60MS和WAKE_700US对应上电、唤醒等待；POLL_20MS决定轮询周期；
// COOLDOWN_300MS限制同一动作重复上报。I2C器件地址固定为7'h73。
// 初始化表采用公开的Seeed手势模式寄存器序列，许可说明见根目录THIRD_PARTY_LICENSE.txt。
// raw43/raw44保留传感器原始标志，gesture_code输出系统内部统一手势码。
// 调试记录：0x43可能同时出现多个方向位，代码只接受单一目标位；组合位返回异常码，
// 不按位优先级猜测方向，避免快速挥动时出现左右反跳。
module mm_paj7620_controller #(
    parameter integer WAIT_60MS=3000000,
    parameter integer WAKE_700US=35000,
    parameter integer POLL_20MS=1000000,
    parameter integer COOLDOWN_300MS=0
)( 
    input  wire       clk,
    input  wire       rst,
    input  wire       int_n,
    inout  wire       scl,
    inout  wire       sda,
    output reg        sensor_ready,
    output reg        sensor_error,
    output reg  [3:0] gesture_code,
    output reg        gesture_event,
    output reg[7:0] raw43,raw44,cfg41,cfg42,
    output reg raw_valid,cfg_valid
);
    localparam [6:0] DEV_ADDR = 7'h73;

    reg master_start, master_read;
    reg [7:0] master_reg, master_wdata;
    wire [7:0] master_rdata;
    wire master_busy, master_done, master_ack_error;

    mm_i2c_reg_master u_i2c(
        .clk(clk), .rst(rst), .start(master_start),
        .read_not_write(master_read), .dev_addr(DEV_ADDR),
        .reg_addr(master_reg), .write_data(master_wdata),
        .read_data(master_rdata), .busy(master_busy), .done(master_done),
        .ack_error(master_ack_error), .scl(scl), .sda(sda)
    );

    function [15:0] init_word;
        input [7:0] index;
        begin
            case(index)
                8'd0: init_word=16'hEF00;
                8'd1: init_word=16'h3229;
                8'd2: init_word=16'h3301;
                8'd3: init_word=16'h3400;
                8'd4: init_word=16'h3501;
                8'd5: init_word=16'h3600;
                8'd6: init_word=16'h3707;
                8'd7: init_word=16'h3817;
                8'd8: init_word=16'h3906;
                8'd9: init_word=16'h3A12;
                8'd10: init_word=16'h3F00;
                8'd11: init_word=16'h4002;
                8'd12: init_word=16'h41FF;
                8'd13: init_word=16'h4201;
                8'd14: init_word=16'h462D;
                8'd15: init_word=16'h470F;
                8'd16: init_word=16'h483C;
                8'd17: init_word=16'h4900;
                8'd18: init_word=16'h4A1E;
                8'd19: init_word=16'h4B00;
                8'd20: init_word=16'h4C20;
                8'd21: init_word=16'h4D00;
                8'd22: init_word=16'h4E1A;
                8'd23: init_word=16'h4F14;
                8'd24: init_word=16'h5000;
                8'd25: init_word=16'h5110;
                8'd26: init_word=16'h5200;
                8'd27: init_word=16'h5C02;
                8'd28: init_word=16'h5D00;
                8'd29: init_word=16'h5E10;
                8'd30: init_word=16'h5F3F;
                8'd31: init_word=16'h6027;
                8'd32: init_word=16'h6128;
                8'd33: init_word=16'h6200;
                8'd34: init_word=16'h6303;
                8'd35: init_word=16'h64F7;
                8'd36: init_word=16'h6503;
                8'd37: init_word=16'h66D9;
                8'd38: init_word=16'h6703;
                8'd39: init_word=16'h6801;
                8'd40: init_word=16'h69C8;
                8'd41: init_word=16'h6A40;
                8'd42: init_word=16'h6D04;
                8'd43: init_word=16'h6E00;
                8'd44: init_word=16'h6F00;
                8'd45: init_word=16'h7080;
                8'd46: init_word=16'h7100;
                8'd47: init_word=16'h7200;
                8'd48: init_word=16'h7300;
                8'd49: init_word=16'h74F0;
                8'd50: init_word=16'h7500;
                8'd51: init_word=16'h8042;
                8'd52: init_word=16'h8144;
                8'd53: init_word=16'h8204;
                8'd54: init_word=16'h8320;
                8'd55: init_word=16'h8420;
                8'd56: init_word=16'h8500;
                8'd57: init_word=16'h8610;
                8'd58: init_word=16'h8700;
                8'd59: init_word=16'h8805;
                8'd60: init_word=16'h8918;
                8'd61: init_word=16'h8A10;
                8'd62: init_word=16'h8B01;
                8'd63: init_word=16'h8C37;
                8'd64: init_word=16'h8D00;
                8'd65: init_word=16'h8EF0;
                8'd66: init_word=16'h8F81;
                8'd67: init_word=16'h9006;
                8'd68: init_word=16'h9106;
                8'd69: init_word=16'h921E;
                8'd70: init_word=16'h930D;
                8'd71: init_word=16'h940A;
                8'd72: init_word=16'h950A;
                8'd73: init_word=16'h960C;
                8'd74: init_word=16'h9705;
                8'd75: init_word=16'h980A;
                8'd76: init_word=16'h9941;
                8'd77: init_word=16'h9A14;
                8'd78: init_word=16'h9B0A;
                8'd79: init_word=16'h9C3F;
                8'd80: init_word=16'h9D33;
                8'd81: init_word=16'h9EAE;
                8'd82: init_word=16'h9FF9;
                8'd83: init_word=16'hA048;
                8'd84: init_word=16'hA113;
                8'd85: init_word=16'hA210;
                8'd86: init_word=16'hA308;
                8'd87: init_word=16'hA430;
                8'd88: init_word=16'hA519;
                8'd89: init_word=16'hA610;
                8'd90: init_word=16'hA708;
                8'd91: init_word=16'hA824;
                8'd92: init_word=16'hA904;
                8'd93: init_word=16'hAA1E;
                8'd94: init_word=16'hAB1E;
                8'd95: init_word=16'hCC19;
                8'd96: init_word=16'hCD0B;
                8'd97: init_word=16'hCE13;
                8'd98: init_word=16'hCF64;
                8'd99: init_word=16'hD021;
                8'd100: init_word=16'hD10F;
                8'd101: init_word=16'hD288;
                8'd102: init_word=16'hE001;
                8'd103: init_word=16'hE104;
                8'd104: init_word=16'hE241;
                8'd105: init_word=16'hE3D6;
                8'd106: init_word=16'hE400;
                8'd107: init_word=16'hE50C;
                8'd108: init_word=16'hE60A;
                8'd109: init_word=16'hE700;
                8'd110: init_word=16'hE800;
                8'd111: init_word=16'hE900;
                8'd112: init_word=16'hEE07;
                8'd113: init_word=16'hEF01;
                8'd114: init_word=16'h001E;
                8'd115: init_word=16'h011E;
                8'd116: init_word=16'h020F;
                8'd117: init_word=16'h0310;
                8'd118: init_word=16'h0402;
                8'd119: init_word=16'h0500;
                8'd120: init_word=16'h06B0;
                8'd121: init_word=16'h0704;
                8'd122: init_word=16'h080D;
                8'd123: init_word=16'h090E;
                8'd124: init_word=16'h0A9C;
                8'd125: init_word=16'h0B04;
                8'd126: init_word=16'h0C05;
                8'd127: init_word=16'h0D0F;
                8'd128: init_word=16'h0E02;
                8'd129: init_word=16'h0F12;
                8'd130: init_word=16'h1002;
                8'd131: init_word=16'h1102;
                8'd132: init_word=16'h1200;
                8'd133: init_word=16'h1301;
                8'd134: init_word=16'h1405;
                8'd135: init_word=16'h1507;
                8'd136: init_word=16'h1605;
                8'd137: init_word=16'h1707;
                8'd138: init_word=16'h1801;
                8'd139: init_word=16'h1904;
                8'd140: init_word=16'h1A05;
                8'd141: init_word=16'h1B0C;
                8'd142: init_word=16'h1C2A;
                8'd143: init_word=16'h1D01;
                8'd144: init_word=16'h1E00;
                8'd145: init_word=16'h2100;
                8'd146: init_word=16'h2200;
                8'd147: init_word=16'h2300;
                8'd148: init_word=16'h2501;
                8'd149: init_word=16'h2600;
                8'd150: init_word=16'h2739;
                8'd151: init_word=16'h287F;
                8'd152: init_word=16'h2908;
                8'd153: init_word=16'h3003;
                8'd154: init_word=16'h3100;
                8'd155: init_word=16'h321A;
                8'd156: init_word=16'h331A;
                8'd157: init_word=16'h3407;
                8'd158: init_word=16'h3507;
                8'd159: init_word=16'h3601;
                8'd160: init_word=16'h37FF;
                8'd161: init_word=16'h3836;
                8'd162: init_word=16'h3907;
                8'd163: init_word=16'h3A00;
                8'd164: init_word=16'h3EFF;
                8'd165: init_word=16'h3F00;
                8'd166: init_word=16'h4077;
                8'd167: init_word=16'h4140;
                8'd168: init_word=16'h4200;
                8'd169: init_word=16'h4330;
                8'd170: init_word=16'h44A0;
                8'd171: init_word=16'h455C;
                8'd172: init_word=16'h4600;
                8'd173: init_word=16'h4700;
                8'd174: init_word=16'h4858;
                8'd175: init_word=16'h4A1E;
                8'd176: init_word=16'h4B1E;
                8'd177: init_word=16'h4C00;
                8'd178: init_word=16'h4D00;
                8'd179: init_word=16'h4EA0;
                8'd180: init_word=16'h4F80;
                8'd181: init_word=16'h5000;
                8'd182: init_word=16'h5100;
                8'd183: init_word=16'h5200;
                8'd184: init_word=16'h5300;
                8'd185: init_word=16'h5400;
                8'd186: init_word=16'h5780;
                8'd187: init_word=16'h5910;
                8'd188: init_word=16'h5A08;
                8'd189: init_word=16'h5B94;
                8'd190: init_word=16'h5CE8;
                8'd191: init_word=16'h5D08;
                8'd192: init_word=16'h5E3D;
                8'd193: init_word=16'h5F99;
                8'd194: init_word=16'h6045;
                8'd195: init_word=16'h6140;
                8'd196: init_word=16'h632D;
                8'd197: init_word=16'h6402;
                8'd198: init_word=16'h6596;
                8'd199: init_word=16'h6600;
                8'd200: init_word=16'h6797;
                8'd201: init_word=16'h6801;
                8'd202: init_word=16'h69CD;
                8'd203: init_word=16'h6A01;
                8'd204: init_word=16'h6BB0;
                8'd205: init_word=16'h6C04;
                8'd206: init_word=16'h6D2C;
                8'd207: init_word=16'h6E01;
                8'd208: init_word=16'h6F32;
                8'd209: init_word=16'h7100;
                8'd210: init_word=16'h7201;
                8'd211: init_word=16'h7335;
                8'd212: init_word=16'h7400;
                8'd213: init_word=16'h7533;
                8'd214: init_word=16'h7631;
                8'd215: init_word=16'h7701;
                8'd216: init_word=16'h7C84;
                8'd217: init_word=16'h7D03;
                8'd218: init_word=16'h7E01;

                default: init_word=16'hEF00;
            endcase
        end
    endfunction

    localparam [4:0] S_WAIT=0, S_BANK0=1, S_BANK0_WAIT=2,
                     S_ID0=3, S_ID0_WAIT=4, S_ID1=5, S_ID1_WAIT=6,
                     S_INIT=7, S_INIT_WAIT=8, S_MODE_BANK=9, S_MODE_BANK_WAIT=10,
                     S_MODE_RATE=11, S_MODE_RATE_WAIT=12, S_MODE_END=13,
                     S_MODE_END_WAIT=14, S_POLL=15, S_FLAG0_WAIT=16,
                     S_FLAG1=17, S_FLAG1_WAIT=18,S_WAKE=19,S_WAKE_WAIT=20,S_WAKE_DELAY=21,S_CFG41=22,S_CFG41_WAIT=23,S_CFG42=24,S_CFG42_WAIT=25;
    reg [4:0] state;
    reg [21:0] wait_count;
    reg [22:0] poll_count;
    reg [23:0] cooldown_count;
    reg [7:0] init_index;
    reg [7:0] id_low;
    reg [7:0] flag0;
    reg int_meta, int_sync;
    wire [15:0] current_init = init_word(init_index);

    task launch_write;
        input [7:0] addr;
        input [7:0] data;
        begin
            master_read  <= 1'b0;
            master_reg   <= addr;
            master_wdata <= data;
            master_start <= 1'b1;
        end
    endtask
    task launch_read;
        input [7:0] addr;
        begin
            master_read  <= 1'b1;
            master_reg   <= addr;
            master_wdata <= 8'd0;
            master_start <= 1'b1;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_WAIT;
            wait_count     <= 22'd0;
            poll_count     <= 20'd0;
            cooldown_count <= 24'd0;
            init_index     <= 8'd0;
            id_low         <= 8'd0;
            flag0          <= 8'd0;
            int_meta       <= 1'b1;
            int_sync       <= 1'b1;
            master_start   <= 1'b0;
            master_read    <= 1'b0;
            master_reg     <= 8'd0;
            master_wdata   <= 8'd0;
            sensor_ready   <= 1'b0;
            sensor_error   <= 1'b0;
            gesture_code   <= 4'd0;
            gesture_event  <= 1'b0;raw43<=0;raw44<=0;cfg41<=0;cfg42<=0;raw_valid<=0;cfg_valid<=0;
        end else begin
            master_start  <= 1'b0;
            gesture_event <= 1'b0;raw_valid<=0;cfg_valid<=0;
            int_meta      <= int_n;
            int_sync      <= int_meta;
            if (cooldown_count != 0)
                cooldown_count <= cooldown_count - 1'b1;
            case(state)
                S_WAIT: begin
                    sensor_ready<=0;
                    if (wait_count == WAIT_60MS-1) begin
                        wait_count <= 0; state <= S_WAKE;
                    end else wait_count <= wait_count + 1'b1;
                end
                S_WAKE: if(!master_busy) begin launch_write(8'hEF,8'h00);state<=S_WAKE_WAIT;end
                // 参考初始化时序连续两次选择BANK0，第二次用于完成传感器唤醒。
                S_WAKE_WAIT: if(master_done) begin wait_count<=0;state<=S_WAKE_DELAY;end
                S_WAKE_DELAY: if(wait_count==WAKE_700US-1) begin wait_count<=0;state<=S_BANK0;end
                              else wait_count<=wait_count+1'b1;
                S_BANK0: if (!master_busy) begin launch_write(8'hEF,8'h00); state<=S_BANK0_WAIT; end
                S_BANK0_WAIT: if (master_done) begin
                    if (master_ack_error) begin sensor_error<=1'b1; state<=S_WAIT; end
                    else state<=S_ID0;
                end
                S_ID0: if (!master_busy) begin launch_read(8'h00); state<=S_ID0_WAIT; end
                S_ID0_WAIT: if (master_done) begin
                    if(master_ack_error) begin sensor_ready<=0;sensor_error<=1;wait_count<=0;state<=S_WAIT;end
                    else begin id_low<=master_rdata;state<=S_ID1;end
                end
                S_ID1: if (!master_busy) begin launch_read(8'h01); state<=S_ID1_WAIT; end
                S_ID1_WAIT: if (master_done) begin
                    if (master_ack_error || id_low!=8'h20 || master_rdata!=8'h76) begin
                        sensor_error<=1'b1; wait_count<=0; state<=S_WAIT;
                    end else begin init_index<=0; state<=S_INIT; end
                end
                S_INIT: if (!master_busy) begin
                    launch_write(current_init[15:8],current_init[7:0]); state<=S_INIT_WAIT;
                end
                S_INIT_WAIT: if (master_done) begin
                    if (master_ack_error) begin sensor_error<=1'b1; wait_count<=0; state<=S_WAIT; end
                    // 完成219组寄存器初始化后保持普通手势模式。
                    else if (init_index==8'd218) state<=S_MODE_END;
                    else begin init_index<=init_index+1'b1; state<=S_INIT; end
                end
                S_MODE_BANK: if (!master_busy) begin launch_write(8'hEF,8'h01); state<=S_MODE_BANK_WAIT; end
                S_MODE_BANK_WAIT: if (master_done) begin
                    if (master_ack_error) begin
                        sensor_ready<=1'b0; sensor_error<=1'b1;
                        wait_count<=0; state<=S_WAIT;
                    end else state<=S_MODE_RATE;
                end
                S_MODE_RATE: if (!master_busy) begin launch_write(8'h65,8'h12); state<=S_MODE_RATE_WAIT; end
                S_MODE_RATE_WAIT: if (master_done) begin
                    if (master_ack_error) begin
                        sensor_ready<=1'b0; sensor_error<=1'b1;
                        wait_count<=0; state<=S_WAIT;
                    end else state<=S_MODE_END;
                end
                S_MODE_END: if (!master_busy) begin launch_write(8'hEF,8'h00); state<=S_MODE_END_WAIT; end
                S_MODE_END_WAIT: if (master_done) begin
                    sensor_ready<=0;
                    if(master_ack_error)begin sensor_error<=1;wait_count<=0;state<=S_WAIT;end
                    else state<=S_CFG41;
                end
                S_CFG41:if(!master_busy)begin launch_read(8'h41);state<=S_CFG41_WAIT;end
                S_CFG41_WAIT:if(master_done)begin
                  if(master_ack_error)begin sensor_error<=1;wait_count<=0;state<=S_WAIT;end
                  else begin cfg41<=master_rdata;state<=S_CFG42;end
                end
                S_CFG42:if(!master_busy)begin launch_read(8'h42);state<=S_CFG42_WAIT;end
                S_CFG42_WAIT:if(master_done)begin
                  cfg42<=master_rdata;cfg_valid<=1;poll_count<=0;
                  if(master_ack_error||cfg41!=8'hff||master_rdata!=8'h01)begin sensor_error<=1;wait_count<=0;state<=S_WAIT;end
                  else begin sensor_ready<=1;sensor_error<=0;state<=S_POLL;end
                end
                S_POLL: begin
                    if (!sensor_ready) begin wait_count<=0; state<=S_WAIT; end
                    else if (!int_sync || poll_count==POLL_20MS-1) begin
                        poll_count<=0;
                        if (!master_busy) begin launch_read(8'h43); state<=S_FLAG0_WAIT; end
                    end else poll_count<=poll_count+1'b1;
                end
                S_FLAG0_WAIT: if (master_done) begin
                    if (master_ack_error) begin sensor_ready<=1'b0; sensor_error<=1'b1; wait_count<=0; state<=S_WAIT; end
                    else begin flag0<=master_rdata; state<=S_FLAG1; end
                end
                S_FLAG1: if (!master_busy) begin launch_read(8'h44); state<=S_FLAG1_WAIT; end
                S_FLAG1_WAIT: if (master_done) begin
                    if(!master_ack_error)begin raw43<=flag0;raw44<=master_rdata;raw_valid<=1;end
                    if (!master_ack_error && cooldown_count==0) begin
                        // 忽略靠近/远离等附带位；仅一个目标动作位才接受。
                        // 左+右或方向+旋转等多个目标位仍拒绝，不能任意猜方向。
                        case(flag0 & 8'hCF)
                          8'h01:gesture_code<=4; // 传感器标准左挥
                          8'h02:gesture_code<=3; // 传感器标准右挥
                          8'h04:gesture_code<=1; // 传感器标准上挥
                          8'h08:gesture_code<=2; // 传感器标准下挥
                          8'h10:gesture_code<=5; // 由 8'hCF 掩码清零，不会进入该分支
                          8'h20:gesture_code<=6; // 由 8'hCF 掩码清零，不会进入该分支
                          8'h40:gesture_code<=7;
                          8'h80:gesture_code<=8;
                          8'h00:if(master_rdata[0])gesture_code<=9; // 0x44挥手标志单独映射
                          default:gesture_code<=10; // 多方向位同时出现时不推断方向
                        endcase
                        if (((flag0 & 8'hCF)!=0) || master_rdata[0]) begin
                            gesture_event<=1'b1; cooldown_count<=COOLDOWN_300MS;
                        end
                    end
                    if(master_ack_error) begin sensor_ready<=0;sensor_error<=1;wait_count<=0;state<=S_WAIT;end
                    else state<=S_POLL;
                end
                default: state<=S_WAIT;
            endcase
        end
    end
endmodule

