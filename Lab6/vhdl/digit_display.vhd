library ieee;
use ieee.std_logic_1164.all;

entity digit_display is
    port(
        clk  : in std_logic;
        rst  : in std_logic;
        din  : in std_logic_vector(3 downto 0);
        dout : out std_logic_vector(6 downto 0)
    );
end entity digit_display;

architecture data_flow of digit_display is
begin
    ----------------------------------------------------------
    -- TODO: Implement a clocked process for a seven-segment 
    -- digit display.  The output is active low.
    ----------------------------------------------------------
    dout <= (others => '1');  -- default to blank

end architecture data_flow;