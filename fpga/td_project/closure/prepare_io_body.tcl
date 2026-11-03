set_param flow thread 1
set_inst_attr -model_name top -inst {sys_pll_m0/pll_inst} -attr_key CLKC2_CPHASE -attr_value 4
set_inst_attr -model_name top -inst {sys_pll_m0/pll_inst} -attr_key CLKC3_ENABLE -attr_value ENABLE
set_inst_attr -model_name top -inst {sys_pll_m0/pll_inst} -attr_key CLKC3_DIV -attr_value 8
set_inst_attr -model_name top -inst {sys_pll_m0/pll_inst} -attr_key CLKC3_CPHASE -attr_value 8
set_inst_attr -model_name top -inst {sys_pll_m0/pll_inst} -attr_key CLKC3_FPHASE -attr_value 0
create_net {v21_dq_capture_clk}
connect_net -net {v21_dq_capture_clk} -objects [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_1.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_1.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_1} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_1} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_1.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_1.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_18.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_18.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_18} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_18} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_18.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_18.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_19.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_19.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_19} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_19} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_19.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_19.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_2.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_2.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_2} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_2} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_2.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_2.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_20.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_20.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_20} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_20} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_20.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_20.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_21.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_21.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_21} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_21} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_21.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_21.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_22.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_22.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_22} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_22} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_22.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_22.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_23.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_23.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_23} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_23} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_23.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_23.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_24.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_24.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_24} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_24} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_24.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_24.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_25.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_25.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_25} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_25} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_25.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_25.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_26.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_26.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_26} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_26} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_26.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_26.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_27.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_27.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_27} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_27} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_27.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_27.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_28.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_28.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_28} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_28} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_28.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_28.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_29.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_29.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_29} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_29} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_29.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_29.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_3.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_3.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_3} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_3} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_3.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_3.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_30.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_30.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_30} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_30} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_30.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_30.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_31.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_31.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_31} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_31} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_31.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_31.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_32.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_32.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_32} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_32} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_32.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_32.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_33.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_33.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_33} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_33} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_33.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_33.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_34.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_34.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_34} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_34} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_34.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_34.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_35.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_35.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_35} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_35} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_35.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_35.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_43.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_43.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_43} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_43} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_43.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_43.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_47.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_47.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_47} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_47} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_47.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_47.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_48.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_48.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_48} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_48} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_48.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_48.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_49.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_49.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_49} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_49} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_49.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_49.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_50.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_50.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_50} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_50} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_50.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_50.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_51.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_51.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_51} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_51} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_51.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_51.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_52.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_52.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_52} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_52} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_52.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_52.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_53.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_53.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_53} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_53} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_53.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_53.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_54.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_54.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_54} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_54} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_54.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_54.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_55.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_55.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_55} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_55} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_55.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_55.ipclk}]
disconnect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t} -objects [get_pins {U3/sdram_syn_7.ts}]
connect_net -net {U3/u2_ram/original_controller/u2_wrrd/sdr_t_reg_syn_5} -objects [get_pins {U3/sdram_syn_7.ts}]
set_inst_attr -model_name top -inst {U3/sdram_syn_7} -attr_key TO_DFFMODE -attr_value FF
set_inst_attr -model_name top -inst {U3/sdram_syn_7} -attr_key TO_REGSET -attr_value SET
disconnect_net -net {U3/u2_ram/Sdr_clk} -objects [get_pins {U3/sdram_syn_7.ipclk}]
connect_net -net {v21_dq_capture_clk} -objects [get_pins {U3/sdram_syn_7.ipclk}]
update_pll_param
clear_sdc -user
read_sdc [file normalize [file join $::hx_root {phase1_complete_timing.sdc}]]
read_sdc [file normalize [file join $::hx_root {../user_source/constraints_source/reset_sync.sdc}]]
read_sdc [file normalize [file join $::hx_root {../user_source/constraints_source/alarm_io.sdc}]]
read_sdc [file normalize [file join $::hx_root {read_cycle_pairs.sdc}]]




