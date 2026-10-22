library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity metronome is
    generic(
        SAMPLE_RATE_HZ : natural := 48_000
    );
    port(
        clk     : in  std_logic;
        rst     : in  std_logic;
        pulse   : in  std_logic;
        enable  : in  std_logic;
        speed   : in  std_logic_vector(1 downto 0);
        trigger : out std_logic;
        led     : out std_logic
    );
end entity metronome;

architecture behavioral of metronome is

    ----------------------------------------------------------------
    -- Function to compute the number of audio samples per beat
    ----------------------------------------------------------------
    function samples_per_beat(sel : std_logic_vector(1 downto 0)) return natural is
        constant SAMPLES_PER_BEAT : natural := SAMPLE_RATE_HZ * 60;
    begin
        case sel is
            when "00" => return SAMPLES_PER_BEAT / 60;
            when "01" => return SAMPLES_PER_BEAT / 90;
            when "10" => return SAMPLES_PER_BEAT / 120;
            when "11" => return SAMPLES_PER_BEAT / 180;
            when others => return SAMPLES_PER_BEAT / 60;
        end case;
    end function;

    ----------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------
    -- 100 ms flash, shorter than the fastest beat (180 BPM = 333 ms).
    constant LED_HOLD_SAMPLES : natural := SAMPLE_RATE_HZ / 10;

    ----------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------
    signal beat_counter : natural range 0 to SAMPLE_RATE_HZ;
    signal led_counter  : natural range 0 to SAMPLE_RATE_HZ;
    signal led_reg      : std_logic;
    signal trigger_reg  : std_logic;

begin

    ----------------------------------------------------------------
    -- Metronome pulse generator
    --
    -- The `pulse` input is a one-clock strobe at the audio sample rate
    -- (48 kHz). We count those pulses and assert `trigger` for one `clk`
    -- cycle every beat interval set by `speed`.
    ----------------------------------------------------------------
    metronome_process : process(clk, rst)
        variable beat_divider : natural;
    begin
        if ( rst = '1' ) then
            beat_counter <= 0;
            trigger_reg <= '0';
        elsif ( rising_edge(clk) ) then
            trigger_reg <= '0';
            beat_divider := samples_per_beat(speed);

            if ( enable = '0' ) then
                beat_counter <= 0;
            elsif ( pulse = '1' ) then
                beat_counter <= beat_counter + 1;
                if ( beat_counter >= beat_divider-1 ) then
                    trigger_reg <= '1';
                    beat_counter <= 0;
                end if;
            end if;
        end if;
    end process;

    trigger <= trigger_reg;

    ----------------------------------------------------------------
    -- LED indicator for metronome trigger
    -- Flashes for LED_HOLD_SAMPLES after each metronome trigger.
    -- Each trigger restarts the flash so every beat is visible.
    ----------------------------------------------------------------
    led_process : process(clk, rst)
    begin
        if ( rst = '1' ) then
            led_reg     <= '0';
            led_counter <= 0;
        elsif ( rising_edge(clk) ) then
            if ( trigger_reg = '1' ) then
                led_reg     <= '1';
                led_counter <= 0;
            elsif ( led_reg = '1' and pulse = '1' ) then
                if ( led_counter >= LED_HOLD_SAMPLES-1 ) then
                    led_reg     <= '0';
                    led_counter <= 0;
                else
                    led_counter <= led_counter + 1;
                end if;
            end if;
        end if;
    end process;

    led <= led_reg;

end architecture behavioral;