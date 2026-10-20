vlib work
vcom -2008 ../vhdl/pwm_servo.vhd
vcom -2008 ../vhdl/gesture_controller.vhd
vcom -2008 ../vhdl/robotic_hand.vhd
vcom -2008 ../vhdl/robotic_hand_tb.vhd
vsim -voptargs=+acc robotic_hand_tb
add wave -group "TESTBENCH" sim:/robotic_hand_tb/*
add wave -group "DUT"       sim:/robotic_hand_tb/dut/*
add wave -group "GESTURES"  sim:/robotic_hand_tb/dut/gesture_controller_inst/*
run 1200 ms