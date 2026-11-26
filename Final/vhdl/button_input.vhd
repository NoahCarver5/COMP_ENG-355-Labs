library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.whac_pkg.all;

entity button_input is
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        key  : in  std_logic_vector(3 downto 0);  -- active-low, KEY[3:0]
        hand : out hand_t
    );
end entity button_input;

architecture rtl of button_input is

    -- Double-flop synchronizer registers
    signal key_s1, key_s2 : std_logic_vector(3 downto 0);

    -- Previous synchronized value for edge detection (key_s2 = '0' && key_prev = '1')
    signal key_prev : std_logic_vector(3 downto 0);

    -- Current hole index (0–5)
    signal hole_idx : unsigned(2 downto 0);

begin

    -- 2FF Synchronizers
    process(clk)
    begin
        if rising_edge(clk) then
            key_s1 <= key;
            key_s2 <= key_s1;
        end if;
    end process;

    -- register key_s2 into key_prev for falling-edge detection
    process(clk)
    begin
        if rising_edge(clk) then
            key_prev <= key_s2;
        end if;
    end process;

    -- move cursor logic
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                hole_idx    <= (others => '0');
                hand.strike <= '0';
            else
                hand.strike <= '0';

                if key_prev(3) = '1' and key_s2(3) = '0' then  -- KEY3: left
                    if hole_idx = 0 then
                        hole_idx <= to_unsigned(5, 3);
                    else
                        hole_idx <= hole_idx - 1;
                    end if;
                end if;

                if key_prev(2) = '1' and key_s2(2) = '0' then  -- KEY2: right
                    if hole_idx = 5 then
                        hole_idx <= to_unsigned(0, 3);
                    else
                        hole_idx <= hole_idx + 1;
                    end if;
                end if;

                if key_prev(0) = '1' and key_s2(0) = '0' then  -- KEY0: strike
                    hand.strike <= '1';
                end if;
            end if;
        end if;
    end process;

    hand.hole_idx <= hole_idx;

end architecture rtl;
