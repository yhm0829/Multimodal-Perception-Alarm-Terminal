`timescale 1ns/1ps
// 单时钟读出的字模 ROM，按字模行直接查表。
module mm_font16_rom(input wire clk,input wire [7:0]glyph_id,input wire[3:0]row,output wire[15:0]row_bits);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16),.ADDR_WIDTH_A(12),.DATA_DEPTH_A(4096),
        .DATA_WIDTH_B(16),.ADDR_WIDTH_B(12),.DATA_DEPTH_B(4096),
        .MODE("SP"),.REGMODE_A("NOREG"),.IMPLEMENT("32K"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),
        .INIT_FILE("../../td_project/al_ip/font_resource.mif"),.FILL_ALL("NONE")
    ) storage (
        .clka(clk),.clkb(1'b0),.cea(1'b1),.ceb(1'b0),.ocea(1'b0),.oceb(1'b0),
        .wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
        .dia(16'd0),.dib(16'd0),.addra({glyph_id,row}),.addrb(12'd0),.doa(row_bits),.dob());
endmodule

