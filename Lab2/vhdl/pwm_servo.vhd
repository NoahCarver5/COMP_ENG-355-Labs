library ieee;
use ieee.std_logic_1164.all;

entity pwm_servo is
    generic(
        INVERT : boolean := false
    );
    port(
        clk   : in  std_logic;
        reset : in  std_logic;
        deg   : in  std_logic_vector(2 downto 0);
        pwm   : out std_logic
    );
end entity pwm_servo;

architecture rtl of pwm_servo is

    -- one pwm period at 50 mhz is 20 ms when the counter reaches 1,000,000.
    constant PERIOD_CYCLES : natural := 1000000;

    -- servo pulse widths for the five supported positions.
    constant PULSE_MIN  : natural := 25000;
    constant PULSE_45   : natural := 50000;
    constant PULSE_90   : natural := 75000;
    constant PULSE_135  : natural := 100000;
    constant PULSE_MAX  : natural := 125000;

    signal counter     : natural range 0 to PERIOD_CYCLES - 1;
    signal pulse_width : natural range PULSE_MIN to PULSE_MAX;
    signal pulse_high  : natural range PULSE_MIN to PULSE_MAX;

begin

    -- map the 3-bit command to a servo pulse width in clock cycles.
    pulse_width <= PULSE_MIN when deg = "000" else
                   PULSE_45  when deg = "001" else
                   PULSE_90  when deg = "010" else
                   PULSE_135 when deg = "011" else
                   PULSE_MAX when deg = "100" else
                   PULSE_MIN;

    -- mirror the pulse width for a servo mounted in the reverse direction.
    pulse_high <= (PULSE_MIN + PULSE_MAX - pulse_width) when INVERT else
                  pulse_width;

    pwm_process : process(clk, reset)
    begin
        if (reset = '1') then
            counter <= 0;
            pwm <= '0';
        elsif ( rising_edge(clk) ) then
            counter <= counter + 1;
            if (counter = PERIOD_CYCLES - 1) then
                counter <= 0;
            end if;
            if ( counter < pulse_high) then
                pwm <= '1';
            else
                pwm <= '0';
            end if;
        end if;
    end process pwm_process;

end architecture rtl;