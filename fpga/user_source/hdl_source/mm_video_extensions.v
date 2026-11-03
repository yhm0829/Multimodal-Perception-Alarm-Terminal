`timescale 1ns/1ps

// 640x480低资源视频后处理器，位于SDRAM读图与HDMI封装之间。
// 本模块只修改像素内容，不改变TF卡、SDRAM、HDMI引脚和行场时序协议。
// 处理顺序为：坐标/状态同步 -> 边缘与图像效果 -> OSD/频谱/告警叠加 -> 亮度与环境补偿。
// 采用单行亮度缓存而不是整帧缓存完成梯度检测，以一行BRAM换取较低LUT和存储开销。
// EFFECT_FRAMES控制转场持续帧数；RELEASE_FRAMES和PEAK_FALL_FRAMES控制频谱保持与回落；
// ENABLE_DYNAMIC_FONT为0时只使用固化字模，为1时允许SD卡字模缓存参与显示。
module mm_video_extensions #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer EFFECT_FRAMES = 32,
    parameter integer RELEASE_FRAMES = 1,
    parameter integer PEAK_FALL_FRAMES = 3,
    parameter integer ENABLE_DYNAMIC_FONT = 0 // Pair with control ENABLE_CUSTOM_UART.
)(
    input wire roi_mode_i, input wire [3:0] roi_position_i,
    input wire [31:0] alarm_uptime_i,
    input wire alarm_active_i,alarm_blink_i, input wire [1:0] alarm_reasons_i,
    input  wire        clk,
    input  wire        rst,
    input  wire [23:0] rgb_i_src,
    input  wire        hs_i_src,
    input  wire        vs_i_src,
    input  wire        de_i_src,
    input  wire [1:0]  disp_buf_idx_i,
    input  wire [1:0]  transition_mode_i,
    input  wire        text_select_i,
    input  wire [1:0]  edge_mode_i,
    input  wire [1:0]  zoom_mode_i,
    input  wire        ui_update_toggle_i,
    input  wire [5:0]  brightness_i,
    input  wire [5:0]  contrast_i,
    input  wire [255:0] audio_bars_i,
    input  wire [7:0]  audio_volume_i,
    input  wire [7:0]  volume_peak_i,   // 告警音频峰值，用于相对强弱分级提示
    input  wire        selected_adjust_i,
    input  wire [255:0] text_glyphs_i,
    input wire caption_palette_i,
    input  wire [5:0]  text_length_i,
    input  wire        text_custom_valid_i,
    input  wire        text_entry_mode_i,
    input  wire        font_row_write_toggle_i,
    input  wire [8:0]  font_row_write_addr_i,
    input  wire [15:0] font_row_write_data_i,
    input  wire        audio_demo_i,
    input  wire        gesture_ready_i,
    input  wire        gesture_error_i,
    input  wire [3:0]  gesture_code_i,
    input  wire [7:0]  ambient_darkness_i,
    input  wire        ambient_valid_i,
    output wire        hs_o,
    output wire        vs_o,
    output wire        de_o,
    output wire [23:0] rgb_o
);

    // ROI、手势和环境光状态来自50MHz板级域，变化速度远低于像素时钟。
    // 两级同步后只在视频域使用，避免异步翻转直接进入OSD组合逻辑。
    reg hs_i, vs_i, de_i;
    reg [4:0] roi_m,roi_v,roi_frame;
    reg [9:0] roi_l,roi_r;
    reg [8:0] roi_t,roi_b;
    reg roi_hit_stage;
    always @(posedge clk or posedge rst) begin
      if(rst) begin roi_m<=0;roi_v<=0;roi_frame<=0;roi_l<=0;roi_r<=212;roi_t<=0;roi_b<=159;end
      else begin
        roi_m<={roi_mode_i,roi_position_i};roi_v<=roi_m;
        if(frame_tick) roi_frame<=roi_v;
        case(roi_frame[3:0])
          0,3,6:begin roi_l<=0;roi_r<=212;end
          1,4,7:begin roi_l<=213;roi_r<=425;end
          default:begin roi_l<=426;roi_r<=639;end
        endcase
        case(roi_frame[3:0])
          0,1,2:begin roi_t<=0;roi_b<=159;end
          3,4,5:begin roi_t<=160;roi_b<=319;end
          default:begin roi_t<=320;roi_b<=479;end
        endcase
      end
    end
    always @(posedge clk or posedge rst)
      if(rst) roi_hit_stage<=0;
      else roi_hit_stage<=roi_frame[4] && de_i &&
       (((x_pos==roi_l || x_pos==roi_r) && y_pos>=roi_t && y_pos<=roi_b) ||
        ((y_pos==roi_t || y_pos==roi_b) && x_pos>=roi_l && x_pos<=roi_r));
    wire frame_tick;
    reg audio_demo_m,audio_demo_v;
    reg [7:0] ambient_dim;
    // 光敏RC值按感知曲线换算：弱变化在低亮区更明显，同时保留非零亮度下限。
    // 该增益只作用于最终RGB，不反馈到SDRAM地址和读写协议。
    function [7:0] darkness_to_dim;
        input [7:0] darkness;
        begin
            if(darkness<16) darkness_to_dim={darkness[5:0],2'b00};
            else if(darkness<64) darkness_to_dim=8'd64+((darkness-8'd16)<<1);
            else darkness_to_dim=8'd160+((darkness-8'd64)>>3);
        end
    endfunction
    wire [8:0] ambient_gain=9'd256-{1'b0,ambient_dim};
    reg gesture_ready_m, gesture_ready_v, gesture_error_m, gesture_error_v;
    reg [3:0] gesture_code_m, gesture_code_v;
    reg [7:0] ambient_darkness_m, ambient_darkness_v;
    wire [7:0] ambient_target=darkness_to_dim(ambient_darkness_v);
    reg ambient_valid_m, ambient_valid_v;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_demo_m<=1;audio_demo_v<=1;ambient_dim<=0;
            gesture_ready_m<=0; gesture_ready_v<=0; gesture_error_m<=0; gesture_error_v<=0;
            gesture_code_m<=0; gesture_code_v<=0; ambient_darkness_m<=0; ambient_darkness_v<=0;
            ambient_valid_m<=0; ambient_valid_v<=0;
        end else begin
            audio_demo_m<=audio_demo_i;audio_demo_v<=audio_demo_m;
            if(frame_tick) begin
                if(!ambient_valid_v) ambient_dim<=0;
                else if(ambient_dim < ambient_target)
                    ambient_dim<=((ambient_target-ambient_dim)>4)?ambient_dim+8'd4:ambient_target;
                else if(ambient_dim > ambient_target)
                    ambient_dim<=((ambient_dim-ambient_target)>4)?ambient_dim-8'd4:ambient_target;
            end
            gesture_ready_m<=gesture_ready_i; gesture_ready_v<=gesture_ready_m;
            gesture_error_m<=gesture_error_i; gesture_error_v<=gesture_error_m;
            gesture_code_m<=gesture_code_i; gesture_code_v<=gesture_code_m;
            ambient_darkness_m<=ambient_darkness_i; ambient_darkness_v<=ambient_darkness_m;
            ambient_valid_m<=ambient_valid_i; ambient_valid_v<=ambient_valid_m;
        end
    end

    localparam [7:0] G_SPACE = 8'd0;
    localparam [7:0] G_COLON = 8'd11;
    localparam [7:0] G_X     = 8'd12;
    localparam [7:0] G_B     = 8'd13;
    localparam [7:0] G_R     = 8'd14;
    localparam [7:0] G_T     = 8'd15;
    localparam [7:0] G_C     = 8'd16;
    localparam [7:0] G_N     = 8'd17;
    localparam [7:0] G_D     = 8'd18;

    reg  vs_d;
    reg  de_d;
    reg [10:0] x_pos;
    reg [9:0]  y_pos;
    reg        first_active_line;

    assign frame_tick = vs_d && !vs_i;

    // Synchronizers for controls generated by the 50 MHz board domain.
    reg [1:0] mode_meta, mode_v;
    reg text_meta, text_v;
    reg caption_palette_meta, caption_palette_v;
    wire [23:0] caption_ink = caption_palette_v ? 24'hb8f6ff : 24'hffd66b;
    reg [1:0] edge_meta, edge_v, zoom_meta, zoom_v;
    reg ui_meta, ui_v, ui_last;
    reg [5:0] bright_meta, bright_v;
    reg [5:0] contrast_meta, contrast_v;
    reg adjust_meta, adjust_v;
    reg custom_meta, custom_v, entry_meta, entry_v;
    reg [5:0] text_len_meta, text_len_v;
    reg [255:0] text_glyphs_v;
    reg [1:0] buf_meta, buf_v, buf_last;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vs_d             <= 1'b0;
            de_d             <= 1'b0;
            x_pos            <= 11'd0;
            y_pos            <= 10'd0;
            first_active_line<= 1'b1;
            mode_meta        <= 2'd0;
            mode_v           <= 2'd0;
            text_meta        <= 1'b0;
            caption_palette_meta <= 0; caption_palette_v <= 0;
            text_v           <= 1'b0;
            edge_meta        <= 2'd1;
            edge_v           <= 2'd1;
            zoom_meta        <= 2'd0;
            zoom_v           <= 2'd0;
            ui_meta          <= 1'b0;
            ui_v             <= 1'b0;
            bright_meta      <= 6'd0;
            bright_v         <= 6'd0;
            contrast_meta    <= 6'd0;
            contrast_v       <= 6'd0;
            adjust_meta      <= 1'b0;
            adjust_v         <= 1'b0;
            custom_meta      <= 1'b0;
            custom_v         <= 1'b0;
            entry_meta       <= 1'b0;
            entry_v          <= 1'b0;
            text_len_meta    <= 6'd0;
            text_len_v       <= 6'd0;
            text_glyphs_v    <= 256'h00000000000000000000000000000000a7bebcabbbbdb9b3b8a6c1ada1b5a5a0;
            buf_meta         <= 2'd0;
            buf_v            <= 2'd0;
        end else begin
            vs_d          <= vs_i;
            de_d          <= de_i;
            mode_meta     <= transition_mode_i;
            mode_v        <= mode_meta;
            text_meta     <= text_select_i;
            caption_palette_meta <= caption_palette_i; caption_palette_v <= caption_palette_meta;
            text_v        <= text_meta;
            edge_meta     <= edge_mode_i;
            edge_v        <= edge_meta;
            zoom_meta     <= zoom_mode_i;
            zoom_v        <= zoom_meta;
            ui_meta       <= ui_update_toggle_i;
            ui_v          <= ui_meta;
            bright_meta   <= brightness_i;
            bright_v      <= bright_meta;
            contrast_meta  <= contrast_i;
            contrast_v     <= contrast_meta;
            adjust_meta    <= selected_adjust_i;
            adjust_v       <= adjust_meta;
            custom_meta    <= text_custom_valid_i;
            custom_v       <= custom_meta;
            entry_meta     <= text_entry_mode_i;
            entry_v        <= entry_meta;
            text_len_meta  <= text_length_i;
            text_len_v     <= text_len_meta;
            buf_meta       <= disp_buf_idx_i;
            buf_v          <= buf_meta;

            // The UART buffer is stable after Enter. Capture it only when the
            // synchronized UI event changes, avoiding a 224-bit synchronizer.
            if (ui_v != ui_last)
                text_glyphs_v <= text_glyphs_i;

            // Coordinates are derived from active-video edges. This avoids
            // relying on the internal blanking counter of the base generator.
            if (frame_tick) begin
                x_pos             <= 11'd0;
                y_pos             <= 10'd0;
                first_active_line <= 1'b1;
            end else if (de_i && !de_d) begin
                x_pos <= 11'd0;
                if (first_active_line) begin
                    y_pos             <= 10'd0;
                    first_active_line <= 1'b0;
                end else if (y_pos == V_ACTIVE - 1) begin
                    y_pos <= 10'd0;
                end else begin
                    y_pos <= y_pos + 10'd1;
                end
            end else if (de_i) begin
                if (x_pos == H_ACTIVE - 1)
                    x_pos <= 11'd0;
                else
                    x_pos <= x_pos + 11'd1;
            end
        end
    end

    // A change of display buffer is the commit event from the base example.
    // The effect begins on the following frame, so no partially written frame
    // is ever used.
    reg       effect_pending;
    reg       effect_active;
    reg [1:0] effect_mode;
    reg [5:0] effect_count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buf_last      <= 2'd0;
            effect_pending<= 1'b0;
            effect_active <= 1'b0;
            effect_mode   <= 2'd0;
            effect_count  <= 6'd0;
        end else begin
            if (buf_v != buf_last) begin
                buf_last       <= buf_v;
                effect_pending <= 1'b1;
                effect_mode    <= mode_v;
            end

            if (frame_tick) begin
                if (effect_pending) begin
                    effect_pending <= 1'b0;
                    effect_active  <= (effect_mode != 2'd0);
                    effect_count   <= 6'd0;
                end else if (effect_active) begin
                    if (effect_count == EFFECT_FRAMES - 1) begin
                        effect_active <= 1'b0;
                        effect_count  <= 6'd0;
                    end else begin
                        effect_count <= effect_count + 6'd1;
                    end
                end
            end
        end
    end

    // Timestamp and scrolling cursor, updated once per video frame.
    reg [5:0] frame_count;
    reg [5:0] flow_phase;
    reg [3:0] hour_t, hour_u, min_t, min_u, sec_t, sec_u;
    reg [10:0] scroll_x;
    wire [10:0] preset_text_width = text_v ? 11'd96 : 11'd144;
    wire [10:0] text_width = custom_v ? {text_len_v,4'b0000} : preset_text_width;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_count <= 6'd0;
            flow_phase  <= 6'd0;
            hour_t      <= 4'd0;
            hour_u      <= 4'd0;
            min_t       <= 4'd0;
            min_u       <= 4'd0;
            sec_t       <= 4'd0;
            sec_u       <= 4'd0;
            scroll_x    <= 11'd0;
            ui_last     <= 1'b0;
        end else if (frame_tick) begin
            flow_phase <= flow_phase + 6'd1;
            if (frame_count == 6'd59) begin
                frame_count <= 6'd0;
                if ((sec_t == 4'd5) && (sec_u == 4'd9)) begin
                    sec_t <= 4'd0;
                    sec_u <= 4'd0;
                    if ((min_t == 4'd5) && (min_u == 4'd9)) begin
                        min_t <= 4'd0;
                        min_u <= 4'd0;
                        if ((hour_t == 4'd2) && (hour_u == 4'd3)) begin
                            hour_t <= 4'd0;
                            hour_u <= 4'd0;
                        end else if (hour_u == 4'd9) begin
                            hour_u <= 4'd0;
                            hour_t <= hour_t + 4'd1;
                        end else begin
                            hour_u <= hour_u + 4'd1;
                        end
                    end else if (min_u == 4'd9) begin
                        min_u <= 4'd0;
                        min_t <= min_t + 4'd1;
                    end else begin
                        min_u <= min_u + 4'd1;
                    end
                end else if (sec_u == 4'd9) begin
                    sec_u <= 4'd0;
                    sec_t <= sec_t + 4'd1;
                end else begin
                    sec_u <= sec_u + 4'd1;
                end
            end else begin
                frame_count <= frame_count + 6'd1;
            end

            // UART或按键更新字幕时复位滚动位置，使新内容立即从起点进入画面。
            if (ui_v != ui_last) begin
                ui_last  <= ui_v;
                scroll_x <= 11'd0;
            end else if (scroll_x >= (11'd640 + text_width - 11'd1))
                scroll_x <= 11'd0;
            else
                scroll_x <= scroll_x + 11'd1;
        end
    end

    function [7:0] ascii_digit_id;
        input [3:0] d;
        begin ascii_digit_id = d + 8'd1; end
    endfunction

    function [7:0] text_glyph;
        input       select_text;
        input [3:0] index;
        begin
            text_glyph = G_SPACE;
            if (!select_text) begin
                case (index)
                    4'd0: text_glyph = 8'd32; // 这
                    4'd1: text_glyph = 8'd33; // 是
                    4'd2: text_glyph = 8'd34; // 一
                    4'd3: text_glyph = 8'd35; // 个
                    4'd4: text_glyph = 8'd36; // 多
                    4'd5: text_glyph = 8'd37; // 媒
                    4'd6: text_glyph = 8'd38; // 体
                    4'd7: text_glyph = 8'd39; // 系
                    default: text_glyph = 8'd40; // 统
                endcase
            end else begin
                case (index)
                    4'd0: text_glyph = 8'd41; // 安
                    4'd1: text_glyph = 8'd42; // 路
                    4'd2: text_glyph = 8'd43; // 图
                    4'd3: text_glyph = 8'd44; // 像
                    4'd4: text_glyph = 8'd45; // 处
                    default: text_glyph = 8'd46; // 理
                endcase
            end
        end
    endfunction

    // Brightness/contrast use the displayed 0..63 values directly.  A native
    // 9x7 signed multiply maps to the device DSP fabric; this shortens the
    // pixel path substantially and uses otherwise-idle dedicated resources.
    function [7:0] clamp8;
        input integer value;
        begin
            if (value < 0) clamp8 = 8'd0;
            else if (value > 255) clamp8 = 8'd255;
            else clamp8 = value[7:0];
        end
    endfunction

    function [7:0] adjust_channel;
        input [7:0] channel;
        input [5:0] bright_level;
        input [5:0] contrast_level;
        input [6:0] ambient_offset;
        reg signed [7:0] centered_s;
        reg signed [6:0] contrast_s;
        reg signed [15:0] contrast_product_s;
        reg signed [10:0] correction_s;
        reg signed [10:0] value_s;
        reg signed [8:0] light_offset_s;
        begin
            centered_s = $signed({~channel[7],channel[6:0]});
            contrast_s = {1'b0,contrast_level};
            contrast_product_s = centered_s * contrast_s;
            // Keep every operand signed: an unsigned channel in the same
            // expression otherwise turns a negative arithmetic shift positive.
            // Legal range is -253..443, so 11 bits cover all intermediate sums.
            correction_s = contrast_product_s >>> 6;
            light_offset_s = $signed({3'b000,bright_level}) - $signed({2'b00,ambient_offset});
            value_s = ($signed({3'b000,channel}) + correction_s) + light_offset_s;
            if (value_s < 0) adjust_channel = 8'd0;
            else if (value_s > 255) adjust_channel = 8'd255;
            else adjust_channel = value_s[7:0];
        end
    endfunction

    reg [7:0] rgb_bc_r, rgb_bc_g, rgb_bc_b;
    // Pipeline cut: pixel correction and edge/transition are separate cycles.
    // Delay the complete timing tuple, so pixel coordinates remain aligned.

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rgb_bc_r<=0; rgb_bc_g<=0; rgb_bc_b<=0;
            hs_i<=0; vs_i<=0; de_i<=0;
        end else begin
            rgb_bc_r<=adjust_channel(rgb_i_src[23:16], bright_v, contrast_v, 7'd0);
            rgb_bc_g<=adjust_channel(rgb_i_src[15:8], bright_v, contrast_v, 7'd0);
            rgb_bc_b<=adjust_channel(rgb_i_src[7:0], bright_v, contrast_v, 7'd0);
            hs_i<=hs_i_src; vs_i<=vs_i_src; de_i<=de_i_src;
        end
    end
    wire [9:0] luma_cur = {2'b0, (rgb_bc_r >> 2)} +
                          {2'b0, (rgb_bc_g >> 1)} +
                          {2'b0, (rgb_bc_b >> 4)};

    // 当前像素与左邻点、上一行同列亮度做梯度比较。原图颜色保持不变，
    // 仅在超过阈值的边缘像素叠加青色，形成轮廓与原图融合效果。
    // 调试记录：整帧卷积会超出当前器件资源预算，单行梯度在清晰度和资源之间更稳定。
    reg [7:0] luma_line [0:H_ACTIVE-1];
    reg [7:0] luma_left;
    wire [7:0] luma_up = luma_line[x_pos];
    wire [7:0] luma_left_now = (x_pos == 0) ? luma_cur[7:0] : luma_left;
    wire [9:0] diff_up = (luma_cur[7:0] >= luma_up) ?
                         (luma_cur[7:0] - luma_up) : (luma_up - luma_cur[7:0]);
    wire [9:0] diff_left = (luma_cur[7:0] >= luma_left_now) ?
                           (luma_cur[7:0] - luma_left_now) : (luma_left_now - luma_cur[7:0]);
    wire [10:0] edge_mag = diff_up + diff_left;
    wire edge_on = (x_pos != 0) && (y_pos != 0) && (edge_mag > 11'd24);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            luma_left <= 8'd0;
        end else if (de_i) begin
            luma_line[x_pos] <= luma_cur[7:0];
            luma_left <= luma_cur[7:0];
        end else if (de_d) begin
            luma_left <= 8'd0;
        end
    end

    function [7:0] edge_mix;
        input [7:0] channel;
        input [7:0] add_value;
        integer value;
        begin
            value = (channel >> 1) + add_value;
            edge_mix = clamp8(value);
        end
    endfunction

    // E/e cycles: original -> fused cyan contour -> neon contour -> monochrome outline.
    reg [23:0] rgb_edge;
    always @(*) begin
        case (edge_v)
            2'd0: rgb_edge = {rgb_bc_r, rgb_bc_g, rgb_bc_b};
            2'd1: rgb_edge = edge_on ? {edge_mix(rgb_bc_r,8'd0),edge_mix(rgb_bc_g,8'd28),edge_mix(rgb_bc_b,8'd64)} : {rgb_bc_r,rgb_bc_g,rgb_bc_b};
            2'd2: rgb_edge = edge_on ? 24'h00f4ff : {rgb_bc_r >> 1, rgb_bc_g >> 1, rgb_bc_b >> 1};
            default: rgb_edge = edge_on ? 24'hffffff : 24'h000000;
        endcase
    end

    function [7:0] fade_channel;
        input [7:0] channel;
        input [5:0] level;
        reg [4:0] alpha;
        reg [12:0] product;
        begin
            alpha = (level > 31) ? 5'd31 : level[4:0];
            product = channel * alpha;
            fade_channel = product[12:5];
        end
    endfunction

    reg [23:0] rgb_transition;
    integer slide_limit;
    always @(*) begin
        rgb_transition = rgb_edge;
        slide_limit = H_ACTIVE - ((effect_count + 1) * 20);
        if (effect_active) begin
            case (effect_mode)
                2'd1: begin // vertical blinds, repeated 64-pixel slats
                    if (x_pos[5:0] >= ((effect_count + 1) << 1))
                        rgb_transition = 24'd0;
                end
                2'd2: begin // fade in from black
                    rgb_transition = {
                        fade_channel(rgb_edge[23:16], effect_count),
                        fade_channel(rgb_edge[15:8],  effect_count),
                        fade_channel(rgb_edge[7:0],   effect_count)
                    };
                end
                2'd3: begin // slide in from the right
                    if (x_pos < slide_limit)
                        rgb_transition = 24'd0;
                end
                default: rgb_transition = rgb_edge;
            endcase
        end
    end

    // Top-right Anlogic logo.  Keep it below the clock so both remain visible.
    // ROM is read, so transparent pixels leave the video unchanged.
    wire logo_enable = de_i && (x_pos >= 11'd504) && (x_pos < 11'd632) &&
                       (y_pos >= 10'd32) && (y_pos < 10'd128);
    wire [6:0] logo_x = x_pos - 11'd504;
    wire [6:0] logo_y = y_pos - 10'd32;
    wire [1:0] logo_pixel;
    mm_logo_rom u_logo_rom(
        .clk(clk),
        .enable (logo_enable),
        .x      (logo_x),
        .y      (logo_y),
        .pixel  (logo_pixel)
    );

    wire [23:0] audio_bar_color;
    wire [2:0] audio_coverage;
    wire audio_dot_off=1'b0;
    wire audio_bar_on=(audio_coverage!=0);
    wire audio_peak_on,audio_spark_on;
    mm_fire_spectrum u_fire(
        .clk(clk),.rst(rst),.frame_tick(frame_tick),.x(x_pos),.y(y_pos),
        .bars(audio_bars_i),.phase(flow_phase),.style(mode_v),
        .color(audio_bar_color),.coverage(audio_coverage),
        .peak_on(audio_peak_on),.spark_on(audio_spark_on));
    reg       gauge_outline_on;
    reg       gauge_fill_on;
    reg [23:0] gauge_color;
    always @(*) begin
        gauge_outline_on=0;gauge_fill_on=0;gauge_color=24'h00eaff;

        // Eight cells correspond to 0..63. Strict '<' makes level zero light
        // 数值0不点亮任何格，数值与图形从同一6位控制量计算。
        if ((y_pos >= 10'd144) && (y_pos < 10'd208)) begin
            if ((x_pos >= 11'd8) && (x_pos < 11'd30)) begin
                if ((x_pos == 11'd8) || (x_pos == 11'd29) || (y_pos[2:0] == 3'd0))
                    gauge_outline_on = 1'b1;
                if ((x_pos >= 11'd11) && (x_pos < 11'd27) &&
                    (y_pos[2:0] >= 3'd2) &&
                    ((7-((y_pos-10'd144)>>3)) < ((bright_v+6'd7)>>3))) begin
                    gauge_fill_on = 1'b1; gauge_color = 24'h40d8ff;
                end
            end
            if ((x_pos >= 11'd610) && (x_pos < 11'd632)) begin
                if ((x_pos == 11'd610) || (x_pos == 11'd631) || (y_pos[2:0] == 3'd0))
                    gauge_outline_on = 1'b1;
                if ((x_pos >= 11'd613) && (x_pos < 11'd629) &&
                    (y_pos[2:0] >= 3'd2) &&
                    ((7-((y_pos-10'd144)>>3)) < ((contrast_v+6'd7)>>3))) begin
                    gauge_fill_on = 1'b1; gauge_color = 24'hff4f86;
                end
            end
        end
    end

    reg [7:0] font_id;
    reg [3:0] font_row;
    reg [3:0] font_col;
    reg       font_active;
    reg [23:0] font_color;
    integer   slot;
    integer   text_pos_i;
    reg [3:0] value_hundreds, value_tens, value_ones;
    // Only 0..255 is displayed. Share one bounded decimal conversion between
    // LGT and VOL instead of synthesizing 32-bit division/multiplication.
    function [11:0] decimal_digits;
        input [7:0] value;
        reg [7:0] remainder;
        reg [3:0] hundreds, tens, ones;
        begin
            if(value>=200) begin hundreds=2; remainder=value-8'd200; end
            else if(value>=100) begin hundreds=1; remainder=value-8'd100; end
            else begin hundreds=0; remainder=value; end
            if(remainder>=90) begin tens=9; ones=remainder-8'd90; end
            else if(remainder>=80) begin tens=8; ones=remainder-8'd80; end
            else if(remainder>=70) begin tens=7; ones=remainder-8'd70; end
            else if(remainder>=60) begin tens=6; ones=remainder-8'd60; end
            else if(remainder>=50) begin tens=5; ones=remainder-8'd50; end
            else if(remainder>=40) begin tens=4; ones=remainder-8'd40; end
            else if(remainder>=30) begin tens=3; ones=remainder-8'd30; end
            else if(remainder>=20) begin tens=2; ones=remainder-8'd20; end
            else if(remainder>=10) begin tens=1; ones=remainder-8'd10; end
            else begin tens=0; ones=remainder[3:0]; end
            decimal_digits={hundreds,tens,ones};
        end
    endfunction
    wire [7:0] decimal_input=(y_pos<10'd64)?ambient_darkness_v:audio_volume_i;
    wire [11:0] decimal_value=decimal_digits(decimal_input);

    function [7:0] letter_id;
        input [7:0] ch;
        begin
            if ((ch >= "A") && (ch <= "M")) letter_id = (ch-"A")+8'd19;
            else if ((ch >= "N") && (ch <= "Z")) letter_id = (ch-"N")+8'd47;
            else letter_id = G_SPACE;
        end
    endfunction

    function [3:0] tens63;
        input [5:0] value;
        begin
            if(value>=60)tens63=6; else if(value>=50)tens63=5; else if(value>=40)tens63=4;
            else if(value>=30)tens63=3; else if(value>=20)tens63=2; else if(value>=10)tens63=1;
            else tens63=0;
        end
    endfunction

    // All small OSD fields use the same 16x16 font ROM. Text layout is fixed
    // to 640x480 so it has no additional line buffer or frame memory.
    always @(*) begin
        font_id     = G_SPACE;
        font_row    = 4'd0;
        font_col    = 4'd0;
        font_active = 1'b0;
        font_color  = 24'hffd400;
        slot        = 0;
        text_pos_i  = 0;
        value_hundreds = 0;
        value_tens = 0;
        value_ones = 0;

        if ((y_pos >= 10'd28) && (y_pos < 10'd44) &&
            (x_pos >= 11'd336) && (x_pos < 11'd400) && ambient_valid_v) begin
            font_active=1'b1; font_color=24'h50e080;
            font_row=y_pos-10'd28; slot=(x_pos-11'd336)>>4; font_col=(x_pos-11'd336)&15;
            case(slot)
              0:font_id=letter_id("A"); 1:font_id=letter_id("U");
              2:font_id=letter_id("T"); default:font_id=letter_id("O");
            endcase
        end else if ((y_pos >= 10'd48) && (y_pos < 10'd64) &&
            (x_pos >= 11'd208) && (x_pos < 11'd336)) begin
            font_active=1'b1; font_color=audio_demo_v?24'hffb030:24'h20ffb0;
            font_row=y_pos-10'd48; slot=(x_pos-11'd208)>>4; font_col=(x_pos-11'd208)&15;
            case(slot)
                0:font_id=letter_id("A");1:font_id=letter_id("U");2:font_id=letter_id("D");
                3:font_id=G_COLON;
                4:font_id=audio_demo_v?letter_id("T"):letter_id("E");
                5:font_id=audio_demo_v?letter_id("E"):letter_id("X");
                6:font_id=audio_demo_v?letter_id("S"):letter_id("T");
                7:font_id=audio_demo_v?letter_id("T"):G_SPACE;
                default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd8) && (y_pos < 10'd24) &&
            (x_pos >= 11'd504) && (x_pos < 11'd632)) begin
            font_active = 1'b1;
            font_color  = 24'hff8800;
            font_row    = y_pos - 10'd8;
            slot        = (x_pos - 11'd504) >> 4;
            font_col    = (x_pos - 11'd504) & 15;
            case (slot)
                0: font_id = ascii_digit_id(hour_t);
                1: font_id = ascii_digit_id(hour_u);
                2: font_id = G_COLON;
                3: font_id = ascii_digit_id(min_t);
                4: font_id = ascii_digit_id(min_u);
                5: font_id = G_COLON;
                6: font_id = ascii_digit_id(sec_t);
                default: font_id = ascii_digit_id(sec_u);
            endcase
        end else if ((y_pos >= 10'd8) && (y_pos < 10'd24) &&
                     (x_pos >= 11'd208) && (x_pos < 11'd304)) begin
            font_active=1'b1; font_color=gesture_error_v?24'hff3030:24'h00b85a;
            font_row=y_pos-10'd8; slot=(x_pos-11'd208)>>4; font_col=(x_pos-11'd208)&15;
            case(slot)
                0:font_id=letter_id("G"); 1:font_id=letter_id("E");
                2:font_id=letter_id("S"); 3:font_id=G_COLON;
                4:font_id=gesture_error_v?letter_id("E"):ascii_digit_id(gesture_ready_v?((gesture_code_v==3)?4'd1:((gesture_code_v==4)?4'd2:((gesture_code_v==8)?4'd3:((gesture_code_v==7)?4'd4:((gesture_code_v==1)?4'd5:4'd0))))):4'd0);
                default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd28) && (y_pos < 10'd44) &&
                     (x_pos >= 11'd208) && (x_pos < 11'd336)) begin
            {value_hundreds,value_tens,value_ones}=decimal_value;
            font_active=1'b1; font_color=24'hff7a00;
            font_row=y_pos-10'd28; slot=(x_pos-11'd208)>>4; font_col=(x_pos-11'd208)&15;
            case(slot)
                0:font_id=letter_id("L"); 1:font_id=letter_id("G");
                2:font_id=letter_id("T"); 3:font_id=G_COLON;
                4:font_id=ascii_digit_id(ambient_valid_v?value_hundreds:0);
                5:font_id=ascii_digit_id(ambient_valid_v?value_tens:0);
                6:font_id=ascii_digit_id(ambient_valid_v?value_ones:0);
                default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd8) && (y_pos < 10'd24) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd152)) begin
            font_active = 1'b1;
            font_row    = y_pos - 10'd8;
            slot        = (x_pos - 11'd8) >> 4;
            font_col    = (x_pos - 11'd8) & 15;
            case (slot)
                0:font_id=letter_id("B"); 1:font_id=letter_id("R"); 2:font_id=letter_id("T");
                3:font_id=G_COLON; 4:font_id=ascii_digit_id(tens63(bright_v));
                5:font_id=ascii_digit_id(bright_v-(tens63(bright_v)*10));
                6:font_id=8'd62; 7:font_id=ascii_digit_id(6); default:font_id=ascii_digit_id(3);
            endcase
        end else if ((y_pos >= 10'd28) && (y_pos < 10'd44) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd152)) begin
            font_active = 1'b1;
            font_row=y_pos-10'd28; slot=(x_pos-11'd8)>>4; font_col=(x_pos-11'd8)&15;
            case(slot)
                0:font_id=letter_id("C"); 1:font_id=letter_id("O"); 2:font_id=letter_id("N");
                3:font_id=G_COLON; 4:font_id=ascii_digit_id(tens63(contrast_v));
                5:font_id=ascii_digit_id(contrast_v-(tens63(contrast_v)*10));
                6:font_id=8'd62; 7:font_id=ascii_digit_id(6); default:font_id=ascii_digit_id(3);
            endcase
        end else if ((y_pos >= 10'd48) && (y_pos < 10'd64) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd168)) begin
            font_active = 1'b1;
            font_row=y_pos-10'd48; slot=(x_pos-11'd8)>>4; font_col=(x_pos-11'd8)&15;
            case(slot)
                0:font_id=letter_id("Z");1:font_id=letter_id("O");2:font_id=letter_id("O");3:font_id=letter_id("M");4:font_id=G_COLON;
                5:font_id=ascii_digit_id((zoom_v==1)?0:1);
                6:font_id=ascii_digit_id((zoom_v==0)?0:((zoom_v==1)?7:((zoom_v==2)?2:5)));
                7:font_id=ascii_digit_id((zoom_v==0)?0:((zoom_v==1)?5:((zoom_v==2)?5:0)));
                8:font_id=8'd61; default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd68) && (y_pos < 10'd84) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd184)) begin
            font_active=1'b1; font_row=y_pos-10'd68; slot=(x_pos-11'd8)>>4; font_col=(x_pos-11'd8)&15;
            case(slot)
                0:font_id=letter_id("S");1:font_id=letter_id("R");2:font_id=letter_id("C");3:font_id=G_COLON;
                4:font_id=ascii_digit_id((zoom_v==0)?6:((zoom_v==1)?4:((zoom_v==2)?5:4)));
                5:font_id=ascii_digit_id((zoom_v==0)?4:((zoom_v==1)?8:((zoom_v==2)?1:2)));
                6:font_id=ascii_digit_id((zoom_v==3)?6:((zoom_v==2)?2:0));
                7:font_id=G_X;
                8:font_id=ascii_digit_id((zoom_v==0)?4:3);
                9:font_id=ascii_digit_id((zoom_v==0)?8:((zoom_v==1)?6:((zoom_v==2)?8:2)));
                default:font_id=ascii_digit_id((zoom_v==2)?4:0);
            endcase
        end else if ((y_pos >= 10'd88) && (y_pos < 10'd104) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd136)) begin
            font_active=1'b1; font_row=y_pos-10'd88; slot=(x_pos-11'd8)>>4; font_col=(x_pos-11'd8)&15;
            case(slot)
                0:font_id=letter_id("A");1:font_id=letter_id("D");2:font_id=letter_id("J");3:font_id=G_COLON;
                4:font_id=adjust_v?letter_id("C"):letter_id("B");
                5:font_id=adjust_v?letter_id("O"):letter_id("R");
                6:font_id=adjust_v?letter_id("N"):letter_id("T");
                default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd112) && (y_pos < 10'd128) &&
                     (x_pos >= 11'd8) && (x_pos < 11'd136)) begin
            {value_hundreds,value_tens,value_ones}=decimal_value;
            font_active=1'b1; font_color=24'hff5a00; font_row=y_pos-10'd112;
            slot=(x_pos-11'd8)>>4; font_col=(x_pos-11'd8)&15;
            case(slot)
                0:font_id=letter_id("V");1:font_id=letter_id("O");2:font_id=letter_id("L");3:font_id=G_COLON;
                4:font_id=ascii_digit_id(value_hundreds);5:font_id=ascii_digit_id(value_tens);
                6:font_id=ascii_digit_id(value_ones); default:font_id=G_SPACE;
            endcase
        end else if ((y_pos >= 10'd448) && (y_pos < 10'd464)) begin
            text_pos_i = x_pos + text_width - scroll_x;
            if ((text_pos_i >= 0) && (text_pos_i < text_width)) begin
                font_active = 1'b1;
                // 字幕使用高饱和深橙色，保证在地图和轮廓背景上保持对比度。
                font_color  = entry_v ? 24'hff3d00 : caption_ink;
                font_row    = y_pos - 10'd448;
                font_col    = text_pos_i & 15;
                if (custom_v)
                    font_id = text_glyphs_v[((text_pos_i>>4)*8) +: 8];
                else
                    font_id = text_glyph(text_v, text_pos_i >> 4);
            end
        end
    end

    // SD-card GBK font cache.  The SD domain holds write address/data stable
    // around the toggle; the video domain synchronizes that event and writes
    // one 16-pixel row.  32 caption slots x 16 rows = 512 words.
    wire [15:0] font_bits_rom, font_bits_dynamic;
    generate if (ENABLE_DYNAMIC_FONT) begin: optional_font_cache
    reg [15:0] dynamic_font_rows [0:511];
    reg [2:0] font_wr_toggle_sync;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            font_wr_toggle_sync <= 3'b000;
        end else begin
            font_wr_toggle_sync <= {font_wr_toggle_sync[1:0],font_row_write_toggle_i};
            if (font_wr_toggle_sync[2] != font_wr_toggle_sync[1])
                dynamic_font_rows[font_row_write_addr_i] <= font_row_write_data_i;
        end
    end

    reg [15:0] dynamic_read;
    always @(posedge clk) dynamic_read<=dynamic_font_rows[{font_id[4:0],font_row}];
    assign font_bits_dynamic=dynamic_read;
    end else begin: fixed_caption_font
        assign font_bits_dynamic=16'd0;
    end endgenerate
    reg font_active_stage,font_bold_stage,font_dynamic_stage;
    reg [3:0] font_col_stage;
    always @(posedge clk or posedge rst) begin
        if(rst)begin font_active_stage<=0;font_bold_stage<=0;font_dynamic_stage<=0;font_col_stage<=0;end
        else begin font_active_stage<=font_active;font_bold_stage<=(x_pos<184 && y_pos<104);
            font_dynamic_stage<=(font_id>=96 && font_id<128);font_col_stage<=font_col;end
    end
    wire [15:0] font_bits=font_dynamic_stage?font_bits_dynamic:font_bits_rom;
    wire [15:0] font_bits_bold=font_bits | (font_bits<<1) | (font_bits>>1);
    wire font_bit_stage=font_active_stage && (font_bold_stage?font_bits_bold[15-font_col_stage]:font_bits[15-font_col_stage]);
    mm_font16_rom u_font_rom(
        .clk(clk),
        .glyph_id (font_id),
        .row      (font_row),
        .row_bits (font_bits_rom)
    );

    // A light horizontal two-tap filter is enabled only during Z scaling.  It
    // blends duplicated/skipped nearest-neighbour samples without adding a
    // full-frame buffer or touching the 100% picture path.
    reg [23:0] zoom_filter_left;
    wire [8:0] zoom_sum_r = {1'b0,rgb_transition[23:16]} + {1'b0,zoom_filter_left[23:16]};
    wire [8:0] zoom_sum_g = {1'b0,rgb_transition[15:8]}  + {1'b0,zoom_filter_left[15:8]};
    wire [8:0] zoom_sum_b = {1'b0,rgb_transition[7:0]}   + {1'b0,zoom_filter_left[7:0]};
    wire [23:0] rgb_zoom_smooth = ((zoom_v != 2'd0) && (x_pos != 0)) ?
                                  {zoom_sum_r[8:1],zoom_sum_g[8:1],zoom_sum_b[8:1]} : rgb_transition;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            zoom_filter_left <= 24'd0;
        end else if (de_i) begin
            zoom_filter_left <= rgb_transition;
        end else if (de_d) begin
            zoom_filter_left <= 24'd0;
        end
    end

    // Pipeline the expensive overlay decisions before the final color mux.
    // All members of the video tuple advance together, so this adds only one
    // fixed pixel of latency and does not change any visible feature.
    reg [2:0] audio_coverage_stage;
    reg alarm_frame,alarm_stage,alarm_panel_stage,alarm_ink_stage,alarm_border_stage;
    reg [1:0] alarm_reason_frame;
    wire alarm_ink,alarm_headline;
    wire [1:0] alarm_icon;
    reg [1:0] alarm_icon_stage;
    wire locator_hit;
    wire [23:0] locator_color;
    reg locator_hit_stage;
    reg [23:0] locator_color_stage;
    reg alarm_pulse_frame,alarm_pulse_stage;
    reg [31:0] alarm_time_frame;
    mm_alarm_icon u_alarm_icon(.x(x_pos),.y(y_pos),.pixel(alarm_icon));
    mm_alarm_locator u_alarm_locator(.x(x_pos),.y(y_pos),.alarm_active(alarm_frame),
      .audio_alarm(alarm_reason_frame[0]),.peak(volume_peak_i),.zoom_v(zoom_v),
      .clk(clk),.rst(rst),.hit(locator_hit),.color(locator_color));
    reg alarm_headline_stage;
    mm_alarm_headline u_alarm_headline(.x(x_pos),.y(y_pos),.pixel(alarm_headline));
    mm_alarm_glyphs u_alarm_glyphs(.x(x_pos),.y(y_pos),.reasons(alarm_reason_frame),
      .darkness(ambient_darkness_v),.valid(ambient_valid_v),.timestamp_ms(alarm_time_frame),.pixel(alarm_ink));
    always @(posedge clk or posedge rst)begin
     if(rst)begin alarm_frame<=0;alarm_reason_frame<=0;alarm_stage<=0;
      alarm_time_frame<=0;alarm_pulse_frame<=0;alarm_pulse_stage<=0;alarm_icon_stage<=0;alarm_panel_stage<=0;alarm_ink_stage<=0;alarm_border_stage<=0;alarm_headline_stage<=0;locator_hit_stage<=0;locator_color_stage<=0;end
     else begin
      if(frame_tick)begin alarm_frame<=alarm_active_i;alarm_reason_frame<=alarm_reasons_i;alarm_pulse_frame<=alarm_blink_i;alarm_time_frame<=alarm_uptime_i;end
      alarm_pulse_stage<=alarm_pulse_frame;alarm_icon_stage<=alarm_icon;
      locator_hit_stage<=locator_hit;locator_color_stage<=locator_color;
      alarm_stage<=alarm_frame;
      alarm_panel_stage<=(y_pos>=444);
      alarm_ink_stage<=alarm_ink;
      alarm_headline_stage<=alarm_headline;
      alarm_border_stage<=alarm_blink_i && (x_pos<5 || x_pos>=635 || y_pos<5 || y_pos>=475);
     end
    end
    reg [23:0] rgb_base_stage;
    reg [23:0] audio_bar_color_stage, gauge_color_stage, font_color_stage;
    reg hs_stage, vs_stage, de_stage;
    reg left_status_stage, caption_panel_stage, caption_border_stage;
    reg audio_dot_stage, audio_bar_stage, audio_peak_stage, audio_spark_stage;
    reg gauge_outline_stage, gauge_fill_stage;
    wire logo_blue_stage=(logo_pixel==2'b01);
    wire logo_red_stage=(logo_pixel==2'b10);
    // Color payload is unconditionally pipelined. It needs no asynchronous
    // reset: audio_bar_stage and de_stage qualify it and are cleared by reset.
    // 无需额外的高扇出复位端点，不改变可见数据、有效时序与流水延迟。
    always @(posedge clk) audio_bar_color_stage <= audio_bar_color;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            audio_coverage_stage <= 3'd0;
            rgb_base_stage       <= 24'd0;
            gauge_color_stage    <= 24'd0;
            font_color_stage     <= 24'd0;
            hs_stage             <= 1'b0;
            vs_stage             <= 1'b0;
            de_stage             <= 1'b0;
            left_status_stage    <= 1'b0;
            caption_panel_stage  <= 1'b0;
            caption_border_stage <= 1'b0;
            audio_dot_stage      <= 1'b0;
            audio_bar_stage      <= 1'b0;
            audio_peak_stage     <= 1'b0;
            audio_spark_stage    <= 1'b0;
            gauge_outline_stage  <= 1'b0;
            gauge_fill_stage     <= 1'b0;



        end else begin
            audio_coverage_stage <= audio_coverage;
            rgb_base_stage        <= rgb_zoom_smooth;
            gauge_color_stage     <= gauge_color;
            font_color_stage      <= font_color;
            hs_stage              <= hs_i;
            vs_stage              <= vs_i;
            de_stage              <= de_i;
            left_status_stage     <= (x_pos >= 11'd4) && (x_pos < 11'd188) &&
                                     (y_pos >= 10'd4) && (y_pos < 10'd108);
            caption_panel_stage   <= (y_pos >= 10'd444) && (y_pos < 10'd468);
            caption_border_stage  <= ((y_pos >= 10'd444) && (y_pos < 10'd446)) ||
                                     ((y_pos >= 10'd466) && (y_pos < 10'd468)) ||
                                     (((x_pos < 11'd2) || (x_pos >= 11'd638)) &&
                                      (y_pos >= 10'd444) && (y_pos < 10'd468));
            audio_dot_stage       <= audio_dot_off;
            audio_bar_stage       <= audio_bar_on;
            audio_peak_stage      <= audio_peak_on;
            audio_spark_stage     <= audio_spark_on;
            gauge_outline_stage   <= gauge_outline_on;
            gauge_fill_stage      <= gauge_fill_on;
            
            
            
        end
    end

    function [7:0] blend_coverage;
        input [7:0] background,foreground;
        input [2:0] alpha;
        reg [10:0] total;
        begin
            case(alpha)
                0:total={1'b0,background,2'b0};
                1:total={3'b0,background}+{2'b0,background,1'b0}+{3'b0,foreground};
                2:total={2'b0,background,1'b0}+{2'b0,foreground,1'b0};
                3:total={3'b0,background}+{3'b0,foreground}+{2'b0,foreground,1'b0};
                default:total={1'b0,foreground,2'b0};
            endcase
            blend_coverage=total[9:2];
        end
    endfunction
    reg [23:0] rgb_next;
    always @(*) begin
        rgb_next = rgb_base_stage;
        if (!de_stage) begin
            rgb_next = 24'd0;
        end else begin
            // 告警只做颜色覆盖，底图仍来自相同RGB流水线。亮相R/2+128、G/B/2；暗相各通道/4。
            if(alarm_stage)begin
                if(alarm_pulse_stage)rgb_next={1'b1,rgb_base_stage[23:17],1'b0,rgb_base_stage[15:9],1'b0,rgb_base_stage[7:1]};
                else rgb_next={2'b0,rgb_base_stage[23:18],2'b0,rgb_base_stage[15:10],2'b0,rgb_base_stage[7:2]};
            end
            // High-contrast backing keeps the left status text continuous and
            // readable on bright photos; yellow glyphs replace the pale cyan.
            if (!alarm_stage && left_status_stage)
                rgb_next = {rgb_base_stage[23:18],2'b00,
                            rgb_base_stage[15:10],2'b00,
                            rgb_base_stage[7:2],2'b00};

            // Dark translucent strip behind the scrolling caption.  Its top
            // edge begins exactly one line below the spectrum baseline.
            if (!alarm_stage && caption_panel_stage)
                rgb_next = {rgb_base_stage[23:18],2'b00,
                            rgb_base_stage[15:10],2'b00,
                            rgb_base_stage[7:2],2'b00};

            // Saturated orange frame makes the caption readable on both dark
            // and bright pictures.  The top border is the spectrum's bottom
            // edge; the lower border remains clear of the 16-pixel glyphs.
            if (!alarm_stage && caption_border_stage)
                rgb_next = entry_v ? 24'hff3d00 : caption_ink;

            // No opaque spectrum panel: LEDs are overlaid directly on the image.
            if (audio_dot_stage)
                rgb_next = {rgb_next[23:17],1'b0,rgb_next[15:9],1'b0,rgb_next[7:1],1'b0};
            if (audio_bar_stage)
                rgb_next={blend_coverage(rgb_next[23:16],audio_bar_color_stage[23:16],audio_coverage_stage),
                          blend_coverage(rgb_next[15:8],audio_bar_color_stage[15:8],audio_coverage_stage),
                          blend_coverage(rgb_next[7:0],audio_bar_color_stage[7:0],audio_coverage_stage)};
            if(audio_peak_stage) rgb_next=24'hff6010;
            if(audio_spark_stage) rgb_next=24'hffb020;

            if (!alarm_stage && gauge_outline_stage)
                rgb_next = 24'hd8f5ff;
            if (!alarm_stage && gauge_fill_stage)
                rgb_next = gauge_color_stage;

            if (!alarm_stage && logo_blue_stage)
                rgb_next = 24'h0b2b75;
            else if (!alarm_stage && logo_red_stage)
                rgb_next = 24'hec2634;

            if (!alarm_stage && font_bit_stage)
                rgb_next = font_color_stage;
            if(alarm_stage)begin
                if(alarm_panel_stage)rgb_next=24'h100000;
                if(alarm_ink_stage)rgb_next=24'hffdd99;
                // 大感叹号调淡，凸显强弱指示图标
                if(alarm_icon_stage==1)rgb_next=24'hec7880;
                if(alarm_icon_stage==2)rgb_next=24'hffffff;
                // 告警强弱指示图标（叠加在最上层）
                if(locator_hit_stage)rgb_next=locator_color_stage;
            end
        end
    end

    // Target indicator stays visible above the alarm overlay.
    wire [23:0] roi_rgb_next=(roi_hit_stage && de_stage)?24'h00ffff:rgb_next;
    // Register the complete video tuple together. This isolates the HDMI
    // input from the OSD/edge/transition combinational cone and keeps RGB,
    // DE, HS and VS aligned by construction.
    reg [23:0] rgb_pipe;
    reg        hs_pipe, vs_pipe, de_pipe;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rgb_pipe <= 24'd0;
            hs_pipe  <= 1'b0;
            vs_pipe  <= 1'b0;
            de_pipe  <= 1'b0;
        end else begin
            rgb_pipe <= roi_rgb_next;
            hs_pipe  <= hs_stage;
            vs_pipe  <= vs_stage;
            de_pipe  <= de_stage;
        end
    end

    // Auto compensation is applied once, after spectrum/text/logo composition.
    // Manual BRT/CON processing is unchanged. No extra pixel-cycle latency:
    // the existing downstream register captures RGB with the existing syncs.
    function [7:0] apply_ambient_gain;
        input [7:0] channel;
        input [8:0] gain;
        reg [16:0] product;
        begin product=channel*gain+17'd128; apply_ambient_gain=product[15:8]; end
    endfunction
    assign rgb_o = {apply_ambient_gain(rgb_pipe[23:16],ambient_gain),
                    apply_ambient_gain(rgb_pipe[15:8],ambient_gain),
                    apply_ambient_gain(rgb_pipe[7:0],ambient_gain)};
    assign hs_o  = hs_pipe;
    assign vs_o  = vs_pipe;
    assign de_o  = de_pipe;
endmodule


