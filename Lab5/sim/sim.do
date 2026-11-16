vlib work

vcom -2008 ../vhdl/pixel_pkg.vhd
vcom -2008 ../vhdl/bram.vhd
vcom -2008 ../vhdl/digit_display.vhd
vcom -2008 ../vhdl/video_store.vhd
vcom -2008 ../vhdl/filter_pass.vhd
vcom -2008 ../vhdl/filter_gray.vhd
vcom -2008 ../vhdl/filter_invert.vhd
vcom -2008 ../vhdl/filter_sepia.vhd
vcom -2008 ../vhdl/filter_swap.vhd
vcom -2008 ../vhdl/filter_threshold.vhd
vcom -2008 ../vhdl/filter_edge.vhd
vcom -2008 ../vhdl/filter_cartoonify.vhd
vcom -2008 ../vhdl/filters.vhd
vcom -2008 ../vhdl/image_processor.vhd
vcom -2008 ../vhdl/image_processor_tb.vhd
vsim -voptargs=+acc image_processor_tb
add wave -group "TESTBENCH" sim:/image_processor_tb/*
add wave -group "IMAGE PROCESSOR" sim:/image_processor_tb/dut/*
add wave -group "VIDEO STORE" sim:/image_processor_tb/dut/u_video_store/*
add wave -group "FILTERS" sim:/image_processor_tb/dut/u_filters/*

run -all