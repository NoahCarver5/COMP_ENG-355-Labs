library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity drum_pad_tb is
end entity drum_pad_tb;

architecture behavioral of drum_pad_tb is

    ----------------------------------------------------------------
    -- Simulation timing and output file names
    ----------------------------------------------------------------
    -- 320 kHz sim clock (10 clocks per 32 kHz sample) instead of 50 MHz,
    -- so simulation runs ~156x faster. Synthesis still uses 50 MHz.
    -- constant CLK_PERIOD_NS   : time := 20 ns;
    constant CLK_PERIOD_NS   : time := 3125 ns;
    constant CLK_FREQUENCY   : natural := 1_000_000_000 / (CLK_PERIOD_NS / 1 ns);
    constant SAMPLE_RATE_HZ  : natural := 32_000;
    constant RAW_FILE_NAME   : string  := "drum_pad.raw";
    constant WAV_FILE_NAME   : string  := "drum_pad.wav";

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal key          : std_logic_vector(3 downto 0) := (others => '0');
    signal sw           : std_logic_vector(2 downto 0) := (others => '0');
    signal led          : std_logic := '0';
    signal sample_pulse : std_logic := '0';
    signal audio_out    : std_logic_vector(15 downto 0) := (others => '0');
    signal sim_done     : boolean := false;

    -- Character-file writes allow exact byte-level WAV output in pure VHDL.
    type char_file_t is file of character;

    component drum_pad is
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
    end component drum_pad;

    -- Write little-endian integer fields used by RIFF/WAV headers.
    procedure write_u8(file f : char_file_t; v : natural) is
    begin
        write(f, character'val(v mod 256));
    end procedure;

    procedure write_u16(file f : char_file_t; v : natural) is
    begin
        write_u8(f, v mod 256);
        write_u8(f, (v / 256) mod 256);
    end procedure;

    procedure write_u32(file f : char_file_t; v : natural) is
    begin
        write_u8(f, v mod 256);
        write_u8(f, (v / 256) mod 256);
        write_u8(f, (v / 65_536) mod 256);
        write_u8(f, (v / 16_777_216) mod 256);
    end procedure;

    procedure write_wav_header(file f : char_file_t; sample_rate : natural; sample_count : natural) is
        constant CHANNELS         : natural := 1;
        constant BITS_PER_SAMPLE  : natural := 16;
        constant BYTE_RATE        : natural := sample_rate * CHANNELS * (BITS_PER_SAMPLE / 8);
        constant BLOCK_ALIGN      : natural := CHANNELS * (BITS_PER_SAMPLE / 8);
        constant DATA_BYTES       : natural := sample_count * BLOCK_ALIGN;
        constant RIFF_SIZE        : natural := 36 + DATA_BYTES;
    begin
        -- RIFF chunk descriptor
        write(f, 'R'); write(f, 'I'); write(f, 'F'); write(f, 'F');
        write_u32(f, RIFF_SIZE);
        write(f, 'W'); write(f, 'A'); write(f, 'V'); write(f, 'E');
        -- PCM format subchunk
        write(f, 'f'); write(f, 'm'); write(f, 't'); write(f, ' ');
        write_u32(f, 16);
        write_u16(f, 1);
        write_u16(f, CHANNELS);
        write_u32(f, sample_rate);
        write_u32(f, BYTE_RATE);
        write_u16(f, BLOCK_ALIGN);
        write_u16(f, BITS_PER_SAMPLE);
        -- Data subchunk header (payload bytes follow this header)
        write(f, 'd'); write(f, 'a'); write(f, 't'); write(f, 'a');
        write_u32(f, DATA_BYTES);
    end procedure;

begin
    -- Instantiate the drum_pad DUT
    dut : drum_pad
        generic map(
            DATA_WIDTH     => 16,
            CLK_FREQUENCY  => CLK_FREQUENCY,
            SAMPLE_RATE_HZ => SAMPLE_RATE_HZ
        )
        port map(
            clk          => clk,
            rst          => rst,
            key          => key,
            sw           => sw,
            led          => led,
            sample_pulse => sample_pulse,
            audio_out    => audio_out
        );

    -- Clock process
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD_NS / 2;
        clk <= '1';
        wait for CLK_PERIOD_NS / 2;
    end process clk_process;

    -- Reset process
    reset_process : process
    begin
        rst <= '0';
        wait for CLK_PERIOD_NS;
        rst <= '1';
        wait for CLK_PERIOD_NS;
        rst <= '0';
        wait;
    end process reset_process;

    -- Stimulus process to simulate key presses and switch settings
    -- Sequence:
    -- 1) let metronome run
    -- 2) hit each pad separately,
    -- 3) hit all pads together
    -- 4) stop simulation.
    stimulus_process : process
    begin
        wait until rst = '1';
        wait until rst = '0';
        wait for CLK_PERIOD_NS;

        -- Enable metronome at medium speed for background click.
        sw <= "111";

        -- wait for 4 seconds to let the metronome run.
        wait for 4000 ms;
    
        -- Simulate key presses for each drum pad
        wait until rising_edge(clk);
        key(0) <= '1'; 
        wait for CLK_PERIOD_NS; 
        key(0) <= '0';
        wait for 1000 ms;
        key(1) <= '1';
        wait for CLK_PERIOD_NS;
        key(1) <= '0';
        wait for 1000 ms;
        key(2) <= '1';
        wait for CLK_PERIOD_NS;
        key(2) <= '0';
        wait for 1000 ms;
        key(3) <= '1';
        wait for CLK_PERIOD_NS;
        key(3) <= '0';
        wait for 1000 ms;
        key(0) <= '1';
        key(1) <= '1';
        key(2) <= '1';
        key(3) <= '1';
        wait for CLK_PERIOD_NS;
        key(0) <= '0';
        key(1) <= '0';
        key(2) <= '0';
        key(3) <= '0';
        wait for 1000 ms;




        

        ---------------------------------------------------------------
        -- TODO: Add enable the different keys to test the different
        -- drum voices. Each key should be pressed, released, then wait
        -- at least 1 second before the next key press. Then try 
        -- multiple keys at once to test polyphony. 
        ---------------------------------------------------------------
        
        wait for 1000 ms;
        sim_done <= true;
        wait;
    end process stimulus_process;


    ----------------------------------------------------------------
    -- WAV capture process
    --
    -- We do not know the final sample count in advance, so we first stream
    -- PCM data to a raw file, count samples, then write the WAV header with
    -- the final count and append the raw payload.
    ----------------------------------------------------------------
    wav_capture_process : process
        file raw_file      : char_file_t;
        file raw_read_file : char_file_t;
        file wav_file      : char_file_t;
        variable count     : natural := 0;
        variable sample    : natural := 0;
        variable raw_byte  : character;
    begin
        wait until rst = '1';
        wait until rst = '0';

        -- Stream raw PCM data to a temp file while counting samples.
        file_open(raw_file, RAW_FILE_NAME, write_mode);
        loop
            -- Only wake the process on sample pulses, not every clock edge.
            wait until rising_edge(clk) and sample_pulse = '1';
            exit when sim_done;

            -- Convert signed 16-bit sample to unsigned 16-bit for byte output.
            if (signed(audio_out) < to_signed(0, audio_out'length)) then
                sample := to_integer(signed(audio_out)) + 65_536;
            else
                sample := to_integer(signed(audio_out));
            end if;

            write_u16(raw_file, sample);
            count := count + 1;
        end loop;
        file_close(raw_file);

        -- Build final WAV using the measured sample count.
        file_open(wav_file, WAV_FILE_NAME, write_mode);
        write_wav_header(wav_file, SAMPLE_RATE_HZ, count);

        -- Append the raw PCM data to the WAV file.
        file_open(raw_read_file, RAW_FILE_NAME, read_mode);
        while not endfile(raw_read_file) loop
            read(raw_read_file, raw_byte);
            write(wav_file, raw_byte);
        end loop;

        -- Close all files and stop the simulation.
        file_close(raw_read_file);
        file_close(wav_file);

        report "WAV capture complete: " & WAV_FILE_NAME & " (samples=" & integer'image(count) & ")" severity note;
        stop;
    end process wav_capture_process;

end architecture behavioral;