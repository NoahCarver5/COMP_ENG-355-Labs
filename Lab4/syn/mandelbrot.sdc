#**************************************************************
# Board oscillator (input to VIDEO_PLL) 
create_clock -period "50MHz" [get_ports clk_50] 
# VIDEO_PLL output: 100 MHz system clock 
derive_pll_clocks 
# Clock jitter and uncertainty 
derive_clock_uncertainty 
# Push buttons and switch: asynchronous, human-speed inputs 
set_false_path -from [get_ports {reset_n keys_n[*]}] 
# HDMI video outputs: clock and data aligned by construction in hdmi.vhd 
set_false_path -to [get_ports {hdmi_tx_clk hdmi_tx_d[*] hdmi_tx_hs hdmi_tx_vs hdmi_tx_de}] 
# HDMI interrupt and I2C bus: slow signals 
set_false_path -from [get_ports {hdmi_tx_int i2c_sda}] 
set_false_path -to   [get_ports {i2c_scl i2c_sda}] 
# viewport registers change only once per frame 
set viewport_regs [get_registers {*viewport_inst|x0_r* *viewport_inst|y0_r* *viewport_inst|pixel_step_r*}] 
set_multicycle_path -setup 4 -from $viewport_regs -to $viewport_regs 
set_multicycle_path -hold  3 -from $viewport_regs -to $viewport_regs
