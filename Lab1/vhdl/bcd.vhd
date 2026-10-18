library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

------------------------------------------------------------------
-- Entity Declaration: Binary to BCD Converter
------------------------------------------------------------------
entity bcd is
    port(
        bin       : in  std_logic_vector(11 downto 0);
        thousands : out std_logic_vector(3 downto 0);
        hundreds  : out std_logic_vector(3 downto 0);
        tens      : out std_logic_vector(3 downto 0);
        ones      : out std_logic_vector(3 downto 0)
    );
end entity bcd;

-------------------------------------------------------------------
-- Architecture Declaration: Behavioral
-------------------------------------------------------------------
architecture behavioral of bcd is
begin

    ----------------------------------------------------------------
    -- Double dabble (shift-and-add-3)
    --
    -- The binary input is shifted left one bit at a time into the
    -- BCD digits. Before each shift, any digit of 5 or more has 3
    -- added so that it carries into the next digit when doubled.
    ----------------------------------------------------------------
    process(bin)
        -- 16 bits of BCD digits followed by the 12-bit binary input
        variable shift : std_logic_vector(27 downto 0);
    begin
        shift := X"0000" & bin;

        for i in 0 to 11 loop
            -- Add 3 to any BCD digit that is 5 or more
            if shift(15 downto 12) > 4 then shift(15 downto 12) := shift(15 downto 12) + 3; end if;
            if shift(19 downto 16) > 4 then shift(19 downto 16) := shift(19 downto 16) + 3; end if;
            if shift(23 downto 20) > 4 then shift(23 downto 20) := shift(23 downto 20) + 3; end if;
            if shift(27 downto 24) > 4 then shift(27 downto 24) := shift(27 downto 24) + 3; end if;

            -- Shift everything left by one bit
            shift := shift(26 downto 0) & '0';
        end loop;

        thousands <= shift(27 downto 24);
        hundreds  <= shift(23 downto 20);
        tens      <= shift(19 downto 16);
        ones      <= shift(15 downto 12);
    end process;

end architecture behavioral;
