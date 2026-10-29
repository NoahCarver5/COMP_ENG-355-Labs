library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- Mandelbrot renderer.  STRUCTURAL ONLY -- instances and wiring.  There
-- is not a process in this file; every register lives in a submodule.
--
-- WHAT THE WHOLE THING COMPUTES
--
-- The screen is a window onto the complex plane.  Every pixel stands for
-- one complex number c, and the question asked of each one is the same:
--
--     start with z = 0, apply  z <- z*z + c  over and over.
--     Does z stay near the origin, or does it run away to infinity?
--
-- Points where it stays are the Mandelbrot set, and are painted black.
-- Points where it runs away are colored by HOW FAST they ran -- the
-- number of steps before z got further than 2 from the origin.  All the
-- structure you see is in that count: the black shape is the set, and the
-- bands around it are its escape times.
--
-- A complex number includes a real part and an imaginary part, so each one 
-- is stored as two signed signals:
--
--     c = cx + cy*i      cx = real part, cy = imaginary part
--     z = x  + y*i       x  = real part, y  = imaginary part
--
-- (i is not a signal; it only marks the imaginary part.  mandel_engine
-- explains how z*z + c becomes two equations on x and y.)
--
-- The screen maps onto the plane like a graph: the column (left/right)
-- sets cx on the horizontal (real) axis, and the row (up/down) sets cy
-- on the vertical (imaginary) axis.  Each pixel is one step apart:
--
--     cx = x0 + col * pixel_step
--     cy = y0 + row * pixel_step
--
-- viewport owns x0, y0 and pixel_step, which is to say it owns where the
-- window is and how big it is.  mandel_engine_bank walks the window, hands each c
-- to an iterator, and colors the answer.
--
-- PIPELINE
--
--     viewport => mandel_engine_bank => (hdmi)
--         ^
--     keys_n
--
--     viewport      where on the plane we are looking; zooms and pans
--                   once per frame
--     mandel_engine_bank   walks the raster, farms each point out to N iterators
--                   worked round robin, then colors the answer.  Runs N
--                   points ahead, so the pixel is ready when asked for
--
-- There is no frame buffer.  Pixels go straight to hdmi as the raster
-- scans them, which works because the bank keeps its engines running a
-- fixed number of pixels AHEAD of the raster: every pixel is finished
-- before it is asked for, so there is nothing to store and nothing to
-- wait for.
--
-- THE ONE NUMBER THAT MATTERS
--
--     MAX_ITER + 2  <=  N_ENGINES * PIX_DIV
--
-- The display needs a pixel every PIX_DIV clocks and each iterator needs
-- MAX_ITER clocks per pixel, so the only way to keep up is to run enough
-- of them in parallel -- or to raise the clock, which lifts PIX_DIV and
-- costs no silicon. 
--
-- Deeper zoom wants a lot more iterations, so it wants more engines: that
-- is the whole lesson.  Throughput comes from replication once latency
-- cannot be reduced any further.
--------------------------------------------------------------------------
entity mandelbrot is
    generic (
        IMG_W      : natural := 640;
        IMG_H      : natural := 480;

        -- Parallel iterators.  Also how far ahead of the raster the
        -- engines run -- see mandel_engine_bank.
        N_ENGINES  : natural := 16;

        -- Iterations per pixel.  2**k - 1 is the efficient shape: the
        -- counter inside each engine then fills its width exactly.
        MAX_ITER   : natural := 120;

        -- Zoom rate: each frame the view shrinks to ZOOM_NUM / the next
        -- power of two up.  2047 means 2047/2048, which reaches 4x in
        -- about 45 seconds and bottoms out after five minutes.  See the
        -- table in mandelbrot_system for the other rates worth trying.
        -- The testbench winds it up so a few simulated frames move.
        ZOOM_NUM   : natural := 2047;

        -- How far a held key slides the view, in pixels per frame.
        PAN_PIXELS : natural := 8;

        -- Where the view starts, and so where the zoom ends up: the center
        -- of the first frame as a numerator over a denominator, and how
        -- wide that frame is in units of the plane.  Passed straight to
        -- viewport, which is where they are explained.
        CENTER_X_NUM : integer := -500000000;
        CENTER_Y_NUM : integer := 0;
        VIEW_WIDTH   : natural := 4
    );
    port (
        clock      : in  std_logic;
        reset      : in  std_logic;                       -- async, active high

        -- KEY[3:0], active low: left, right, up, down.
        keys_n     : in  std_logic_vector(4 downto 0);

        -- ---- from hdmi ----
        frame_sync : in  std_logic;
        pixel_req  : in  std_logic;

        -- ---- to hdmi ----
        pixel      : out std_logic_vector(23 downto 0)
    );
end entity mandelbrot;


architecture structural of mandelbrot is

    ----------------------------------------------------------------------
    -- Component Declarations
    -- TODO: Declare the viewport and mandel_engine_bank components
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- Signal Declarations
    -- TODO: Declare the signals that connect the viewport and mandel_engine_bank
    ----------------------------------------------------------------------

begin

    ----------------------------------------------------------------------
    -- TODO: Instantiate and wire together the viewport and 
    -- mandel_engine_bank components.
    ----------------------------------------------------------------------

end architecture structural;
