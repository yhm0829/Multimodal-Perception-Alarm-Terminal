module bmp_read #(
    parameter integer CLK_FREQ_HZ   = 100_000_000,
    parameter integer LOAD_TIMEOUT_MS = 100   // 单扇区读取/写请求超时
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,
    output reg                  font_found_valid,
    output reg [31:0]           font_found_sector,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    output reg                  load_fail,          // 加载失败（BMP 头不匹配等）脉冲，供上层解除 load_busy

    // One-glyph lookup in the contiguous GBK16V1 font file.
    input                       font_start,
    input  [31:0]               font_base_sector,
    input  [15:0]               font_gbk_code,
    input  [4:0]                font_slot,
    output reg                  font_row_we,
    output reg [8:0]            font_row_addr,
    output reg [15:0]           font_row_data,
    output reg                  font_done,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    // Sector-level back-pressure from the SDRAM write FIFO.  The active
    // sector completes normally; the next sector waits, preserving RGB byte
    // and pixel alignment.
    input                       pause_i,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam [3:0] ST_IDLE        = 4'd0;
localparam [3:0] ST_SCAN        = 4'd1;
localparam [3:0] ST_LOAD_HDR    = 4'd2;
localparam [3:0] ST_LOAD_WAIT   = 4'd3;
localparam [3:0] ST_LOAD_DATA   = 4'd4;
localparam [3:0] ST_FONT        = 4'd5;
localparam [3:0] ST_FONT_INDEX  = 4'd6;
localparam [3:0] ST_FONT_RECORD = 4'd7;
localparam [3:0] ST_FONT_ADDR   = 4'd8;
localparam [3:0] ST_SCAN_SIZE   = 4'd9;
localparam [3:0] ST_SCAN_ADVANCE= 4'd10;
localparam [3:0] ST_FONT_CHECK  = 4'd11;
localparam [31:0] FONT_FILE_SECTORS = 32'd1504;
localparam [31:0] TIMEOUT_TICKS = (CLK_FREQ_HZ / 1000) * LOAD_TIMEOUT_MS;

reg [3:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [7:0]  header_2, header_3, header_4, header_5, header_6, header_7;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] scan_sector;
reg [31:0] scan_sector_count_latched;
reg [31:0] scan_next_latched;
reg        scan_target_reached_latched;
reg [31:0] timeout_cnt;      // 单扇区读取/写握手超时计数
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg [8:0]  font_byte_offset;
reg [7:0]  font_first_byte;
reg [4:0]  font_slot_latched;
reg [15:0] font_code_latched;
reg [31:0] font_base_sector_latched;
reg        font_ascii_latched;
reg [14:0] font_lead_scaled;
reg [7:0]  font_trail_index_latched;
reg [20:0] font_record_byte_latched;

wire header_match;
wire font_header_match;

// Register the header qualifiers so their wide comparisons cannot become
// part of the sector-address clock-enable cone.  They are consumed only when
// a sector finishes, so the extra SD-clock cycle does not alter the protocol.
reg header_match_r;
reg font_header_match_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_match_r      <= 1'b0;
        font_header_match_r <= 1'b0;
    end else begin
        header_match_r      <= header_match;
        font_header_match_r <= font_header_match;
    end
end
wire [9:0] font_relative_byte = rd_cnt - {1'b0,font_byte_offset};
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_miss;

// Pipeline the byte-valid comparison and byte together.  This removes the
// file_len/pixel_offset comparator from the address-control fan-in while
// preserving byte alignment exactly.
reg bmp_data_valid_r;
reg [7:0] sd_sec_read_data_r;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_valid_r   <= 1'b0;
        sd_sec_read_data_r <= 8'd0;
    end else begin
        bmp_data_valid_r   <= bmp_data_valid;
        sd_sec_read_data_r <= sd_sec_read_data;
    end
end

assign ready = (state == ST_IDLE);
assign header_match = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (width[15:0]  == bmp_width) &&
                      (height[15:0] == bmp_height) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0);
assign font_header_match = (header_0=="G") && (header_1=="B") &&
                           (header_2=="K") && (header_3=="1") &&
                           (header_4=="6") && (header_5=="V") &&
                           (header_6=="1") && (header_7=="!");
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

// SD接口时序修复：只缓存结束判断，不改像素字节/valid流水线。
// 原SD命令控制器在512个数据字节之后读完两个CRC字节，才发出
// sd_sec_read_end。因此此标志在扇区结束时已稳定，等价于原比较。
// 接口回归逐拍验证该前提；不把任意同拍data_valid/end源当作合法SD源。
reg file_complete_r;
always @(posedge clk or posedge rst) begin
    if (rst) file_complete_r <= 1'b0;
    else file_complete_r <= (bmp_len_cnt >= file_len);
end


always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR) || (state == ST_FONT)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        header_2     <= 8'd0; header_3 <= 8'd0; header_4 <= 8'd0;
        header_5     <= 8'd0; header_6 <= 8'd0; header_7 <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;
            10'd2 : begin header_2 <= sd_sec_read_data; file_len[7:0] <= sd_sec_read_data; end
            10'd3 : begin header_3 <= sd_sec_read_data; file_len[15:8] <= sd_sec_read_data; end
            10'd4 : begin header_4 <= sd_sec_read_data; file_len[23:16] <= sd_sec_read_data; end
            10'd5 : begin header_5 <= sd_sec_read_data; file_len[31:24] <= sd_sec_read_data; end
            10'd6 : header_6 <= sd_sec_read_data;
            10'd7 : header_7 <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid_r)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid_r) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data_r;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data_r;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data_r;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        font_found_valid  <= 1'b0;
        font_found_sector <= 32'd0;
        scan_sector       <= 32'd0;
        scan_sector_count_latched <= 32'd1;
        scan_next_latched <= 32'd0;
        scan_target_reached_latched <= 1'b0;
        load_sector_latched <= 32'd0;
        load_fail         <= 1'b0;
        font_row_we       <= 1'b0;
        font_row_addr     <= 9'd0;
        font_row_data     <= 16'd0;
        font_done         <= 1'b0;
        font_byte_offset  <= 9'd0;
        font_first_byte   <= 8'd0;
        font_slot_latched <= 5'd0;
        font_code_latched <= 16'd0;
        font_base_sector_latched <= 32'd0;
        font_ascii_latched <= 1'b0;
        font_lead_scaled <= 15'd0;
        font_trail_index_latched <= 8'd0;
        font_record_byte_latched <= 21'd0;
        timeout_cnt       <= 32'd0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        font_found_valid  <= 1'b0;
        font_found_sector <= 32'd0;
        scan_sector       <= 32'd0;
        scan_sector_count_latched <= 32'd1;
        scan_next_latched <= 32'd0;
        scan_target_reached_latched <= 1'b0;
        load_sector_latched <= 32'd0;
        load_fail         <= 1'b0;
        font_row_we       <= 1'b0;
        font_done         <= 1'b0;
        timeout_cnt       <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;
        font_found_valid <= 1'b0;
        load_fail        <= 1'b0;   // 默认清除；仅在头部校验失败时置位一拍
        font_row_we      <= 1'b0;
        font_done        <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end else if (font_start) begin
                    // GBK字节地址分多拍计算。乘法、加法和扇区地址若同拍完成，
                    // 会形成SD时钟域长组合路径；增加准备状态不改变读取字节和字幕内容。
                    font_code_latched        <= font_gbk_code;
                    font_base_sector_latched <= font_base_sector;
                    font_slot_latched        <= font_slot;
                    state                    <= ST_FONT_CHECK;
                end
            end

            ST_FONT_CHECK: begin
                // 单独一拍校验已锁存编码，使范围比较器不进入字模请求的时钟使能路径。
                // 接受的ASCII/GBK编码范围保持不变。
                if (((font_code_latched[15:8] == 8'h00) &&
                     (font_code_latched[7:0] >= 8'h20) &&
                     (font_code_latched[7:0] <= 8'h7e)) ||
                    ((font_code_latched[15:8] >= 8'h81) &&
                     (font_code_latched[15:8] <= 8'hfe) &&
                     (font_code_latched[7:0] >= 8'h40) &&
                     (font_code_latched[7:0] <= 8'hfe) &&
                     (font_code_latched[7:0] != 8'h7f)))
                    state <= ST_FONT_INDEX;
                else
                    state <= ST_IDLE;
            end

            ST_FONT_INDEX: begin
                font_ascii_latched <= (font_code_latched[15:8] == 8'h00);
                if (font_code_latched[15:8] == 8'h00) begin
                    font_lead_scaled         <= 15'd0;
                    font_trail_index_latched <= 8'd0;
                end else begin
                    // x*190 = x*128 + x*64 - x*2; shifts use no DSP.
                    font_lead_scaled <=
                        ({7'd0,(font_code_latched[15:8]-8'h81)} << 7) +
                        ({7'd0,(font_code_latched[15:8]-8'h81)} << 6) -
                        ({7'd0,(font_code_latched[15:8]-8'h81)} << 1);
                    font_trail_index_latched <= (font_code_latched[7:0] < 8'h7f) ?
                                                (font_code_latched[7:0] - 8'h40) :
                                                (font_code_latched[7:0] - 8'h41);
                end
                state <= ST_FONT_RECORD;
            end

            ST_FONT_RECORD: begin
                if (font_ascii_latched)
                    font_record_byte_latched <=
                        21'd512 + ((font_code_latched[7:0] - 8'h20) << 5);
                else
                    font_record_byte_latched <=
                        21'd3552 + ((font_lead_scaled + font_trail_index_latched) << 5);
                state <= ST_FONT_ADDR;
            end

            ST_FONT_ADDR: begin
                sd_sec_read_addr <= font_base_sector_latched +
                                    (font_record_byte_latched >> 9);
                font_byte_offset <= font_record_byte_latched[8:0];
                state            <= ST_FONT;
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;

                    if (font_header_match_r) begin
                        font_found_valid  <= 1'b1;
                        font_found_sector <= scan_sector;
                        sd_sec_read_addr  <= scan_sector + FONT_FILE_SECTORS;
                        scan_sector       <= scan_sector + FONT_FILE_SECTORS;
                    end else if (header_match_r) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;
                        // Split size rounding, sector addition and the range
                        // comparison across registers.  Scanning gains only
                        // two SD-clock cycles per discovered BMP, while the
                        // file_len-to-scan_done critical cone is removed.
                        scan_sector_count_latched <= file_sector_count;
                        scan_target_reached_latched <=
                            (scan_found_total + 3'd1 >= scan_target_count);
                        state <= ST_SCAN_SIZE;
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end else if (timeout_cnt >= TIMEOUT_TICKS) begin
                    // 读扇区超时（SD 卡异常/接触不良）：结束扫描，避免永久卡死
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    scan_done   <= 1'b1;
                    state       <= ST_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end

            ST_SCAN_SIZE: begin
                state_code        <= 4'd2;
                sd_sec_read       <= 1'b0;
                scan_next_latched <= scan_sector + scan_sector_count_latched;
                state             <= ST_SCAN_ADVANCE;
            end

            ST_SCAN_ADVANCE: begin
                state_code       <= 4'd2;
                sd_sec_read      <= 1'b0;
                sd_sec_read_addr <= scan_next_latched;
                scan_sector      <= scan_next_latched;
                if (scan_target_reached_latched ||
                    (scan_next_latched > scan_max_sector)) begin
                    scan_done <= 1'b1;
                    state     <= ST_IDLE;
                end else begin
                    state <= ST_SCAN;
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    if (header_match_r) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        load_fail <= 1'b1;
                        state     <= ST_IDLE;
                    end
                end else if (timeout_cnt >= TIMEOUT_TICKS) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    load_fail   <= 1'b1;
                    state       <= ST_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    timeout_cnt <= 32'd0;
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end else if (timeout_cnt >= TIMEOUT_TICKS) begin
                    // SDRAM 写请求握手超时：释放，交给上层重试
                    timeout_cnt <= 32'd0;
                    write_req   <= 1'b0;
                    load_fail   <= 1'b1;
                    state       <= ST_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= ~pause_i;

                if (sd_sec_read_end) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    if (file_complete_r) begin
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end else if (timeout_cnt >= TIMEOUT_TICKS) begin
                    // 读像素数据超时：宣告加载失败，上层解除 load_busy 并可重试
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    load_fail   <= 1'b1;
                    state       <= ST_IDLE;
                end else if (!pause_i) begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end

            ST_FONT: begin
                state_code  <= 4'd5;
                sd_sec_read <= 1'b1;
                if (sd_sec_read_data_valid && (rd_cnt >= font_byte_offset) &&
                    (rd_cnt < font_byte_offset + 10'd32)) begin
                    if (font_relative_byte[0] == 1'b0)
                        font_first_byte <= sd_sec_read_data;
                    else begin
                        font_row_addr <= {font_slot_latched,font_relative_byte[4:1]};
                        font_row_data <= {font_first_byte,sd_sec_read_data};
                        font_row_we   <= 1'b1;
                    end
                end
                if (sd_sec_read_end) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    font_done   <= 1'b1;
                    state       <= ST_IDLE;
                end else if (timeout_cnt >= TIMEOUT_TICKS) begin
                    timeout_cnt <= 32'd0;
                    sd_sec_read <= 1'b0;
                    font_done   <= 1'b1;
                    state       <= ST_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt + 32'd1;
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
