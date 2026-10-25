library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-----------------------------------------------------------------------
-- drum_voice
--
-- Plays one drum sample by stepping an address through its sample
-- ROM. The ROM itself lives outside this module; drum_voice only
-- produces the address, so the same module works for every voice.
--
-- Operation:
--   idle     : playing = '0' and address = 0. Pulses are ignored.
--   trigger  : on any clock where trigger = '1', address restarts at
--              0 and playing goes to '1'. A trigger during playback
--              restarts the sample from the beginning.
--   playing  : on each sample pulse, address advances by one, so the
--              ROM outputs one new sample per pulse.
--   end      : on the pulse when address reaches DATA_SIZE-1, address
--              returns to 0 and playing goes back to '0'.
--
-- trigger is level-sensitive and has priority over pulse. While it
-- is held high, the address stays at 0, so the sample plays once
-- trigger is released.
--
-- Generics:
--   ADDR_WIDTH : width of rom_address; must be able to hold DATA_SIZE-1
--   DATA_SIZE  : number of samples to play before stopping
--
-- Outputs:
--   rom_address : current ROM address for this voice
--   active      : '1' while the sample is playing
-----------------------------------------------------------------------

entity drum_voice is
    generic(
        ADDR_WIDTH   : natural := 10;
        DATA_SIZE    : natural  := 1024
    );
    port(
        clk         : in  std_logic;
        rst         : in  std_logic;
        pulse       : in  std_logic;
        trigger     : in  std_logic;
        rom_address : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        active      : out std_logic
    );
end entity drum_voice;


architecture rtl of drum_voice is

    signal cur_address : std_logic_vector (ADDR_WIDTH-1 downto 0);
    signal play_flag : std_logic;

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------
begin

    ----------------------------------------------------------------
    -- TODO: Implement the clocked process to step through the ROM
    -- addresses on each pulse while playing. The process should also
    -- handle the trigger input to restart the sample from the beginning.
    --
    -- OUTPUTS:
    -- rom_address: should be registered to avoid timing issues with the ROM.
    -- active: should be '1' while the sample is playing.
    ----------------------------------------------------------------
    
    clocked_process: process(clk, rst)
    begin
        if ( rst = '1' ) then
            cur_address <= (others => '0');
            play_flag <= '0';
        elsif ( rising_edge(clk) ) then
            if (trigger = '1') then
                cur_address <= (others =>'0');
                play_flag <= '1';
            else
                if (play_flag = '1') then
                    if (to_integer(unsigned(cur_address)) = DATA_SIZE-1) then
                        play_flag <= '0';
                        cur_address <= (others => '0');
                    else 
                        play_flag <= '1';
                        cur_address <= STD_LOGIC_VECTOR(unsigned(cur_address) + 1);
                    end if;
                else
                    cur_address <= (others => '0');
                    play_flag <= '0';
                end if;
            end if;



            rom_address <= (others => '0');
            active      <= '0';
        end if;
    end process;

end architecture rtl;