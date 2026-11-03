`timescale 1ns/1ps

// 有 I2S 输入时选择真实 FFT 频谱；无外部音频时钟/数据时输出一段动画频谱，
// 使显示、峰值保持与火花渲染在没有外部音频接入时也能正常工作。
module mm_audio_display_source #(
    parameter integer NO_AUDIO_CLOCKS = 5000000
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         vs,
    input  wire         audio_valid,
    input  wire [255:0] fft_bars,
    input  wire [7:0]   fft_volume,
    output wire [255:0] display_bars,
    output wire [7:0]   display_volume,
    output wire         demo_active
);
    reg vs_d;
    wire frame_tick = vs_d && !vs;
    reg [22:0] no_audio_count;
    reg audio_present;
    reg [7:0] demo_phase;
    reg [15:0] lfsr;
    reg [255:0] demo_bars;
    reg [7:0] demo_volume;
    integer i;

    function [7:0] demo_level;
        input [4:0] band;
        input [7:0] phase;
        input [15:0] noise;
        reg [5:0] p;
        reg [5:0] triangle_v;
        reg [7:0] value;
        begin
            p = phase[5:0] + {band,1'b0} + band;
            triangle_v = p[5] ? (6'd63-p) : p;
            value = 8'd7 + triangle_v + {5'd0,(noise[2:0]^band[2:0])};
            if ((phase[3:0] < 4'd3) && (band < 5'd13))
                value = value + 8'd27 - {3'd0,band};
            if (band > 5'd21)
                value = value - {3'd0,band[4:1]};
            demo_level = (value > 8'd63) ? 8'd63 : value;
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_d <= 1'b0;
            no_audio_count <= 0;
            audio_present <= 1'b0;
            demo_phase <= 0;
            lfsr <= 16'h1ace;
            demo_bars <= 0;
            demo_volume <= 0;
        end else begin
            vs_d <= vs;
            if (audio_valid) begin
                no_audio_count <= 0;
                audio_present <= 1'b1;
            end else if (no_audio_count < NO_AUDIO_CLOCKS) begin
                no_audio_count <= no_audio_count + 1'b1;
            end else begin
                audio_present <= 1'b0;
            end

            if (frame_tick) begin
                demo_phase <= demo_phase + 1'b1;
                lfsr <= {lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
                for (i=0;i<32;i=i+1)
                    demo_bars[i*8 +: 8] <= demo_level(i[4:0],demo_phase,lfsr);
                demo_volume <= 8'd72 + {2'd0,demo_phase[5:0]} +
                               ((demo_phase[3:0]<4'd3) ? 8'd72 : 8'd0);
            end
        end
    end

    assign demo_active = !audio_present;
    assign display_bars = audio_present ? fft_bars : demo_bars;
    assign display_volume = audio_present ? fft_volume : demo_volume;
endmodule
