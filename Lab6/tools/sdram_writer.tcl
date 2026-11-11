#--------------------------------------------------------------------------
# sdram_writer.tcl -- send a 4096x2048 image from the PC into the board's
# SDRAM, over the JTAG cable that is already plugged in.
#
#     quartus_stp -t sdram_writer.tcl image.raw
#     quartus_stp -t sdram_writer.tcl image.mif
#     quartus_stp -t sdram_writer.tcl                 (built-in test pattern)
#
# quartus_stp IS NOT ON THE PATH by default on this machine.  It lives
# with the rest of the command-line tools:
#
#     C:/altera_pro/26.1.1/quartus/bin64/quartus_stp -t sdram_writer.tcl ...
#
# or add that directory to PATH once, which quartus_syn, quartus_fit
# and quartus_sta need anyway.  "quartus_stp: command not found" means
# the PATH, not a missing install -- the executable ships with every
# edition.
#
# The FPGA must already be configured and running.  This talks to
# jtag_sdram_writer through Virtual JTAG; nothing is sent over the
# programming interface itself.  Program the .sof first:
#
#     quartus_pgm -m jtag -o "p;output_files/sdram_test.sof"
#
#--------------------------------------------------------------------------
# TWO THINGS ABOUT THE FORMAT, AND BOTH MATTER
#--------------------------------------------------------------------------
#
# BLOCKS, NOT PIXELS.  Each device_virtual_dr_shift is a USB round trip
# costing a millisecond or two whatever its length, so one shift per
# pixel would be four hours of latency with the cable idle throughout.
# PIXELS_PER_SHIFT pixels go per shift instead: 65_536 round trips for
# the whole image.  This number MUST match the generic of the same name
# in jtag_sdram_writer -- there is no handshake that would catch a
# mismatch, the picture would simply come out wrong.
#
# ORDER WITHIN A BLOCK IS REVERSED.  JTAG shifts least significant bit
# first, so the pixel that must arrive FIRST has to sit in the LOWEST
# 24 bits of the shifted value.  A hex string is written most
# significant digit first, so the block is assembled backwards: last
# pixel at the head of the string, first pixel at the tail.
#
#--------------------------------------------------------------------------
# PREFER .raw
#--------------------------------------------------------------------------
#
# A raw file is three bytes per pixel, R then G then B, in raster order
# from the top left: 25 MB for this image, and a chunk of it converts
# to the hex a shift wants in one binary scan.
#
# The same image as a .mif is a ~100 MB text file that has to be parsed
# a line at a time, and is minutes slower for no benefit -- a .mif
# exists to initialise memory inside the FPGA at configuration time,
# which is precisely the thing that cannot be done here.  Use
# tools/mif_to_raw.py once and keep the .raw.
#
# HOW LONG.  Expect a couple of minutes for .raw.  LEDR0 on the board
# is lit for the whole transfer and goes dark on the last pixel;
# nothing is read out of the SDRAM until it does, so the screen stays
# black until the image is complete.
#--------------------------------------------------------------------------

set IMG_W  4096
set IMG_H  2048
set N_PIXELS [expr {$IMG_W * $IMG_H}]

# MUST match jtag_sdram_writer's generic.
set PIXELS_PER_SHIFT 128
set SHIFT_BITS [expr {$PIXELS_PER_SHIFT * 24}]

set INSTANCE 0
set IR_RESET 1
set IR_IDLE  0

set N_BLOCKS [expr {$N_PIXELS / $PIXELS_PER_SHIFT}]
if { $N_BLOCKS * $PIXELS_PER_SHIFT != $N_PIXELS } {
    puts "N_PIXELS must be a whole number of blocks."
    exit 1
}

#--------------------------------------------------------------------------
# Shifting one block
#
# blk is a list of PIXELS_PER_SHIFT hex strings of 6 characters each, in
# the order the pixels are to be written.  lreverse puts the first pixel
# at the tail of the string, which is where the low bits are.
#--------------------------------------------------------------------------
proc send_block { blk } {
    global INSTANCE SHIFT_BITS
    device_virtual_dr_shift -instance_index $INSTANCE \
                            -length $SHIFT_BITS \
                            -dr_value [join [lreverse $blk] ""] \
                            -value_in_hex -no_captured_dr_value
}

#--------------------------------------------------------------------------
# The built-in pattern.
#
# Colour bars, left to right:
#
#     white  yellow  cyan  green  magenta  red  blue  black
#
# THE BARS REPEAT EVERY 640 PIXELS, not once across the image.  Only the
# middle 640x480 of the stored image is ever displayed, and bars spread
# across all 4096 columns would put just two of them in that window --
# green and magenta as it happens, which are the two colours an R/B swap
# leaves unchanged.  The test would have shown nothing at all.  Repeating
# at the window's own width guarantees all eight are visible wherever the
# window lands.
#
# What each part is evidence of:
#
#   the bars    swapped channels.  Under an R/B swap yellow and cyan
#               trade places, and so do red and blue; white, green,
#               magenta and black do not move.  So the failure is
#               legible even in a photograph.
#   the grid    a wrong stride or a shear, every 64 pixels.
#
# Generated a row at a time so nothing larger than one row is ever held
# in memory.
#--------------------------------------------------------------------------
proc pattern_row { y w } {
    set bars { FFFFFF FFFF00 00FFFF 00FF00 FF00FF FF0000 0000FF 000000 }
    set row {}
    if { $y % 64 == 0 } {
        for { set x 0 } { $x < $w } { incr x } { lappend row FFFFFF }
        return $row
    }
    for { set x 0 } { $x < $w } { incr x } {
        if { $x % 64 == 0 } {
            lappend row FFFFFF
        } else {
            lappend row [lindex $bars [expr {(($x % 640) * 8) / 640}]]
        }
    }
    return $row
}

#--------------------------------------------------------------------------
# Find the board
#--------------------------------------------------------------------------
set hw_names [get_hardware_names]
if { [llength $hw_names] == 0 } {
    puts "No JTAG hardware found.  Is the USB cable plugged in?"
    exit 1
}
set hw [lindex $hw_names 0]

set dev_names [get_device_names -hardware_name $hw]
if { [llength $dev_names] == 0 } {
    puts "No device on $hw."
    exit 1
}
set dev [lindex $dev_names 0]

puts "Hardware   : $hw"
puts "Device     : $dev"
puts "Image      : ${IMG_W}x${IMG_H} = $N_PIXELS pixels"
puts "Shifts     : $N_BLOCKS of $SHIFT_BITS bits"

#--------------------------------------------------------------------------
# Open the source before touching the cable, so a bad filename fails
# before the board is locked.
#--------------------------------------------------------------------------
set mode "pattern"
set fh ""
if { $argc > 0 } {
    set src [lindex $argv 0]
    if { ![file exists $src] } {
        puts "No such file: $src"
        exit 1
    }
    if { [string match -nocase "*.mif" $src] } {
        set mode "mif"
        set fh [open $src r]
    } else {
        set mode "raw"
        set fh [open $src rb]
        set sz [file size $src]
        if { $sz != $N_PIXELS * 3 } {
            puts "WARNING: $src is $sz bytes, expected [expr {$N_PIXELS * 3}]."
            puts "         Sending what is there; short files pad with black."
        }
    }
    puts "Source     : $src ($mode)"
} else {
    puts "Source     : built-in test pattern"
}

#--------------------------------------------------------------------------
# Send it
#
# The instruction shift resets the address counter, so a transfer that
# was interrupted can simply be run again without reprogramming or
# resetting the board.
#--------------------------------------------------------------------------
open_device -hardware_name $hw -device_name $dev
device_lock -timeout 10000

device_virtual_ir_shift -instance_index $INSTANCE -ir_value $IR_RESET \
                        -no_captured_ir_value
device_virtual_ir_shift -instance_index $INSTANCE -ir_value $IR_IDLE \
                        -no_captured_ir_value

set start [clock seconds]
set sent 0
set step [expr {$N_BLOCKS / 20}]
set blk {}
set pend {}
set y 0

for { set b 0 } { $b < $N_BLOCKS } { incr b } {

    switch -- $mode {
        raw {
            set chunk [read $fh [expr {$PIXELS_PER_SHIFT * 3}]]
            binary scan $chunk H* h
            set blk [regexp -all -inline {.{6}} $h]
            # A short read at end of file pads with black rather than
            # shifting a wrong-length value.
            while { [llength $blk] < $PIXELS_PER_SHIFT } {
                lappend blk 000000
            }
        }
        mif {
            while { [llength $pend] < $PIXELS_PER_SHIFT } {
                if { [gets $fh line] < 0 } { break }
                # The "--" IS the pattern, not an option.  Without the
                # separator Tcl reads a leading "--" as end-of-options
                # and complains about a bad switch -- which is a
                # confusing way to be told that a .mif comment marker
                # and Tcl's option terminator are spelled the same.
                regsub -- {--.*$} $line "" line
                if { [regexp {:\s*([0-9A-Fa-f]+)\s*;} $line -> v] } {
                    lappend pend [format %06X [expr {"0x$v"}]]
                }
            }
            while { [llength $pend] < $PIXELS_PER_SHIFT } {
                lappend pend 000000
            }
            set blk [lrange $pend 0 [expr {$PIXELS_PER_SHIFT - 1}]]
            set pend [lrange $pend $PIXELS_PER_SHIFT end]
        }
        pattern {
            while { [llength $pend] < $PIXELS_PER_SHIFT } {
                set pend [concat $pend [pattern_row $y $IMG_W]]
                incr y
            }
            set blk [lrange $pend 0 [expr {$PIXELS_PER_SHIFT - 1}]]
            set pend [lrange $pend $PIXELS_PER_SHIFT end]
        }
    }

    send_block $blk
    incr sent $PIXELS_PER_SHIFT

    if { $step > 0 && ($b + 1) % $step == 0 } {
        set el [expr {[clock seconds] - $start}]
        puts "  [expr {100 * ($b + 1) / $N_BLOCKS}]%  ($sent / $N_PIXELS, $el s)"
        flush stdout
    }
}

if { $fh ne "" } { close $fh }

device_unlock
close_device

puts "Sent $sent pixels in [expr {[clock seconds] - $start}] s."
puts "LEDR0 should now be dark and the image on screen."
