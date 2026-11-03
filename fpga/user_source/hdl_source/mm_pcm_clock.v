`timescale 1ns/1ps
// Two remaining PLLs: 50/5*64/25 =25.6 MHz; 25.6/5*120/50 =12.288 MHz.
// VCOs 640 and 614.4 MHz are within the documented 300..1200 MHz range.
module mm_pcm_clock(input wire clk,reset,output wire mclk,locked);
 wire [4:0] c0,c1;wire lock0,lock1;wire ref_audio;
 EG_LOGIC_BUFG ref_buf(.i(c0[0]),.o(ref_audio));
 assign mclk=c1[0];assign locked=lock0 & lock1;
 EG_PHY_PLL #(.FIN("50.000000"),.FEEDBK_MODE("NOCOMP"),.FEEDBK_PATH("VCO_PHASE_0"),
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.STDBY_ENABLE("DISABLE"),
 .PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
 .REFCLK_DIV(5),.FBCLK_DIV(64),.CLKC0_ENABLE("ENABLE"),
 .CLKC0_DIV(25),.CLKC0_CPHASE(24),.CLKC0_FPHASE(0)) pll_a(
 .refclk(clk),.reset(reset),.extlock(lock0),.clkc(c0),
 .stdby(1'b0),.fbclk(1'b0),.load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),
 .psstep(1'b0),.psclksel(3'b0),.psdone(),.dclk(1'b0),.dcs(1'b0),.dwe(1'b0),
 .di(8'b0),.daddr(6'b0),.do());
 EG_PHY_PLL #(.FIN("25.600000"),.FEEDBK_MODE("NOCOMP"),.FEEDBK_PATH("VCO_PHASE_0"),
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.STDBY_ENABLE("DISABLE"),
 .PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
 .REFCLK_DIV(5),.FBCLK_DIV(120),.CLKC0_ENABLE("ENABLE"),
 .CLKC0_DIV(50),.CLKC0_CPHASE(49),.CLKC0_FPHASE(0)) pll_b(
 .refclk(ref_audio),.reset(reset | !lock0),.extlock(lock1),.clkc(c1),
 .stdby(1'b0),.fbclk(1'b0),.load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),
 .psstep(1'b0),.psclksel(3'b0),.psdone(),.dclk(1'b0),.dcs(1'b0),.dwe(1'b0),
 .di(8'b0),.daddr(6'b0),.do());
endmodule
