library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- mandel_engine: computes the color of ONE pixel of the Mandelbrot set.
--
-- WHAT IS THE MANDELBROT SET?
--
-- Treat each pixel as a point on a plane, with horizontal coordinate cx
-- and vertical coordinate cy.  Start a second point (x, y) at the origin,
-- (0, 0), and move it over and over with this rule:
--
--     new x = x*x - y*y + cx
--     new y = 2*x*y     + cy
--
-- For some pixels, (x, y) stays near the origin no matter how many times
-- the rule is applied.  Those pixels are IN the Mandelbrot set and are
-- drawn dark.  For every other pixel, (x, y) eventually runs away.  The
-- number of steps it takes to get farther than 2 from the origin is the
-- pixel's "escape count", and that count picks the pixel's color.
--
-- WHERE THE RULE COMES FROM: COMPLEX NUMBERS
--
-- The rule is usually written with complex numbers.  A complex number is
-- a pair of ordinary numbers, a REAL part and an IMAGINARY part, written
--
--     z = x + y*i         x is the real part, y is the imaginary part
--     c = cx + cy*i       cx is the real part, cy is the imaginary part
--
-- Here i is NOT a variable or a signal.  It is the imaginary unit,
-- defined by i*i = -1, and it only marks which number is the imaginary
-- part.  So z = x + y*i is just the point (x, y), and c = cx + cy*i is
-- the pixel (cx, cy).  The rule above is the expansion of
--
--     z <- z*z + c
--
-- Multiplying out z*z and using i*i = -1:
--
--     z*z = (x + y*i)(x + y*i) = x*x + 2*x*y*i + y*y*i*i
--         = (x*x - y*y)  +  (2*x*y)*i
--            real part      imaginary part
--
-- Adding c adds cx to the real part and cy to the imaginary part, which
-- gives the two update equations at the top.  The hardware has no complex
-- type and never uses i: it stores the real part x and the imaginary part
-- y as two separate signed numbers.
--
-- THE ESCAPE TEST
--
-- The distance of (x, y) from the origin is sqrt(x*x + y*y).  It is a
-- known property of the Mandelbrot set that once this distance is more
-- than 2 (the escape radius), the point is guaranteed to keep running
-- away, so it has "escaped".  To avoid a square root, square both sides
-- and compare against the radius squared instead:
--
--     sqrt(x*x + y*y) > 2      is the same as      x*x + y*y > 2*2 = 4
--
-- That 4 is the constant ESCAPE_SQ in mandel_pkg, stored in the same
-- fixed-point format as the coordinates (4 * 2**SCALE_BITS).
--
-- A point that has not escaped after MAX_ITER steps is treated as being
-- in the set.
--
-- THE OUTPUT
--
-- The engine turns the escape count into a 24-bit RGB color with
-- get_color (a lookup table in mandel_pkg) and drives it on pixel.
--
-- FIXED TIMING
--
-- The engine always runs for MAX_ITER clocks, even when a point escapes
-- early.  After it escapes, (x, y) simply stops changing.  Because every
-- pixel takes the same number of clocks, mandel_engine_bank can run many
-- engines side by side and know exactly when each one is finished.
--
-- THE NUMBER FORMAT
--
-- Coordinates are COORD_WIDTH-bit (36-bit) FIXED-POINT numbers.  The low
-- SCALE_BITS (32) bits are the fraction, so a stored integer N means the
-- value N / 2**32.  The top 4 bits hold the sign and a range of +/- 8.
--
--   - Adding two fixed-point numbers works directly.
--   - Multiplying them gives a 72-bit result that is 2**32 too big.
--     Keep bits (SCALE_BITS + COORD_WIDTH - 1 downto SCALE_BITS) to divide
--     it back down.
--   - x, y, cx and cy can be negative, so they are SIGNED.  The escape
--     count and x*x + y*y are never negative, so they are UNSIGNED.
--------------------------------------------------------------------------
entity mandel_engine is
    generic (
        MAX_ITER : natural := 120
    );
    port (
        clock : in  std_logic;
        reset : in  std_logic;                            -- async, active high

        -- Start a new point.  One clock wide.
        start : in  std_logic;
        cx    : in  std_logic_vector(COORD_WIDTH - 1 downto 0);
        cy    : in  std_logic_vector(COORD_WIDTH - 1 downto 0);

        -- High when this engine can take a new point
        ready : out std_logic;

        -- Color of the point.  Registered, and settles on the same edge
        -- that ready goes high.  Held until the next start.
        pixel : out std_logic_vector(23 downto 0)
    );
end entity mandel_engine;


architecture rtl of mandel_engine is

    --------------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------------
    -- Wide enough to hold 0 .. MAX_ITER.  Derived, not a generic: there is
    -- exactly one right answer and no reason to make the caller supply it.
    -- MAX_ITER of 2**k - 1 fills the width exactly, which is why 127 is a
    -- better choice than 128 -- 128 would need an eighth bit to hold one
    -- extra value.
    constant ITER_WIDTH : natural := log2(MAX_ITER + 1);

    -- Extra integer bits for the escape test only.  x and y fit in
    -- COORD_WIDTH (+/- 8), but the iteration that first crosses |z| = 2
    -- can leave a component near 6, whose square is near 36.  Sliced to
    -- COORD_WIDTH that square wraps, the test misses the escape, and the
    -- pixel keeps iterating garbage.  Four more bits hold squares to 128.
    constant GUARD_BITS : natural := 4;

    --------------------------------------------------------------------------
    -- Signal Declarations
    --------------------------------------------------------------------------

begin

    --------------------------------------------------------------------------
    -- TODO: Implement the mandel_engine process.  It should run the iteration
    -- z <- z*z + c, counting how many iterations it takes to escape.
    -- The header at the top of this file explains the math.
    --
    -- THE ALGORITHM  (one step per cycle)
    --   1. On start: save cx and cy, set x = 0 and y = 0, and clear the
    --      escape count.
    --   2. On each clock after that, until MAX_ITER clocks have passed:
    --        - compute x*x, y*y and x*y
    --        - if the point has not escaped yet:
    --            if x*x + y*y > 4, mark it as escaped (x and y stop changing)
    --            otherwise update x and y with the two equations and add 1
    --            to the escape count
    --   3. Once MAX_ITER clocks have passed, set ready to '1'.  Drive pixel
    --      with get_color(escape count, MAX_ITER) on every clock.
    --
    -- NOTES ON THE NUMBERS
    --   - Keep signals as std_logic_vector, and cast to signed or unsigned
    --     inside each expression, then resize as needed, and cast back to 
    --     std_logic_vector for storage.
    --   - On the step that escapes, x*x + y*y can be bigger than the +/- 8
    --     range, so give the escape test GUARD_BITS extra bits.  ESCAPE_SQ is
    --     the value 4 in the fixed-point format.
    --------------------------------------------------------------------------

    clocked_process : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            pixel   <= (others => '0');
            ready   <= '0';
        elsif rising_edge(clock) then
            pixel   <= (others => '0');
            ready   <= '0';
        end if;
    end process clocked_process;



end architecture rtl;
