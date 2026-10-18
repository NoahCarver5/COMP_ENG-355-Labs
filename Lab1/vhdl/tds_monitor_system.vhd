library ieee;
use ieee.std_logic_1164.all;

------------------------------------------------------------------
-- Entity Declaration: TDS Monitor System
------------------------------------------------------------------
entity tds_monitor_system is
    port(
        clk      : in  std_logic;
        reset_n  : in  std_logic;

        -- TLA2518 SPI interface
        adc_dout : in  std_logic;
        adc_din  : out std_logic;
        adc_sclk : out std_logic;
        adc_cs_n : out std_logic;

        -- 7-segment displays
        hex0     : out std_logic_vector(6 downto 0);
        hex1     : out std_logic_vector(6 downto 0);
        hex2     : out std_logic_vector(6 downto 0);
        hex3     : out std_logic_vector(6 downto 0);

        -- LED
        led      : out std_logic
    );
end entity tds_monitor_system;

------------------------------------------------------------------
-- Architecture Declaration: Structural
------------------------------------------------------------------
architecture structural of tds_monitor_system is

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------
    signal adc_sample   : std_logic_vector(11 downto 0);
    signal threshold    : std_logic;

    ----------------------------------------------------------------
    -- Component declarations
    ----------------------------------------------------------------
    component tla2518_adc is
        generic(
            CLOCK_DIVIDER : positive := 25;
            PAUSE_CYCLES  : positive := 200_000_000
        );
        port(
            clk      : in  std_logic;
            reset_n  : in  std_logic;
            adc_dout : in  std_logic;
            adc_din  : out std_logic;
            adc_sclk : out std_logic;
            adc_cs_n : out std_logic;
            sample   : out std_logic_vector(11 downto 0)
        );
    end component tla2518_adc;

    component tds_monitor is
        port(
            adc     : in  std_logic_vector(11 downto 0);
            hex0    : out std_logic_vector(6 downto 0);
            hex1    : out std_logic_vector(6 downto 0);
            hex2    : out std_logic_vector(6 downto 0);
            hex3    : out std_logic_vector(6 downto 0);
            led     : out std_logic
        );
    end component tds_monitor;

begin

    ----------------------------------------------------------------
    -- TLA2518 ADC
    ----------------------------------------------------------------
    adc_inst : tla2518_adc
        port map(
            clk      => clk,
            reset_n  => reset_n,
            adc_dout => adc_dout,
            adc_din  => adc_din,
            adc_sclk => adc_sclk,
            adc_cs_n => adc_cs_n,
            sample   => adc_sample
        );

    ----------------------------------------------------------------
    -- TDS Monitor
    ----------------------------------------------------------------
    tds_monitor_inst : tds_monitor
        port map(
            adc     => adc_sample,
            hex0    => hex0,
            hex1    => hex1,
            hex2    => hex2,
            hex3    => hex3,
            led     => threshold
        );

    ----------------------------------------------------------------
    -- LED
    --
    -- The DE25-Standard LEDs are active low (driving the pin low
    -- turns the LED on), so invert the threshold output.
    ----------------------------------------------------------------
    led <= not threshold;

end architecture structural;
