
module sd_card_bmp #(
    // 自动轮播间隔和失败重试间隔由输入时钟换算为计数周期。
    // 扫描只记录前SCAN_TARGET_COUNT张BMP，默认4张，对应数码管1..4。
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer AUTO_INTERVAL_MS  = 3000,
    parameter integer LOAD_FAIL_RETRY_MS = 100,   // 首图加载失败后的自动重试间隔
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4
)(
    input                       clk,
    input                       rst,
    input                       vsync_in,
    input                       key_next,
    input                       key_auto,
    input                       gesture_next_n,
    input                       gesture_auto_n,
    input                       gesture_prev_n,
    input                       alarm_active_i,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    input                       caption_commit_toggle,
    input  [511:0]              caption_gbk_codes,
    input  [31:0]               caption_gbk_valid,
    input  [5:0]                caption_length,
    output reg                  font_row_write_toggle,
    output reg [8:0]            font_row_write_addr,
    output reg [15:0]           font_row_write_data,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,
    output wire [1:0]           current_image_idx,
    output wire                 auto_play_active,
    output wire                 image_load_busy,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    input                       write_fifo_afull,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

 wire key_next_press_phys;
wire key_auto_press_phys;
wire key_next_press;
wire key_auto_press;
reg  gesture_next_meta, gesture_next_sync, gesture_next_last;
reg  gesture_auto_meta, gesture_auto_sync, gesture_auto_last;
wire gesture_next_press = gesture_next_last && !gesture_next_sync;
wire gesture_auto_press = gesture_auto_last && !gesture_auto_sync;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;
wire             load_fail;   // bmp_read 加载失败脉冲（BMP 头不匹配等）
wire             font_found_valid;
wire [31:0]      font_found_sector;
wire             font_row_we;
wire [8:0]       font_row_addr;
wire [15:0]      font_row_data;
wire             font_done;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              scan_complete;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending;
reg              load_busy;
reg [31:0]       fail_gate_cnt;      // 加载失败后的重试间隔计数
reg [31:0]       font_base_sector;
reg              font_available;
reg [2:0]        caption_commit_sync;
reg [511:0]      caption_codes_latched;
reg [31:0]       caption_valid_latched;
reg [5:0]        caption_length_latched;
reg [5:0]        font_load_slot;
reg              font_load_active;
reg              font_wait_done;
reg              font_start_pulse;
reg              vsync_meta, vsync_sync, vsync_last;
reg [1:0]        reuse_guard_frames;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;
// 写完成和源文件读取完成属于两个独立时钟域事件。两者可能同拍到达，
// 必须分别锁存；不能只在 source_done_seen 已置位时才接收写完成脉冲。
reg              write_done_seen;
reg              frame_commit_pending;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;
wire             frame_start_pulse = vsync_last && !vsync_sync;

wire auto_tick;
localparam [31:0] AUTO_TICKS = (CLK_FREQ_HZ / 1000) * AUTO_INTERVAL_MS;
localparam [31:0] FAIL_RETRY_TICKS = (CLK_FREQ_HZ / 1000) * LOAD_FAIL_RETRY_MS;
wire [1:0] next_from_current;

(* async_reg="true" *) reg alarm_m,alarm_s;
// 所有扫描到的图片均参与正常演示；告警保持当前显示缓冲，不发起换图。
wire [2:0] normal_image_count=img_found_count;
wire restore_pending=1'b0;
always @(posedge clk or posedge rst)begin
 if(rst)begin alarm_m<=0;alarm_s<=0;end
 else begin alarm_m<=alarm_active_i;alarm_s<=alarm_m;end
end
reg prev_m,prev_s,prev_last,prev_pending;
 wire prev_press=prev_last && !prev_s && !alarm_s && !restore_pending;
 wire [1:0] prev_index=(normal_image_count<=1)?2'd0:((img_idx==0)?normal_image_count[1:0]-2'd1:img_idx-2'd1);
 wire choose_prev=prev_press || (prev_pending && !key_next_press);
 wire [1:0] manual_index=choose_prev?prev_index:next_from_current;
 always @(posedge clk or posedge rst) begin
  if(rst) begin prev_m<=1;prev_s<=1;prev_last<=1;prev_pending<=0;end
  else begin
   prev_m<=gesture_prev_n;prev_s<=prev_m;prev_last<=prev_s;
   if(load_start_pulse) prev_pending<=0;
   if(key_next_press) prev_pending<=0;
   if(prev_press) prev_pending<=1;
   if(alarm_s)prev_pending<=0;
  end
 end

assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = (auto_cnt >= (AUTO_TICKS - 1));
assign next_from_current = next_index_limited(img_idx, normal_image_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign key_next_press = (key_next_press_phys | gesture_next_press) && !alarm_s && !restore_pending;
assign key_auto_press = (key_auto_press_phys | gesture_auto_press) && !alarm_s && !restore_pending;
assign current_image_idx = img_idx;
assign auto_play_active = auto_play_en;
assign image_load_busy = load_busy;

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press_phys)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press_phys)
);

// 手势脉冲来自50MHz外设域，独立同步后再与物理按键合并。
// 不使用手势状态组合门控按键，因此PAJ模块断开或异常不会阻塞key1/key2。
always @(posedge clk or posedge rst) begin
    if (rst) begin
        gesture_next_meta <= 1'b1;
        gesture_next_sync <= 1'b1;
        gesture_next_last <= 1'b1;
        gesture_auto_meta <= 1'b1;
        gesture_auto_sync <= 1'b1;
        gesture_auto_last <= 1'b1;
    end else begin
        gesture_next_meta <= gesture_next_n;
        gesture_next_sync <= gesture_next_meta;
        gesture_next_last <= gesture_next_sync;
        gesture_auto_meta <= gesture_auto_n;
        gesture_auto_sync <= gesture_auto_meta;
        gesture_auto_last <= gesture_auto_sync;
    end
end

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        scan_complete         <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        fail_gate_cnt         <= 32'd0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        frame_commit_pending  <= 1'b0;
        display_valid         <= 1'b0;
        font_base_sector      <= 32'd0;
        font_available        <= 1'b0;
        caption_commit_sync   <= 3'b000;
        caption_codes_latched <= 512'd0;
        caption_valid_latched <= 32'd0;
        caption_length_latched<= 6'd0;
        font_load_slot        <= 6'd0;
        font_load_active      <= 1'b0;
        font_wait_done        <= 1'b0;
        font_start_pulse      <= 1'b0;
        vsync_meta            <= 1'b0;
        vsync_sync            <= 1'b0;
        vsync_last            <= 1'b0;
        reuse_guard_frames    <= 2'd0;
        font_row_write_toggle <= 1'b0;
        font_row_write_addr   <= 9'd0;
        font_row_write_data   <= 16'd0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        vsync_meta       <= vsync_in;
        vsync_sync       <= vsync_meta;
        vsync_last       <= vsync_sync;
        if (frame_start_pulse && reuse_guard_frames != 0)
            reuse_guard_frames <= reuse_guard_frames - 1'b1;
        caption_commit_sync <= {caption_commit_sync[1:0],caption_commit_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        font_start_pulse <= 1'b0;

        if (font_row_we) begin
            font_row_write_addr   <= font_row_addr;
            font_row_write_data   <= font_row_data;
            font_row_write_toggle <= ~font_row_write_toggle;
        end

        if (font_found_valid) begin
            font_base_sector <= font_found_sector;
            font_available   <= 1'b1;
        end

        if (caption_commit_sync[2] != caption_commit_sync[1]) begin
            caption_codes_latched  <= caption_gbk_codes;
            caption_valid_latched  <= caption_gbk_valid;
            caption_length_latched <= caption_length;
            font_load_slot         <= 6'd0;
            font_load_active       <= 1'b1;
            font_wait_done         <= 1'b0;
        end else if (font_load_active) begin
            if (font_wait_done) begin
                if (font_done) begin
                    font_wait_done <= 1'b0;
                    font_load_slot <= font_load_slot + 6'd1;
                    caption_valid_latched <= {1'b0,caption_valid_latched[31:1]};
                end
            end else if (font_load_slot >= caption_length_latched) begin
                font_load_active <= 1'b0;
            end else if (!caption_valid_latched[0]) begin
                font_load_slot <= font_load_slot + 6'd1;
                    caption_valid_latched <= {1'b0,caption_valid_latched[31:1]};
            end else if (font_available && bmp_ready) begin
                font_start_pulse <= 1'b1;
                font_wait_done   <= 1'b1;
            end
        end

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            scan_complete         <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            fail_gate_cnt         <= 32'd0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            frame_commit_pending  <= 1'b0;
            display_valid         <= 1'b0;
            reuse_guard_frames    <= 2'd0;
            font_available        <= 1'b0;
            font_load_active      <= 1'b0;
            font_wait_done        <= 1'b0;
        end else begin
            // bmp_read 的 scan_done 仅为一个时钟脉冲；锁存后作为轮播
            // 状态使用，否则脉冲结束后手动/自动加载条件永久为假。
            if (scan_done)
                scan_complete <= 1'b1;

            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_busy && bmp_ready)
                source_done_seen <= 1'b1;
            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            // 加载失败（BMP 头不匹配 / 读取超时）：立即解除 load_busy，不再卡死。
            // 若已有图在显示，则推进 img_idx 跳过坏图并保留“下一张”请求，
            // 让手动切换/轮播自动尝试下一张；首图失败则等 fail_gate 后再重试。
            if (load_fail) begin
                load_busy        <= 1'b0;
                source_done_seen <= 1'b0;
                write_done_seen  <= 1'b0;
                frame_commit_pending <= 1'b0;
                fail_gate_cnt    <= FAIL_RETRY_TICKS;
                if (display_valid && (normal_image_count > 3'd1)) begin
                    img_idx          <= next_from_current;
                    next_req_pending <= 1'b1;
                end else begin
                    next_req_pending <= 1'b0;
                end
            end else if (fail_gate_cnt != 32'd0) begin
                fail_gate_cnt    <= fail_gate_cnt - 32'd1;
            end

            // 同时确认“源图送入写 FIFO 完成”和“SDRAM 整帧写完”。
            // 将当前拍的输入一并纳入判断，避免两个事件同拍时漏脉冲、卡在 load_busy。
            if (load_busy && (source_done_seen || bmp_ready) &&
                (write_done_seen || write_finish_pulse)) begin
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                frame_commit_pending  <= 1'b1;
            end

            // 仅在真实视频帧边界切换显示缓冲。完整图像在此之前保留在后缓冲，
            // 因此同一显示帧不会混用两个缓冲区的地址。
            if (frame_start_pulse && frame_commit_pending && (!alarm_s || !display_valid)) begin
                frame_commit_pending  <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
                // 读侧在帧边界观察到新索引后才复用旧缓冲；等待两个帧沿，
                // 覆盖video到SD、SD到memory两次跨时钟传播。
                reuse_guard_frames    <= 2'd2;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                scan_complete         <= 1'b0;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                frame_commit_pending  <= 1'b0;
                reuse_guard_frames    <= 2'd0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张。
                // 扫描结束前按下也保留这一次请求，首图提交后会立即执行。
                if (key_next_press)
                    next_req_pending <= 1'b1;
                if(alarm_s)next_req_pending<=0;

                

                // 自动播放开/关
                if (key_auto_press && scan_complete && (normal_image_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放 3s 计数：只有当前没有写图任务时才计时
                if (!alarm_s && !restore_pending && scan_complete && auto_play_en && display_valid && !load_busy && first_image_committed && (normal_image_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_complete && !first_image_committed && bmp_ready && !load_busy && (fail_gate_cnt == 32'd0) && (normal_image_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    frame_commit_pending <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_complete && bmp_ready && display_valid && !load_busy &&
                         (reuse_guard_frames == 0) &&
                         (!alarm_s && !restore_pending) && (next_req_pending || key_next_press || prev_pending || prev_press) && (normal_image_count != 3'd0)) begin
                    load_idx         <= manual_index;
                    load_sector      <= sector_lut(manual_index);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    frame_commit_pending <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_complete && bmp_ready && display_valid && !load_busy &&
                         (reuse_guard_frames == 0) &&
                         !alarm_s && !restore_pending && auto_play_en && auto_tick && !key_auto_press && (normal_image_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    frame_commit_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

// write_req_ack产生于外部存储时钟域，BMP读取器按电平握手使用。
// 进入SD时钟域前做两级同步，避免亚稳态和无意义的跨域4ns时序路径。
reg write_req_ack_meta;
reg write_req_ack_sync;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_req_ack_meta <= 1'b0;
        write_req_ack_sync <= 1'b0;
    end else begin
        write_req_ack_meta <= write_req_ack;
        write_req_ack_sync <= write_req_ack_meta;
    end
end

bmp_read bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .font_found_valid       (font_found_valid),
    .font_found_sector      (font_found_sector),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),
    .load_fail              (load_fail),
    .font_start             (font_start_pulse),
    .font_base_sector       (font_base_sector),
    .font_gbk_code          (caption_codes_latched[font_load_slot*16 +: 16]),
    .font_slot              (font_load_slot[4:0]),
    .font_row_we            (font_row_we),
    .font_row_addr          (font_row_addr),
    .font_row_data          (font_row_data),
    .font_done              (font_done),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack_sync),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .pause_i                (write_fifo_afull),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top #(
    // SPI remains 12.5 MHz for either 50 or 100 MHz controller clock.  The original 25 MHz setting
    // provided little margin on a cabled SD module and the block reader does
    // not validate data CRC, so use the conservative rate to prevent a noisy
    // CMD17/address or data bit from selecting foreign image sectors.
    .SPI_LOW_SPEED_DIV((CLK_FREQ_HZ / 400_000) - 2),
    .SPI_HIGH_SPEED_DIV((CLK_FREQ_HZ / 25_000_000) - 2)
) sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
