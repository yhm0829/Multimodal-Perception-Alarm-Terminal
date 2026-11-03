`timescale 1ns/1ps

// 50 MHz / 115200 8-N-1 UART receiver.
// The input is synchronized before edge detection and the start bit is
// sampled at its centre, so the module is safe to use from the board clock.
module mm_uart_rx #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer BAUD_HZ = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_pin,
    output reg [7:0]  data,
    output reg        valid
);
    localparam integer BIT_CYCLES  = CLK_HZ / BAUD_HZ;
    localparam integer HALF_CYCLES = BIT_CYCLES / 2;

    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_DATA  = 2'd2;
    localparam [1:0] S_STOP  = 2'd3;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [15:0] baud_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta  <= 1'b1;
            rx_sync  <= 1'b1;
            state    <= S_IDLE;
            baud_cnt <= 16'd0;
            bit_cnt  <= 3'd0;
            shift_reg<= 8'd0;
            data     <= 8'd0;
            valid    <= 1'b0;
        end else begin
            rx_meta <= rx_pin;
            rx_sync <= rx_meta;
            valid   <= 1'b0;

            case (state)
                S_IDLE: begin
                    baud_cnt <= 16'd0;
                    bit_cnt  <= 3'd0;
                    if (!rx_sync) begin
                        state    <= S_START;
                        baud_cnt <= HALF_CYCLES[15:0];
                    end
                end

                S_START: begin
                    if (baud_cnt == 16'd0) begin
                        if (!rx_sync) begin
                            state    <= S_DATA;
                            bit_cnt  <= 3'd0;
                            baud_cnt <= BIT_CYCLES - 1;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                S_DATA: begin
                    if (baud_cnt == 16'd0) begin
                        shift_reg[bit_cnt] <= rx_sync;
                        baud_cnt <= BIT_CYCLES - 1;
                        if (bit_cnt == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                S_STOP: begin
                    if (baud_cnt == 16'd0) begin
                        if (rx_sync) begin
                            data  <= shift_reg;
                            valid <= 1'b1;
                        end
                        state <= S_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
