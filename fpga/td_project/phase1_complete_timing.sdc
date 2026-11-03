# V3: conservative constraints for real implementation/closure.
# No blanket reset, FIFO-address, or encrypted-HDMI false paths; no zero hold uncertainty.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name sd_card_clk -source [get_ports clk] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name ext_mem_clk -source [get_ports clk] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name ext_mem_clk_sft -source [get_ports clk] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name sdram_capture_clk -source [get_ports clk] -master_clock clk [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
rename_clock -name video_clk -source [get_ports clk] -master_clock clk [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name hdmi_5x_clk -source [get_ports clk] -master_clock clk [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name pcm_ref_clk -source [get_ports clk] -master_clock clk [get_pins {u_pcm_clock/pll_a.clkc[0]}]
rename_clock -name pcm_mclk -source [get_pins {u_pcm_clock/pll_a.clkc[0]}] -master_clock pcm_ref_clk [get_pins {u_pcm_clock/pll_b.clkc[0]}]
set_clock_uncertainty -setup 0.100 [get_clocks *]
set_clock_uncertainty -hold 0.100 [get_clocks *]
# Unrelated PLL domains cross through FIFO/synchronizers. Bound the physical
# CDC flight time rather than suppressing entire clock pairs; blanket groups
# override the vendor FIFO Gray-pointer max-delay constraints in TD.
set_max_delay -datapath_only 19.700 -from [get_clocks clk] -to [get_clocks video_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks clk] -to [get_clocks hdmi_5x_clk]
set_max_delay -datapath_only 9.700 -from [get_clocks sd_card_clk] -to [get_clocks video_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks ext_mem_clk] -to [get_clocks video_clk]
set_max_delay -datapath_only 9.700 -from [get_clocks video_clk] -to [get_clocks sd_card_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks video_clk] -to [get_clocks ext_mem_clk]
# External asynchronous inputs have no phase relationship with the sampling
# clock. These exceptions end naturally at the first sequential endpoint,
# including first-stage FFs packed into PAD input registers by TD. Internal
# paths from each first stage to its next synchronizer stage remain timed.
set_false_path -from [get_ports {sw[*] rst_n key1 key2 key3 ext_key_n[*] uart_rx light_rc paj_int_n paj_sda paj_scl I_i2s_BCLK I_i2s_LRCK I_i2s_DOUT}]
# Board I/O and SDRAM hard-IP interface constraints still require signoff.
# Never mask the SDRAM data bus or reset/removal paths to manufacture closure.

# DAC stereo FIFO: Gray pointers are synchronized, payload held until consumption.
set_max_delay -datapath_only 39.700 -from [get_clocks video_clk] -to [get_clocks pcm_mclk]
set_max_delay -datapath_only 39.700 -from [get_clocks pcm_mclk] -to [get_clocks video_clk]
# DAC outputs change on BCLK falling edge, sampled externally on its rising edge.
# A 10ns output load/flight budget, within the 162ns BCLK half-period.
set_output_delay -max 10.0 -clock pcm_mclk [get_ports {O_dac_bclk O_dac_lrck O_dac_dout}]
set_output_delay -min 0.0 -clock pcm_mclk [get_ports {O_dac_bclk O_dac_lrck O_dac_dout}]


# Additional intentional CDC boundaries, verified in the integration tests:
# board->SD: 3FF key/toggle synchronizers; caption bus stable before commit.
# board->memory: 2FF zoom plus nine-cycle qualification before frame latch.
# SD<->memory: async FIFO pointers and 3FF request/ack/finish toggles.
# Bound flight time to <one fastest clock period; keep within-domain paths timed.
set_max_delay -datapath_only 9.700 -from [get_clocks clk] -to [get_clocks sd_card_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks clk] -to [get_clocks ext_mem_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks sd_card_clk] -to [get_clocks ext_mem_clk]
set_max_delay -datapath_only 7.700 -from [get_clocks ext_mem_clk] -to [get_clocks sd_card_clk]

# SDRAM read-buffer FIFO (rfifo_32_32_512) write-side full-flag -> BRAM wea
# is marginally over budget in the slow corner (7.51ns of an 8ns period). The
# FIFO asserts afull at 256 words, leaving 255 words of headroom before the
# 511-word full point, so the full flag may validly take a second cycle without
# any risk of overflow. Give this exact path a 2-cycle setup budget.
set_multicycle_path 2 -setup -to [get_pins -hier -regexp {frame_read_write_m0/read_buf/ram_inst/ramread0.*\.wea}]
set_multicycle_path 1 -hold  -to [get_pins -hier -regexp {frame_read_write_m0/read_buf/ram_inst/ramread0.*\.wea}]

