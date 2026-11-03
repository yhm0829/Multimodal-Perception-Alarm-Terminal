`timescale 1ns/1ps
// Isolated pixel-address adapter for the controller's sequential BL4 contract.
// 100% bypass has no additional registers in data/valid or request paths.
// Scaled requests fetch aligned sixteen-word groups, then select/repeat pixels
// from a sixteen-word cache. Writes remain on the original application path.
module mm_sdram_pixel_fetch #(
    parameter ADDR_BITS = 21,
    parameter DATA_BITS = 32
) (
    input wire clk,
    input wire rst,
    input wire resample_enable,
    input wire invalidate,
    input wire logical_read,
    input wire [ADDR_BITS-1:0] logical_address,
    input wire write_accept,
    input wire [ADDR_BITS-1:0] write_address,
    input wire memory_busy,
    input wire memory_valid,
    input wire [DATA_BITS-1:0] memory_data,
    output wire busy,
    output wire memory_read,
    output wire [ADDR_BITS-1:0] memory_address,
    output wire logical_valid,
    output wire [DATA_BITS-1:0] logical_data
);
    localparam IDLE=2'd0, ISSUE=2'd1, RECEIVE=2'd2;
    reg [1:0] state;
    reg [3:0] issue_index, receive_index, requested_lane;
    reg [ADDR_BITS-5:0] cache_tag;
    reg cache_valid;
    reg [DATA_BITS-1:0] cache_words [0:15];
    reg pixel_valid;
    reg [DATA_BITS-1:0] pixel_data;
    wire write_conflict = write_accept && (write_address[ADDR_BITS-1:4]==cache_tag);
    wire cache_hit = cache_valid && (logical_address[ADDR_BITS-1:4]==cache_tag);

    assign busy = memory_busy || (resample_enable && state!=IDLE);
    assign memory_read = resample_enable ? (state==ISSUE && !memory_busy) : logical_read;
    assign memory_address = resample_enable ? {cache_tag,issue_index} : logical_address;
    assign logical_valid = resample_enable ? pixel_valid : memory_valid;
    assign logical_data = resample_enable ? pixel_data : memory_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            issue_index <= 0;
            receive_index <= 0;
            requested_lane <= 0;
            cache_tag <= 0;
            cache_valid <= 0;
            pixel_valid <= 0;
            pixel_data <= 0;
        end else begin
            pixel_valid <= 0;
            if (invalidate || write_conflict || !resample_enable)
                cache_valid <= 0;
            if (resample_enable) begin
                case (state)
                    IDLE: if (logical_read && !memory_busy) begin
                        if (cache_hit && !invalidate && !write_conflict) begin
                            pixel_data <= cache_words[logical_address[3:0]];
                            pixel_valid <= 1;
                        end else begin
                            cache_tag <= logical_address[ADDR_BITS-1:4];
                            requested_lane <= logical_address[3:0];
                            issue_index <= 0;
                            receive_index <= 0;
                            cache_valid <= 0;
                            state <= ISSUE;
                        end
                    end
                    ISSUE: if (memory_read) begin
                        if (issue_index==15)
                            state <= RECEIVE;
                        else
                            issue_index <= issue_index+1'b1;
                    end
                    RECEIVE: begin end
                    default: state <= IDLE;
                endcase
                if (state!=IDLE && memory_valid) begin
                    cache_words[receive_index] <= memory_data;
                    if (receive_index==15) begin
                        // The last lane is not yet in cache_words before NBA.
                        pixel_data <= (requested_lane==15) ? memory_data : cache_words[requested_lane];
                        pixel_valid <= 1;
                        cache_valid <= 1;
                        state <= IDLE;
                    end else
                        receive_index <= receive_index+1'b1;
                end
            end
        end
    end
endmodule
