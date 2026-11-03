`timescale 1ns/1ps
// 告警相对强弱指示图标：峰值越高颜色越深，峰值越低颜色越淡。
// 本模块不计算声源方向或距离，图标位置只用于把四档相对强弱直观分开。
// 坐标和颜色在音频告警上升沿锁存，告警期间保持稳定；渲染只使用减法和比较。
// 图形采用曼哈顿距离近似圆形，并叠加白色感叹号，减少乘法和开方资源。
module mm_alarm_locator(
    input wire [10:0] x, input wire [9:0] y,
    input wire alarm_active, input wire audio_alarm,
    input wire [7:0] peak, input wire [1:0] zoom_v,
    input wire clk, rst,
    output wire hit, output wire [23:0] color
);
    wire [7:0] inv = 8'd255 - peak;
    wire [7:0] d = 8'd20 + {1'b0, inv[7:1]};
    reg [7:0] latched_peak;
    reg [10:0] cxl, cyl;
    reg [23:0] latched_color;
    reg prev_audio;
    always @(posedge clk or posedge rst) begin
        if(rst) begin latched_peak<=8'd0; prev_audio<=1'b0; cxl<=11'd0; cyl<=11'd0; latched_color<=24'hff1414; end
        else begin
            prev_audio<=audio_alarm;
            if(audio_alarm && !prev_audio) begin
                latched_peak<=peak;
                cxl <= 11'd320 + {3'b0, d};
                cyl <= 11'd240 - {3'b0, d};
                case(peak[7:6])
                    2'd3: latched_color<=24'hff1414;
                    2'd2: latched_color<=24'hff5050;
                    2'd1: latched_color<=24'hff9090;
                    default: latched_color<=24'hffc0c0;
                endcase
            end else if(!alarm_active) begin
                latched_peak<=8'd0; cxl<=11'd0; cyl<=11'd0;
            end
        end
    end

    // 半径实时随 zoom 缩放：10/14/18/22
    wire [7:0] r = 8'd10 + {6'b0, zoom_v, 2'b00};

    // 曼哈顿距离（菱形近似圆），cx/cy 为寄存器，路径浅
    wire [11:0] dx_raw = {1'b0, x} - {1'b0, cxl};
    wire [11:0] dx_abs = dx_raw[11] ? (~dx_raw + 12'd1) : dx_raw;
    wire [10:0] dy_raw = {1'b0, y} - {1'b0, cyl};
    wire [10:0] dy_abs = dy_raw[10] ? (~dy_raw + 11'd1) : dy_raw;
    wire [11:0] manhattan = {1'b0, dx_abs} + {1'b0, dy_abs};

    wire in_head = (manhattan <= {4'b0, r});
    // 中心白色感叹号：竖线 + 圆点
    wire [10:0] r1_4 = r >> 2;
    wire [10:0] r1_2 = r >> 1;
    wire [10:0] r2_3 = r - r1_4;
    wire ex_bar = (dx_abs <= 12'd1) && (y >= (cyl - {3'b0, r2_3})) && (y <= (cyl + {3'b0, r1_4}));
    wire ex_dot = (dx_abs <= 12'd1) && (y >= (cyl + {3'b0, r1_2})) && (y <= (cyl + {3'b0, r2_3}));

    wire exclaim = ex_bar || ex_dot;
    assign hit = audio_alarm && (in_head || exclaim);
    assign color = exclaim ? 24'hffffff : latched_color;
endmodule
