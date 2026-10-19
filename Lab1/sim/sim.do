vlib work

vcom -2008 ../vhdl/digit_display.vhd 
vcom -2008 ../vhdl/bcd.vhd 
vcom -2008 ../vhdl/tds_converter.vhd 
vcom -2008 ../vhdl/tds_monitor.vhd 
vcom -2008 ../vhdl/tds_monitor_tb.vhd 
vsim -voptargs=+acc tds_monitor_tb 
add wave -group "TESTBENCH" sim:/tds_monitor_tb/* 
add wave -group "TDS MONITOR" sim:/tds_monitor_tb/dut/* 
add wave -group "TDS CONVERTER" sim:/tds_monitor_tb/dut/tds_converter_instance/* 
add wave -group "BCD" sim:/tds_monitor_tb/dut/bcd_instance/* 
run 1000 ns