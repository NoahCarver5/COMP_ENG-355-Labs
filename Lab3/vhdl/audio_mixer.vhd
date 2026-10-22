library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity audio_mixer is
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
end entity audio_mixer;


architecture behavioral of audio_mixer is

    -- number of bits needed to hold the values 0 to n-1.
    function clog2(n : natural) return natural is
        variable bits : natural := 0;
    begin
        while ( 2**bits < n ) loop
            bits := bits + 1;
        end loop;
        return bits;
    end function clog2;

    -- the sum of NUM_VOICES samples grows by clog2(NUM_VOICES) bits.
    constant SUM_WIDTH : natural := DATA_WIDTH + clog2(NUM_VOICES);
    constant AUDIO_MAX : integer := 2**(DATA_WIDTH-1)-1;
    constant AUDIO_MIN : integer := -(2**(DATA_WIDTH-1));

    type sample_array_t is array (0 to NUM_VOICES-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal voice_array : sample_array_t;

    signal mix_sum    : signed(SUM_WIDTH-1 downto 0);

begin

    -------------------------------------------------------------------------
    -- TODO: Use for-generate to unpack the flattened voice sample bus into 
    -- a per-voice array.
    -------------------------------------------------------------------------
    voice_array <= (others => (others => '0'));

    ----------------------------------------------------------------
    -- Mix voices at the audio sample pulse.
    --
    -- The math is split across 2 pipeline stages so each fits in one
    -- 50 MHz clock period. The sum and average stages run every
    -- clock; the voice samples only change once per pulse, so the
    -- pipeline has settled long before the next pulse captures it.
    ----------------------------------------------------------------
    mixer_process : process(clk, rst)
    begin
        if ( rst = '1' ) then
            mix_sum    <= (others => '0');
            audio      <= (others => '0');
        elsif ( rising_edge(clk) ) then
            --------------------------------------------------------------------
            -- TODO: Implement the two-stage mixer pipeline. The voice samples 
            -- are in the array voice_array.  The final audio output should be 
            -- saturated to the range AUDIO_MIN to AUDIO_MAX.  The output should 
            -- only be updated on the pulse signal; otherwise it should hold its value.
            --------------------------------------------------------------------
            -- Stage 1: sum the voices.
            mix_sum <= (others => '0');

            -- Stage 2: saturate the output to avoid overflow at the sample pulse.
            audio <= (others => '0');
        end if;
    end process;

end architecture behavioral;