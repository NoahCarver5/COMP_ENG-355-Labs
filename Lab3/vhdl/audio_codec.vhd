library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity audio_codec is
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
end entity audio_codec;


architecture behavioral of audio_codec is

    constant FRAME_WIDTH     : natural := 2 * DATA_WIDTH;
    constant XCK_DIVIDER     : natural := CLK_FREQUENCY / (2 * 256 * SAMPLE_RATE_HZ);
    constant BCLK_DIVIDER    : natural := CLK_FREQUENCY / (2 * FRAME_WIDTH * SAMPLE_RATE_HZ);
    constant I2C_DIVIDER     : natural := CLK_FREQUENCY / 100_000;
    constant CFG_DELAY_TICKS : natural := 2000; -- ~20 ms power-up delay

    -- The DE25-Standard SSM2603 codec is at 7-bit address 0x1B (0x36 + W);
    -- 0x1A (0x34) is used by another device on the shared I2C bus.
    constant I2C_ADDR_WRITE  : std_logic_vector(7 downto 0) := x"36"; -- 7-bit 0x1B + W

    -- Each entry is a 7-bit register address followed by 9 bits of data.
    type cfg_lut_t is array (natural range <>) of std_logic_vector(15 downto 0);
    constant CFG_LUT : cfg_lut_t := (
        x"1E00", -- R15 Reset: restore register defaults
        x"047F", -- R2  Left headphone out volume: +6 dB (max)
        x"067F", -- R3  Right headphone out volume: +6 dB (max)
        x"0812", -- R4  Analog path: DAC to output (DACSEL), mute mic, no bypass
        x"0A00", -- R5  Digital path: DAC soft mute off, no de-emphasis
        x"0C00", -- R6  Power control: all blocks powered on
        x"0E02", -- R7  Digital audio interface: I2S, 16-bit, codec slave mode
        x"1000", -- R8  Sampling control: normal mode, 256 fs
        x"1201"  -- R9  Activate digital core
    );

    type i2c_state_t is (
        CFG_RESET_DELAY,
        CFG_START_A,
        CFG_START_B,
        CFG_BIT_LOW,
        CFG_BIT_HIGH,
        CFG_BIT_FALL,
        CFG_ACK_LOW,
        CFG_ACK_HIGH,
        CFG_ACK_FALL,
        CFG_STOP_A,
        CFG_STOP_B,
        CFG_STOP_C,
        CFG_NEXT,
        CFG_DONE
    );

    signal xck_counter    : natural range 0 to XCK_DIVIDER-1;
    signal bclk_counter   : natural range 0 to BCLK_DIVIDER-1;
    signal i2c_counter    : natural range 0 to I2C_DIVIDER-1;
    signal cfg_delay      : natural range 0 to CFG_DELAY_TICKS;

    signal xck_reg        : std_logic;
    signal bclk_reg       : std_logic;
    signal dacdat_reg     : std_logic;
    signal scl_reg        : std_logic;
    signal sda_drive_low  : std_logic;

    signal sample_latched : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal frame_shift    : std_logic_vector(FRAME_WIDTH-1 downto 0);
    signal bit_index      : natural range 0 to FRAME_WIDTH-1;

    signal i2c_state      : i2c_state_t;
    signal i2c_tick       : std_logic;
    signal cfg_index      : natural range 0 to CFG_LUT'length-1;
    signal byte_index     : natural range 0 to 2;
    signal bit_ptr        : natural range 0 to 7;
    signal tx_byte        : std_logic_vector(7 downto 0);


begin

    AUD_XCK     <= xck_reg;
    AUD_BCLK    <= bclk_reg;
    AUD_DACDAT  <= dacdat_reg;
    AUD_DACLRCK <= '0' when bit_index >= DATA_WIDTH else '1';

    FPGA_I2C_SCL <= scl_reg;
    FPGA_I2C_SDA <= '0' when sda_drive_low = '1' else 'Z';

    ----------------------------------------------------------------
    -- Codec clocking + DAC serial data
    ----------------------------------------------------------------
    audio_stream_process : process(clk, rst)
    begin
        if ( rst = '1' ) then
            xck_counter    <= 0;
            bclk_counter   <= 0;
            xck_reg        <= '0';
            bclk_reg       <= '0';
            dacdat_reg     <= '0';
            sample_latched <= (others => '0');
            frame_shift    <= (others => '0');
            bit_index      <= FRAME_WIDTH-1;
        elsif ( rising_edge(clk) ) then
            if ( pulse = '1' ) then
                sample_latched <= audio;
            end if;

            if ( xck_counter = XCK_DIVIDER-1 ) then
                xck_counter <= 0;
                xck_reg <= not xck_reg;
            else
                xck_counter <= xck_counter + 1;
            end if;

            if ( bclk_counter = BCLK_DIVIDER-1 ) then
                bclk_counter <= 0;
                bclk_reg <= not bclk_reg;

                -- Shift data on BCLK falling edge.
                if ( bclk_reg = '1' ) then
                    dacdat_reg <= frame_shift(FRAME_WIDTH-1);
                    frame_shift <= frame_shift(FRAME_WIDTH-2 downto 0) & '0';

                    if ( bit_index = 0 ) then
                        frame_shift <= sample_latched & sample_latched;
                        bit_index <= FRAME_WIDTH-1;
                    else
                        bit_index <= bit_index - 1;
                    end if;
                end if;
            else
                bclk_counter <= bclk_counter + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Minimal write-only I2C configuration engine.
    --
    -- SDA only changes while SCL is already low, one tick after the
    -- falling edge, so a data change is never seen as a START/STOP.
    ----------------------------------------------------------------
    i2c_config_process : process(clk, rst)
    begin
        if ( rst = '1' ) then
            i2c_counter   <= 0;
            i2c_tick      <= '0';
            cfg_delay     <= 0;
            i2c_state     <= CFG_RESET_DELAY;
            cfg_index     <= 0;
            byte_index    <= 0;
            bit_ptr       <= 7;
            tx_byte       <= I2C_ADDR_WRITE;
            scl_reg       <= '1';
            sda_drive_low <= '0';
        elsif ( rising_edge(clk) ) then
            if ( i2c_counter = I2C_DIVIDER-1 ) then
                i2c_counter <= 0;
                i2c_tick <= '1';
            else
                i2c_counter <= i2c_counter + 1;
                i2c_tick <= '0';
            end if;

            if ( i2c_tick = '1' ) then
                case i2c_state is
                    when CFG_RESET_DELAY =>
                        scl_reg <= '1';
                        sda_drive_low <= '0';
                        if ( cfg_delay = CFG_DELAY_TICKS ) then
                            cfg_delay <= 0;
                            cfg_index <= 0;
                            byte_index <= 0;
                            bit_ptr <= 7;
                            tx_byte <= I2C_ADDR_WRITE;
                            i2c_state <= CFG_START_A;
                        else
                            cfg_delay <= cfg_delay + 1;
                        end if;

                    when CFG_START_A =>
                        scl_reg <= '1';
                        sda_drive_low <= '1';
                        i2c_state <= CFG_START_B;

                    when CFG_START_B =>
                        scl_reg <= '0';
                        bit_ptr <= 7;
                        i2c_state <= CFG_BIT_LOW;

                    when CFG_BIT_LOW =>
                        -- SCL is already low; set up the data bit.
                        if ( tx_byte(bit_ptr) = '0' ) then
                            sda_drive_low <= '1';
                        else
                            sda_drive_low <= '0';
                        end if;
                        i2c_state <= CFG_BIT_HIGH;

                    when CFG_BIT_HIGH =>
                        scl_reg <= '1';
                        i2c_state <= CFG_BIT_FALL;

                    when CFG_BIT_FALL =>
                        scl_reg <= '0';
                        if ( bit_ptr = 0 ) then
                            i2c_state <= CFG_ACK_LOW;
                        else
                            bit_ptr <= bit_ptr - 1;
                            i2c_state <= CFG_BIT_LOW;
                        end if;

                    when CFG_ACK_LOW =>
                        sda_drive_low <= '0'; -- release SDA for ACK bit
                        i2c_state <= CFG_ACK_HIGH;

                    when CFG_ACK_HIGH =>
                        scl_reg <= '1';
                        i2c_state <= CFG_ACK_FALL;

                    when CFG_ACK_FALL =>
                        scl_reg <= '0';
                        if ( byte_index = 2 ) then
                            i2c_state <= CFG_STOP_A;
                        else
                            byte_index <= byte_index + 1;
                            bit_ptr <= 7;
                            if ( byte_index = 0 ) then
                                tx_byte <= CFG_LUT(cfg_index)(15 downto 8);
                            else
                                tx_byte <= CFG_LUT(cfg_index)(7 downto 0);
                            end if;
                            i2c_state <= CFG_BIT_LOW;
                        end if;

                    when CFG_STOP_A =>
                        -- SCL is already low; pull SDA low before the STOP.
                        sda_drive_low <= '1';
                        i2c_state <= CFG_STOP_B;

                    when CFG_STOP_B =>
                        scl_reg <= '1';
                        i2c_state <= CFG_STOP_C;

                    when CFG_STOP_C =>
                        -- SDA rising while SCL is high is the STOP condition.
                        sda_drive_low <= '0';
                        i2c_state <= CFG_NEXT;

                    when CFG_NEXT =>
                        if ( cfg_index = CFG_LUT'length-1 ) then
                            i2c_state <= CFG_DONE;
                        else
                            cfg_index <= cfg_index + 1;
                            byte_index <= 0;
                            bit_ptr <= 7;
                            tx_byte <= I2C_ADDR_WRITE;
                            i2c_state <= CFG_START_A;
                        end if;

                    when CFG_DONE =>
                        scl_reg <= '1';
                        sda_drive_low <= '0';
                end case;
            end if;
        end if;
    end process;

end architecture behavioral;