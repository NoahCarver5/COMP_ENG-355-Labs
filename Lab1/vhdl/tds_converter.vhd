library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

------------------------------------------------------------------
-- Entity Declaration: TDS Converter
------------------------------------------------------------------
entity tds_converter is
    generic(
        TDS_THRESHOLD : integer := 250  -- ppm
    );
    port(
        adc         : in  std_logic_vector(11 downto 0);
        tds         : out std_logic_vector(11 downto 0);
        threshold   : out std_logic
    );
end entity tds_converter;

------------------------------------------------------------------
-- Architecture Declaration: Data Flow
--
-- The sensor voltage is converted to TDS (ppm) using the
-- manufacturer's calibration curve (at 25 C):
--
--     V   = adc * 3.3 / 4095
--     TDS = (133.42*V^3 - 255.86*V^2 + 857.39*V) * 0.5
--
-- Instead of multiplying, the curve is split into 8 segments of
-- 512 ADC counts, selected by the top 3 bits of the ADC sample.
-- Each segment starts at the curve's value and adds the offset
-- within the segment scaled by right shifts.
--
--     adc      voltage          start ppm   slope (ppm/count)
--     0x000    0.000 - 0.412 V      0       1/4 + 1/16
--     0x200    0.413 - 0.824 V    160       1/4 + 1/32
--     0x400    0.825 - 1.237 V    304       1/4 + 1/16
--     0x600    1.238 - 1.649 V    461       1/4 + 1/8
--     0x800    1.650 - 2.062 V    659       1/2 + 1/128
--     0xA00    2.063 - 2.475 V    926       1/2 + 1/4
--     0xC00    2.476 - 2.887 V   1289       1
--     0xE00    2.888 - 3.300 V   1778       1   + 1/4
------------------------------------------------------------------
architecture data_flow of tds_converter is
    signal offset : std_logic_vector(11 downto 0);
    signal tds_i  : std_logic_vector(11 downto 0);

begin
    ----------------------------------------------------------------
    -- Output the ADC voltage x 100 instead of TDS
    -- (e.g. 2.50 V displays as 0250)
    --
    --     V * 100 = adc * 330 / 4095  ~=  adc * 165 / 2048
    --
    -- adc * 165 = adc*128 + adc*32 + adc*4 + adc, then divide by 2048
    -- (shift right 11). Adding 1024 first rounds to the nearest 0.01 V.
    ----------------------------------------------------------------

    -- Position of the sample within its segment (0 to 511)
    offset <= "000" & adc(8 downto 0);
    
    ----------------------------------------------------------------
    -- TDS conversion using a WITH-SELECT statement
    --
    -- TODO: Complete the dataflow description of the TDS converter 
    -- using a WITH-SELECT statement to map the 4-bit binary input 
    -- to the 7-segment output.
    ----------------------------------------------------------------
    with adc(11 downto 9) select
        tds_i <= 0 + shift_right(offset, 2) + shift_right(offset, 4) when "000",
                 160 + shift_right(offset, 2) + shift_right(offset, 5) when "001",
                 304 + shift_right(offset, 2) + shift_right(offset, 4) when "010",
                 461 + shift_right(offset, 2) + shift_right(offset, 3) when "011",
                 659 + shift_right(offset, 1) + shift_right(offset, 7) when "100",
                 926 + shift_right(offset, 1) + shift_right(offset, 2) when "101",
                 1289 + offset when "110",
                 1778 + offset + shift_right(offset, 2) when "111",
                 (others=> '0') when others;


    tds <= tds_i;

    -- Threshold detection
    threshold <= '1' when tds_i > TDS_THRESHOLD else '0';

end architecture data_flow;
