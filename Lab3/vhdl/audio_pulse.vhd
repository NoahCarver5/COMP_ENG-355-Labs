library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_pulse is
    generic(
        CLK_FREQUENCY   : natural := 50_000_000;
        SAMPLE_RATE_HZ  : natural := 48_000
    );
    port(
        clk   : in  std_logic;
        rst   : in  std_logic;
        pulse : out std_logic
    );
end entity audio_pulse;

architecture behavioral of audio_pulse is

    constant AUDIO_DIVIDER : natural := CLK_FREQUENCY / SAMPLE_RATE_HZ;

    signal pulse_counter : natural range 0 to AUDIO_DIVIDER - 1;
    
begin
    ------------------------------------------------------------------------------
    -- TODO: Implement the audio sample pulse generator. It should only assert 
    -- the pulse output for one clock cycle every 1/SAMPLE_RATE_HZ seconds 
    -- (e.g. when the pulse counter reaches AUDIO_DIVIDER-1).
    ----------------------------------------------------------------
    audio_pulse_process : process(clk, rst)
    begin
        if ( rst = '1' ) then
            pulse <= '0';
        elsif ( rising_edge(clk) ) then
            if (pulse_counter = AUDIO_DIVIDER - 1) then
                pulse <= '1';
                pulse_counter <= 0;
            else
                pulse <= '1';
                pulse_counter <= pulse_counter + 1;
            end if;
        end if;
    end process;

end architecture behavioral;