library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Lab N top level.  PROVIDED -- pure wiring.
--
--           +----------------------------------+
--   D8M ==> | video_store ==> bram ==> filters | ==> HDMI
--           +--------- image processor --------+
--
-- The camera writes the frame buffer on its own pixel clock; the display
-- reads it on the video clock.  Nothing here needs changing.
--------------------------------------------------------------------------
entity image_processor_system is
    generic (
        -- How many filters IN TOTAL, the passthrough included, so the
        -- list runs 0 to N_FILTERS - 1 and filter 0 is the passthrough.
        -- 8 builds every branch of the generate inside filters.vhd.
        --
        -- Not capped by the buttons any more: two keys step through the
        -- list however long it is.  The ceiling is the number of
        -- branches written in filters.vhd, and the two HEX digits,
        -- which run out at filter 255.
        N_FILTERS : natural := 8
    );
    port (
        -- ---- clocks and reset ----
        clk_50         : in    std_logic;   -- board oscillator
        reset_n        : in    std_logic;   -- KEY, active low

        -- ---- user interface ----
        keys_n         : in    std_logic_vector(1 downto 0);  -- ACTIVE LOW: 0 next, 1 prev
        hex0           : out   std_logic_vector(6 downto 0);   -- filter number,
        hex1           : out   std_logic_vector(6 downto 0);   -- two digits

        -- ---- D8M daughter card ----
        mipi_pixel_clk : in    std_logic;
        mipi_pixel_d   : in    std_logic_vector(9 downto 0);
        mipi_pixel_hs  : in    std_logic;
        mipi_pixel_vs  : in    std_logic;
        mipi_refclk    : out   std_logic;
        mipi_cs_n      : out   std_logic;
        mipi_reset_n   : out   std_logic;
        mipi_i2c_scl   : inout std_logic;
        mipi_i2c_sda   : inout std_logic;
        camera_i2c_scl : inout std_logic;
        camera_i2c_sda : inout std_logic;
        camera_pwdn_n  : out   std_logic;

        -- ---- HDMI TX ----
        hdmi_tx_clk    : out   std_logic;
        hdmi_tx_d      : out   std_logic_vector(23 downto 0);
        hdmi_tx_hs     : out   std_logic;
        hdmi_tx_vs     : out   std_logic;
        hdmi_tx_de     : out   std_logic;
        hdmi_tx_int    : in    std_logic;   -- active low (hot plug)

        -- ---- I2C, to configure the HDMI transmitter ----
        -- FPGA_I2C_SCLK / FPGA_I2C_SDAT.  A third bus, separate from the
        -- two the D8M uses.
        hdmi_i2c_scl   : out   std_logic;
        hdmi_i2c_sda   : inout std_logic
    );
end entity image_processor_system;


architecture rtl of image_processor_system is

    constant IMG_W   : natural := 640;
    constant IMG_H   : natural := 480;
    constant ADDR_W  : natural := 19;      -- 640*480 = 307_200

    -- What the PLL puts out on outclk_1, and what hdmi divides down for
    -- both the pixel rate and the I2C bit rate.
    constant CLK_FREQUENCY : natural := 100_000_000;

    -- System clock divided by this gives the 25 MHz pixel rate.
    --
    --     100 MHz -> 4        125 MHz -> 5        150 MHz -> 6
    --
    -- It must also be at least 4 so that video_store can recover the
    -- camera clock by oversampling.
    constant PIX_DIV : natural := 4;

    ----------------------------------------------------------------
    -- Video PLL.
    --
    -- Quartus-generated Altera PLL, 50 MHz in:
    --
    --     outclk_0    20 MHz   MIPI bridge reference clock
    --     outclk_1   100 MHz   system clock
    --
    -- There is no pixel clock output.  hdmi divides the system clock down
    -- to the pixel rate and drives hdmi_tx_clk from that same divider, so
    -- the TX clock and its data are aligned by construction.  Regenerate
    -- the IP from the catalog if the board oscillator changes.
    --
    -- The PLL is deliberately outside image_processor: clocks are a board
    -- concern, and the testbench drives the system clock directly.
    ----------------------------------------------------------------
    component VIDEO_PLL is
        port (
            refclk   : in  std_logic;
            rst      : in  std_logic;
            outclk_0 : out std_logic;   --  20 MHz
            outclk_1 : out std_logic;   -- 100 MHz
            locked   : out std_logic
        );
    end component;

    component d8m is
        generic (
            MAX_LINE      : natural := 2048;
            RESET_TICKS   : natural := 50_000_000;
            BAYER_SWAP_RB : boolean := false;
            BAYER_X_ODD   : boolean := false;
            BAYER_Y_ODD   : boolean := false
        );
        port (
            clk_50         : in    std_logic;
            rst_n          : in    std_logic;
            mipi_pixel_clk : in    std_logic;
            mipi_pixel_d   : in    std_logic_vector(9 downto 0);
            mipi_pixel_hs  : in    std_logic;
            mipi_pixel_vs  : in    std_logic;
            mipi_cs_n      : out   std_logic;
            mipi_reset_n   : out   std_logic;
            mipi_i2c_scl   : inout std_logic;
            mipi_i2c_sda   : inout std_logic;
            camera_i2c_scl : inout std_logic;
            camera_i2c_sda : inout std_logic;
            camera_pwdn_n  : out   std_logic;
            cam_clk        : out   std_logic;
            cam_vs         : out   std_logic;
            cam_de         : out   std_logic;
            cam_pixel      : out   std_logic_vector(23 downto 0);
            ready          : out   std_logic
        );
    end component;

    component image_processor is
        generic (
            IMG_W           : natural := 640;
            IMG_H           : natural := 480;
            ADDR_W          : natural := 19;
            N_FILTERS       : natural := 8;
            DEBOUNCE_TICKS  : natural := 2**20
        );
        port (
            clock       : in  std_logic;
            reset       : in  std_logic;
            cam_clk     : in  std_logic;
            cam_vs      : in  std_logic;
            cam_de      : in  std_logic;
            cam_pixel   : in  std_logic_vector(23 downto 0);
            keys_n      : in  std_logic_vector(1 downto 0);
            hex0        : out std_logic_vector(6 downto 0);
            hex1        : out std_logic_vector(6 downto 0);
            frame_sync  : in  std_logic;
            pixel_req   : in  std_logic;
            pixel       : out std_logic_vector(23 downto 0);
            pixel_valid : out std_logic
        );
    end component;

    component hdmi is
        generic (
            CLK_FREQUENCY : natural := 100_000_000;
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
            reset       : in    std_logic;
            frame_sync  : out   std_logic;
            pixel_req   : out   std_logic;
            pixel       : in    std_logic_vector(23 downto 0);
            hdmi_tx_clk : out   std_logic;
            hdmi_tx_d   : out   std_logic_vector(23 downto 0);
            hdmi_tx_hs  : out   std_logic;
            hdmi_tx_vs  : out   std_logic;
            hdmi_tx_de  : out   std_logic;
            hdmi_tx_int : in    std_logic;
            i2c_scl     : out   std_logic;
            i2c_sda     : inout std_logic
        );
    end component;

    signal clock        : std_logic;    -- system clock, 100 MHz
    signal reset        : std_logic;    -- active high
    signal pll_locked   : std_logic;

    signal cam_clk   : std_logic;
    signal cam_vs    : std_logic;
    signal cam_de    : std_logic;
    signal cam_pixel : std_logic_vector(23 downto 0);

    signal frame_sync : std_logic;
    signal pixel_req  : std_logic;
    signal pixel      : std_logic_vector(23 downto 0);

begin

    -- The board reset is active low; everything internal is active high.
    reset <= not reset_n;

    --------------------------------------------------------------------
    -- Clocks
    --------------------------------------------------------------------
    u_video_pll : VIDEO_PLL
        port map (
            refclk   => clk_50,
            rst      => '0',
            outclk_0 => mipi_refclk,
            outclk_1 => clock,
            locked   => pll_locked
        );

    --------------------------------------------------------------------
    -- D8M ==>
    --------------------------------------------------------------------
    u_d8m : d8m
        generic map (
            -- MEASURED ON HARDWARE, and it came out the opposite of what
            -- the register table predicted.
            --
            -- The prediction was: the sensor is natively BGGR, the config
            -- script turns on both mirror (0x3821 = 0x70) and flip
            -- (0x3820 = 0x06), each shifts the Bayer phase by one pixel,
            --
            --     B G   --mirror-->   G B   --flip-->   R G
            --     G R                 R G               G B
            --
            -- so RGGB arrives, which is BGGR with red and blue exchanged,
            -- so SWAP_RB should be true.  That was wrong.
            --
            -- What actually happens: with true, the picture comes out
            -- strongly blue -- the sensor's manual white balance boosts
            -- red hardest (0x5018/0x501a/0x501c = 0x19/0x10/0x17, red at
            -- about 1.56x green) and that boosted channel was landing in
            -- blue.  Selecting filter_swap, which exchanges red and blue
            -- back again, produced natural colour.  Two exchanges cancel,
            -- so there should be none here.
            --
            -- Leave filter_swap in the list: if the picture ever goes
            -- blue again it says in one button press whether the phase
            -- has moved.  BAYER_X_ODD and BAYER_Y_ODD reach the
            -- remaining phases if it has.
            BAYER_SWAP_RB => false,
            BAYER_X_ODD   => false,
            BAYER_Y_ODD   => false
        )
        port map (
            clk_50         => clk_50,
            rst_n          => reset_n,

            mipi_pixel_clk => mipi_pixel_clk,
            mipi_pixel_d   => mipi_pixel_d,
            mipi_pixel_hs  => mipi_pixel_hs,
            mipi_pixel_vs  => mipi_pixel_vs,
            mipi_cs_n      => mipi_cs_n,
            mipi_reset_n   => mipi_reset_n,
            mipi_i2c_scl   => mipi_i2c_scl,
            mipi_i2c_sda   => mipi_i2c_sda,
            camera_i2c_scl => camera_i2c_scl,
            camera_i2c_sda => camera_i2c_sda,
            camera_pwdn_n  => camera_pwdn_n,

            cam_clk        => cam_clk,
            cam_vs         => cam_vs,
            cam_de         => cam_de,
            cam_pixel      => cam_pixel,
            ready          => open
        );

    --------------------------------------------------------------------
    -- ==> video_store ==> bram ==> filters ==>
    --------------------------------------------------------------------
    u_image_processor : image_processor
        generic map (
            IMG_W       => IMG_W,
            IMG_H       => IMG_H,
            ADDR_W      => ADDR_W,
            N_FILTERS   => N_FILTERS,

            -- 10.5 ms of unbroken hold before a key press counts.
            DEBOUNCE_TICKS => 2**20
        )
        port map (
            clock       => clock,
            reset       => reset,

            cam_clk     => cam_clk,
            cam_vs      => cam_vs,
            cam_de      => cam_de,
            cam_pixel   => cam_pixel,

            keys_n      => keys_n,
            hex0        => hex0,
            hex1        => hex1,

            frame_sync  => frame_sync,
            pixel_req   => pixel_req,
            pixel       => pixel,
            pixel_valid => open
        );

    --------------------------------------------------------------------
    -- ==> HDMI
    --
    -- Video timing, the transmitter pins, and the transmitter's I2C setup,
    -- all in one module and given nothing but the clock rate and video
    -- mode.  The ADV7513 stays powered down until that I2C list arrives,
    -- so without this the video pins go nowhere.
    --------------------------------------------------------------------
    u_hdmi : hdmi
        generic map (
            CLK_FREQUENCY => CLK_FREQUENCY,
            PIX_DIV       => PIX_DIV,
            H_ACTIVE      => IMG_W,
            V_ACTIVE      => IMG_H
        )
        port map (
            clock       => clock,
            reset       => reset,

            frame_sync  => frame_sync,
            pixel_req   => pixel_req,
            pixel       => pixel,

            hdmi_tx_clk => hdmi_tx_clk,
            hdmi_tx_d   => hdmi_tx_d,
            hdmi_tx_hs  => hdmi_tx_hs,
            hdmi_tx_vs  => hdmi_tx_vs,
            hdmi_tx_de  => hdmi_tx_de,
            hdmi_tx_int => hdmi_tx_int,

            i2c_scl     => hdmi_i2c_scl,
            i2c_sda     => hdmi_i2c_sda
        );

end architecture rtl;
