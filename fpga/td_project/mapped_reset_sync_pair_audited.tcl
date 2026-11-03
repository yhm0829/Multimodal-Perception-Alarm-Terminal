# Reapply the existing reset_sync.sdc exception after TD packs the two reset
# synchronizer FFs into slices with unrelated names. Do NOT except fanout SRs.
# The RTL is unchanged; only the SR pins of the two known synchronizer drivers
# are allowed. Reject an unexpected packing instead of widening the exception.
set audit_sdc [open mapped_reset_sync.sdc w]
puts $audit_sdc {# Generated only after validating the two packed synchronizer FFs.}
foreach i {0 1} {
    set n [get_nets -hier -regexp [format {^u_dac/reset_read_sync\[%d\]$} $i]]
    if {[llength $n] != 1} {error "Missing/ambiguous DAC reset synchronizer net $i"}
    set drivers {}
    foreach p [get_pins -of $n] {
        if {[regexp {^(.*)\.q\[([01])\]$} $p ignored cell bit]} {
            lappend drivers [list $cell $bit]
        }
    }
    if {[llength $drivers] != 1} {error "Reset net $i does not have one packed FF driver"}
    lassign [lindex $drivers 0] cell bit
    set other [expr {1-$bit}]
    set other_pin [format {%s.q[%d]} $cell $other]
    set other_nets [get_nets -of [get_pins [list $other_pin]]]
    # Both FFs may be the two explicitly excepted reset synchronizer stages.
    # Reject any unrelated live FF; never except a shared SR blindly.
    set expected_other [format {u_dac/reset_read_sync[%d]} [expr {1-$i}]]
    if {[llength $other_nets] != 0 &&
        ([llength $other_nets] != 1 || [lindex $other_nets 0] ne $expected_other)} {
        error "Packed reset slice contains an unrelated live FF: $other_nets"
    }
    puts "AUDITED_RESET_PAIR $i driver=$cell.q\[$bit\] other=$other_nets"
    set sr [get_pins [list "$cell.sr"]]
    set rstnet [get_nets -of $sr]
    if {[llength $sr] != 1 || $rstnet ne "u_dac/rst"} {
        error "Unexpected reset SR connection for $cell: $rstnet"
    }
    puts "AUDITED_RESET_SYNC_SR $i $sr (Q drives $n)"
    puts $audit_sdc [format {set_false_path -to [get_pins {%s.sr}]} $cell]
}
# Audit the serializer reset chain after packing; never mask downstream SRs.
foreach i {0 1} {
    set n [get_nets -hier -regexp [format {^rst_hdmi_sync\[%d\]$} $i]]
    if {[llength $n] != 1} {error "Missing HDMI reset synchronizer net $i"}
    set drivers {}
    foreach p [get_pins -of $n] {
        if {[regexp {^(.*)\.q\[([01])\]$} $p ignored cell bit]} {
            lappend drivers [list $cell $bit]
        }
    }
    if {[llength $drivers] != 1} {error "Ambiguous HDMI reset FF driver $i"}
    lassign [lindex $drivers 0] cell bit
    set other_pin [format {%s.q[%d]} $cell [expr {1-$bit}]]
    set other_nets [get_nets -of [get_pins [list $other_pin]]]
    set expected_other [format {rst_hdmi_sync[%d]} [expr {1-$i}]]
    if {[llength $other_nets] != 0 &&
        ([llength $other_nets] != 1 || [lindex $other_nets 0] ne $expected_other)} {
        error "HDMI reset shares SR with an unrelated FF: $other_nets"
    }
    set sr [get_pins [list "$cell.sr"]]
    set rstnet [get_nets -of $sr]
    if {[llength $sr] != 1 || [llength $rstnet] != 1 || [lindex $rstnet 0] ne {rst_video_sync[1]}} {
        error "Unexpected HDMI synchronizer SR connection: $rstnet"
    }
    puts "AUDITED_HDMI_RESET_SYNC_SR $i $sr (Q drives $n)"
    puts $audit_sdc [format {set_false_path -to [get_pins {%s.sr}]} $cell]
}
close $audit_sdc

# Restore the vendor FIFO Gray-pointer bounds after physical packing.
read_sdc -ip rfifo_32_32_512 [file normalize [file join $::hx_root {../user_source/hdl_source/IP/afifo_32_16_256.tcl}]]
read_sdc -ip wfifo_32_32_512 [file normalize [file join $::hx_root {../user_source/hdl_source/IP/afifo_16_32_256.tcl}]]
puts HX20R4_FIFO_BOUNDS_RESTORED

