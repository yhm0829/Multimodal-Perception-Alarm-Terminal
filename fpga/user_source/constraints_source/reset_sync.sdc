# Reset synchronizers intentionally accept asynchronous assertion/release at
# their SR pins. Only these two-stage chains' asynchronous control pins are
# excepted. Their stage-to-stage data paths and ALL downstream reset removal
# paths remain timed; downstream release is synchronous to its own clock.
set_false_path -to [get_pins -hier -regexp {^(rst_mem_sync_reg|rst_sd_sync_reg|rst_video_sync_reg)\[[01]\](_syn_[0-9]+)?\.sr$}]
set_false_path -to [get_pins -hier -regexp {^u_dac/reset_(read|write)_sync_reg\[[01]\](_syn_[0-9]+)?\.sr$}]
set_false_path -to [get_pins -hier -regexp {^rst_hdmi_sync_reg\[[01]\](_syn_[0-9]+)?\.sr$}]
