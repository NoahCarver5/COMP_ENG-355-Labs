library ieee;
use ieee.std_logic_1164.all;

entity tds_monitor_tb is
end entity tds_monitor_tb;

architecture behavioral of tds_monitor_tb is

    ----------------------------------------------------------------
    -- Signals connected to the device under test
    --
    -- TODO: Add signal declarations 

    signal hex0: std_logic_vector(6 downto 0);
    signal hex1: std_logic_vector(6 downto 0);
    signal hex2: std_logic_vector(6 downto 0);
    signal hex3: std_logic_vector (6 downto 0);
    signal led: std_logic;

    ----------------------------------------------------------------
    signal adc  : std_logic_vector(11 downto 0);


    ----------------------------------------------------------------
    -- Component Declaration: Device Under Test
    --
    -- TODO: Add component declaration for tds_monitor
    ----------------------------------------------------------------
    
    component tds_monitor is 
        port(
        adc     : in  std_logic_vector(11 downto 0);

        hex0    : out std_logic_vector(6 downto 0);
        hex1    : out std_logic_vector(6 downto 0);
        hex2    : out std_logic_vector(6 downto 0);
        hex3    : out std_logic_vector(6 downto 0);
        led     : out std_logic
    );

    end component;

begin

    ----------------------------------------------------------------
    -- Device Under Test
    --
    -- TODO: Instantiate the tds_monitor component and connect the signals
    ----------------------------------------------------------------

    dut: tds_monitor 
        port map(
        adc => adc,
        hex0 => hex0,
        hex1 => hex1,
        hex2 => hex2,
        hex3 => hex3,
        led => led
    );
    

    ----------------------------------------------------------------
    -- Test Stimulus
    --
    -- The test stimulus is a series of ADC values that correspond to 
    -- various TDS levels. The LED output is expected to turn on when 
    -- the TDS level exceeds the threshold defined in the tds_monitor entity.
    --
    -- ADC = Vin * (4095 / 3.3)
    -- Vin = (ADC / 4095) * 3.3

    -- LED states assume TDS_THRESHOLD => 250 in tds_monitor.
    ----------------------------------------------------------------
    stimulus : process
    begin

        -- 0.000 V : 0000 ppm, LED off (dry probe)
        adc <= X"000";
        wait for 20 ns;
        ----------------------------------------------------------------
        -- TODO: Add more test cases for different ADC values 
        ----------------------------------------------------------------

             --test case: approximately 250 ppm (threshold)
        -- adc = 832, input voltage around 0.534 V
        -- expected LED state: OFF
        adc <= X"340";
        wait for 20 ns;

        --test case: max ppm (around 2416)
        -- adc = 4095, input voltage around 3.3V
        --expected LED state: ON
        adc<= X"FFF";
        wait for 20 ns;

        --test case: min ppm (0)
        -- adc = 0, input voltage around 0V
        --expected LED state: OFF
        adc<= X"000";
        wait for 20 ns;

        --test case: increasing ppm, from below to above threshold

        -- around 93 ppm
        --adc = 300, input voltage around 0.24V
        -- expected LED state: off
        adc<= X"12C";
        wait for 20 ns;

        -- around 160 ppm
        --adc = 512, input voltage around 0.412V
        -- expected LED state: OFF
        adc<= X"200";
        wait for 20 ns;

         -- 196 ppm
         --adc = 640, input voltage around 0.516V
        -- expected LED state: OFF
        adc<= X"280";
        wait for 20 ns;

        -- 268 ppm (crossing threshold)
        --adc = 896, input voltage around 0.722V
        -- expected LED state: ONN
        adc <= X"380";
        wait for 20 ns;
    
        -- 659 ppm
        --adc = 2048, input voltage around 1.650 V
        --expected LED state: ON
        adc <= X"800";
        wait for 20 ns;

        --test case: going from above to below theshold
        -- 80 ppm
        --adc = 256, input voltage around 0.206 V
        --expected LED state: OFF
        adc <= X"100";
        wait for 20 ns;

        -- wait forever
        wait;

    end process stimulus;

end architecture behavioral;
