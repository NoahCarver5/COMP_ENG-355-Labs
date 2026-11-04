#**************************************************************
# This .sdc file is created by Terasic Tool.
# Users are recommended to modify this file to match users logic.
#**************************************************************

#**************************************************************
# Create Clock
#**************************************************************
# CLOCK (CLOCK2_50 -> VIDEO_PLL refclk)
create_clock -period "50MHz" [get_ports clk_50]

# The camera's pixel clock, from the D8M's TC358748 bridge.  This is
# the design's only genuine second clock domain: d8m.vhd clocks its
# line counters and the Bayer demosaic on it.
#
# 25 MHz is what the bridge's register script produces for 640x480
# -- the same figure the card's own demos constrain this clock at and
# divide down for their 1 Hz activity LED.  The whole design here is
# built around that number:
#
#   * video_store recovers this clock by OVERSAMPLING it on the 100
#     MHz system clock, which needs at least 4 system clocks per
#     camera clock.  100 / 25 = 4 exactly -- there is no margin.
#   * hdmi's PIX_DIV = 4 divides the same 100 MHz to the 25 MHz
#     pixel rate.
#
# So if the bridge is ever reconfigured to a different pixel clock,
# this constraint is not the only thing that has to move: either the
# system clock goes up with it, or video_store's oversampling breaks
# silently and pixels are dropped.
create_clock -period "25MHz" -name cam_clk [get_ports mipi_pixel_clk]


#**************************************************************
# Create Generated Clock
#**************************************************************
# VIDEO_PLL outclk_0  =  20 MHz, MIPI bridge reference clock
# VIDEO_PLL outclk_1  = 100 MHz, system clock
#
# NOTHING TO DO HERE.  Agilex 5 does not support derive_pll_clocks
# -- calling it only earns a warning.  Quartus generates an SDC
# alongside the PLL IP (VIDEO_PLL/altera_iopll_*/synth/*.sdc) and
# reads it automatically, and that file creates both output clocks.
#
# Which means the PLL IP has to have been generated before timing
# analysis means anything.  If these two clocks are missing from the
# Timing Analyzer's clock list, that is the reason.


#**************************************************************
# Set Clock Uncertainty
#**************************************************************
derive_clock_uncertainty


#**************************************************************
# Set Input Delay
#**************************************************************
# The camera bus is source-synchronous: the bridge drives these 12
# pins from mipi_pixel_clk, and d8m.vhd captures them on that same
# clock.  2.0 ns is the figure the card's vendor publishes for this
# interface, so it is taken as given rather than re-derived.
#
# Given with neither -max nor -min, so it applies to both and the
# analyzer sees a 2 ns window either side.  At a 40 ns period that is
# not a tight constraint; it is here so the fitter knows the arrival
# time exists at all, rather than treating these as unconstrained.
set_input_delay 2.0 -clock cam_clk [get_ports {mipi_pixel_d[*]}]
set_input_delay 2.0 -clock cam_clk [get_ports mipi_pixel_hs]
set_input_delay 2.0 -clock cam_clk [get_ports mipi_pixel_vs]


#**************************************************************
# Set Clock Groups
#**************************************************************
# The camera clock comes back from the bridge, not from our PLL.  It
# is nominally derived from mipi_refclk, but it goes out to the card,
# through the bridge's own PLL and back, so there is no phase
# relationship the timing analyzer can use.
#
# One group named, so cam_clk is asynchronous to every other clock in
# the design.  Naming the PLL outputs explicitly would mean spelling
# out whatever derive_pll_clocks called them, which changes with the
# instance path; this way there is nothing to keep in step.
set_clock_groups -asynchronous -group [get_clocks {cam_clk}]


#**************************************************************
# Set False Path
#**************************************************************
# Pushbuttons: asynchronous, human-speed inputs.
set_false_path -from [get_ports {reset_n keys_n[*]}]

# Seven-segment digits: they show which filter is selected, and
# nothing reads them back or cares when in the cycle they land.
set_false_path -to [get_ports {hex0[*] hex1[*]}]

# HDMI TX: hdmi_tx_clk is a register output divided down from the
# system clock alongside the data it latches, so the TX clock and data
# are aligned by construction (see hdmi.vhd) rather than by constraint.
#
# THIS IS A CHOICE, NOT THE ONLY WAY.  The textbook alternative is
# create_clock on the hdmi_tx_clk output pin with set_output_delay
# against it on the data, which is how a source-synchronous output is
# normally constrained when its clock comes from somewhere the
# analyzer cannot see.  Here it comes from the same register stage as
# the data, half a pixel period earlier by construction, and the
# pixel period is 40 ns: the fitter would have to add about 20 ns of
# pin-to-pin skew before the eye closed.  The false path is the
# honest description of that, and it keeps the design single-clock.
# If a monitor ever refuses to lock, switching to the create_clock
# form is the first thing to try -- it constrains what this one only
# argues.
set_false_path -to [get_ports {hdmi_tx_clk hdmi_tx_d[*] hdmi_tx_hs hdmi_tx_vs hdmi_tx_de}]

# HDMI transmitter interrupt (synchronized in hdmi) and its I2C bus,
# which runs at tens of kHz off a clock enable.
set_false_path -from [get_ports {hdmi_tx_int hdmi_i2c_sda}]
set_false_path -to   [get_ports {hdmi_i2c_scl hdmi_i2c_sda}]

# D8M control and configuration.  The two I2C buses run at 400 kHz off
# CLOCKMEM dividers, and the reset, chip select and power-down pins are
# set once at startup and never move again.
set_false_path -from [get_ports {mipi_i2c_sda camera_i2c_sda}]
set_false_path -to   [get_ports {mipi_i2c_scl mipi_i2c_sda camera_i2c_scl camera_i2c_sda}]
set_false_path -to   [get_ports {mipi_cs_n mipi_reset_n camera_pwdn_n}]

# mipi_refclk is VIDEO_PLL outclk_0 driven straight off chip as the
# bridge's reference.  The bridge locks its own PLL to it; there is no
# setup or hold relationship on this side to constrain.
set_false_path -to [get_ports {mipi_refclk}]


#**************************************************************
# Set Maximum Skew / Net Delay
#**************************************************************
# THE ONE CLOCK DOMAIN CROSSING.
#
# video_store does not clock anything on cam_clk.  It runs three flops
# on the system clock to catch the rising edge of cam_clk and make one
# tick per camera pixel, then samples cam_de and cam_pixel on that
# tick.  Those 25 bits are NOT synchronized individually -- the scheme
# relies on them still being flat when the tick arrives, which holds
# because d8m drives them once per camera clock and they sit still for
# the rest of that period.
#
# set_clock_groups above cuts these paths, which on its own would let
# the fitter route the 25 data bits with arbitrary skew against each
# other and against the recovered clock.  These two put a bound back:
# 10 ns is one system clock, a quarter of the camera period, so the bus
# still lands flat inside the window where the data is stable.
#
# set_max_skew and set_net_delay are the right tools here rather than
# set_max_delay -- they constrain the routing of a cut path, which is
# exactly what a synchronized bus crossing needs, instead of trying to
# re-open a timing arc between two clocks that have no relationship.
set cam_data_src [get_registers {*u_d8m|rgb_*}]
set cam_data_dst [get_registers {*u_video_store|*}]
set_max_skew  -from $cam_data_src -to $cam_data_dst 10.000
set_net_delay -from $cam_data_src -to $cam_data_dst -max 10.000


#**************************************************************
# Set Multicycle Path
#**************************************************************
# None.  Everything on the display side advances once per pixel_req,
# which is one system clock in every four, but the logic between those
# registers is single-cycle -- the enable gates when they update, not
# how long they have to settle.
