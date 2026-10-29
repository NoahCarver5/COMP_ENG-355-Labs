library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- HDMI output: video timing, transmit pins, and ADV7513 setup.  PROVIDED.
--
-- Everything the board's HDMI connector needs, in one entity.  Give it a
-- clock and a pixel source; it generates the 640x480 @ 60 Hz raster,
-- drives the transmitter's video pins, and configures the transmitter
-- over I2C.
--
-- THERE IS NO PIXEL CLOCK DOMAIN.  The pixel rate is a clock ENABLE on
-- the system clock, not a second clock:
--
--     PIX_DIV = system clock / pixel rate      4 at 100 MHz
--                                              5 at 125 MHz
--                                              6 at 150 MHz
--
-- One divider produces both the pixel enable and hdmi_tx_clk, so the TX
-- clock and the data it latches are aligned by construction rather than
-- by an SDC constraint.  The whole design is therefore single clock, and
-- there are no synchronizers anywhere on the display side.
--
-- HANDSHAKE WITH THE IMAGE PROCESSOR
--
--     pixel_req    one system clock wide, once per ACTIVE pixel
--     frame_sync   high between frames; holds the read address at zero
--
-- frame_sync is the vertical blanking interval seen from the consumer's
-- side: it is called vblank inside this module, because that is what it
-- is here, and frame_sync on the port, because a module with no raster
-- has no blanking -- only a frame boundary to reset its position on.
--
-- pixel_req only fires during active lines, so the source counts out
-- 640 x 480 pixels while this raster counts 800 x 525 -- the two cannot
-- drift.
--
-- There is no latency to account for.  pixel_req advances the source at
-- the START of a pixel period, and the source has the rest of that period
-- (3 to 5 system clocks) to produce the pixel.  It is already waiting when
-- the TX register latches it at the END of the period, alongside the sync
-- signals for that same pixel.  Add pipeline stages and nothing here
-- changes, as long as they still fit inside one pixel period.
--
-- A source that CANNOT answer within one pixel period has to arrange to be
-- ahead rather than behind -- see mandel_engine_bank, which keeps its
-- compute pipeline running a fixed number of pixels in front of the raster
-- so the answer is finished before it is asked for.  Nothing here has to
-- know about that.
--
-- Pixel rate for this mode is nominally 25.175 MHz; 25 MHz is close
-- enough for most monitors to lock.
--
-- TRANSMITTER SETUP (I2C)
--
-- The ADV7513 powers up switched off and ignores the video pins until it
-- is told, over I2C, to power up, what format the video arrives in, and a
-- handful of fixed register values the datasheet requires.  This module
-- sends that list once after reset and then leaves the bus idle.
--
-- Plugging or unplugging a monitor resets the ADV7513 back to powered
-- down.  It signals that by pulling hdmi_tx_int low, and the answer is to
-- send the whole list again -- the last entry clears the interrupt, which
-- releases the pin.  So a monitor connected after the board is running
-- still gets a picture.
--
-- The I2C engine is the write-only one from Lab 3's audio_codec: SDA only
-- changes while SCL is low, and ACKs are not checked.
--------------------------------------------------------------------------
entity hdmi is
    generic (
        -- System clock frequency, for the I2C bit rate.
        CLK_FREQUENCY : natural := 100_000_000;

        -- System clock divided by this gives the pixel rate.  Even values
        -- give an exact 50% duty cycle on hdmi_tx_clk.
        PIX_DIV  : natural := 4;

        H_ACTIVE : natural := 640;
        H_FRONT  : natural := 16;
        H_SYNC   : natural := 96;
        H_BACK   : natural := 48;

        V_ACTIVE : natural := 480;
        V_FRONT  : natural := 10;
        V_SYNC   : natural := 2;
        V_BACK   : natural := 33
    );
    port (
        clock       : in    std_logic;
        reset       : in    std_logic;                   -- async, active high

        -- ---- to the image processor ----
        frame_sync  : out   std_logic;                   -- holds read address at 0
        pixel_req   : out   std_logic;                   -- next active pixel
        pixel       : in    std_logic_vector(23 downto 0);

        -- ---- HDMI TX pins ----
        hdmi_tx_clk : out   std_logic;
        hdmi_tx_d   : out   std_logic_vector(23 downto 0);
        hdmi_tx_hs  : out   std_logic;
        hdmi_tx_vs  : out   std_logic;
        hdmi_tx_de  : out   std_logic;
        hdmi_tx_int : in    std_logic;                   -- active low (hot plug)

        -- ---- I2C bus to the transmitter (FPGA_I2C_SCLK / FPGA_I2C_SDAT) ----
        i2c_scl     : out   std_logic;
        i2c_sda     : inout std_logic
    );
end entity hdmi;


architecture rtl of hdmi is

    ----------------------------------------------------------------------
    -- Video timing
    ----------------------------------------------------------------------
    constant H_TOTAL : natural := H_ACTIVE + H_FRONT + H_SYNC + H_BACK;  -- 800
    constant V_TOTAL : natural := V_ACTIVE + V_FRONT + V_SYNC + V_BACK;  -- 525

    -- Pixel rate divider
    signal div_cnt : unsigned(7 downto 0);
    signal pix_ce  : std_logic;
    signal tx_clk  : std_logic;

    -- Raster position
    signal h_count : unsigned(9 downto 0);
    signal v_count : unsigned(9 downto 0);

    signal vblank  : std_logic;     -- the vertical blanking interval
    signal de_now  : std_logic;
    signal hs_now  : std_logic;
    signal vs_now  : std_logic;

    ----------------------------------------------------------------------
    -- Transmitter setup
    ----------------------------------------------------------------------
    constant I2C_DIVIDER     : natural := CLK_FREQUENCY / 100_000;
    constant CFG_DELAY_TICKS : natural := 2000; -- ~20 ms power-up delay

    -- ADV7513 main map at 7-bit address 0x39 (0x72 + W).
    constant I2C_ADDR_WRITE  : std_logic_vector(7 downto 0) := x"72"; -- 7-bit 0x39 + W

    -- Each entry is an 8-bit register address followed by 8 bits of data.
    -- Values follow Terasic's DE25-Standard HDMI demonstration, with the
    -- audio setup left out.
    type cfg_lut_t is array (natural range <>) of std_logic_vector(15 downto 0);
    constant CFG_LUT : cfg_lut_t := (
        x"4110", -- 0x41 Power up the transmitter
        x"9803", -- 0x98 Fixed: must be 0x03
        x"9902", -- 0x99 Fixed: must be 0x02
        x"9AE0", -- 0x9A Fixed: must be 0xE0
        x"9C30", -- 0x9C Fixed: PLL filter
        x"9D61", -- 0x9D Fixed: clock divide
        x"A2A4", -- 0xA2 Fixed: must be 0xA4
        x"A3A4", -- 0xA3 Fixed: must be 0xA4
        x"A504", -- 0xA5 Fixed: must be 0x04
        x"AB40", -- 0xAB Fixed: must be 0x40
        x"D1FF", -- 0xD1 Fixed: must be 0xFF
        x"DE10", -- 0xDE Fixed: must be 0x10
        x"E460", -- 0xE4 Fixed: must be 0x60
        x"FA7D", -- 0xFA Fixed: phase search count
        x"1500", -- 0x15 Input ID 0: 24-bit RGB 4:4:4, separate syncs
        x"1630", -- 0x16 4:4:4 output, 8 bits per channel, RGB
        x"1846", -- 0x18 Color space converter off
        x"AF16", -- 0xAF HDMI mode (not DVI)
        x"BA60", -- 0xBA No input clock delay: the divider centers the clock itself
        x"4080", -- 0x40 General control packet enable
        x"5510", -- 0x55 AVI infoframe: RGB
        x"5608", -- 0x56 AVI infoframe: active format same as picture
        x"94C0", -- 0x94 Interrupt enable: hot plug and monitor sense
        x"96F6"  -- 0x96 Clear pending interrupts, releasing HDMI_TX_INT
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

    signal i2c_counter    : natural range 0 to I2C_DIVIDER-1;
    signal cfg_delay      : natural range 0 to CFG_DELAY_TICKS;

    signal scl_reg        : std_logic;
    signal sda_drive_low  : std_logic;

    signal i2c_state      : i2c_state_t;
    signal i2c_tick       : std_logic;
    signal cfg_index      : natural range 0 to CFG_LUT'length-1;
    signal byte_index     : natural range 0 to 2;
    signal bit_ptr        : natural range 0 to 7;
    signal tx_byte        : std_logic_vector(7 downto 0);

    -- hdmi_tx_int comes from off chip, asynchronous to the clock.
    signal int_sync       : std_logic_vector(1 downto 0);

begin

    ----------------------------------------------------------------------
    -- Pixel rate divider
    --
    -- pix_ce marks the last system clock of each pixel period, so every
    -- register that runs at pixel rate updates on the boundary between
    -- one pixel and the next.
    --
    -- hdmi_tx_clk rises half a pixel period after that boundary, which
    -- puts its edge in the middle of the data eye.
    ----------------------------------------------------------------------
    divider : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            div_cnt <= (others => '0');
            tx_clk  <= '0';
        elsif rising_edge(clock) then
            if ( div_cnt = PIX_DIV - 1 ) then
                div_cnt <= (others => '0');
                tx_clk  <= '0';
            else
                div_cnt <= div_cnt + 1;
                if ( div_cnt = (PIX_DIV / 2) - 1 ) then
                    tx_clk <= '1';
                end if;
            end if;
        end if;
    end process divider;

    pix_ce      <= '1' when div_cnt = PIX_DIV - 1 else '0';
    hdmi_tx_clk <= tx_clk;

    ----------------------------------------------------------------------
    -- Raster counters, one step per pixel period
    ----------------------------------------------------------------------
    raster : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            h_count <= (others => '0');
            v_count <= (others => '0');
        elsif rising_edge(clock) then
            if ( pix_ce = '1' ) then
                if ( h_count = H_TOTAL - 1 ) then
                    h_count <= (others => '0');
                    if ( v_count = V_TOTAL - 1 ) then
                        v_count <= (others => '0');
                    else
                        v_count <= v_count + 1;
                    end if;
                else
                    h_count <= h_count + 1;
                end if;
            end if;
        end if;
    end process raster;

    de_now <= '1' when (h_count < H_ACTIVE) and (v_count < V_ACTIVE) else '0';

    -- Sync pulses are active low and sit after the front porch.
    hs_now <= '0' when (h_count >= H_ACTIVE + H_FRONT) and
                       (h_count <  H_ACTIVE + H_FRONT + H_SYNC) else '1';

    vs_now <= '0' when (v_count >= V_ACTIVE + V_FRONT) and
                       (v_count <  V_ACTIVE + V_FRONT + V_SYNC) else '1';

    ----------------------------------------------------------------------
    -- To the image processor
    ----------------------------------------------------------------------
    vblank <= '1' when v_count >= V_ACTIVE else '0';

    pixel_req  <= pix_ce and de_now;
    frame_sync <= vblank;

    ----------------------------------------------------------------------
    -- Transmit side
    --
    -- One register, clocked at pixel rate.  The pixel and the sync
    -- signals describing it are sampled on the same enable.
    ----------------------------------------------------------------------
    transmit : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            hdmi_tx_d  <= (others => '0');
            hdmi_tx_hs <= '1';
            hdmi_tx_vs <= '1';
            hdmi_tx_de <= '0';
        elsif rising_edge(clock) then
            if ( pix_ce = '1' ) then
                hdmi_tx_hs <= hs_now;
                hdmi_tx_vs <= vs_now;
                hdmi_tx_de <= de_now;

                if ( de_now = '1' ) then
                    hdmi_tx_d <= pixel;
                else
                    hdmi_tx_d <= (others => '0');
                end if;
            end if;
        end if;
    end process transmit;

    ----------------------------------------------------------------------
    -- Transmitter setup: minimal write-only I2C configuration engine.
    --
    -- SDA only changes while SCL is already low, one tick after the
    -- falling edge, so a data change is never seen as a START/STOP.
    ----------------------------------------------------------------------
    i2c_scl <= scl_reg;
    i2c_sda <= '0' when sda_drive_low = '1' else 'Z';

    i2c_config : process (clock, reset) is
    begin
        if ( reset = '1' ) then
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
            int_sync      <= (others => '1');
        elsif rising_edge(clock) then
            int_sync <= int_sync(0) & hdmi_tx_int;

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
                        -- Hot plug: the transmitter has reset itself, so
                        -- wait for the connector to settle and resend.
                        if ( int_sync(1) = '0' ) then
                            i2c_state <= CFG_RESET_DELAY;
                        end if;
                end case;
            end if;
        end if;
    end process i2c_config;

end architecture rtl;
