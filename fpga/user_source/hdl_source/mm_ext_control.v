`timescale 1ns/1ps

// 板级交互控制器：统一处理按键、拨码开关和UART命令，输出低速UI状态。
// 模式0001调亮度、0010调对比度、0100/0111调缩放、1000切轮廓、1100选字幕。
// 亮度与对比度范围为0..63，四个按键对应-20、-10、+10、+20并做饱和限制。
// UART保留1/2/E/Z、B/C和+/-命令；自定义字幕由ENABLE_CUSTOM_UART控制。
module mm_ext_control #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer ENABLE_CUSTOM_UART = 0 // 0：使用两组固定字幕；1：允许UART录入自定义字幕
)(
    input wire clk, input wire rst_n, input wire [3:0] key_press,
    input wire gesture_effect_n,
    input wire [3:0] sw, input wire uart_rx,
    output reg [1:0] transition_mode, output reg text_select,
    output reg [1:0] edge_mode, output reg [1:0] zoom_mode,
    output reg ui_update_toggle,
    output reg [5:0] brightness_level, output reg [5:0] contrast_level,
    output reg selected_adjust,
    output reg [255:0] text_glyphs, output reg [5:0] text_length,
    output reg [511:0] text_gbk_codes, output reg [31:0] text_gbk_valid,
    output reg caption_commit_toggle,
    output wire caption_palette,
    output reg text_custom_valid, output reg text_entry_mode
);
    localparam integer DEBOUNCE_CYCLES = (CLK_HZ / 1000) * DEBOUNCE_MS;
    reg key_meta, key_sync, key_stable;
    reg [20:0] key_cnt;
    reg gesture_effect_meta, gesture_effect_sync, gesture_effect_last;
    reg [3:0] sw_meta, sw_sync, sw_last;
    wire [7:0] uart_data;
    wire uart_valid;
    reg gbk_pending;
    reg [7:0] gbk_lead;

    mm_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD_HZ(115_200)) u_uart_rx (
        .clk(clk), .rst_n(rst_n), .rx_pin(uart_rx), .data(uart_data), .valid(uart_valid)
    );

    function [5:0] coarse64;
        input [1:0] value;
        begin
            case (value)
                2'd0: coarse64 = 6'd0;
                2'd1: coarse64 = 6'd21;
                2'd2: coarse64 = 6'd42;
                default: coarse64 = 6'd63;
            endcase
        end
    endfunction

    // Preserve the original OSD scale 0..63; saturate instead of wrapping.
    function [5:0] step_level;
        input [5:0] level; input [3:0] keys;
        reg signed [7:0] value; // Exact range: -20..83 before saturation.
        begin
            value=level;
            if(keys[3]) value=value+20;
            else if(keys[2]) value=value+10;
            else if(keys[1]) value=value-10;
            else if(keys[0]) value=value-20;
            if(value<0) step_level=0;
            else if(value>63) step_level=63;
            else step_level=value[5:0];
        end
    endfunction

    // Uppercase keeps the original IDs.  Lowercase has its own 64..89 range,
    // so UART captions preserve case instead of silently forcing a..z to A..Z.
    function [6:0] ascii_glyph;
        input [7:0] ch;
        begin
            if ((ch >= "0") && (ch <= "9"))
                ascii_glyph = (ch - "0") + 7'd1;
            else if (ch == ":") ascii_glyph = 7'd11;
            else if ((ch >= "A") && (ch <= "M"))
                ascii_glyph = (ch - "A") + 7'd19;
            else if ((ch >= "N") && (ch <= "Z"))
                ascii_glyph = (ch - "N") + 7'd47;
            else if ((ch >= "a") && (ch <= "z"))
                ascii_glyph = (ch - "a") + 7'd64;
            else if (ch == "-") ascii_glyph = 7'd60;
            else if (ch == "%") ascii_glyph = 7'd61;
            else if (ch == "/") ascii_glyph = 7'd62;
            else if (ch == " ") ascii_glyph = 7'd0;
            else ascii_glyph = 7'd63;
        end
    endfunction

    function [6:0] utf8_glyph;
        input [23:0] code;
        begin
            case (code)
                24'he8bf99: utf8_glyph = 6'd32; // 这
                24'he698af: utf8_glyph = 6'd33; // 是
                24'he4b880: utf8_glyph = 6'd34; // 一
                24'he4b8aa: utf8_glyph = 6'd35; // 个
                24'he5a49a: utf8_glyph = 6'd36; // 多
                24'he5aa92: utf8_glyph = 6'd37; // 媒
                24'he4bd93: utf8_glyph = 6'd38; // 体
                24'he7b3bb: utf8_glyph = 6'd39; // 系
                24'he7bb9f: utf8_glyph = 6'd40; // 统
                24'he5ae89: utf8_glyph = 6'd41; // 安
                24'he8b7af: utf8_glyph = 6'd42; // 路
                24'he59bbe: utf8_glyph = 6'd43; // 图
                24'he5838f: utf8_glyph = 6'd44; // 像
                24'he5a484: utf8_glyph = 6'd45; // 处
                24'he79086: utf8_glyph = 6'd46; // 理
                default:   utf8_glyph = 6'd63;
            endcase
        end
    endfunction

    reg [1:0] caption_group, caption_language;
    assign caption_palette=caption_group[0];
    wire [1:0] caption_next_group = key_press[3] ? ((caption_group==1)?2'd0:caption_group+2'd1) : caption_group;
    wire [1:0] caption_next_language = key_press[3] ? caption_language : (key_press[0]?2'd0:(key_press[1]?2'd1:2'd2));
    function [255:0] preset_glyphs;
      input [1:0] group_id, language_id;
      begin case ({group_id,language_id})
        4'd0:preset_glyphs=256'h000000000000000000000000000000000000000000000029f0aabba4a8b7baa9; // 方寸芯屏,守我平安
        4'd1:preset_glyphs=256'h001718133400343600192f1b3117171d00a42f171733153400351513311f3015; // COMPACT SCREEN, KEEPING US SAFE
        4'd2:preset_glyphs=256'h004445405200525400464d484f44444a00a44d4444514252005342404f4c4e42; // compact screen, keeping us safe
        4'd4:preset_glyphs=256'h0000000000000000000000000000000000000000000000b6b1a3a2c0bfb4b2ae; // 多模态感知告警系统
        4'd5:preset_glyphs=256'h001f1735343a34001f33131e1300192f1b342f1734001e1316301f1b351e361f; // MULTIMODAL SENSING ALARM SYSTEM
        4'd6:preset_glyphs=256'h004c4453525852004c51404b4000464d48524d4452004b40434e4c48534b544c; // multimodal sensing alarm system
        default:preset_glyphs=0;
      endcase end
    endfunction
    function [5:0] preset_length;
      input [1:0] group_id, language_id;
      begin case ({group_id,language_id})
        4'd0:preset_length=6'd9;
        4'd1:preset_length=6'd31;
        4'd2:preset_length=6'd31;
        4'd4:preset_length=6'd9;
        4'd5:preset_length=6'd31;
        4'd6:preset_length=6'd31;
        default:preset_length=0;
      endcase end
    endfunction
    task append_glyph;
        input [6:0] glyph;
        begin
            if (text_length < 6'd32) begin
                text_glyphs[text_length*8 +: 8] <= glyph;
                text_length <= text_length + 6'd1;
            end else begin
                text_glyphs <= {1'b0,glyph, text_glyphs[255:8]};
            end
        end
    endtask

    // Dynamic glyph IDs 96..127 address the 32-entry SD-card font cache.
    // Chinese input is GBK/GB18030 two-byte data, matching Windows terminals.
    task append_gbk;
        input [15:0] code;
        integer slot_index;
        begin
            if (text_length < 6'd32) begin
                // Constant slices infer local write enables instead of a
                // 512-bit variable part-select steering network.
                for(slot_index=0;slot_index<32;slot_index=slot_index+1)begin
                  if(text_length==slot_index)begin
                text_glyphs[slot_index*8 +: 8] <= 7'd96 + text_length[4:0];

                text_gbk_valid[slot_index] <= 1'b1;
                  end
                end
                text_length <= text_length + 6'd1;
            end
        end
    endtask

    // Printable ASCII also uses the SD font cache.  This covers every key from
    // space (0x20) through '~' (0x7e), including case and punctuation.
    task append_ascii;
        input [7:0] ch;
        integer slot_index;
        begin
            if (text_length < 6'd32) begin
                // Constant slices infer local write enables instead of a
                // 512-bit variable part-select steering network.
                for(slot_index=0;slot_index<32;slot_index=slot_index+1)begin
                  if(text_length==slot_index)begin
                text_glyphs[slot_index*8 +: 8] <= 7'd96 + text_length[4:0];

                text_gbk_valid[slot_index] <= 1'b1;
                  end
                end
                text_length <= text_length + 6'd1;
            end
        end
    endtask

    // Payload is meaningful only where text_gbk_valid is set. No reset mux
    // is needed on these512 data bits; validity is reset in the control block.
    wire cache_ascii_write=uart_valid && text_entry_mode && !uart_data[7] &&
                         uart_data>=8'h20 && uart_data<=8'h7e;
    wire cache_gbk_write=uart_valid && text_entry_mode && uart_data[7] && gbk_pending;
    wire [15:0] cache_input=cache_gbk_write?{gbk_lead,uart_data}:{8'h00,uart_data};
    genvar cache_slot;
    generate for(cache_slot=0;cache_slot<32;cache_slot=cache_slot+1)begin: cache_payload
      always @(posedge clk)
        if(rst_n && (cache_ascii_write || cache_gbk_write) && text_length==cache_slot)
          text_gbk_codes[cache_slot*16+:16]<=cache_input;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1; key_sync <= 1'b1; key_stable <= 1'b1; key_cnt <= 21'd0;
            gesture_effect_meta <= 1'b1; gesture_effect_sync <= 1'b1; gesture_effect_last <= 1'b1;
            sw_meta <= 4'd0; sw_sync <= 4'd0; sw_last <= 4'd0;
            caption_group<=0;caption_language<=0;
            transition_mode <= 2'd0; text_select <= 1'b0;
            edge_mode <= 2'd0; zoom_mode <= 2'd0; ui_update_toggle <= 1'b0;
            brightness_level <= 6'd0; contrast_level <= 6'd0; selected_adjust <= 1'b0;
            text_glyphs <= 256'h00000000000000000000000000000000a7bebcabbbbdb9b3b8a6c1ada1b5a5a0; text_length <= 6'd16;
            text_gbk_valid <= 32'd0;
            caption_commit_toggle <= 1'b0;
            text_custom_valid <= 1'b1; text_entry_mode <= 1'b0;
            gbk_pending <= 1'b0; gbk_lead <= 8'd0;
        end else begin
            gesture_effect_meta <= gesture_effect_n;
            gesture_effect_sync <= gesture_effect_meta;
            gesture_effect_last <= gesture_effect_sync;
            if ((sw==0 && key_press[2]) || (gesture_effect_last && !gesture_effect_sync)) begin
                transition_mode <= transition_mode + 2'd1;
                ui_update_toggle <= ~ui_update_toggle;
            end
            if (|key_press) begin
                ui_update_toggle <= ~ui_update_toggle;
                case(sw)
                    4'b0001: begin
                        selected_adjust<=0;
                        brightness_level<=step_level(brightness_level,key_press);
                    end
                    4'b0010: begin
                        selected_adjust<=1;
                        contrast_level<=step_level(contrast_level,key_press);
                    end
                    4'b0111, 4'b0100: begin
                        if(key_press[3]) zoom_mode<=3;
                        else if(key_press[2]) zoom_mode<=2;
                        else if(key_press[1]) zoom_mode<=0;
                        else if(key_press[0]) zoom_mode<=1;
                    end
                    4'b1000: begin
                        if(key_press[3]) edge_mode<=3;
                        else if(key_press[2]) edge_mode<=2;
                        else if(key_press[1]) edge_mode<=1;
                        else if(key_press[0]) edge_mode<=0;
                    end
                    4'b1100: begin
                        text_custom_valid<=1; text_entry_mode<=0;
                        text_gbk_valid<=0; gbk_pending<=0;
                        caption_group<=caption_next_group;
                        caption_language<=caption_next_language;
                        text_glyphs<=preset_glyphs(caption_next_group,caption_next_language);
                        text_length<=preset_length(caption_next_group,caption_next_language);
                    end
                    default:;
                endcase
            end

            if (uart_valid) begin
                if (text_entry_mode) begin
                    // CR 与 LF 都视为提交：很多串口助手/Terminal 只发 LF(0x0a)，
                    // 若只认 0x0d，T 模式会一直收不到提交，之后按 '1'/'2' 会被当成字幕字符。
                    if ((uart_data == 8'h0d) || (uart_data == 8'h0a)) begin
                        text_entry_mode <= 1'b0;
                        text_custom_valid <= (text_length != 0);
                        gbk_pending <= 1'b0;
                        caption_commit_toggle <= ~caption_commit_toggle;
                        ui_update_toggle <= ~ui_update_toggle;
                    end else if ((uart_data == 8'h08) || (uart_data == 8'h7f)) begin
                        if (text_length != 0) begin
                            text_length <= text_length - 6'd1;
                            text_glyphs[(text_length-1'b1)*8 +: 8] <= 7'd0;
                        end
                        gbk_pending <= 1'b0;
                    end else if (uart_data == 8'h1b) begin
                        text_entry_mode <= 1'b0; gbk_pending <= 1'b0;
                    end else if (!uart_data[7]) begin
                        if ((uart_data >= 8'h20) && (uart_data <= 8'h7e))
                            append_ascii(uart_data);
                        gbk_pending <= 1'b0;
                    end else if (!gbk_pending) begin
                        gbk_lead <= uart_data; gbk_pending <= 1'b1;
                    end else begin
                        append_gbk({gbk_lead,uart_data});
                        gbk_pending <= 1'b0;
                    end
                end else begin
                    case (uart_data)
                        8'h31,8'h01: begin text_select <= 1'b0; text_custom_valid <= 1'b1; caption_group<=0; caption_language<=0; text_glyphs<=preset_glyphs(0,0); text_length<=preset_length(0,0); text_gbk_valid<=0; ui_update_toggle <= ~ui_update_toggle; end
                        8'h32,8'h02: begin text_select <= 1'b1; text_custom_valid <= 1'b1; caption_group<=1; caption_language<=0; text_glyphs<=preset_glyphs(1,0); text_length<=preset_length(1,0); text_gbk_valid<=0; ui_update_toggle <= ~ui_update_toggle; end
                        8'h45,8'h65: begin edge_mode <= edge_mode + 2'd1; ui_update_toggle <= ~ui_update_toggle; end
                        8'h5a,8'h7a: begin zoom_mode <= zoom_mode + 2'd1; ui_update_toggle <= ~ui_update_toggle; end
                        8'h42,8'h62: begin selected_adjust <= 1'b0; ui_update_toggle <= ~ui_update_toggle; end
                        8'h43,8'h63: begin selected_adjust <= 1'b1; ui_update_toggle <= ~ui_update_toggle; end
                        8'h2b,8'h3d: begin
                            if (!selected_adjust && (brightness_level != 6'd63)) brightness_level <= brightness_level + 6'd1;
                            else if (selected_adjust && (contrast_level != 6'd63)) contrast_level <= contrast_level + 6'd1;
                            ui_update_toggle <= ~ui_update_toggle;
                        end
                        8'h2d,8'h5f: begin
                            if (!selected_adjust && (brightness_level != 6'd0)) brightness_level <= brightness_level - 6'd1;
                            else if (selected_adjust && (contrast_level != 6'd0)) contrast_level <= contrast_level - 6'd1;
                            ui_update_toggle <= ~ui_update_toggle;
                        end
                        8'h54,8'h74: if (ENABLE_CUSTOM_UART) begin
                            text_entry_mode <= 1'b1; text_glyphs <= 256'd0;
                            text_gbk_valid <= 32'd0;
                            text_length <= 6'd0; gbk_pending <= 1'b0;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule

