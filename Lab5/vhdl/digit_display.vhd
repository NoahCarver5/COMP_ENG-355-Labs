library ieee;
use ieee.std_logic_1164.all;

--------------------------------------------------------------------------
-- One seven-segment digit.  From Lab 1, with a register added.
--
-- A nibble in, seven ACTIVE LOW segments out, decoding 0-F.  Bit 0 is
-- segment a and a '0' lights it, which is how the board is wired.
--
-- Reset blanks the digit rather than showing a zero: the segments are
-- active low, so all ones is dark.  "Held in reset" then looks different
-- from "running, displaying 0", which is worth being able to tell apart.
--------------------------------------------------------------------------

entity digit_display is
port(
    clock : in std_logic;
    reset : in std_logic;                      -- async, active high
    din  : in std_logic_vector(3 downto 0);
    dout : out std_logic_vector(6 downto 0)
);
end entity digit_display;

architecture rtl of digit_display is
begin
    ----------------------------------------------------------
    -- TODO: Implement a clocked process for a seven-segment 
    -- digit display.  The output is active low.
    ----------------------------------------------------------
    
    process(clock, reset) begin

        if (reset = '1') then

            dout <= "1111111";
        
        elsif rising_edge(clock) then

            case din is
                when "0000" => dout <= "1000000";
                when "0001" => dout <= "1111001";
                when "0010" => dout <= "0100100";
                when "0011" => dout <= "0110000";
                when "0100" => dout <= "0011001";
                when "0101" => dout <= "0010010";
                when "0110" => dout <= "0000010";
                when "0111" => dout <= "1111000";
                when "1000" => dout <= "0000000";
                when "1001" => dout <= "0011000";
                when "1010" => dout <= "0001000";
                when "1011" => dout <= "0000011";
                when "1100" => dout <= "1000110";
                when "1101" => dout <= "0100001";
                when "1110" => dout <= "0000110";
                when "1111" => dout <= "0001110";
                when others => dout <= "1111111";
            end case;
        end if;
    end process;

end architecture rtl;
