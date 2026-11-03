import_device eagle_s20.db -package EG4S20BG256
open_project HX21A5.al
commit_param -step design
set_param flow thread 1
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc ../user_source/constraints_source/reset_sync.sdc
read_sdc ../user_source/constraints_source/alarm_io.sdc
export_db image4_elaborate.db
optimize_rtl
export_db image4_rtl.db
set_param gate opt_area high
set_param gate pack_effort high
optimize_gate -packarea
legalize_phy_inst
export_db image4_gate.db
set ::hx_root [pwd]
source closure/prepare_io_body.tcl
set_param place effort high
set_param place seed 3
set_param place hold_fix high
place
source mapped_reset_sync_pair_audited.tcl
read_sdc mapped_reset_sync.sdc
export_db image4_place.db
set_param route effort high
set_param route fix_hold on
route
set_inst_attr -model_name top -inst uart_tx_syn_4 -attr_key SLEWRATE -attr_value FAST
fix_hold -clock_opt
fix_hold -net panel_reset_request -buffer_opt -eco
update_timing -mode final
report_area -io_info -file ../../resource.rpt
report_timing_summary -file ../../timing.rpt
report_timing_exception -file image4_exception.timing
check_timing -file ../../timing_check.rpt
report_qor -step route -file image4_route.qor
report_route_status -drc
report_route_status -file image4_route.rpt
export_db image4_pr.db
set f [open ../../timing.rpt r]
set t [read $f]
close $f
foreach m {SWNS HWNS} {
 if {![regexp [format {%s:\s*([-0-9.]+)ns} $m] $t unused slack]} {error "Missing $m"}
 if {$slack <= 0} {error "Refusing bitgen: $m=$slack"}
}
bitgen -bit ../../HX21A5_ROI_20261102.bit -unused_io_status pullup
puts ROI_CLOSED_BIT_COMPLETE
exit
