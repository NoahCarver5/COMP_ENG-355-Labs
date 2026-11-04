library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- D8M camera daughter card front end.  PROVIDED.
--
-- Everything the camera needs to come up and produce a usable RGB stream
-- lives in here:
--
--   * reset sequencing                this file
--   * bridge and sensor registers     MIPI_BRIDGE_CAMERA_Config
--   * Bayer demosaic                  this file
--
-- Those two are Terasic Verilog from the D8M reference design;
-- add the .v files to the project and Quartus binds them.  The register
-- script inside the config block is a thousand lines of vendor knowledge
-- for the TC358748 bridge and the sensor -- not something to rewrite.
--
-- Out of this module comes an ordinary raster stream:
--
--   cam_clk     pixel clock from the sensor
--   cam_vs      frame valid, active high
--   cam_de      pixel valid, active high
--   cam_pixel   RGB888
--
-- FIXED FOCUS.  The reference design also drives the voice coil to focus
-- automatically, which costs FOCUS_ADJ and the whole VCM subtree beneath
-- it, and puts a second master on the camera I2C bus.  None of that is
-- needed to see a picture, so it is left out: the lens stays wherever it
-- is set.  Adding it back means instantiating AUTO_FOCUS_ON and
-- FOCUS_ADJ and muxing camera_i2c_scl between them and the config block,
-- which is the handover the reference design's I2C_RELEASE signal marks.
--
-- No gamma either.  The reference design wires D8M_LUT in with its enable
-- tied low, so it is a passthrough there too.
--
-- RESOLUTION is not set here.  MIPI_BRIDGE_CAMERA_Config already does
-- it -- registers 0x3808..0x380b program the sensor to 0x0280 x 0x01E0,
-- which is 640 x 480, with 0x3814 binning the full array down to reach
-- it.  Nothing in this file needs to agree with that: the line length is
-- measured from hs, not assumed.
--
-- BAYER PHASE is the one thing still guessed.  The sensor's native
-- pattern is BGGR, but the same config script enables both mirror
-- (0x3821) and flip (0x3820), and each shifts the phase by a pixel, so
-- what arrives should be RGGB -- which is BGGR with red and blue
-- exchanged.  Hence BAYER_SWAP_RB defaulting true at the top level.
-- That is read off the register table, not measured; the three BAYER_*
-- generics between them reach every phase if it turns out wrong.
--
-- UNVERIFIED otherwise: none of this has run against real hardware.
--------------------------------------------------------------------------
entity d8m is
    generic (
        -- Widest line the sensor might send.  Only sizes the line buffer;
        -- the actual line length is measured, not assumed.  2048 x 10
        -- bits is 20 kbit, which is nothing next to the frame buffer.
        MAX_LINE       : natural := 2048;

        -- Startup delay, in clk_50 ticks.  50e6 is one second, which is
        -- what the reference design uses.  Wind it down to something like
        -- 200 in a testbench, or the camera spends 150 million clocks
        -- coming up before a single pixel arrives.
        RESET_TICKS    : natural := 50_000_000;

        -- Bayer phase.  The sensor is assumed to start each frame on a
        -- blue pixel (BGGR).  If the colors come out wrong, these three
        -- reach all eight possibilities between them: SWAP_RB exchanges
        -- red and blue, and the two offsets shift the phase by a column
        -- or a row.
        BAYER_SWAP_RB  : boolean := false;
        BAYER_X_ODD    : boolean := false;
        BAYER_Y_ODD    : boolean := false
    );
    port (
        clk_50    : in    std_logic;
        rst_n     : in    std_logic;    -- from KEY, active low

        -- ---- D8M daughter card ----
        mipi_pixel_clk : in    std_logic;
        mipi_pixel_d   : in    std_logic_vector(9 downto 0);
        mipi_pixel_hs  : in    std_logic;   -- line valid
        mipi_pixel_vs  : in    std_logic;   -- frame valid
        mipi_cs_n      : out   std_logic;
        mipi_reset_n   : out   std_logic;
        mipi_i2c_scl   : inout std_logic;
        mipi_i2c_sda   : inout std_logic;
        camera_i2c_scl : inout std_logic;
        camera_i2c_sda : inout std_logic;
        camera_pwdn_n  : out   std_logic;

        -- ---- video stream out ----
        cam_clk   : out   std_logic;
        cam_vs    : out   std_logic;
        cam_de    : out   std_logic;
        cam_pixel : out   std_logic_vector(23 downto 0);   -- RGB888

        ready     : out   std_logic     -- camera configured and streaming
    );
end entity d8m;


architecture rtl of d8m is

    ----------------------------------------------------------------------
    -- Terasic reference-design Verilog
    ----------------------------------------------------------------------
    component MIPI_BRIDGE_CAMERA_Config is
        port (
            RESET_N            : in    std_logic;
            CLK_50             : in    std_logic;
            MIPI_I2C_SCL       : inout std_logic;
            MIPI_I2C_SDA       : inout std_logic;
            MIPI_I2C_RELEASE   : out   std_logic;
            CAMERA_I2C_SCL     : out   std_logic;
            CAMERA_I2C_SDA     : inout std_logic;
            CAMERA_I2C_RELAESE : out   std_logic;
            VCM_RELAESE        : out   std_logic
        );
    end component;

    ----------------------------------------------------------------------
    -- Reset and configuration
    ----------------------------------------------------------------------
    signal reset_n       : std_logic;
    signal reset_n_delay : std_logic;

    signal mipi_release   : std_logic;
    signal camera_release : std_logic;
    signal scl_config     : std_logic;

    ----------------------------------------------------------------------
    -- Reset sequencing
    ----------------------------------------------------------------------
    constant READY0_AT : natural := RESET_TICKS / 4;
    constant READY1_AT : natural := RESET_TICKS / 2;

    signal delay_cnt : natural range 0 to RESET_TICKS := 0;

    ----------------------------------------------------------------------
    -- Demosaic
    ----------------------------------------------------------------------
    type line_t is array (0 to MAX_LINE - 1) of std_logic_vector(9 downto 0);
    signal prev_line : line_t;

    signal col      : natural range 0 to MAX_LINE - 1 := 0;
    signal row      : natural range 0 to MAX_LINE - 1 := 0;
    signal vs_d     : std_logic := '0';
    signal hs_d     : std_logic := '0';

    -- Registered copies of the pixel and the line-buffer word from the
    -- previous clock, which is one column to the left.
    signal cur      : std_logic_vector(9 downto 0) := (others => '0');
    signal up       : std_logic_vector(9 downto 0) := (others => '0');

    signal rgb_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal rgb_g    : std_logic_vector(7 downto 0) := (others => '0');
    signal rgb_b    : std_logic_vector(7 downto 0) := (others => '0');
    signal rgb_de   : std_logic := '0';
    signal rgb_vs   : std_logic := '0';

begin

    ----------------------------------------------------------------------
    -- Card control pins
    ----------------------------------------------------------------------
    camera_pwdn_n <= '1';
    mipi_cs_n     <= '0';
    mipi_reset_n  <= reset_n;

    cam_clk <= mipi_pixel_clk;

    -- Configuration is finished once both halves let go of the I2C bus.
    -- With no focus controller nothing else wants it, so SCL comes
    -- straight from the config block instead of being muxed.
    ready          <= camera_release and mipi_release;
    camera_i2c_scl <= scl_config;

    ----------------------------------------------------------------------
    -- Reset sequencing
    --
    -- The card needs time to settle before it is talked to.  Two staged
    -- releases: reset_n lets go of the bridge and the sensor, then a
    -- quarter of the window later reset_n_delay starts the register
    -- writes.  Both stay released until the next reset.
    ----------------------------------------------------------------------
    reset_sequence : process (rst_n, clk_50) is
    begin
        if ( rst_n = '0' ) then
            delay_cnt     <= 0;
            reset_n       <= '0';
            reset_n_delay <= '0';

        elsif rising_edge(clk_50) then
            if ( delay_cnt < RESET_TICKS ) then
                delay_cnt <= delay_cnt + 1;
            end if;

            if ( delay_cnt = READY0_AT ) then
                reset_n <= '1';
            end if;

            if ( delay_cnt = READY1_AT ) then
                reset_n_delay <= '1';
            end if;
        end if;
    end process reset_sequence;

    ----------------------------------------------------------------------
    -- MIPI bridge and sensor register setup
    ----------------------------------------------------------------------
    u_config : MIPI_BRIDGE_CAMERA_Config
        port map (
            RESET_N            => reset_n_delay,
            CLK_50             => clk_50,
            MIPI_I2C_SCL       => mipi_i2c_scl,
            MIPI_I2C_SDA       => mipi_i2c_sda,
            MIPI_I2C_RELEASE   => mipi_release,
            CAMERA_I2C_SCL     => scl_config,
            CAMERA_I2C_SDA     => camera_i2c_sda,
            CAMERA_I2C_RELAESE => camera_release,

            -- Only the voice coil driver cared about this, and there
            -- isn't one.
            VCM_RELAESE        => open
        );

    ----------------------------------------------------------------------
    -- Pixel position within the frame
    --
    -- The line length is MEASURED, not assumed.  A line ends when hs
    -- falls, whatever the sensor happens to be configured for, so nothing
    -- here breaks if the camera is not sending exactly 640 pixels.  The
    -- only thing MAX_LINE has to be is big enough for the line buffer.
    ----------------------------------------------------------------------
    counters : process (mipi_pixel_clk) is
    begin
        if rising_edge(mipi_pixel_clk) then
            vs_d <= mipi_pixel_vs;
            hs_d <= mipi_pixel_hs;

            if (vs_d = '0') and (mipi_pixel_vs = '1') then       -- frame start
                col <= 0;
                row <= 0;

            elsif (hs_d = '1') and (mipi_pixel_hs = '0') then    -- line end
                col <= 0;
                if row < MAX_LINE - 1 then
                    row <= row + 1;
                end if;

            elsif (mipi_pixel_vs = '1') and (mipi_pixel_hs = '1') then
                if col < MAX_LINE - 1 then
                    col <= col + 1;
                end if;
            end if;
        end if;
    end process counters;

    ----------------------------------------------------------------------
    -- Bayer demosaic
    --
    -- A 2x2 window always holds one red, one blue and two greens no
    -- matter which phase it lands on -- only which corner is which
    -- changes.  Nearest neighbour: cheap, and good enough to see the
    -- filters working.
    --
    --     p_upleft   p_up
    --     p_left     p_cur
    --
    -- WHERE THE WINDOW COMES FROM
    --
    -- cur and up are SIGNALS, so reading them gives last clock's values,
    -- which is one column to the left.  The two right-hand corners have
    -- to come from the raw inputs instead:
    --
    --     p_cur    = mipi_pixel_d        row r,   col c
    --     p_left   = cur                 row r,   col c-1
    --     p_up     = prev_line(col)      row r-1, col c
    --     p_upleft = up                  row r-1, col c-1
    --
    -- prev_line(col) is safe to read here even though it is written in
    -- the same process: the write is a signal assignment, so the read
    -- still sees the previous line's value.
    --
    -- The top row and the left column have no neighbours above or to the
    -- left, so those pixels come out wrong.  They are emitted anyway --
    -- dropping them would shift every following address by one.
    --
    -- One line buffer, MAX_LINE deep.  At 2048 that is 20 kbit.
    ----------------------------------------------------------------------
    demosaic : process (mipi_pixel_clk) is
        variable p_cur, p_left, p_up, p_upleft : unsigned(9 downto 0);
        variable r, g, b : unsigned(9 downto 0);
        variable g_sum   : unsigned(10 downto 0);
        variable even_x  : boolean;
        variable even_y  : boolean;
    begin
        if rising_edge(mipi_pixel_clk) then
            rgb_de <= '0';
            rgb_vs <= mipi_pixel_vs;

            if (mipi_pixel_vs = '1') and (mipi_pixel_hs = '1') then

                -- The 2x2 window ending at this pixel.
                p_cur    := unsigned(mipi_pixel_d);
                p_left   := unsigned(cur);
                p_up     := unsigned(prev_line(col));
                p_upleft := unsigned(up);

                -- Slide the window along and remember this line.
                cur <= mipi_pixel_d;
                up  <= prev_line(col);
                prev_line(col) <= mipi_pixel_d;

                even_x := ((col mod 2) = 0) xor BAYER_X_ODD;
                even_y := ((row mod 2) = 0) xor BAYER_Y_ODD;

                if even_y and even_x then           -- cur = B
                    b     := p_cur;
                    r     := p_upleft;
                    g_sum := resize(p_left, 11) + resize(p_up, 11);
                elsif even_y and not even_x then    -- cur = G, left = B, up = R
                    b     := p_left;
                    r     := p_up;
                    g_sum := resize(p_cur, 11) + resize(p_upleft, 11);
                elsif not even_y and even_x then    -- cur = G, left = R, up = B
                    b     := p_up;
                    r     := p_left;
                    g_sum := resize(p_cur, 11) + resize(p_upleft, 11);
                else                                -- cur = R
                    r     := p_cur;
                    b     := p_upleft;
                    g_sum := resize(p_left, 11) + resize(p_up, 11);
                end if;

                g := resize(shift_right(g_sum, 1), 10);

                if BAYER_SWAP_RB then
                    rgb_r <= std_logic_vector(b(9 downto 2));
                    rgb_b <= std_logic_vector(r(9 downto 2));
                else
                    rgb_r <= std_logic_vector(r(9 downto 2));
                    rgb_b <= std_logic_vector(b(9 downto 2));
                end if;
                rgb_g <= std_logic_vector(g(9 downto 2));

                rgb_de <= '1';
            end if;
        end if;
    end process demosaic;

    ----------------------------------------------------------------------
    -- Out at full 8:8:8.
    --
    -- The squeeze down to RGB686 happens in video_store, on the way into
    -- the frame buffer, so the loss lives next to the memory that forces
    -- it rather than being baked into the camera front end.
    ----------------------------------------------------------------------
    cam_pixel <= rgb_r & rgb_g & rgb_b;
    cam_de    <= rgb_de;
    cam_vs    <= rgb_vs;

end architecture rtl;
