library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- Lab: Mandelbrot.
--
--                 +---------------------- mandelbrot ---------------------+
--                 |                                                       |
--                 |  +----------+   x0, y0,     +---------------------+   |   pixel
--   keys_n(4:0) --+->| viewport |   pixel_step  | mandel_engine_bank  |   | (24-bit RGB)
--                 |  |          |-------------->|  N_ENGINES copies   |---+------------+
--                 |  |  pan /   |               |  of mandel_engine,  |   |            |
--                 |  |  zoom    |               |  run in parallel    |   |            v
--                 |  +----------+               +---------------------+   |     +------------+
--                 |       ^                        ^           ^          |     |            |--> hdmi_tx_clk
--                 +-------|------------------------|---------- | ---------+     |            |--> hdmi_tx_d(23:0)
--                         |                        |           |                |    hdmi    |--> hdmi_tx_hs/vs/de
--                         |       frame_sync       |           |                |            |<-- hdmi_tx_int
--                         +------------------------+---------- | ---------------|            |--> i2c_scl
--                                                              |   pixel_req    |            |<-> i2c_sda
--                                                              +----------------|            |
--                                                                               +------------+
--
--   clk_50 --> VIDEO_PLL --> clock (100 MHz) --> all modules
--   reset_n --> not -----> reset (active high) --> all modules
--
--   viewport           : tracks where on the plane the screen is looking
--                        (x0, y0 = top-left corner, pixel_step = spacing
--                        between pixels).  Pans with keys_n(3:0), zooms
--                        continuously in or out as set by keys_n(4), and
--                        updates once per frame.
--   mandel_engine_bank : walks the screen pixel by pixel, gives each
--                        point c to a free mandel_engine, and returns the
--                        finished color.
--   hdmi               : generates the 640x480 video timing, asks for
--                        each pixel (pixel_req), marks the start of each
--                        frame (frame_sync), and drives the HDMI
--                        transmitter, which it configures over I2C.
--
-- No frame buffer, no SDRAM, no camera.  The picture is computed as the
-- raster scans it and handed straight to the transmitter.
--
-- CLOCKING
--
-- The PLL takes the board's 50 MHz to 100 MHz, and hdmi divides that by
-- PIX_DIV = 4 for the 25 MHz pixel rate.  There is exactly one clock in
-- this design; the pixel rate is an enable on it.
--
-- The 100 MHz is not about the display -- 50 MHz would drive a 640x480
-- raster perfectly well with PIX_DIV = 2.  It is about the engines.  Four
-- clocks per pixel across 28 engines is 112 clocks to spend on 110
-- iterations; two clocks per pixel would only be 56, and the picture would
-- show stale counts.  Faster clock, or more engines: those are the two
-- ways to buy iterations.  The clock is free until timing stops closing,
-- and one Mandelbrot iteration is about 9 ns of logic, so 100 MHz is as
-- far as it goes.  The rest has to come from engines, and they run out
-- too -- see N_ENGINES below, which is capped by the DSP blocks.
--
-- The PLL is deliberately outside mandelbrot -- clocks are a board
-- concern, and the testbench drives the system clock directly.
--------------------------------------------------------------------------
entity mandelbrot_system is
    port (
        -- ---- clocks and reset ----
        clk_50      : in  std_logic;                      -- board oscillator
        reset_n     : in  std_logic;                      -- KEY, active low

        -- ---- navigation ----
        -- Bits 0 to 3 are left, right, up, down: momentary keys, ACTIVE
        -- LOW.  Bit 4 is the zoom direction: a SWITCH, ACTIVE HIGH, 0 to
        -- close in and 1 to open back out.
        keys_n      : in  std_logic_vector(4 downto 0);

        -- ---- HDMI TX ----
        hdmi_tx_clk : out std_logic;
        hdmi_tx_d   : out std_logic_vector(23 downto 0);
        hdmi_tx_hs  : out std_logic;
        hdmi_tx_vs  : out std_logic;
        hdmi_tx_de  : out std_logic;
        hdmi_tx_int : in  std_logic;                      -- active low

        -- ---- I2C, to configure the HDMI transmitter ----
        i2c_scl     : out   std_logic;
        i2c_sda     : inout std_logic
    );
end entity mandelbrot_system;


architecture structural of mandelbrot_system is

    constant IMG_W      : natural := 640;
    constant IMG_H      : natural := 480;

    ----------------------------------------------------------------------
    -- ENGINES, AND WHAT LIMITS THEM
    --
    -- Each engine squares a 36-bit coordinate three times over, which the
    -- fitter builds from 6 DSP blocks.  The device has 188, so 31 engines
    -- is the hard ceiling and 28 leaves room for the fitter to breathe.
    --
    -- The schedule then sets the depth: MAX_ITER + 2 <= N_ENGINES *
    -- PIX_DIV is 112 <= 112, so 110 iterations.  The lost 10 are not
    -- visible -- a point that survives 110 iterations almost always
    -- survives 120 as well.
    ----------------------------------------------------------------------
    constant N_ENGINES  : natural := 28;
    constant MAX_ITER   : natural := 110;

    constant CLK_FREQUENCY : natural := 100_000_000;

    -- 100 MHz / 4 = 25 MHz pixel rate.
    constant PIX_DIV    : natural := 4;

    ----------------------------------------------------------------------
    -- ZOOM RATE -- THE ONE TO TRY ON THE BOARD
    --
    -- Each frame the view shrinks to ZOOM_NUM / the next power of two up.
    -- Change this one number and rebuild; nothing else has to follow,
    -- because viewport derives ZOOM_BITS, the zoom-out numerator and the
    -- floor from it.  Times are at 60 Hz:
    --
    --                        4x    16x   100x   deepest      in     out
    --     8191 / 8192      3:09   6:18  10:26    3,276x   17:27   19:44
    --     4095 / 4096      1:34   3:09   5:13    6,553x    9:30   10:39
    --     2047 / 2048      0:47   1:34   2:37   13,107x    5:09    5:43
    --     1023 / 1024      0:23   0:47   1:18   26,214x    2:46    3:03
    --      511 /  512      0:12   0:24   0:39   52,428x    1:29    1:38
    --  >>  255 /  256      0:06   0:12   0:20  104,857x    0:47    0:52
    --
    -- Read the "deepest" column twice, because it is the opposite of what
    -- everyone expects: the SLOW rate is also the SHALLOW one.  The floor
    -- is STEP_MIN = 2**ZOOM_BITS, so a gentler rate raises the floor as
    -- fast as it slows the descent.  8191 is worse than 1023 on every
    -- count except how long it lasts.  Why the floor cannot go lower is
    -- the integer-truncation argument at STEP_MIN in viewport.
    --
    -- 255 is the default because the zoom is visibly moving within a
    -- couple of seconds and a full descent fits in under a minute.
    --
    -- Note what is NOT on this list: how easy it is to steer.  The keys
    -- move the view PAN_PIXELS a frame, and 255/256 pulls the screen edge
    -- in by 320/256 = 1.25 pixels a frame, so a 2 pixel pan still outruns
    -- the zoom everywhere on the screen.  Slower rates only widen that gap.
    ----------------------------------------------------------------------
    constant ZOOM_NUM   : natural := 255;

    -- How far a held key slides the view, in pixels per frame.  2 is 120
    -- pixels a second at 60 Hz, about five seconds to cross the screen.
    constant PAN_PIXELS : natural := 2;

    ----------------------------------------------------------------------
    -- WHERE THE VIEW STARTS
    --
    -- Centered on the set, 4 units wide: the view everybody recognizes,
    -- and the one to start a lab session from.  Written in billionths --
    -- -500000000 is -0.5 -- on the scale CENTER_DEN fixes in viewport.
    -- 4 units is the tightest frame the whole set fits in.
    --
    -- THE BOARD IS MEANT TO BE DRIVEN.  The zoom holds the middle of the
    -- screen still, so left alone it closes in on -0.5 + 0i, which is deep
    -- inside the main cardioid.  At the default rate it is 16x deep after
    -- 12 seconds and a black screen from there on.  That is not a fault:
    -- the middle of the set is solid, and no iteration count changes it.
    --
    -- The keys are the answer.  Pan onto the boundary while the view is
    -- still wide -- the seam left of center, around -0.75, is the easiest
    -- to find -- and the same zoom then has something to descend into.
    -- viewport lists two destinations worth steering for.
    --    
    -- Select an alternate starting point, and the same zoom will descend 
    -- into it. Measured black fraction of the screen on the way down:
    --
    --                            X_NUM       Y_NUM  WIDTH  10x  100x 1000x
    --   centered (default)  -500000000           0      4  94%  100%  100%
    --   seahorse            -743643887  +131825904      4  81%   48%   15%
    --   tendril               +1643722  -822467633      6  19%    0%    0%

    ----------------------------------------------------------------------
    constant CENTER_X_NUM : integer := -500000000;
    constant CENTER_Y_NUM : integer := 0;
    constant VIEW_WIDTH   : natural := 4;

    ----------------------------------------------------------------------
    -- Video PLL.  Quartus-generated PLL, 50 MHz in, 100 MHz out.
    -- Regenerate the IP from the catalog if the board oscillator changes.
    ----------------------------------------------------------------------
    component VIDEO_PLL is
        port (
            refclk   : in  std_logic;
            rst      : in  std_logic;
            outclk_0 : out std_logic;   -- 100 MHz system clock
            locked   : out std_logic
        );
    end component;

    component mandelbrot is
        generic (
            IMG_W      : natural := 640;
            IMG_H      : natural := 480;
            N_ENGINES  : natural := 16;
            MAX_ITER   : natural := 120;
            ZOOM_NUM   : natural := 2047;
            PAN_PIXELS : natural := 8;
            CENTER_X_NUM : integer := -500000000;
            CENTER_Y_NUM : integer := 0;
            VIEW_WIDTH   : natural := 4
        );
        port (
            clock      : in  std_logic;
            reset      : in  std_logic;
            keys_n     : in  std_logic_vector(4 downto 0);
            frame_sync : in  std_logic;
            pixel_req  : in  std_logic;
            pixel      : out std_logic_vector(23 downto 0)
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

    signal clock      : std_logic;      -- system clock, 100 MHz
    signal reset      : std_logic;      -- active high
    signal pll_locked : std_logic;

    signal frame_sync : std_logic;
    signal pixel_req  : std_logic;
    signal pixel      : std_logic_vector(23 downto 0);

begin

    -- The board reset is active low; everything internal is active high.
    reset <= not reset_n;

    ----------------------------------------------------------------------
    -- Clocks
    ----------------------------------------------------------------------
    u_video_pll : VIDEO_PLL
        port map (
            refclk   => clk_50,
            rst      => '0',
            outclk_0 => clock,
            locked   => pll_locked
        );

    ----------------------------------------------------------------------
    -- Renderer
    ----------------------------------------------------------------------
    u_mandelbrot : mandelbrot
        generic map (
            IMG_W      => IMG_W,
            IMG_H      => IMG_H,
            N_ENGINES  => N_ENGINES,
            MAX_ITER   => MAX_ITER,
            ZOOM_NUM   => ZOOM_NUM,
            PAN_PIXELS => PAN_PIXELS,
            CENTER_X_NUM => CENTER_X_NUM,
            CENTER_Y_NUM => CENTER_Y_NUM,
            VIEW_WIDTH   => VIEW_WIDTH
        )
        port map (
            clock      => clock,
            reset      => reset,
            keys_n     => keys_n,
            frame_sync => frame_sync,
            pixel_req  => pixel_req,
            pixel      => pixel
        );


    ----------------------------------------------------------------------
    -- HDMI output
    --
    -- Video timing, the transmitter pins, and the transmitter's I2C setup,
    -- all in one module and given nothing but the clock rate and video
    -- mode.  It asks for a pixel and one is already there:
    -- mandel_engine_bank keeps its engines running ahead of the raster, so
    -- there is no latency here to compensate for.
    ----------------------------------------------------------------------
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

            i2c_scl     => i2c_scl,
            i2c_sda     => i2c_sda
        );

end architecture structural;
