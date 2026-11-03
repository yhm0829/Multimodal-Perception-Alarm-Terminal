`timescale 1ns/1ps
// One clock read; transparency and coordinate range are aligned with ROM data.
module mm_logo_rom(input wire clk,enable,input wire[6:0]x,y,output wire[1:0]pixel);
wire[1:0]data;reg visible;always @(posedge clk) visible<=enable && y<96;
assign pixel=visible?data:2'b00;
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(2),.ADDR_WIDTH_A(14),.DATA_DEPTH_A(16384),
        .DATA_WIDTH_B(2),.ADDR_WIDTH_B(14),.DATA_DEPTH_B(16384),
        .MODE("SP"),.REGMODE_A("NOREG"),.IMPLEMENT("32K"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),
        .INIT_FILE("../../td_project/al_ip/logo_resource.mif"),.FILL_ALL("NONE")
    ) storage (
        .clka(clk),.clkb(1'b0),.cea(1'b1),.ceb(1'b0),.ocea(1'b0),.oceb(1'b0),
        .wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
        .dia(2'd0),.dib(2'd0),.addra({y,x}),.addrb(14'd0),.doa(data),.dob());
endmodule

