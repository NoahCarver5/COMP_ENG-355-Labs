library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- Testbench for the Mandelbrot renderer.
--
--     mandelbrot ==> image_0.bmp, image_1.bmp, ...
--
-- The display side of the design is three signals -- a request once per
-- pixel and a flag that says a frame has ended -- so the testbench
-- generates them itself rather than instantiating hdmi.  That keeps the
-- run pointed at mandelbrot alone, and keeps the simulation off the
-- 800 x 525 raster, most of which is blanking nobody needs to simulate.
--
-- Timing is the same as the real thing where it matters: one pixel period
-- is PIX_DIV clocks, and pixel_req is asserted for exactly one clock at
-- the end of each period, which is when the color for that pixel is read.
--
-- WATCHING IT ZOOM
--
-- One frame on its own says little -- the interesting thing is the view
-- moving.  So the testbench writes N_IMAGES pictures, FRAME_INTERVAL
-- frames apart, and they should show the view closing in on the same
-- point with more detail each time.
--
-- Only the captured frames are drawn.  The view advances once per
-- frame_sync whether or not any pixels are asked for, so the frames in
-- between are blanking only: a few hundred clocks instead of two and a
-- half million.  That is what makes a visible zoom affordable to simulate.
--
-- Checking is by eye.  A Mandelbrot set is about the most self-checking
-- image there is: the shape is famous, so a wrong sign, a mis-scaled step
-- or a head start off by one is obvious at a glance.  Getting the head
-- start wrong shears the picture sideways -- a torn edge that no assertion
-- needed to find.
--
-- RUNTIME.  Each drawn frame is IMG_W x IMG_H pixels at PIX_DIV clocks
-- each -- about 2.5 million clocks.  Lower N_IMAGES while iterating.
--------------------------------------------------------------------------
entity mandelbrot_tb is
end entity mandelbrot_tb;

architecture behavioral of mandelbrot_tb is

    ---------------------------------------------------------------------
    -- CONFIGURATION -- DELIBERATELY NOT THE BOARD'S
    --
    -- Three of these are overridden to keep the simulation short.  The
    -- structure being tested is untouched: same engine count, same round
    -- robin, same head start, same arithmetic.  What is reduced is only
    -- how much WORK each pixel represents.
    --
    --                 board    here   why it was changed
    --   N_ENGINES        28      16   fewer engines to evaluate; the
    --                                 round robin is the same at any count
    --   MAX_ITER        110      62   iterations are the only thing that
    --                                 actually costs simulation time
    --   PIX_DIV           4       4   NOT changed.  Same clocks per pixel
    --                                 as the board.
    --   ZOOM_NUM       2047      15   2047/2048 would need ~800 frames
    --                                 between images to show any movement
    --
    -- Together those are 2x fewer engine evaluations per frame.
    --
    -- WHY THOSE THREE AND NOT OTHERS
    --
    -- Simulator work per frame is
    --
    --     clocks x engines  =  (IMG_W * IMG_H * PIX_DIV) * N_ENGINES
    --
    -- and the schedule needs N_ENGINES * PIX_DIV >= MAX_ITER + 2, so
    --
    --     work >= IMG_W * IMG_H * (MAX_ITER + 2)
    --
    -- That is worth knowing before trying to speed this up further:
    -- PIX_DIV and N_ENGINES trade against each other with NO net effect.
    -- Only MAX_ITER -- or a smaller image -- buys anything at all.
    --
    -- WHAT IS LOST BY DOING IT
    --
    -- Depth, and it is worth being precise about how.  A point that has not
    -- escaped by MAX_ITER is declared to be IN the set and painted black --
    -- the engine has no way to tell "inside" from "would have escaped on
    -- iteration 200".  So cutting MAX_ITER does not make the picture
    -- coarser, it makes it BLACKER, and increasingly so the deeper the zoom
    -- goes, because deep points take longer to escape.  Measured black
    -- fraction of the screen, same view either way:
    --
    --                   10x    100x    320x   1000x
    --   MAX_ITER 120    24%      0%      0%      0%
    --   MAX_ITER  62    25%      1%      2%      4%
    --   MAX_ITER  28    29%     21%     40%     89%
    --
    -- 62 tracks the board closely and 28 does not, which is the whole
    -- reason PIX_DIV is 4 rather than 2 here: the schedule needs
    -- MAX_ITER + 2 <= N_ENGINES * PIX_DIV, so 62 + 2 = 64 = 16 * 4 meets it
    -- exactly.  At PIX_DIV = 2 the ceiling is MAX_ITER = 30 and the last
    -- images go dark.  The extra clocks per pixel are what buys the
    -- iterations; there is no way around it, as the work formula above
    -- says.
    ---------------------------------------------------------------------
    constant IMG_W      : natural := 640;
    constant IMG_H      : natural := 480;
    constant N_PIXELS   : natural := IMG_W * IMG_H;

    constant N_ENGINES  : natural := 16;    -- board has 28
    constant MAX_ITER   : natural := 62;    -- board has 110
    constant PIX_DIV    : natural := 4;     -- board value, kept
    constant ZOOM_NUM   : natural := 15;    -- board has 2047

    constant SYS_PERIOD : time := 10 ns;    -- 100 MHz system clock

    ---------------------------------------------------------------------
    -- How much to look at.
    --
    --   N_IMAGES        how many BMPs to write.  This is the whole cost
    --                   of the run: one drawn frame each.
    --   FRAME_INTERVAL  frames between them.  Nearly free -- a skipped
    --                   frame is blanking only, 257 clocks against
    --                   1,228,800 for a drawn one, so the frames in
    --                   between are about 4,800x cheaper.
    --
    -- That is why ZOOM_NUM does not have to be absurdly fast.  Spacing the
    -- images out costs almost nothing, so the zoom rate can stay somewhere
    -- near realistic and FRAME_INTERVAL can carry the span instead.
    --
    -- At ZOOM_NUM = 15 and 12 frames apart, the eight images land at
    -- roughly 1x, 2x, 5x, 10x, 22x, 48x, 104x and 226x -- a full zoom
    -- ladder, for 0.2% overhead in skipped frames.
    ---------------------------------------------------------------------
    constant N_IMAGES       : natural := 8;
    constant FRAME_INTERVAL : natural := 12;

    ---------------------------------------------------------------------
    -- WHERE TO POINT IT.  OVERRIDDEN -- THE BOARD STARTS CENTERED.
    --
    -- This is the one override that is not about simulation speed.
    --
    -- The board starts on -0.5 + 0i, the whole set, and expects somebody to
    -- press the keys.  The testbench cannot press anything, and the zoom
    -- holds the middle of the screen still, so a run started there would
    -- descend into the main cardioid and write eight increasingly black
    -- pictures.  So it is aimed at the boundary from the first frame.
    --
    -- Written in billionths -- CENTER_DEN in mandel_pkg -- so -743643887
    -- is -0.743643887.  One number per axis, and no denominator to keep in
    -- step with it.
    --
    -- PICK ONE.  Measured black fraction of the screen on the way down:
    --
    --                            X_NUM       Y_NUM  WIDTH  10x  100x 1000x
    --   seahorse  (default) -743643887  +131825904      4  81%   48%   15%
    --   tendril               +1643722  -822467633      6  19%    0%    0%
    --   whole set           -500000000           0      4  94%  100%  100%
    --
    -- Seahorse is the famous one and the default, but read its numbers
    -- before being surprised by the images: that descent runs through the
    -- body of the period-2 bulb and does not clear until about 1000x, well
    -- past the 226x these eight images reach.  The seahorses ARE the black
    -- shapes.  Switch to the tendril to see the same machine produce a
    -- picture that stays colored all the way down.
    --
    -- VIEW_WIDTH is the first frame's width in units of the plane.  4 is
    -- the tightest that fits the whole set and is right for any center
    -- near the axis.  The tendril sits 0.82 below it and needs 6, or the
    -- top of the set falls off image_0 -- which is why the table carries a
    -- width column and not just a point.
    ---------------------------------------------------------------------
    constant CENTER_X_NUM : integer := -743643887;   -- -0.743643887
    constant CENTER_Y_NUM : integer :=  131825904;   -- +0.131825904
    constant VIEW_WIDTH   : natural :=  4;

    ---------------------------------------------------------------------
    -- What the keys and the switch are doing while the images are taken.
    --
    --   bit 0  left      momentary, active LOW  -- '0' means pressed
    --   bit 1  right
    --   bit 2  up
    --   bit 3  down
    --   bit 4  zoom_out  a SWITCH, active HIGH  -- '0' in, '1' out
    --
    -- "01111" is no keys and zoom in, which is what you want to watch the
    -- zoom land.  The view starts centered on CENTER_X_NUM / CENTER_Y_NUM
    -- above, and the zoom holds the middle of the screen still, so leaving
    -- the keys alone walks straight into that point.
    --
    -- Set bit 4 -- "11111" -- and the images come out in the opposite
    -- order, each wider than the last.  That is the quickest check that the
    -- direction switch works.
    --
    -- Hold a direction key instead and the view slides off the point it
    -- was aimed at.  That is panning working, not panning failing, but it
    -- is not the way to aim at somewhere in particular.  To do that, set
    -- CENTER_X_NUM and CENTER_Y_NUM above.
    constant KEY_SETTING : std_logic_vector(4 downto 0) := "01111";

    -- Pixel periods of blanking between frames.  The real raster spends 45
    -- lines here; all the design needs is long enough for the engines to
    -- take their head start, which measures at about 15 pixel periods, so
    -- 64 is four times over and still nothing next to a drawn frame.
    constant BLANK_PERIODS : natural := 64;

    ---------------------------------------------------------------------
    -- A whole frame of 8:8:8 pixels, raster order from the top left.
    ---------------------------------------------------------------------
    type frame_t is array (0 to N_PIXELS - 1) of std_logic_vector(23 downto 0);
    type char_file_t is file of character;

    ---------------------------------------------------------------------
    -- Write one little endian integer.
    ---------------------------------------------------------------------
    procedure put_le (file f              : char_file_t;
                      constant value      : in natural;
                      constant byte_count : in positive) is
        variable t : natural := value;
    begin
        for i in 1 to byte_count loop
            write(f, character'val(t mod 256));
            t := t / 256;
        end loop;
    end procedure put_le;

    ---------------------------------------------------------------------
    -- Write a frame out as a 24-bit uncompressed BMP.
    --
    -- BMP stores its rows bottom up and its channels as B, G, R.  Rows
    -- are padded out to a multiple of four bytes; at 640 x 3 = 1920 there
    -- is none, but the arithmetic is here so another width still works.
    ---------------------------------------------------------------------
    procedure write_bmp (constant file_name : in string;
                         variable img       : in frame_t) is
        file f          : char_file_t;
        variable status : file_open_status;
        variable p      : std_logic_vector(23 downto 0);

        constant PADDING    : natural := (4 - ((IMG_W * 3) mod 4)) mod 4;
        constant ROW_BYTES  : natural := IMG_W * 3 + PADDING;
        constant IMAGE_SIZE : natural := ROW_BYTES * IMG_H;
        constant FILE_SIZE  : natural := 54 + IMAGE_SIZE;
    begin
        file_open(status, f, file_name, write_mode);
        assert status = open_ok
            report "Could not open output image: " & file_name
            severity failure;

        -- File header
        write(f, character'('B'));
        write(f, character'('M'));
        put_le(f, FILE_SIZE, 4);
        put_le(f, 0, 2);
        put_le(f, 0, 2);
        put_le(f, 54, 4);

        -- Info header
        put_le(f, 40, 4);
        put_le(f, IMG_W, 4);
        put_le(f, IMG_H, 4);            -- positive height: bottom up
        put_le(f, 1, 2);
        put_le(f, 24, 2);
        put_le(f, 0, 4);                -- BI_RGB, uncompressed
        put_le(f, IMAGE_SIZE, 4);
        put_le(f, 2835, 4);
        put_le(f, 2835, 4);
        put_le(f, 0, 4);
        put_le(f, 0, 4);

        -- Pixel data, bottom up, B G R
        for y in IMG_H - 1 downto 0 loop
            for x in 0 to IMG_W - 1 loop
                p := img(y * IMG_W + x);
                write(f, character'val(to_integer(unsigned(p( 7 downto  0)))));
                write(f, character'val(to_integer(unsigned(p(15 downto  8)))));
                write(f, character'val(to_integer(unsigned(p(23 downto 16)))));
            end loop;
            for i in 1 to PADDING loop
                write(f, character'val(0));
            end loop;
        end loop;

        file_close(f);
        report "Wrote " & file_name severity note;
    end procedure write_bmp;

    ---------------------------------------------------------------------
    -- Components
    ---------------------------------------------------------------------
    component mandelbrot is
        generic (
            IMG_W      : natural := 640;
            IMG_H      : natural := 480;
            N_ENGINES  : natural := 16;
            MAX_ITER   : natural := 120;
            ZOOM_NUM   : natural := 2047;
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


    ---------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------
    signal clock  : std_logic := '0';
    signal reset  : std_logic := '0';

    signal keys_n : std_logic_vector(4 downto 0) := (others => '1');

    signal frame_sync : std_logic := '0';
    signal pixel_req  : std_logic := '0';
    signal pixel      : std_logic_vector(23 downto 0);

begin

    ---------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------
    dut : mandelbrot
        generic map (
            IMG_W      => IMG_W,
            IMG_H      => IMG_H,
            N_ENGINES  => N_ENGINES,
            MAX_ITER   => MAX_ITER,
            ZOOM_NUM   => ZOOM_NUM,
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

    -- The navigation keys never change during a run.
    keys_n <= KEY_SETTING;

    ---------------------------------------------------------------------
    -- System clock
    ---------------------------------------------------------------------
    sys_clock : process is
    begin
        clock <= '0';
        wait for SYS_PERIOD / 2;
        clock <= '1';
        wait for SYS_PERIOD / 2;
    end process sys_clock;

    ---------------------------------------------------------------------
    -- System reset
    ---------------------------------------------------------------------
    sys_reset : process is
    begin
        reset <= '0';
        wait for SYS_PERIOD / 2;
        reset <= '1';
        wait for SYS_PERIOD / 2;
        reset <= '0';
        wait;
    end process sys_reset;


    ---------------------------------------------------------------------
    -- Drive the display side, and photograph the result.
    --
    -- This is what hdmi does for the design on the board, reduced to the
    -- two signals mandelbrot actually reacts to.
    ---------------------------------------------------------------------
    stimulus_process : process is
        variable img : frame_t;
    begin
        wait until reset = '1';
        wait until reset = '0';
        wait until rising_edge(clock);

        for n in 0 to N_IMAGES - 1 loop
            for f in 0 to FRAME_INTERVAL - 1 loop

                ------------------------------------------------------
                -- The gap between frames.  Holding frame_sync high
                -- sends the walk back to the top left corner and lets
                -- the engines take their head start on the first
                -- N_ENGINES points.  It also moves the view on one
                -- step, which is true whether or not anything is drawn.
                ------------------------------------------------------
                frame_sync <= '1';
                for i in 1 to BLANK_PERIODS * PIX_DIV loop
                    wait until rising_edge(clock);
                end loop;
                frame_sync <= '0';
                wait until rising_edge(clock);

                ------------------------------------------------------
                -- Only the first frame of each group is drawn.  The rest
                -- exist to move the view on, and cost nothing but their
                -- blanking gap.
                ------------------------------------------------------
                if ( f = 0 ) then
                    report "Drawing image " & integer'image(n+1) & " of " &
                           integer'image(N_IMAGES) severity note;

                    for row in 0 to IMG_H - 1 loop
                        for col in 0 to IMG_W - 1 loop

                            -- One pixel period is PIX_DIV clocks.  Wait
                            -- out all but the last of them.
                            for k in 1 to PIX_DIV - 1 loop
                                wait until rising_edge(clock);
                            end loop;

                            -- On the last clock, take the color that has
                            -- been sitting there all period and ask for
                            -- the next pixel.
                            img(row * IMG_W + col) := pixel;
                            pixel_req <= '1';
                            wait until rising_edge(clock);
                            pixel_req <= '0';

                        end loop;
                    end loop;

                    write_bmp("image_" & integer'image(n+1) & ".bmp", img);

                end if;

            end loop;
        end loop;

        report "Wrote " & integer'image(N_IMAGES) & " images, " &
               integer'image(FRAME_INTERVAL) & " frames apart" severity note;
        stop;

    end process stimulus_process;

end architecture behavioral;
