
module top(
    input                       clk,
    input                       rst_n,          // 板载复位键，低有效
    input                       key1,           // 板载按键，功能由sw模式决定
    input                       key2,           // 板载按键，功能由sw模式决定
    input                       key3,           // 板载按键，功能由sw模式决定
    input  [3:0]                ext_key_n,      // 扩展按键S1..S4，低有效
    input  [3:0]                sw,             // 模式选择：基础、亮度、对比度、缩放、ROI、轮廓、字幕
    output                      uart_tx,        // UART状态上报，管脚D12
    input                       uart_rx,        // USB-TTL接收输入，管脚F12
    input                       I_i2s_BCLK,     // 外部音频ADC位时钟，管脚J13
    input                       I_i2s_LRCK,     // 外部音频ADC左右声道时钟，管脚F13
    output                      O_pcm_mclk,     // PCM1808主时钟，J1-19/F14
    input                       I_i2s_DOUT,     // 外部音频ADC数据，管脚L14

    output O_dac_bclk, // D16 -> J1-17
    output O_dac_lrck, // K12 -> J1-9
    output O_dac_dout, // M16 -> J1-28

    // J1 expansion peripherals (3.3 V only)
    inout                       paj_scl,        // J1-5  GPIOA_4 / H13
    inout                       paj_sda,        // J1-33 GPIOA_28 / N16
    input                       paj_int_n,      // J1-25 GPIOA_22 / H15
    inout                       light_rc,       // J1-22 GPIOA_19 / G14

	output [5:0]                seg_sel,
	output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

// 顶层按数据流划分为传感器采集、事件判决、图像/音频处理和输出四部分。
// 手势、光敏、SDRAM、视频与I2S处于不同的时钟域；低速状态先同步，
// 再进入控制状态机，避免异步信号直接参与像素或音频组合路径。

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] vout_ext_data;
wire        display_valid;
wire        hs_ext, vs_ext, de_ext;

wire [1:0] transition_mode;
wire text_select;
wire [1:0] edge_mode;
wire [1:0] zoom_mode;
wire [3:0] roi_position;
wire roi_mode=(panel_mode==7);
wire ui_update_toggle;
wire [5:0] brightness_level, contrast_level;
wire       selected_adjust;
wire [255:0] text_glyphs;
wire [511:0] text_gbk_codes;
wire [31:0] text_gbk_valid;
wire caption_commit_toggle;
wire [5:0] text_length;
wire       text_custom_valid;
wire       text_entry_mode;
wire font_row_write_toggle;
wire [8:0] font_row_write_addr;
wire [15:0] font_row_write_data;
wire audio_valid;
wire external_valid;
wire [23:0] external_left,external_right;
wire [23:0] audio_left, audio_right;
wire [255:0] audio_bars;
wire [7:0] audio_volume;
wire [255:0] fft_audio_bars;
wire [7:0] fft_audio_volume;
wire audio_demo_active;
wire paj_sensor_ready, paj_sensor_error, paj_gesture_event;
wire [3:0] paj_gesture_code;
wire [7:0] paj_raw43,paj_raw44;
wire paj_raw_valid;
wire gesture_next_n, gesture_auto_n, gesture_effect_n, gesture_prev_n;
wire [7:0] ambient_darkness;
wire ambient_valid;
wire acr_valid;
wire [19:0] acr_cts, acr_n;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        sd_card_write_fifo_afull;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [1:0]  current_image_idx_sd;
wire        auto_play_active_sd;
wire        image_load_busy_sd;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 相关
wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 链路
wire rst_all;
wire caption_palette;
wire [3:0] panel_mode, panel_press;
wire panel_next_n,panel_auto_n,panel_reset_request;
wire panel_reset_raw;
// Preserve a physical routing point on the board reset request. The buffer
// is combinational and does not add a clock cycle or change reset logic.
(* keep="true", dont_touch="true" *) EG_LOGIC_BUF u_panel_reset_route_buffer(
 .i(panel_reset_raw),.o(panel_reset_request));
mm_panel_control u_panel(.clk(clk),.rst(rst_all),.sw(sw),
 .keys_n({rst_n,key3,key2,key1} & ext_key_n),.mode(panel_mode),.press(panel_press),
 .next_n(panel_next_n),.auto_n(panel_auto_n),.reset_request(panel_reset_raw));

reg [19:0] rst_cnt = 20'd0;
reg rst_all_reg = 1'b1;

always @(posedge clk) begin
    if (panel_reset_request) begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end else if (!rst_all_reg) begin
        // 一旦复位释放，忽略后续微小的 PLL 抖动，防止系统在使用时随机复位
        rst_all_reg <= 1'b0;
    end else if (rst_all_reg) begin
        // The supplied sys_pll/video_pll IPs do not export a lock port.
        // Hold reset for 20 ms after the board reset is released instead.
        if (rst_cnt < 20'd1_000_000) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_all_reg <= 1'b1;
        end else begin
            rst_all_reg <= 1'b0;
        end
    end else begin
        rst_cnt <= 20'd0;
        rst_all_reg <= 1'b1;
    end
end

assign rst_all = rst_all_reg;

// Asynchronous assertion, synchronous release for the SDRAM controller.  This
// removes the reset deassertion path from the unrelated 50 MHz board domain
// while retaining immediate reset assertion.
(* async_reg="true" *) reg [1:0] rst_mem_sync = 2'b11;
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        rst_mem_sync <= 2'b11;
    else
        rst_mem_sync <= {rst_mem_sync[0],1'b0};
end
wire rst_mem = rst_mem_sync[1];
// Every destination releases reset only on its own clock edge.
(* async_reg="true" *) reg [1:0] rst_sd_sync=2'b11, rst_video_sync=2'b11;
always @(posedge sd_card_clk or posedge rst_all)
 if(rst_all) rst_sd_sync<=2'b11; else rst_sd_sync<={rst_sd_sync[0],1'b0};
always @(posedge video_clk or posedge rst_all)
 if(rst_all) rst_video_sync<=2'b11; else rst_video_sync<={rst_video_sync[0],1'b0};
wire rst_sd=rst_sd_sync[1], rst_video=rst_video_sync[1];
// Assert immediately; release the serializer reset on its own 125 MHz clock.
(* async_reg="true", keep="true" *) reg [1:0] rst_hdmi_sync=2'b11;
always @(posedge hdmi_5x_clk or posedge rst_video)
 if(rst_video)rst_hdmi_sync<=2'b11;else rst_hdmi_sync<={rst_hdmi_sync[0],1'b0};


wire alarm_active,alarm_tick_ms,alarm_blink,alarm_beep,alarm_clear;
wire [1:0] alarm_reasons,alarm_report;
wire [2:0] alarm_level;
wire [31:0] uptime_ms;
wire fft_frame_valid,audio_alarm,audio_suspect,fused_audio_alarm,flash_trigger,source_demo,combined_event;
wire [7:0] volume_peak;
wire [1:0] audio_class;
wire [3:0] audio_score;
wire [15:0] audio_latency_ms;
wire audio_decision_valid;
wire [31:0] alarm_low1k; wire [31:0] alarm_energy; wire [29:0] alarm_low200; wire [30:0] alarm_high2k8k; wire [4:0] alarm_wide_bins;
wire [23:0] normal_left,normal_right;
wire normal_valid,alarm_sample_tick;
assign audio_valid=alarm_active?alarm_sample_tick:normal_valid;
wire accepted_toggle;wire [3:0] accepted_code;
(* async_reg="true" *) reg [2:0] gesture_toggle_sync;
(* async_reg="true" *) reg [3:0] accepted_meta,accepted_video;
(* async_reg="true" *) reg [7:0] light_meta,light_video;
(* async_reg="true" *) reg light_valid_meta,light_valid_video;
(* async_reg="true" *) reg alarm_board_meta,alarm_board;
reg [1:0] fft_warm;
(* async_reg="true" *) reg [1:0] gesture_ready_log,gesture_error_log;
(* async_reg="true" *) reg [7:0] raw43_meta,raw43_log,raw44_meta,raw44_log;
(* async_reg="true" *) reg [5:0] bright_log_meta,bright_log;
always @(posedge video_clk or posedge rst_video)
 if(rst_video)begin bright_log_meta<=0;bright_log<=0;gesture_ready_log<=0;gesture_error_log<=0;raw43_meta<=0;raw43_log<=0;raw44_meta<=0;raw44_log<=0;end
 else begin bright_log_meta<=brightness_level;bright_log<=bright_log_meta;gesture_ready_log<={gesture_ready_log[0],paj_sensor_ready};gesture_error_log<={gesture_error_log[0],paj_sensor_error};
 raw43_meta<=paj_raw43;raw43_log<=raw43_meta;raw44_meta<=paj_raw44;raw44_log<=raw44_meta;end
wire gesture_video_event=gesture_toggle_sync[2]^gesture_toggle_sync[1];
always @(posedge clk or posedge rst_all)
 if(rst_all)begin alarm_board_meta<=0;alarm_board<=0;end
 else begin alarm_board_meta<=alarm_active;alarm_board<=alarm_board_meta;end
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin gesture_toggle_sync<=0;accepted_meta<=0;accepted_video<=0;
  light_meta<=0;light_video<=0;light_valid_meta<=0;light_valid_video<=0;fft_warm<=0;end
 else begin
  gesture_toggle_sync<={gesture_toggle_sync[1:0],accepted_toggle};
  accepted_meta<=accepted_code;accepted_video<=accepted_meta;
  light_meta<=ambient_darkness;light_video<=light_meta;
  light_valid_meta<=ambient_valid;light_valid_video<=light_valid_meta;
  if(alarm_active || source_demo || alarm_clear)fft_warm<=0;
  else if(fft_frame_valid && fft_warm<2)fft_warm<=fft_warm+1'b1;
 end
end
audio_alarm_detect u_alarm_audio(.clk(video_clk),.rst(rst_video),.frame_valid(fft_frame_valid),
 .tick_ms(alarm_tick_ms),.enable(!alarm_active && !source_demo && fft_warm==2),
 .clear(alarm_clear),.energy(alarm_energy),.low200(alarm_low200),.low1k(alarm_low1k),.high2k8k(alarm_high2k8k),
 .wide_bins(alarm_wide_bins),.volume(fft_audio_volume),.alarm(audio_alarm),.suspect(audio_suspect),
 .class_code(audio_class),.score(audio_score),.decision_latency_ms(audio_latency_ms),.decision_valid(audio_decision_valid));
mm_flash_alarm u_alarm_light(.clk(video_clk),.rst(rst_video),.tick_ms(alarm_tick_ms),
 .clear(alarm_clear),.valid(light_valid_video),.darkness(light_video),.trigger(flash_trigger));
mm_multimodal_fusion u_alarm_fusion(.clk(video_clk),.rst(rst_video),.tick_ms(alarm_tick_ms),.clear(alarm_clear),
 .audio_alarm(audio_alarm),.audio_suspect(audio_suspect),.flash_trigger(flash_trigger),
 .fused_audio_alarm(fused_audio_alarm),.combined_event(combined_event));
mm_volume_peak u_volume_peak(.clk(video_clk),.rst(rst_video),.frame_valid(fft_frame_valid),
 .freeze(alarm_active),.volume(fft_audio_volume),.peak(volume_peak));
mm_alarm_control u_alarm_control(.clk(video_clk),.rst(rst_video),.audio_alarm(fused_audio_alarm),
 .flash_trigger(flash_trigger),.gesture_event(gesture_video_event),.gesture_code(accepted_video),
 .tick_ms(alarm_tick_ms),.active(alarm_active),.reasons(alarm_reasons),.tone_level(alarm_level),
 .blink(alarm_blink),.beep_on(alarm_beep),.clear_pulse(alarm_clear),
 .report_event(alarm_report),.uptime_ms(uptime_ms));
mm_alarm_uart u_alarm_uart(.clk(video_clk),.rst(rst_video),.events(alarm_report),
 .timestamp_ms(uptime_ms),.darkness(light_video),.volume(fft_audio_volume),
 .brightness(bright_log),.tone_level(alarm_level),.reasons(alarm_reasons),
 .sensor_ready(gesture_ready_log[1]),.sensor_error(gesture_error_log[1]),
 .gesture(accepted_video),.raw43(raw43_log),.raw44(raw44_log),
 .audio_class(audio_class),.audio_score(audio_score),.audio_latency_ms(audio_latency_ms),
 .combined_event(combined_event),.decision_valid(audio_decision_valid),
 .clear(alarm_clear),.tick_ms(alarm_tick_ms),.pcm_valid(external_valid),
 .pcm_sample(external_left[23:8]),.light_valid(light_valid_video),.tx(uart_tx));
mm_alarm_tone u_alarm_tone(.clk(video_clk),.rst(rst_video),.active(alarm_active),
 .beep_on(alarm_beep),.sample_valid(audio_valid),.level(alarm_level),
 .normal_left(normal_left),.normal_right(normal_right),.left(audio_left),.right(audio_right));

// 手势控制与视频/SDRAM数据通路分离，仅向控制模块发送事件。
// 正常模式右挥下一张、左挥上一张；ROI模式左右挥循环选择九宫格；
// 告警模式上挥解除告警，顺时针/逆时针调节告警音量。
// 挥手不控制自动播放，旋转也不切换转场，避免同一动作产生多重含义。
mm_paj7620_controller u_paj7620(
    .clk(clk), .rst(rst_all), .int_n(paj_int_n), .scl(paj_scl), .sda(paj_sda),
    .sensor_ready(paj_sensor_ready), .sensor_error(paj_sensor_error),
    .gesture_code(paj_gesture_code), .gesture_event(paj_gesture_event),
    .raw43(paj_raw43),.raw44(paj_raw44),.raw_valid(paj_raw_valid)
);
mm_gesture_key_bridge u_gesture_keys(
    .clk(clk), .rst(rst_all), .gesture_event(paj_gesture_event),
    .gesture_code(paj_gesture_code), .roi_mode(roi_mode), .roi_position(roi_position), .next_n(gesture_next_n),
    .auto_n(gesture_auto_n), .effect_n(gesture_effect_n), .prev_n(gesture_prev_n),
    .quiet_event(paj_raw_valid && paj_raw43==0 && !paj_raw44[0]),
    .activity_event(paj_raw_valid && (paj_raw43!=0 || paj_raw44[0])),
    .alarm_active(alarm_board),.accepted_toggle(accepted_toggle),.accepted_code(accepted_code)
);
mm_ldr_rc_sensor u_ambient_light(
    .clk(clk), .rst(rst_all), .light_rc(light_rc),
    .darkness(ambient_darkness), .sample_valid(ambient_valid)
);

// TF卡、SDRAM和视频链路使用各自独立时钟域。
sys_pll sys_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .reset      (1'b0),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .vsync_in          (vs_0),
    .key_next          (panel_next_n),
    .key_auto          (panel_auto_n),
    .gesture_next_n    (gesture_next_n),
    .gesture_auto_n    (gesture_auto_n),
    .gesture_prev_n    (gesture_prev_n),
    .alarm_active_i    (alarm_active),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .caption_commit_toggle(caption_commit_toggle),
    .caption_gbk_codes (text_gbk_codes),
    .caption_gbk_valid (text_gbk_valid),
    .caption_length    (text_length),
    .font_row_write_toggle(font_row_write_toggle),
    .font_row_write_addr(font_row_write_addr),
    .font_row_write_data(font_row_write_data),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .current_image_idx (current_image_idx_sd),
    .auto_play_active  (auto_play_active_sd),
    .image_load_busy   (image_load_busy_sd),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_fifo_afull  (sd_card_write_fifo_afull),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// 面板扫描保持在 SD 时钟域，避免多余的跨时钟域处理，
// 板级管脚上的照片序号保持不变。
wire [6:0] seg_data_photo;
seg_decoder seg_decoder_m0(
    .bin_data          ({2'b00,current_image_idx_sd} + 4'd1),
    .seg_data          (seg_data_photo)
);

seg_scan seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (~rst_sd),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .photo_seg         ({1'b1,seg_data_photo}),
    .photo_index       (current_image_idx_sd),
    .auto_active       (auto_play_active_sd),
    .load_busy         (image_load_busy_sd)
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；display_valid 来自 SD 卡时钟域，先做两拍同步，
// 避免把跨域信号直接接进整条视频组合处理链。
reg display_valid_meta, display_valid_video;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        display_valid_meta  <= 1'b0;
        display_valid_video <= 1'b0;
    end else begin
        display_valid_meta  <= display_valid;
        display_valid_video <= display_valid_meta;
    end
end
assign vout_data = display_valid_video ? vout_data_raw : 24'd0;

// Extension controls live at 50 MHz; video module synchronizes them internally.
mm_ext_control u_ext_control (
    .caption_palette(caption_palette),
    .clk(clk), .rst_n(~rst_all), .key_press(panel_press), .gesture_effect_n(gesture_effect_n),
    .sw(panel_mode), .uart_rx(uart_rx),
    .transition_mode(transition_mode), .text_select(text_select),
    .edge_mode(edge_mode), .zoom_mode(zoom_mode), .ui_update_toggle(ui_update_toggle),
    .brightness_level(brightness_level), .contrast_level(contrast_level),
    .selected_adjust(selected_adjust), .text_glyphs(text_glyphs),
    .text_gbk_codes(text_gbk_codes), .text_gbk_valid(text_gbk_valid),
    .caption_commit_toggle(caption_commit_toggle),
    .text_length(text_length), .text_custom_valid(text_custom_valid),
    .text_entry_mode(text_entry_mode)
);

wire audio_clock_lock;
mm_pcm_clock u_pcm_clock(.clk(clk),.reset(rst_all),.mclk(O_pcm_mclk),.locked(audio_clock_lock));
(* async_reg="true" *) reg audio_lock_meta,audio_lock_video;
always @(posedge video_clk or posedge rst_video) begin
 if(rst_video) begin audio_lock_meta<=0;audio_lock_video<=0;end
 else begin audio_lock_meta<=audio_clock_lock;audio_lock_video<=audio_lock_meta;end
end
// External I2S ADC/line input in the video clock domain.
// Receive live stereo PCM samples and their valid strobe.
I2S_receiver u_audio_input (
    .I_clk(video_clk), .I_rst(rst_video | !audio_lock_video),
    .I_i2s_BCLK(I_i2s_BCLK), .I_i2s_LRCK(I_i2s_LRCK), .I_i2s_DOUT(I_i2s_DOUT),
    .O_audio_valid(external_valid), .O_audio_left_data(external_left),
    .O_audio_right_data(external_right)
);
mm_audio_spectrum_1024 #(.DB_FLOOR(24), .SILENCE_GATE(8'd1)) u_audio_visualizer (
    .clk(video_clk), .rst(rst_video), .sample_valid(alarm_active?audio_valid:external_valid),
    .sample_left(alarm_active?audio_left:external_left), .sample_right(alarm_active?audio_right:external_right),
    .bars(fft_audio_bars), .volume(fft_audio_volume),.frame_valid(fft_frame_valid),.alarm_energy(alarm_energy),.alarm_low200(alarm_low200),.alarm_low1k(alarm_low1k),
    .alarm_high2k8k(alarm_high2k8k),.alarm_wide_bins(alarm_wide_bins)
);
mm_audio_source u_audio_source(.clk(video_clk),.rst(rst_video),
 .external_valid(external_valid),.external_left(external_left),.external_right(external_right),
 .valid(normal_valid),.left(normal_left),.right(normal_right),.demo_active(source_demo),.sample_tick(alarm_sample_tick));
mm_dac_output u_dac(.sample_clk(video_clk),.mclk(O_pcm_mclk),
 .rst(rst_all | !audio_clock_lock),.sample_valid(audio_valid),
 .left(audio_left),.right(audio_right),.bclk(O_dac_bclk),.lrck(O_dac_lrck),.dout(O_dac_dout),
 .overflow(),.underflow());
// 外部I2S有效时显示真实FFT结果；未接音频输入时显示帧驱动演示频谱。
// 频谱显示源只影响可视化，HDMI音频播放链路保持独立。
mm_audio_display_source u_audio_display_source (
    .clk(video_clk), .rst(rst_video), .vs(vs), .audio_valid(external_valid),
    .fft_bars(fft_audio_bars), .fft_volume(fft_audio_volume),
    .display_bars(audio_bars), .display_volume(audio_volume),
    .demo_active(audio_demo_active)
);
audio_arc_calculate u_audio_acr (
    .I_clk(video_clk), .I_rst(rst_video), .I_audio_valid(audio_valid),
    .O_acr_valid(acr_valid), .O_acr_cts(acr_cts), .O_acr_n(acr_n)
);

mm_video_extensions u_video_extensions (
    .alarm_active_i(alarm_active),.alarm_reasons_i(alarm_reasons),.alarm_blink_i(alarm_beep),.alarm_uptime_i(uptime_ms),
    .caption_palette_i(caption_palette),
    .clk(video_clk), .rst(rst_video), .rgb_i_src(vout_data), .hs_i_src(hs), .vs_i_src(vs), .de_i_src(de),
    .disp_buf_idx_i(disp_buf_idx), .transition_mode_i(transition_mode),
    .text_select_i(text_select), .edge_mode_i(edge_mode), .zoom_mode_i(zoom_mode), .roi_mode_i(roi_mode), .roi_position_i(roi_position),
    .ui_update_toggle_i(ui_update_toggle), .brightness_i(brightness_level),
    .contrast_i(contrast_level), .audio_bars_i(alarm_active?fft_audio_bars:audio_bars), .audio_volume_i(alarm_active?fft_audio_volume:audio_volume),
    .volume_peak_i(volume_peak),
    .selected_adjust_i(selected_adjust), .text_glyphs_i(text_glyphs),
    .text_length_i(text_length), .text_custom_valid_i(text_custom_valid),
    .text_entry_mode_i(text_entry_mode),
    .font_row_write_toggle_i(font_row_write_toggle),
    .font_row_write_addr_i(font_row_write_addr),
    .font_row_write_data_i(font_row_write_data),
    .audio_demo_i(audio_demo_active), .gesture_ready_i(paj_sensor_ready), .gesture_error_i(paj_sensor_error),
    .gesture_code_i(paj_gesture_code),
    .ambient_darkness_i(ambient_darkness), .ambient_valid_i(ambient_valid),
    .hs_o(hs_ext), .vs_o(vs_ext), .de_o(de_ext), .rgb_o(vout_ext_data)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .zoom_mode         (zoom_mode), .roi_position(roi_mode?roi_position:4'd4),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_fifo_afull  (sd_card_write_fifo_afull)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (vs_ext),
    .I_de          (de_ext),
    .I_rgb         (vout_ext_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

// ===================== HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left),
    .I_audio_right_data (audio_right),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_hdmi_sync[1]),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
