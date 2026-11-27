library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.whac_pkg.all;

entity button_input is
    generic (
        DEBOUNCE_TICKS : natural := 2**20  -- ~10.5 ms @ 100 MHz
    );
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        key  : in  std_logic_vector(3 downto 0);  -- active-low, KEY[3:0]
        hand : out hand_t
    );
end entity button_input;

architecture rtl of button_input is

    -- Double-flop synchronizer registers
    signal key_s1, key_s2 : std_logic_vector(3 downto 0) := (others => '1');
    signal last_key       : std_logic_vector(3 downto 0) := (others => '1');

    -- Single shared debounce/one-shot counter
    signal key_cnt        : natural range 0 to DEBOUNCE_TICKS := 0;

    -- Current hole index (0–5)
    signal hole_idx       : unsigned(2 downto 0) := (others => '0');

begin

    -- 2FF Synchronizers
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                key_s1 <= (others => '1');
                key_s2 <= (others => '1');
            else
                key_s1 <= key;
                key_s2 <= key_s1;
            end if;
        end if;
    end process;

    -- Vector-level debounce + one-shot action on DEBOUNCE_TICKS - 1
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                last_key    <= (others => '1');
                key_cnt     <= 0;
                hole_idx    <= (others => '0');
                hand.strike <= '0';
            else
                last_key    <= key_s2;
                hand.strike <= '0'; -- Default: 1-cycle pulse only when strike fires

                if (last_key = key_s2 and key_s2 /= "1111") then
                    if (key_cnt = DEBOUNCE_TICKS - 1) then
                        key_cnt <= key_cnt + 1;

                        -- Ignore simultaneous left + right presses
                        if (key_s2(3) = '0' and key_s2(2) = '0') then
                            hole_idx <= hole_idx;
                        elsif (key_s2(3) = '0') then       -- KEY3: left (wraps 0 -> 5)
                            if (hole_idx = 0) then
                                hole_idx <= to_unsigned(5, 3);
                            else
                                hole_idx <= hole_idx - 1;
                            end if;
                        elsif (key_s2(2) = '0') then       -- KEY2: right (wraps 5 -> 0)
                            if (hole_idx = 5) then
                                hole_idx <= to_unsigned(0, 3);
                            else
                                hole_idx <= hole_idx + 1;
                            end if;
                        end if;

                        -- KEY0: strike (fires even if held with another key, or put in elsif if exclusive)
                        if (key_s2(0) = '0') then
                            hand.strike <= '1';
                        end if;

                    elsif (key_cnt < DEBOUNCE_TICKS) then
                        key_cnt <= key_cnt + 1;
                    end if;
                else
                    key_cnt <= 0;
                end if;
            end if;
        end if;
    end process;

    hand.hole_idx <= hole_idx;

end architecture rtl;