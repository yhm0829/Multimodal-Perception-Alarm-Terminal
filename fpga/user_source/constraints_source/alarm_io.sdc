# New alarm CDC destination is a 2FF board-domain synchronizer.
set_max_delay -datapath_only 19.700 -from [get_clocks video_clk] -to [get_clocks clk]
# Conservative local output budget, NOT a claim of synchronous CH340 sampling.
# UART receiver samples asynchronously at115200baud; check baud error by simulation.
set_output_delay -max 10.0 -clock clk [get_ports {uart_tx}]
set_output_delay -min 0.0 -clock clk [get_ports {uart_tx}]
