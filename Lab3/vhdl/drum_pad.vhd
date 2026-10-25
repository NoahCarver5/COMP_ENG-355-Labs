library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.audio_package.all;

-----------------------------------------------------------------------
-- drum_pad
--
-- Structural top level of the drum machine (everything except the
-- audio codec interface). Four push buttons play kick, snare, hi-hat
-- and crash samples, and a metronome plays a click at a tempo chosen
-- with the switches. The five voices are mixed into one 16-bit audio
-- stream.
--
--   audio_pulse : divides clk down to a one-cycle pulse at
--                 SAMPLE_RATE_HZ. Every other module advances one
--                 audio sample per pulse.
--   metronome   : while sw(0) is on, triggers the click voice at the
--                 tempo selected by sw(2 downto 1) and blinks led.
--   drum_voice  : one instance per voice (gen_voices). A trigger
--                 starts it stepping a ROM address through its sample,
--                 one address per pulse, until the sample ends.
--   rom_process : reads each voice's address from its sample ROM in
--                 audio_package (KICK, SNARE, HIHAT, CRASH, CLICK).
--   audio_mixer : sums the five voice samples into one output sample
--                 once per pulse.
--
-- The keys are active-high (inverted in drum_pad_system), so voice i
-- is triggered directly by key(i).
--
--               +-------------+
--   clk, rst -->| audio_pulse |-- pulse --+----------------> sample_pulse
--               +-------------+           |  (pulse also goes to the
--                                         |   metronome, every drum_voice
--                                         v   and the audio_mixer)
--                                +--------------+   +-------+
--   key(0) --------------------->| drum_voice 0 |-->| KICK  |--+|
--   key(1) --------------------->| drum_voice 1 |-->| SNARE |--+|
--   key(2) --------------------->| drum_voice 2 |-->| HIHAT |--+|
--   key(3) --------------------->| drum_voice 3 |-->| CRASH |--+|
--                         +----->| drum_voice 4 |-->| CLICK |--+|
--                         |      +--------------+   +-------+   |
--                         |       gen_voices       rom_process  |
--                         |   voice_trigger -> voice_address    |
--                         |        -> rom_sample -> voice_sample|
--            +-----------+|                                     |
--   sw(0) -->|           |+ metronome_trigger                   |
--            | metronome |                                      |
--   sw(2:1)->|           |--> led                               |
--            +-----------+                                      |
--                                    voice_samples_flat         |
--                                    (5 x DATA_WIDTH bits)      |
--                                     +-------------+           |
--                                     | audio_mixer |<----------+
--                                     +-------------+
--                                            |
--                                            +-----------------> audio_out
-----------------------------------------------------------------------

entity drum_pad is
    generic(
        DATA_WIDTH     : natural := 16;
        CLK_FREQUENCY  : natural := 50_000_000;
        SAMPLE_RATE_HZ : natural := 32_000
    );
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        key          : in  std_logic_vector(3 downto 0);
        sw           : in  std_logic_vector(2 downto 0);
        led          : out std_logic;
        sample_pulse : out std_logic;
        audio_out    : out std_logic_vector(15 downto 0)
    );
end entity drum_pad;


architecture structure of drum_pad is

    ----------------------------------------------------------------
    -- Constant declarations
    ----------------------------------------------------------------
    constant NUM_VOICES     : natural := 5;

    ----------------------------------------------------------------
    -- Type declarations
    ----------------------------------------------------------------
    type address_array_t is array (0 to NUM_VOICES-1) of std_logic_vector(ROM_ADDR_WIDTH-1 downto 0);
    type sample_array_t is array (0 to NUM_VOICES-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------

    signal pulse : std_logic;
    signal metronome_trigger : std_logic;
    signal voice_trigger : std_logic_vector(NUM_VOICES-1 downto 0);
    signal voice_address : address_array_t; -- output of drum_voice into ROM
    signal ROM_sample : sample_array_t; -- output of ROM into mixer
    signal voice_sample : sample_array_t;
    signal voice_sample_flat : std_logic_vector(NUM_VOICES*DATA_WIDTH - 1 downto 0);

    ----------------------------------------------------------------
    -- Component declarations
    ----------------------------------------------------------------

    component audio_pulse is
        generic(
        CLK_FREQUENCY  : natural := 50_000_000;
        SAMPLE_RATE_HZ : natural := 48_000
        );
        port(
            clk   : in  std_logic;
            rst   : in  std_logic;
            pulse : out std_logic
        );
    end component audio_pulse;

    component metronome is
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
    end component metronome;
    
    component drum_voice is
        generic(
            ADDR_WIDTH   : natural := 10;
            DATA_SIZE    : natural  := 1024
        );
        port(
            clk         : in  std_logic;
            rst         : in  std_logic;
            pulse       : in  std_logic;
            trigger     : in  std_logic;
            rom_address : out std_logic_vector(ADDR_WIDTH-1 downto 0);
            active      : out std_logic
        );
    end component drum_voice;

    component audio_mixer is
        generic(
            NUM_VOICES  : natural := 5;
            DATA_WIDTH  : natural := 16
        );
        port(
            clk           : in  std_logic;
            rst           : in  std_logic;
            pulse         : in  std_logic;
            voice_samples : in  std_logic_vector(NUM_VOICES * DATA_WIDTH - 1 downto 0);
            audio         : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component audio_mixer;

begin

    ----------------------------------------------------------------
    -- TODO: Instatiate the audio_pulse, metronome, and drum_voice 
    -- components. 
    ----------------------------------------------------------------

    audio_pulse_inst : audio_pulse
        generic map (
            CLK_FREQUENCY => CLK_FREQUENCY,
            SAMPLE_RATE_HZ => SAMPLE_RATE_HZ
        )
        port map (
            clk => clk,
            rst => rst,
            pulse => pulse
        );
    
    metronome_inst : metronome
        generic map(
            SAMPLE_RATE_HZ => SAMPLE_RATE_HZ
        )
        port map(
            clk => clk,
            rst => rst,
            pulse => pulse,
            enable => sw(0),
            speed => sw(2 downto 1),
            trigger => metronome_trigger,
            led => led
        );



    ----------------------------------------------------------------
    -- TODO: Implement drum voices using the for-generate statement. 
    -- Each voice should be an instance of the drum_voice entity, 
    -- and should be connected to the appropriate voice_trigger and 
    -- voice_address signals. The voice_trigger signals should be 
    -- connected to the appropriate key inputs and the metronome 
    -- trigger for the click voice. The voice_address signals should 
    -- be connected to the rom_process for reading the sample data 
    -- from the ROMs.
    ----------------------------------------------------------------

    sample_pulse <= pulse;

    -- voice triggers: push_buttons are active-low (negated at system-level)
    voice_trigger(0) <= key(0);
    voice_trigger(1) <= key(1);
    voice_trigger(2) <= key(2);
    voice_trigger(3) <= key(3);
    voice_trigger(4) <= metronome_trigger; -- Voice 4 triggered by metronome

    gen_drum_voices : for i in 0 to NUM_VOICES - 1 generate
        drum_voice_inst : drum_voice
            generic map(
            ADDR_WIDTH  => ROM_ADDR_WIDTH,
            DATA_SIZE => ROM_DEPTH
            )
            port map(
                clk => clk,
                rst => rst,
                pulse => pulse,
                trigger => voice_trigger(i),
                rom_address => voice_address(i),
                active => open
            );
    end generate gen_drum_voices;


    ----------------------------------------------------------------
    -- TODO: Implement the ROM lookup process. It should read the 
    -- sample data from the appropriate ROMs based on the voice_address 
    -- signals, and output the sample data to the voice_sample signals.
    -- The voice_sample signals should be registered to avoid timing 
    -- issues with the audio_mixer. 

    -- The ROM constant arrays are defined in audio_package. The lookups
    -- must be registered (with no reset) so Quartus infers M20K block
    -- ROMs; a combinational read would be built from LUTs instead.
    -- The second register stage uses the M20K output registers,
    -- keeping the slow ROM read path out of the mixer's timing path.
    ----------------------------------------------------------------
    rom_process : process(clk)
    begin
        if rising_edge(clk) then
            ROM_sample(0) <= KICK_ROM(to_integer(unsigned(voice_address(0))));
            ROM_sample(1) <= SNARE_ROM(to_integer(unsigned(voice_address(1))));
            ROM_sample(2) <= HIHAT_ROM(to_integer(unsigned(voice_address(2))));
            ROM_sample(3) <= CRASH_ROM(to_integer(unsigned(voice_address(3))));
            ROM_sample(4) <= CLICK_ROM(to_integer(unsigned(voice_address(4))));
            voice_sample <= ROM_sample;
        end if;
    end process rom_process;

    flatten_samples : for i in 0 to NUM_VOICES - 1 generate
        voice_sample_flat((i+1) * DATA_WIDTH - 1 downto i * DATA_WIDTH) <= voice_sample(i);
    end generate;

    audio_mixer_inst : audio_mixer
    generic map(
        NUM_VOICES => NUM_VOICES,
        DATA_WIDTH => DATA_WIDTH
    )
    port map(
        clk => clk,
        rst => rst,
        pulse => pulse,
        voice_samples => voice_sample_flat,
        audio => audio_out
    );

end architecture structure;