library ieee;
use ieee.std_logic_1164.all;

------------------------------------------------------------------
-- Entity Declaration: TDS Monitor
--
-- Monitors the TDS (Total Dissolved Solids) level using an ADC and 
-- displays it on 7-segment displays.
-- 
--        ADC (12-bit)
--            |
--            v
--        +------------------+
--        |   TDS Converter  |---------------------> LED
--        |   ADC → TDS ppm  |                      Threshold
--        +------------------+
--            |
--            | TDS Value (8-bit)
--            v
--        +------------------+
--        | Binary-to-BCD    |
--        +------------------+
--            |
--            +----------+----------+----------+
--            |          |          |          |
--            v          v          v          v
--         Digit 0    Digit 1    Digit 2    Digit 3
--         Decoder    Decoder    Decoder    Decoder
--            |          |          |          |
--            v          v          v          v
--           HEX0       HEX1       HEX2       HEX3
--           Ones       Tens     Hundreds   Thousands
--
------------------------------------------------------------------
entity tds_monitor is
    port(
        adc     : in  std_logic_vector(11 downto 0);

        hex0    : out std_logic_vector(6 downto 0);
        hex1    : out std_logic_vector(6 downto 0);
        hex2    : out std_logic_vector(6 downto 0);
        hex3    : out std_logic_vector(6 downto 0);
        led     : out std_logic
    );
end entity tds_monitor;

------------------------------------------------------------------
-- Architecture Declaration: Structural
------------------------------------------------------------------
architecture structural of tds_monitor is

    signal tds : std_logic_vector (11 downto 0);
    signal thousands: std_logic_vector (3 downto 0);
    signal hundreds : std_logic_vector (3 downto 0);
    signal tens : std_logic_vector (3 downto 0);
    signal ones : std_logic_vector (3 downto 0);

    ----------------------------------------------------------------
    -- Signal declarations
    --
    -- TODO: Add signal declarations 
    ----------------------------------------------------------------


    ----------------------------------------------------------------
    -- Component declarations
    --
    -- TODO: Add component declarations
    ----------------------------------------------------------------

    COMPONENT tds_converter is 
        port(

            adc         : in  std_logic_vector(11 downto 0);
            tds         : out std_logic_vector(11 downto 0);
            threshold   : out std_logic);

    END COMPONENT tds_converter;

    component bcd is 
        port(        
            bin       : in  std_logic_vector(11 downto 0);
            thousands : out std_logic_vector(3 downto 0);
            hundreds  : out std_logic_vector(3 downto 0);
            tens      : out std_logic_vector(3 downto 0);
            ones      : out std_logic_vector(3 downto 0)
        );

    end component bcd;

    component digit_display is 
        port(
            din : in std_logic_vector (3 downto 0);
            dout: out std_logic_vector (6 downto 0)
        );

    end component;

begin

    ----------------------------------------------------------------
    -- Component Instantiations
    --
    -- TODO: Add component instantiations
    ----------------------------------------------------------------
    tds_converter_instance: tds_converter 
    PORT MAP(adc => adc, tds => tds, threshold => led);

    bcd_instance: bcd
    port map (bin => tds, thousands => thousands, hundreds => hundreds, tens => tens, ones=> ones);

    digital_display_thousands: digit_display
    PORT MAP(din => thousands, dout=> hex3);
    
    digital_display_hundreds: digit_display
    port map(din=> hundreds, dout => hex2);

    digital_display_tens: digit_display
    PORT MAP(din => tens, dout=> hex1);
    
    digital_display_ones: digit_display
    port map(din=> ones, dout => hex0);
   

end architecture structural;
