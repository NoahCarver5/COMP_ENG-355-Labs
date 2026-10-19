library ieee;
use ieee.std_logic_1164.all;

entity robotic_hand_tb is
end entity robotic_hand_tb;

architecture behavioral of robotic_hand_tb is

    ----------------------------------------------------------------
    -- Signals connected to the device under test
    ----------------------------------------------------------------
    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal rst_n : std_logic := '1';
    signal sw    : std_logic_vector(9 downto 0) := (others => '0');
    signal pwm   : std_logic_vector(4 downto 0) := (others => '0');
    signal led   : std_logic_vector(9 downto 0) := (others => '0');

    ----------------------------------------------------------------
    -- Component Declaration: Device Under Test
    ----------------------------------------------------------------
    component robotic_hand is
        port(
            clk   : in  std_logic;
            rst_n : in  std_logic;
            sw    : in  std_logic_vector(9 downto 0);
            pwm   : out std_logic_vector(4 downto 0);
            led   : out std_logic_vector(9 downto 0)
        );
    end component robotic_hand;

begin

    ----------------------------------------------------------------
    -- Component instantiation
    -- 
    -- TODO: instantiate the robotic_hand component 
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- Clock and Reset Processes
    --
    -- TODO: add processes to generate the clock and reset
    ----------------------------------------------------------------
    rst_n <= not rst;
    

    ----------------------------------------------------------------
    -- Test Stimulus
    --
    -- TODO: add a process to generate test stimulus for the robotic_hand
    -- by driving the sw inputs.  The test should exercise all of the switch
    -- positions, and should hold the switches in the "ok" position for a
    -- long enough time to see the hand perform the "ok" gesture.
    ----------------------------------------------------------------
    stimulus : process
    begin
        sw <= (others => '0');

        -- wait forever
        wait;
    end process stimulus;

end architecture behavioral;