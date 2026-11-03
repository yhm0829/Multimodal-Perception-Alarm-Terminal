`timescale 1ns/1ps

// Small open-drain I2C register master.
// One command transfers either REG+DATA (write) or REG followed by one byte
// (read). Extra high-phase sampling gives <=100 kHz at CLK_HZ=50 MHz.
// Clock stretching is respected, with a bounded 10ms transaction watchdog.
module mm_i2c_reg_master #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer I2C_HZ = 100_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       read_not_write,
    input  wire [6:0] dev_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] write_data,
    output reg  [7:0] read_data,
    output reg        busy,
    output reg        done,
    output reg        ack_error,
    inout  wire       scl,
    inout  wire       sda
);
    localparam integer HALF_DIV = CLK_HZ/(I2C_HZ*2);

    localparam integer DIV_W=(HALF_DIV>1)?$clog2(HALF_DIV):1;
    localparam integer WATCHDOG_W=(CLK_HZ/100>0)?$clog2(CLK_HZ/100+2):1;
    reg [DIV_W-1:0] div_cnt;
    wire tick = (div_cnt == HALF_DIV-1);
    always @(posedge clk or posedge rst) begin
        if (rst || !busy)
            div_cnt <= 0;
        else if (tick)
            div_cnt <= 0;
        else
            div_cnt <= div_cnt + 1'b1;
    end

    reg scl_low, sda_low;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    (* async_reg="true" *) reg sda_meta,sda_sync,scl_meta,scl_sync;
    reg [WATCHDOG_W-1:0] watchdog;
    wire sda_in=sda_sync;
    always @(posedge clk or posedge rst) begin
        if(rst) begin sda_meta<=1;sda_sync<=1;scl_meta<=1;scl_sync<=1;end
        else begin sda_meta<=sda;sda_sync<=sda_meta;scl_meta<=scl;scl_sync<=scl_meta;end
    end

    localparam [4:0] ST_IDLE       = 5'd0,
                     ST_START_A    = 5'd1,
                     ST_START_B    = 5'd2,
                     ST_START_C    = 5'd3,
                     ST_SEND_LOW   = 5'd4,
                     ST_SEND_HIGH  = 5'd5,
                     ST_ACK_LOW    = 5'd6,
                     ST_ACK_HIGH   = 5'd7,
                     ST_RSTART_A   = 5'd8,
                     ST_RSTART_B   = 5'd9,
                     ST_RSTART_C   = 5'd10,
                     ST_RSTART_D   = 5'd11,
                     ST_READ_LOW   = 5'd12,
                     ST_READ_HIGH  = 5'd13,
                     ST_NACK_LOW   = 5'd14,
                     ST_NACK_HIGH  = 5'd15,
                     ST_STOP_A     = 5'd16,
                     ST_STOP_B     = 5'd17,
                     ST_STOP_C     = 5'd18,
                     ST_SEND_HOLD=5'd19,ST_ACK_SAMPLE=5'd20,ST_READ_SAMPLE=5'd21, ST_FALL=5'd22, ST_NACK_HOLD=5'd23,
                     ST_CLEAR_LOW=5'd24,ST_CLEAR_HIGH=5'd25,ST_CLEAR_HOLD=5'd26;

    localparam [2:0] BYTE_DEV_W = 3'd0,
                     BYTE_REG   = 3'd1,
                     BYTE_DATA  = 3'd2,
                     BYTE_DEV_R = 3'd3;

    reg [4:0] state, after_fall;
    reg [3:0] clear_count;
    reg clearing;
    reg stop_to_read;
    reg [2:0] byte_stage;
    reg [2:0] bit_index;
    reg [7:0] tx_byte;
    reg       command_read;
    reg [6:0] dev_latched;
    reg [7:0] reg_latched, data_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stop_to_read<=0;watchdog<=0;after_fall<=ST_IDLE;clear_count<=0;clearing<=0;
            state        <= ST_IDLE;
            byte_stage   <= BYTE_DEV_W;
            bit_index    <= 3'd7;
            tx_byte      <= 8'd0;
            read_data    <= 8'd0;
            busy         <= 1'b0;
            done         <= 1'b0;
            ack_error    <= 1'b0;
            scl_low      <= 1'b0;
            sda_low      <= 1'b0;
            command_read <= 1'b0;
            dev_latched  <= 7'd0;
            reg_latched  <= 8'd0;
            data_latched <= 8'd0;
        end else begin
            done <= 1'b0;
            if(!busy) watchdog<=0;else watchdog<=watchdog+1'b1;
            if (!busy) begin
                scl_low <= 1'b0;
                sda_low <= 1'b0;
                state   <= ST_IDLE;
                if (start) begin
                    busy         <= 1'b1;
                    ack_error    <= 1'b0;
                    command_read <= read_not_write;
                    dev_latched  <= dev_addr;
                    reg_latched  <= reg_addr;
                    data_latched <= write_data;
                    byte_stage   <= BYTE_DEV_W;
                    tx_byte      <= {dev_addr,1'b0};
                    bit_index    <= 3'd7;
                    clear_count<=0;clearing<=!sda_sync;
                    state <= sda_sync?ST_START_A:ST_CLEAR_LOW;
                end
            end else if(watchdog>=CLK_HZ/100) begin
                // Abort a stuck clock/bus transaction after 10ms; controller retries.
                busy<=0;done<=1;ack_error<=1;scl_low<=0;sda_low<=0;stop_to_read<=0;state<=ST_IDLE;
            end else if (tick) begin
                case (state)
                    ST_START_A: begin scl_low<=1'b0; sda_low<=1'b0; state<=ST_START_B; end
                    ST_START_B: if(scl_sync && sda_sync) begin scl_low<=1'b0; sda_low<=1'b1; state<=ST_START_C; end
                    ST_START_C: begin scl_low<=1'b1; sda_low<=1'b1; state<=ST_SEND_LOW; end

                    ST_SEND_LOW: begin
                        scl_low <= 1'b1;
                        sda_low <= ~tx_byte[bit_index];
                        state   <= ST_SEND_HIGH;
                    end
                    ST_SEND_HIGH: begin scl_low<=0;state<=ST_SEND_HOLD;end
                    ST_SEND_HOLD: if(scl_sync) begin
                        state<=ST_FALL;
                        if(bit_index==0) after_fall<=ST_ACK_LOW;
                        else begin bit_index<=bit_index-1'b1;after_fall<=ST_SEND_LOW;end
                    end
                    ST_FALL: begin scl_low<=1;state<=after_fall;end
                    ST_CLEAR_LOW: begin scl_low<=1;sda_low<=0;state<=ST_CLEAR_HIGH;end
                    ST_CLEAR_HIGH: begin scl_low<=0;state<=ST_CLEAR_HOLD;end
                    ST_CLEAR_HOLD: if(scl_sync) begin
                        if(clear_count==8) begin state<=ST_FALL;after_fall<=ST_STOP_A;end
                        else begin clear_count<=clear_count+1'b1;state<=ST_CLEAR_LOW;end
                    end
                    ST_ACK_LOW: begin
                        scl_low <= 1'b1;
                        sda_low <= 1'b0;
                        state   <= ST_ACK_HIGH;
                    end
                    ST_ACK_HIGH: begin scl_low<=0;state<=ST_ACK_SAMPLE;end
                    ST_ACK_SAMPLE: if(scl_sync) begin
                        state<=ST_FALL;
                        if (sda_in)
                            ack_error <= 1'b1;
                        case (byte_stage)
                            BYTE_DEV_W: begin
                                byte_stage <= BYTE_REG;
                                tx_byte    <= reg_latched;
                                bit_index  <= 3'd7;
                                after_fall <= ST_SEND_LOW;
                            end
                            BYTE_REG: begin
                                bit_index <= 3'd7;
                                if (command_read) begin
                                    after_fall <= ST_STOP_A;stop_to_read<=1;
                                end else begin
                                    byte_stage <= BYTE_DATA;
                                    tx_byte    <= data_latched;
                                    after_fall <= ST_SEND_LOW;
                                end
                            end
                            BYTE_DATA: after_fall <= ST_STOP_A;
                            default: begin
                                bit_index <= 3'd7;
                                read_data <= 8'd0;
                                after_fall <= ST_READ_LOW;
                            end
                        endcase
                    end

                    ST_RSTART_A: begin scl_low<=1'b1; sda_low<=1'b0; state<=ST_RSTART_B; end
                    ST_RSTART_B: begin scl_low<=1'b0; sda_low<=1'b0; state<=ST_RSTART_C; end
                    ST_RSTART_C: if(scl_sync) begin scl_low<=1'b0; sda_low<=1'b1; state<=ST_RSTART_D; end
                    ST_RSTART_D: begin
                        scl_low    <= 1'b1;
                        sda_low    <= 1'b1;
                        byte_stage <= BYTE_DEV_R;
                        tx_byte    <= {dev_latched,1'b1};
                        bit_index  <= 3'd7;
                        state      <= ST_SEND_LOW;
                    end

                    ST_READ_LOW: begin
                        scl_low <= 1'b1;
                        sda_low <= 1'b0;
                        state   <= ST_READ_HIGH;
                    end
                    ST_READ_HIGH: begin scl_low<=0;state<=ST_READ_SAMPLE;end
                    ST_READ_SAMPLE: if(scl_sync) begin
                        read_data[bit_index]<=sda_in;state<=ST_FALL;
                        if(bit_index==0) after_fall<=ST_NACK_LOW;
                        else begin bit_index<=bit_index-1'b1;after_fall<=ST_READ_LOW;end
                    end
                    ST_NACK_LOW: begin scl_low<=1;sda_low<=0;state<=ST_NACK_HIGH;end
                    ST_NACK_HIGH: begin scl_low<=0;state<=ST_NACK_HOLD;end
                    ST_NACK_HOLD: if(scl_sync) begin state<=ST_FALL;after_fall<=ST_STOP_A;end
                    ST_STOP_A: begin scl_low<=1'b1; sda_low<=1'b1; state<=ST_STOP_B; end
                    ST_STOP_B: begin scl_low<=1'b0; sda_low<=1'b1; state<=ST_STOP_C; end
                    ST_STOP_C: if(scl_sync) begin
                        scl_low <= 1'b0;
                        sda_low <= 1'b0;
                        if(clearing) begin clearing<=0;state<=ST_START_A;end
                        else if(stop_to_read)begin
                          stop_to_read<=0;byte_stage<=BYTE_DEV_R;tx_byte<={dev_latched,1'b1};bit_index<=7;state<=ST_START_A;
                        end
                        else begin busy<=0;done<=1;state<=ST_IDLE;end
                    end
                    default: begin busy<=1'b0; scl_low<=1'b0; sda_low<=1'b0; state<=ST_IDLE; end
                endcase
            end
        end
    end
endmodule
