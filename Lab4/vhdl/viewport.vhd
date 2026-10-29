library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- Where on the complex plane we are looking.
--
-- Three numbers say everything: the top left corner of the view (x0, y0)
-- and how much of the plane ONE PIXEL COVERS (pixel_step).  The screen
-- then shows a patch IMG_W * pixel_step wide and IMG_H * pixel_step tall,
-- and mandel_engine_bank walks it from that corner.
--
-- PIXEL_STEP IS THE ZOOM LEVEL
--
-- It is the scale bar on a map, and it works the same way round.  A pixel
-- on the screen is always a pixel -- 640 of them across, always.  What
-- changes when you zoom is how much of the PLANE each one stands for:
--
--     zoomed out    pixel_step = 26843545  ->  640 px span 4 units
--     zoomed in     pixel_step = 2048      ->  640 px span 0.000305 units
--
-- So zooming IN makes pixel_step SMALLER.  Nothing on the screen shrinks;
-- the piece of the plane behind each pixel does.  Same as a map: zoom in
-- and the scale bar goes from "100 km" to "100 m" -- the bar is the same
-- length on paper, it just stands for less ground.
--
-- WHAT THIS MODULE DOES, ONCE A FRAME
--
-- It makes pixel_step a little smaller, and it moves the corner.  That is
-- all.  The process below does it in four short steps, and the comments
-- there walk through each one.
--
-- Why the corner has to move at all is the only part that is not obvious,
-- so here it is up front.  The screen covers
--
--     from x0  to  x0 + 640 * pixel_step
--
-- Make pixel_step smaller and leave x0 alone, and only the RIGHT edge
-- comes in -- the left edge is nailed down.  The picture would appear to
-- rush into its top left corner.  Moving the corner in by half of what the
-- view lost keeps the MIDDLE of the screen still instead, which is what
-- anyone means by "zoom in".
--
-- WHY A FRACTION RATHER THAN "TAKE OFF A FIXED AMOUNT"
--
-- Because a fixed fraction looks like a steady speed.  Taking off a fixed
-- AMOUNT each frame would barely move at the start and then swallow most
-- of what was left on the final frame -- it would creep, then lurch.
--
-- IN, OUT, AND NEITHER
--
-- keys_n(4) picks the direction: 0 closes in, 1 opens out.  At each end
-- the view simply stops and waits -- nothing jumps back to the start, so
-- the switch is the only way to reverse.  A full descent takes about 17
-- minutes and the climb back about 20, which is meant to be watched
-- rather than demonstrated.
--
-- ONCE A FRAME, NOT ONCE A CLOCK
--
-- The view must not move while a frame is being drawn or the picture would
-- tear, and frame_sync is exactly the "nothing is being drawn right now"
-- signal.
--
-- The zoom cannot run for ever -- see STEP_MIN below for what stops it --
-- so when it has gone as far as it usefully can it simply holds there,
-- and stays held until the switch is thrown the other way.
--------------------------------------------------------------------------
entity viewport is
    generic (
        IMG_W       : natural := 640;
        IMG_H       : natural := 480;

        -- Each frame the view moves by ZOOM_NUM / the next power of two
        -- up.  2047 means 2047/2048, about 2.9% a second at 60 Hz, which
        -- takes some five minutes to run its course; the testbench uses
        -- 15, meaning 15/16, so that a handful of simulated frames
        -- visibly move.  mandelbrot_system tabulates the rates worth
        -- trying on the board.
        --
        -- This one number sets the whole character of the run.  Smaller is
        -- faster and deeper, larger is slower and shallower -- see
        -- STEP_MIN below for why the two are tied together.
        --
        -- ZOOM_BITS is not a second knob to keep in step, and neither is
        -- the zoom-out numerator -- both are worked out from this one.
        ZOOM_NUM    : natural := 2047;

        -- How far one key press slides the view, in pixels per frame.
        PAN_PIXELS  : natural := 8;

        ------------------------------------------------------------------
        -- WHERE THE VIEW STARTS, AND THEREFORE WHERE THE ZOOM ENDS UP
        --
        -- Generics rather than constants in the body, so the destination
        -- can be changed from the top level -- the board and the testbench
        -- each set their own -- without editing this file.
        --
        -- In billionths of a unit -- see CENTER_DEN below -- so that
        -- -743643887 means -0.743643887.  One number per axis, and no
        -- denominator to keep in step with it.
        --
        -- The default is the view everybody recognizes: the whole set,
        -- centered.  Note what that costs, though, and see the note on
        -- CENTER_X_INIT below -- the middle of the set is solid black at
        -- every depth, so this default is a starting point to navigate
        -- FROM, not a destination.
        ------------------------------------------------------------------
        CENTER_X_NUM : integer := -500000000;      -- -0.5
        CENTER_Y_NUM : integer := 0;               --  0.0

        -- Width of the first frame, in units of the plane.  The set spans
        -- x -2.05 .. +0.5 and y -1.15 .. +1.15, so 4 is the tightest that
        -- fits it when the view is centered on it -- and more than 4 is
        -- needed when it is not.  See PIXEL_STEP_INIT below.
        VIEW_WIDTH   : natural := 4
    );
    port (
        clock      : in  std_logic;
        reset      : in  std_logic;

        -- frame_sync is high between frames, so the view can updated 
        -- without tearing the frame.
        frame_sync : in  std_logic;

        -- KEY[3:0], active low: left, right, up, down.
        keys_n     : in  std_logic_vector(4 downto 0);

        -- Top left corner of the view, and the distance from one pixel to
        -- the next.  mandel_engine_bank walks the screen with these.
        x0         : out std_logic_vector(COORD_WIDTH - 1 downto 0);
        y0         : out std_logic_vector(COORD_WIDTH - 1 downto 0);
        pixel_step : out std_logic_vector(COORD_WIDTH - 1 downto 0)
    );
end entity viewport;


architecture rtl of viewport is

    -- The denominator of the zoom, as a bit position: 2047 -> 2048 -> 11.
    constant ZOOM_BITS : natural := log2(ZOOM_NUM + 1);

    -- Zooming out is the same multiply with the numerator on the other
    -- side of 1: 2047/2048 closes in, 2049/2048 opens out, by the same
    -- proportion each frame.  Derived, so there is still one zoom knob.
    constant ZOOM_OUT_NUM : natural := 2 * (2 ** ZOOM_BITS) - ZOOM_NUM;

    -- Half a screen, in pixels.
    constant HALF_W : natural := IMG_W / 2;
    constant HALF_H : natural := IMG_H / 2;

    -- One pixel is VIEW_WIDTH units of the plane across IMG_W of them.
    --
    -- 4 is the tightest that shows the whole set, and it is right whenever
    -- the view starts centered on the set.  A start point well off the axis
    -- needs more -- a center 0.82 below it, say, would push the top of the
    -- set off a 4 unit frame and want 6.
    constant PIXEL_STEP_INIT : std_logic_vector(COORD_WIDTH - 1 downto 0) :=
        to_coord(VIEW_WIDTH, IMG_W);

    -- WHERE THE ZOOM ENDS UP, AND WHY THE KEYS EXIST
    --
    -- The zoom holds the middle of the screen fixed.  So the point the view
    -- starts centered on is the point it spends the next five minutes closing
    -- in on -- unless somebody moves it.  That is the whole job of the
    -- direction keys, and it is worth being blunt about why they are not
    -- optional decoration.
    --
    -- The default start, -0.5 + 0i, is the view everybody recognizes and
    -- the worst possible destination.  It is deep inside the main cardioid,
    -- so it never escapes at any iteration count:
    --
    --                      black at  1x    4x   16x   64x
    --     -0.5 + 0i                 13%   86%  100%  100%
    --
    -- Left alone the board reaches 16x in about six minutes and then shows
    -- a black screen for the remaining eleven.  Nothing is broken when that
    -- happens -- that IS the middle of the set, which is solid.
    --
    -- The way out is to pan before it gets there.  Everything worth looking
    -- at is on the boundary, and the boundary is what the keys are for.
    -- Two destinations to steer toward, and what they cost:
    --
    --                                    black at 10x   100x   1000x
    --   seahorse   -0.743643887 +0.131825904i     81%    48%     15%
    --   tendril    +0.001643722 -0.822467633i     19%     0%      0%
    --
    -- Note the seahorse figures.  "On the boundary" is necessary but not
    -- sufficient: that road runs straight through the body of the period-2
    -- bulb and does not clear up until about 1000x.  The seahorses in that
    -- valley ARE the black shapes -- black is the set, not a failure to
    -- render it.  The tendril stays colored the whole way down, which is
    -- why the testbench, which cannot press any keys, aims somewhere on the
    -- boundary rather than here.
    --
    -- The generics, put on the coordinate grid.  Nothing is decided here --
    -- the numbers come from whoever instantiated this entity.
    -- The denominator both center generics are quoted over, so that a point
    -- on the plane arrives as ONE number per axis instead of a pair.
    --
    --     -743643887 / 1000000000  =  -0.743643887
    --
    -- Fixed rather than passed in, because there is no reason for two
    -- points in the same design to be on different scales, and a
    -- mismatched denominator is a silent error -- the picture would simply
    -- land somewhere else with nothing to flag it.
    --
    -- 1e9 is as far as this can go: the numerators are VHDL integers, and
    -- those are only guaranteed to +/- (2**31 - 1), just over 2.1e9.  Nine
    -- decimal places is far finer than the first frame can resolve anyway
    -- -- depth comes from SCALE_BITS, not from here.
    constant CENTER_DEN : natural := 1000000000;

    constant CENTER_X_INIT : std_logic_vector(COORD_WIDTH - 1 downto 0) :=
        to_coord(CENTER_X_NUM, CENTER_DEN);
    constant CENTER_Y_INIT : std_logic_vector(COORD_WIDTH - 1 downto 0) :=
        to_coord(CENTER_Y_NUM, CENTER_DEN);

    -- Corner = center, less half a screen.  Vector arithmetic throughout:
    -- HALF_W is a plain pixel count, and scaling a coordinate by a whole
    -- number of pixels leaves it on the same grid, so there is no slice.
    constant X0_INIT : std_logic_vector(COORD_WIDTH - 1 downto 0) :=
        std_logic_vector(signed(CENTER_X_INIT) - resize(signed(PIXEL_STEP_INIT) * HALF_W, COORD_WIDTH));
    constant Y0_INIT : std_logic_vector(COORD_WIDTH - 1 downto 0) :=
        std_logic_vector(signed(CENTER_Y_INIT) - resize(signed(PIXEL_STEP_INIT) * HALF_H, COORD_WIDTH));

    -- How far in the zoom is allowed to go.
    --
    -- Not a free choice: it falls out of the zoom rate.  pixel_step is a
    -- whole number, so
    --
    --     floor(s * (2**B - 1) / 2**B)  =  s - ceil(s / 2**B)
    --
    -- and once s drops below 2**B that is a decrement of exactly 1 every
    -- frame -- the zoom stops being proportional and visibly stalls.
    -- Opening out stalls in the same way, and for the same reason.
    --
    -- So 2**ZOOM_BITS is BOTH the deepest smooth zoom and the point below
    -- which either direction would seize up.  Stopping exactly there is
    -- the right answer to two questions at once, and it means neither
    -- direction needs a special case: at s = STEP_MIN both move by 1,
    -- which is precisely the intended rate.
    --
    -- It also fixes how long a run lasts, because rate and depth are two
    -- ends of the same stick:
    --
    --     depth    = STEP_INIT / 2**ZOOM_BITS
    --     duration = ln(depth) * 2**ZOOM_BITS / 60 seconds
    --
    -- At ZOOM_BITS = 11 and the default 4 unit start that is 13,107x over
    -- about 5 minutes in and 6 back out.  Note which way that goes: a
    -- SMALLER ZOOM_NUM is faster AND deeper, because the floor it stops
    -- at is 2**ZOOM_BITS.  A gentler rate raises the floor as fast as it
    -- slows the descent, so it buys duration at the cost of everything
    -- else.  mandelbrot_system tabulates the four rates worth trying.
    constant STEP_MIN : natural := 2 ** ZOOM_BITS;

    signal x0_r         : std_logic_vector(COORD_WIDTH - 1 downto 0);
    signal y0_r         : std_logic_vector(COORD_WIDTH - 1 downto 0);
    signal pixel_step_r : std_logic_vector(COORD_WIDTH - 1 downto 0);

    signal frame_sync_r : std_logic;

    -- The keys and switch are asynchronous to the clock.  Used raw, an edge
    -- landing on the update clock can capture some bits of x0_r or
    -- pixel_step_r from one decision and some from the other -- and since
    -- those registers accumulate, the view jumps somewhere random and stays
    -- there.  Two flip-flops first, and the logic only ever sees clean bits.
    signal keys_meta : std_logic_vector(4 downto 0);
    signal keys_sync : std_logic_vector(4 downto 0);

    -- Bits 0 to 3 are momentary keys, active LOW: pressed reads '0'.
    alias key_left  : std_logic is keys_sync(0);
    alias key_right : std_logic is keys_sync(1);
    alias key_up    : std_logic is keys_sync(2);
    alias key_down  : std_logic is keys_sync(3);

    -- Bit 4 is not a key.  It is a SWITCH, and it is active HIGH: leave it
    -- at 0 and the view closes in, flip it to 1 and the view opens back out.
    alias zoom_out  : std_logic is keys_sync(4);

begin

    x0         <= x0_r;
    y0         <= y0_r;
    pixel_step <= pixel_step_r;

    key_sync_process : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            keys_meta <= "01111";   -- no keys pressed, zoom in
            keys_sync <= "01111";
        elsif rising_edge(clock) then
            keys_meta <= keys_n;
            keys_sync <= keys_meta;
        end if;
    end process key_sync_process;

    ----------------------------------------------------------------------
    -- One update per frame, on the leading edge of the blanking gap.
    --
    -- Everything here is std_logic_vector, signals and variables alike.
    -- signed() appears in each expression that needs it: the wires do not
    -- carry a sign, the operator does.
    ----------------------------------------------------------------------
    frame_process : process (clock, reset) is
        -- The multiply below needs somewhere twice as wide to land in.
        variable wide      : std_logic_vector(2 * COORD_WIDTH - 1 downto 0);

        variable new_step  : std_logic_vector(COORD_WIDTH - 1 downto 0);
        variable step_diff  : std_logic_vector(COORD_WIDTH - 1 downto 0);
        variable pan : std_logic_vector(COORD_WIDTH - 1 downto 0);

        -- How far the corner moves this frame.  Everything below just adds
        -- to these two, and at the end they are added to the corner.
        variable move_x    : std_logic_vector(COORD_WIDTH - 1 downto 0);
        variable move_y    : std_logic_vector(COORD_WIDTH - 1 downto 0);
    begin
        if ( reset = '1' ) then
            x0_r         <= X0_INIT;
            y0_r         <= Y0_INIT;
            pixel_step_r <= PIXEL_STEP_INIT;
            frame_sync_r <= '0';

        elsif rising_edge(clock) then
            frame_sync_r <= frame_sync;

            -- update the view on the leading edge of the new frame
            if ( frame_sync = '1' and frame_sync_r = '0' ) then

                --------------------------------------------------------
                -- STEP 1.  Move the zoom one notch, whichever way the
                -- switch says.
                --
                -- The screen always has 640 pixels across.  The only
                -- way to show a smaller piece of the plane on them is
                -- to make each pixel worth less of the plane.  So
                -- "zoom in" means pixel_step goes DOWN, to 2047/2048
                -- of what it was, and "zoom out" means it goes UP, to
                -- 2049/2048 -- the same proportion the other way.
                --
                -- There is no divide instruction to hand, so it is
                -- done the way everything else in this design is done:
                -- multiply, then keep the bits you want.  Multiplying
                -- by 2047 makes the number 2047 times too big; starting
                -- the slice 11 bits up divides it back down by 2048.
                -- Only the numerator differs between the two cases.
                --------------------------------------------------------
                if ( zoom_out = '1' ) then
                    wide := std_logic_vector(signed(pixel_step_r) * ZOOM_OUT_NUM);
                else
                    wide := std_logic_vector(signed(pixel_step_r) * ZOOM_NUM);
                end if;

                new_step := wide(ZOOM_BITS + COORD_WIDTH - 1 downto ZOOM_BITS);

                --------------------------------------------------------
                -- Stop at either end and stay there.  The switch is
                -- the way back from both -- nothing jumps or restarts.
                --------------------------------------------------------
                if ( signed(new_step) > signed(PIXEL_STEP_INIT) ) then
                    new_step := PIXEL_STEP_INIT;    -- as far out as we began
                elsif ( signed(new_step) < STEP_MIN ) then
                    new_step := std_logic_vector(to_signed(STEP_MIN, COORD_WIDTH));
                end if;                             -- as far in as it stays smooth

                --------------------------------------------------------
                -- STEP 2.  Slide the corner so the zoom is centered.
                --
                -- Changing pixel_step on its own is not enough, and it
                -- is worth seeing why.  The screen covers
                --
                --     from x0  to  x0 + 640 * pixel_step
                --
                -- If x0 stays put and pixel_step gets smaller, the
                -- right hand edge walks in but the LEFT edge does not
                -- move at all.  The picture would appear to rush into
                -- its top left corner rather than into its middle.
                --
                --     before   |x0=======================|
                --     after    |x0==================|
                --                                   ^ only this edge moved
                --
                -- Each pixel just gave up this much of the plane -- and
                -- when zooming OUT it gave up a negative amount, which
                -- is why the same two lines below serve both directions
                -- with nothing added.
                --------------------------------------------------------
                step_diff := std_logic_vector(signed(pixel_step_r) - signed(new_step));

                -- The whole screen is 640 of them wide, so the view as
                -- a whole lost  640 * step_diff.  Hand HALF of that loss
                -- to the left edge and half to the right, and the
                -- middle of the screen stays on the same point -- which
                -- is what "zooming in" is supposed to mean.
                --
                --     before   |x0=======================|
                --     after    ..|x0==================|..
                --                 ^ corner moves in by half the loss
                move_x := std_logic_vector(resize(signed(step_diff) * HALF_W, COORD_WIDTH));
                move_y := std_logic_vector(resize(signed(step_diff) * HALF_H, COORD_WIDTH));

                --------------------------------------------------------
                -- STEP 3.  Add whatever the keys ask for.
                --
                -- One press slides the view by PAN_PIXELS pixels, and
                -- "8 pixels" as a distance on the plane is simply
                -- 8 * pixel_step.
                --
                -- Measuring the pan in PIXELS rather than in a fixed
                -- distance is what makes the keys feel the same at
                -- every zoom level: eight pixels is eight pixels
                -- whether the screen is showing four units of the
                -- plane or a millionth of one.
                --------------------------------------------------------
                pan := std_logic_vector(resize(signed(pixel_step_r) * PAN_PIXELS, COORD_WIDTH));

                if ( key_left = '0' ) then
                    move_x := std_logic_vector(signed(move_x) - signed(pan));
                elsif ( key_right = '0' ) then
                    move_x := std_logic_vector(signed(move_x) + signed(pan));
                elsif ( key_up = '0' ) then
                    move_y := std_logic_vector(signed(move_y) - signed(pan));
                elsif ( key_down = '0' ) then
                    move_y := std_logic_vector(signed(move_y) + signed(pan));
                end if;

                --------------------------------------------------------
                -- STEP 4.  That is the whole frame's update.
                --------------------------------------------------------
                x0_r         <= std_logic_vector(signed(x0_r) + signed(move_x));
                y0_r         <= std_logic_vector(signed(y0_r) + signed(move_y));
                pixel_step_r <= new_step;

            end if;
        end if;
    end process frame_process;

end architecture rtl;
