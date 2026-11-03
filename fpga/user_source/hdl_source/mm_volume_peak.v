`timescale 1ns/1ps
// 音量峰值跟踪：峰值保持并慢衰减，时间常数约1.3秒。
// 瞬态事件可能只占一个FFT帧，直接显示当前值会漏掉峰值，因此先保持再按比例回落。
// freeze在告警期间冻结峰值；告警后音频通路会混入提示音，继续跟踪会污染相对强弱分级。
module mm_volume_peak(
    input wire clk, rst, frame_valid, freeze,
    input wire [7:0] volume,
    output reg [7:0] peak
);
always @(posedge clk or posedge rst) begin
    if(rst) peak <= 8'd0;
    else if(frame_valid && !freeze) begin
        if(volume > peak) peak <= volume;
        // 慢衰减：至少减1，步长 peak>>6（255 约64帧≈1.3秒）
        else if(peak != 0) peak <= peak - ((peak >> 6) + 8'd1);
    end
end
endmodule
