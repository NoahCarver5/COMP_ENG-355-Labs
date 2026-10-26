library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-----------------------------------------------------------------------
-- drum_pad_system
--
-- Board-level top of the drum machine for the DE25-Standard. It
-- connects the drum_pad (sample playback, metronome and mixer) to the
-- audio_codec, which sends the mixed audio to the SSM2603 codec chip.
--
--   drum_pad    : turns key presses and the metronome into one
--                 DATA_WIDTH-bit audio sample per sample_pulse.
--   audio_codec : configures the SSM2603 over I2C after power-up,
--                 then generates the codec clocks (AUD_XCK, AUD_BCLK,
--                 AUD_DACLRCK) and shifts each audio sample out
--                 serially on AUD_DACDAT.
--
-- Both modules use the same CLK_FREQUENCY and SAMPLE_RATE_HZ, so the
-- drum_pad's sample_pulse matches the codec's sample rate. The push
-- buttons (rst_n, key) and the LED (led_n) are active-low on the board
-- and are inverted here, so drum_pad only sees active-high signals.
--
--                     +------------+                +-------------+
--   clk ------------->| clk        |  sample_pulse  | pulse       |
--                     |            |--------------->|             |--> AUD_XCK
--                     |  drum_pad  |                |             |--> AUD_BCLK
--                     |            |                | audio_codec |--> AUD_DACLRCK
-- key_n(3:0) -[not]-->| key        | audio_sample   |             |--> AUD_DACDAT
--   sw(2:0)  -------->| sw         |--------------->| audio       |--> FPGA_I2C_SCL
--   led_n <-[not]-----| led        |                |             |<-> FPGA_I2C_SDA
--   rst_n --[not]-+-->| rst        |      clk ----->| clk         |
--                 |   +------------+                |             |
--                 +-------------------------------->| rst         |
--                                                   +-------------+
--
--   sw(0)    : metronome on/off
--   sw(2:1)  : metronome tempo
--   key(3:0) : kick, snare, hi-hat, crash (active-low push buttons)
--   led_n    : blinks with the metronome
-----------------------------------------------------------------------

entity drum_pad_system is
    generic(
        DATA_WIDTH     : natural := 16;
        CLK_FREQUENCY  : natural := 50_000_000;
        SAMPLE_RATE_HZ : natural := 32_000
    );
    port(
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        key_n        : in  std_logic_vector(3 downto 0);
        sw           : in  std_logic_vector(2 downto 0);
        led_n        : out std_logic;

        AUD_XCK      : out std_logic;
        AUD_BCLK     : out std_logic;
        AUD_DACLRCK  : out std_logic;
        AUD_DACDAT   : out std_logic;
        FPGA_I2C_SCL : out std_logic;
        FPGA_I2C_SDA : inout std_logic
    );
end entity drum_pad_system;

architecture structure of drum_pad_system is

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------
    signal rst : std_logic;
    signal led_inv : std_logic;
    signal pulse_signal : std_logic;
    signal audio_sample : std_logic_vector (15 downto 0);
    signal key : std_logic_vector (3 downto 0);

    ----------------------------------------------------------------
    -- Component Declarations
    ----------------------------------------------------------------

    component drum_pad is
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        key          : in  std_logic_vector(3 downto 0);
        sw           : in  std_logic_vector(2 downto 0);
        led          : out std_logic;
        sample_pulse : out std_logic;
        audio_out    : out std_logic_vector(15 downto 0)
    );
    end component drum_pad;

    component audio_codec is
    generic(
        DATA_WIDTH     : natural := 16;
        CLK_FREQUENCY  : natural := 50_000_000;
        SAMPLE_RATE_HZ : natural := 32_000
    );
    port(
        clk         : in  std_logic;
        rst         : in  std_logic;
        pulse       : in  std_logic;
        audio       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        AUD_XCK     : out std_logic;
        AUD_BCLK    : out std_logic;
        AUD_DACLRCK : out std_logic;
        AUD_DACDAT  : out std_logic;
        FPGA_I2C_SCL : out std_logic;
        FPGA_I2C_SDA : inout std_logic
    );
    end component audio_codec;


begin

    ------------------------------------------------------------------
    -- TODO: concurrent signal assignments for the reset, key and led
    -- signals, which are all active low. 
    ------------------------------------------------------------------
    key <= not(key_n);
    rst <= not(rst_n);
    led_n <= not(led_inv);
    ------------------------------------------------------------------
    -- TODO: Component instantiations of the drum_pad and audio_codec. 
    ------------------------------------------------------------------

    drum_pad_inst : drum_pad 
    port map(
        clk => clk,
        rst => rst,
        key => key,
        sw => sw,
        led => led_inv,
        sample_pulse => pulse_signal,
        audio_out => audio_sample
    );

        audio_codec_inst: audio_codec

    port map(
        clk => clk,
        rst => rst,
        pulse => pulse_signal,
        audio => audio_sample,
        AUD_XCK => AUD_XCK,
        AUD_BCLK => AUD_BCLK,
        AUD_DACLRCK => AUD_DACLRCK,
        AUD_DACDAT => AUD_DACDAT,
        FPGA_I2C_SCL => FPGA_I2C_SCL,
        FPGA_I2C_SDA => FPGA_I2C_SDA
    );


end architecture structure;
