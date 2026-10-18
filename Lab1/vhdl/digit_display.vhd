library ieee;
use ieee.std_logic_1164.all;

entity digit_display is
port(
	din  : in std_logic_vector(3 downto 0);
	dout : out std_logic_vector(6 downto 0)
);
end entity digit_display;         

architecture data_flow of digit_display is
begin
    ----------------------------------------------------------------
    -- Dataflow description of the 7-segment display
    -- The 7-segment display is active low, so a '0' turns on
    -- the corresponding segment.
    --
    -- TODO: Complete the dataflow description of the 7-segment display
    -- using a WHEN-ELSE statement to map the 4-bit binary input to 
    -- the 7-segment output.

    dout <= "1000000" when din = "0000" else
            "1111001" when din = "0001" else
            "0100100" when din = "0010" else
            "0110000" when din = "0011" else
            "0011001" when din = "0100" else
            "0010010" when din = "0101" else
            "0000010" when din = "0110" else
            "1111000" when din = "0111" else
            "0000000" when din = "1000" else
            "0011000" when din = "1001" else
            "1111111";
    -- ---------------------------------------------------------------      
	
    
end architecture data_flow;            