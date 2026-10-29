library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Constants for the Mandelbrot set.
--
-- Everything in this lab is a SIGNED INTEGER.  There are no fractions and
-- no floating point anywhere.
--
-- The one thing to know is that the interesting part of the plane is only
-- a few units across, so plain integers would give a picture about six
-- pixels wide.  Instead the plane is laid out on a fine grid -- 2**32
-- steps to the unit -- and every coordinate below is an integer count of
-- grid steps.  Nothing else changes: adding two counts is just adding.
--
-- The one place it does show up is multiplication, and it is the whole
-- lesson of the lab:
--
--     count(a) * count(b)  =  a*b*SCALE*SCALE
--
-- which is SCALE times too big.  So after every multiply you take a SLICE
-- of the product -- starting SCALE_BITS up -- and that puts it back on the
-- grid.  Widen so the multiply cannot overflow, then select the bits you
-- want.  That is the technique, and it is written out at every use site
-- rather than wrapped in a function -- see mandel_engine.
--
-- Adds, subtracts and scaling by a plain integer need no slice at all.
--
-- SIGNED AND UNSIGNED
--
-- Nothing in this lab declares a signal, variable or constant of type
-- signed or unsigned.  Everything is std_logic_vector -- which is all a
-- bundle of wires ever is -- and the cast appears in the expression, at
-- the moment it matters:
--
--     x <= std_logic_vector(signed(a) + signed(b));
--
-- The point is that signedness is not a property of the wires.  The same
-- 36 bits are signed or unsigned depending only on which operator you hand
-- them to, and choosing wrongly is silent: signed(all ones) is -1,
-- unsigned(all ones) is 68719476735, and no tool will warn you.  Writing the
-- cast every time keeps that decision visible instead of buried in a
-- declaration a hundred lines away.
--
-- HEADROOM
--
-- COORD_WIDTH is four bits wider than SCALE_BITS, and those four bits are
-- the sign plus a range of +/- 8.  That is not spare room: z stays inside
-- radius 2 until it escapes, which keeps every intermediate under 8.  Move
-- SCALE_BITS without redoing that sum and the arithmetic wraps around and
-- the picture falls apart.
--
-- WHY THERE ARE NO SCALED INTEGERS HERE
--
-- Two different kinds of number live in a file like this.  Signals become
-- flip-flops and can be as wide as you like.  Constants declared as
-- `integer` never become anything -- the COMPILER works them out before
-- any gate exists, using its own integer type, which VHDL only guarantees
-- to reach 2**31 - 1.
--
-- So a line like  constant SCALE : integer := 2 ** SCALE_BITS  would put a
-- 32-bit ceiling on a design whose datapath is as wide as you please: at
-- SCALE_BITS = 29, 4 * SCALE is 2**31, which misses integer'high by one
-- and refuses to elaborate.  Nothing about the hardware is involved.
--
-- Every scaled constant below is therefore built in a VECTOR, wide enough
-- for the job, by to_coord and by shifting.  Small counts -- pixel widths,
-- bit positions, iteration limits -- stay integers, because a screen 640
-- pixels wide is never going to trouble 2**31.
--------------------------------------------------------------------------
package mandel_pkg is

    -- Bits per coordinate: SCALE_BITS below the point, plus sign and a
    -- range of +/- 8 above it.
    constant COORD_WIDTH : natural := 36;

    -- The grid: 2**32 steps to the unit.  SCALE_BITS is how far up a
    -- product has to be sliced to get back onto it.
    --
    -- There is deliberately no  constant SCALE : integer := 2**SCALE_BITS.
    -- A VHDL integer is only guaranteed to reach 2**31 - 1, so that one
    -- line would have capped SCALE_BITS at 28 -- not because the hardware
    -- cannot hold more, but because the COMPILER cannot.  Everything below
    -- is built in vectors instead, which have no such ceiling, and 32 is
    -- past what that line would have allowed.
    constant SCALE_BITS : natural := 32;

    ----------------------------------------------------------------------
    -- num/den as a coordinate on the grid.
    --
    -- The only place a scaled constant is created, and the reason it is a
    -- function: the intermediate  num * 2**SCALE_BITS  is far too big for
    -- an integer, so it is formed in a vector twice as wide as a
    -- coordinate and only then divided down and trimmed.
    --
    -- to_coord(4, IMG_W) is "four units across IMG_W pixels".
    -- to_coord(-743643887, 1000000000) is -0.743643887.
    --
    -- All of it happens at elaboration.  No divider appears on the chip.
    ----------------------------------------------------------------------
    function to_coord (num : integer;
                       den : integer := 1) return std_logic_vector;

    -- Escape test: once x*x + y*y reaches 4 the point is certain to run
    -- away to infinity, so there is no reason to keep iterating it.
    --
    -- One bit wider than a coordinate, to match the sum it is compared
    -- against, and built by shifting rather than by multiplying an integer.
    constant ESCAPE_SQ : std_logic_vector(COORD_WIDTH downto 0) :=
        std_logic_vector(shift_left(to_signed(4, COORD_WIDTH + 1), SCALE_BITS));

    -- Bits needed to hold value, i.e. ceil(log2(value)).  The same
    -- function Lab 5 has in trig_pkg.  Used to work a bit position out
    -- from a number rather than making the caller state both and keep
    -- them in agreement.
    function log2 (value : natural) return natural;

    ----------------------------------------------------------------------
    -- ESCAPE COUNT TO COLOR
    --
    -- The engines produce a number between 0 and MAX_ITER.  On its own
    -- that is a grey ramp, which looks like nothing.  Every Mandelbrot picture you have ever seen owes its
    -- appearance to this table, not to the arithmetic upstream.
    --
    -- It is a constant array indexed by a signal, which is how you write a
    -- ROM in VHDL: the synthesizer turns it into a lookup table.  Small
    -- enough to be a function rather than an entity -- it has no state, no
    -- clock and no reset, so wrapping it in a module would add a port map
    -- and nothing else.
    --
    -- Points that never escaped come out with the full count and are
    -- painted black, which is the convention.  That black region IS the
    -- Mandelbrot set; the colors around it are how quickly the outside
    -- runs away.
    --
    -- Change the table and the picture changes, with nothing else in the
    -- design affected.
    ----------------------------------------------------------------------
    -- Must be a power of two.  get_color stretches the escape count across
    -- the table by shifting it, and a shift is only a multiply or divide by
    -- a power of two -- at any other size that becomes a real multiplier.
    constant PALETTE_SIZE : natural := 128;
    type palette_t is array (0 to PALETTE_SIZE - 1) of std_logic_vector(23 downto 0);

    -- Deep blue -> blue -> white -> orange -> near black, and round again.
    -- A slowly changing count reads as a smooth band and a sharp change
    -- reads as an edge, which is what makes the filaments visible.
    constant PALETTE : palette_t := (
        x"000764", x"020C69", x"03116E", x"051673", x"061B78", x"081F7D", x"092482", x"0B2987",
        x"0C2E8C", x"0E3391", x"103896", x"113D9B", x"1342A0", x"1446A5", x"164BAA", x"1750AF",
        x"1955B4", x"1B5AB9", x"1C5FBF", x"1E64C4", x"1F69C9", x"236DCC", x"2972CD", x"3076CF",
        x"367BD0", x"3C7FD2", x"4284D4", x"4888D5", x"4E8CD7", x"5491D8", x"5B95DA", x"619ADB",
        x"679EDD", x"6DA3DF", x"73A7E0", x"79ACE2", x"80B0E3", x"86B4E5", x"8CB9E6", x"92BDE8",
        x"98C2EA", x"9EC6EB", x"A5CBED", x"ABCFEE", x"B1D4F0", x"B7D8F1", x"BDDCF3", x"C3E1F4",
        x"CAE5F6", x"D0EAF8", x"D6EEF9", x"DCF3FB", x"E2F7FC", x"E8FCFE", x"EDFEFD", x"EEFBF4",
        x"EEF8EB", x"EFF5E2", x"F0F2D9", x"F0EFD0", x"F1ECC7", x"F2E9BE", x"F2E6B5", x"F3E3AC",
        x"F3E0A3", x"F4DD9A", x"F5DA91", x"F5D788", x"F6D47F", x"F7D277", x"F7CF6E", x"F8CC65",
        x"F9C95C", x"F9C653", x"FAC34A", x"FAC041", x"FBBD38", x"FCBA2F", x"FCB726", x"FDB41D",
        x"FEB114", x"FEAE0B", x"FFAB02", x"F8A500", x"EF9F00", x"E59900", x"DC9300", x"D38D00",
        x"CA8700", x"C08100", x"B77B00", x"AE7500", x"A56E00", x"9B6800", x"926200", x"895C00",
        x"805600", x"765000", x"6D4A00", x"644400", x"5A3E00", x"513700", x"483100", x"3F2B00",
        x"352500", x"2C1F00", x"231900", x"1A1300", x"100D00", x"070700", x"000201", x"000207",
        x"00030C", x"000312", x"000317", x"00031D", x"000422", x"000428", x"00042D", x"000533",
        x"000538", x"00053E", x"000543", x"000649", x"00064E", x"000654", x"000659", x"00075F"
    );

    function get_color (iter     : std_logic_vector;
                        max_iter : natural) return std_logic_vector;

end package mandel_pkg;


package body mandel_pkg is

    function to_coord (num : integer;
                       den : integer := 1) return std_logic_vector is
        -- Twice a coordinate wide, so num * 2**SCALE_BITS cannot overflow
        -- on the way through.
        variable acc : signed(2 * COORD_WIDTH - 1 downto 0);
    begin
        acc := shift_left(to_signed(num, 2 * COORD_WIDTH), SCALE_BITS);
        acc := acc / den;
        return std_logic_vector(resize(acc, COORD_WIDTH));
    end function;

    function log2 (value : natural) return natural is
        variable v      : natural;
        variable result : natural := 0;
    begin
        if value <= 1 then
            return 1;
        end if;
        v := value - 1;
        while v > 0 loop
            v := v / 2;
            result := result + 1;
        end loop;
        return result;
    end function;

    function get_color (iter     : std_logic_vector;
                       max_iter : natural) return std_logic_vector is
        constant BLACK : std_logic_vector(23 downto 0) := x"000000";

        -- Bits the count arrives in, and bits the table wants.  Both are
        -- worked out at elaboration from constants, so the difference
        -- between them is a fixed shift distance.
        constant ITER_WIDTH : natural := log2(max_iter + 1);
        constant PAL_WIDTH  : natural := log2(PALETTE_SIZE);

        variable n : natural;
    begin
        n := to_integer(unsigned(iter));

        if ( n >= max_iter ) then
            return BLACK;                       -- inside the set

        elsif ( ITER_WIDTH < PAL_WIDTH ) then
            -- Fewer counts than colors.  Indexing the table directly would
            -- only ever reach its first few entries -- with MAX_ITER = 28
            -- that is entries 0..27 of 128, the whole picture stuck in the
            -- blue run-in of the gradient.  Line the count up with the top
            -- of the table instead, so the gradient is used end to end
            -- whatever MAX_ITER is.  Shifting left by a constant is free:
            -- it is which wires go where, not a multiplier.
            return PALETTE(n * 2 ** (PAL_WIDTH - ITER_WIDTH));

        else
            -- More counts than colors: two or more counts share a color.
            -- Again a constant shift, the other way.
            return PALETTE(n / 2 ** (ITER_WIDTH - PAL_WIDTH));
        end if;
    end function;

end package body mandel_pkg;
