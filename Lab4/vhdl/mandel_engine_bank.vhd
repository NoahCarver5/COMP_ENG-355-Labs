library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mandel_pkg.all;

--------------------------------------------------------------------------
-- The compute side of the lab: walk the raster, farm each point out to a
-- bank of Mandelbrot engines taking it in turns, and hand the finished
-- colors to the display.
--
-- WHY THERE HAS TO BE MORE THAN ONE ENGINE
--
-- The display is not negotiable: 640x480 at 60 Hz needs a pixel every
-- 40 ns, which at a 100 MHz system clock is PIX_DIV = 4 clocks.  One
-- engine needs MAX_ITER clocks per pixel -- 110 of them.  Nearly thirty
-- times too slow.
--
-- The iteration itself cannot be sped up, because each step needs the
-- result of the one before: z <- z*z + c is inherently sequential.  What
-- can be done is work on several pixels at once.
--
-- WHAT IT LOOKS LIKE
--
--       x0, y0, pixel_step   (from viewport, once a frame)
--                 |
--         +-------v--------+
--         |    the walk    |   one point per dispatch, in raster order:
--         |   cx += step   |   c0, c1, c2, c3, ...
--         +-------+--------+
--                 |
--                 |  every engine sees the SAME point on cx_r/cy_r.
--                 |  only the one whose turn it is gets a start pulse.
--     +------+----+---+------+ . . . . . . +
--     |      |        |      |             |
--  +--v--+ +-v---+ +--v--+ +-v---+      +--v---+
--  |eng 0| |eng 1| |eng 2| |eng 3|  ... |eng 15|
--  +--+--+ +-+---+ +--+--+ +-+---+      +--+---+
--     |      |        |      |             |     each holds the color
--     +------+----+---+------+ . . . . . . +     of its own point
--                 |
--            +----v----+
--   slot --->|   mux   |----> pixel   (to hdmi)
--            +---------+
--
-- SLOT IS THE WHOLE SCHEDULE
--
-- One counter.  It picks the engine that is read AND the engine that is
-- restarted -- they are the same engine, on the same clock:
--
--   dispatch #     0     1     2    ...    15     16     17   ...
--   slot           0     1     2    ...    15      0      1   ...
--                  |                              |
--   engine 0    started                    read, then started again
--                  |<------ 16 pixel periods ---->|
--                            to do 120 iterations
--
-- Reading happens before the restart takes effect, because hdmi samples
-- the pixel output on the same clock edge that the engine is given its
-- next point.
--
-- TAKING IT IN TURNS
--
-- Engine k does every N_ENGINES-th pixel.  Each one therefore gets
-- N_ENGINES pixel periods to do its work, which is the entire reason
-- there are N_ENGINES of them:
--
--     MAX_ITER + 2  <=  N_ENGINES * PIX_DIV
--
-- (MAX_ITER iterations, one clock to start, one more for the engine's
-- output register.)  On the board that is 112 <= 28 * 4 = 112.  The
-- assert below enforces it, because getting it wrong produces a picture
-- that is subtly wrong rather than obviously broken -- a color read out
-- of an engine that has not finished yet.
--
-- Note the clock is on the right hand side too, through PIX_DIV.  Raising
-- the system clock buys iterations just as surely as adding engines does.
-- Engines cost multipliers; clock speed is free until timing stops
-- closing.
--
-- THE HEAD START
--
-- The first pixel of a frame cannot be computed after it is asked for --
-- there would be no time.  So the first N_ENGINES points are handed out
-- BEFORE the frame begins, in the blanking gap, when hdmi is asking for
-- nothing and the display cannot see anything.
--
-- The walk already counts columns, so "have the first N_ENGINES points 
-- gone out yet?" is just
--
--     col < N_ENGINES
--
-- and the gap is 288,000 clocks long, so there is no hurry whatsoever.
--
-- START AND READY
--
-- An engine is never handed a point it cannot take: dispatch is gated on
-- that engine's ready line.  During the frame ready is always high when
-- its turn comes -- that is exactly what the constraint above guarantees --
-- so the handshake never actually holds anything up.  During the head
-- start it does the useful work of waiting for each engine to finish
-- whatever the last frame left it doing.
--
-- WHY THE RESULTS COME BACK IN ORDER
--
-- Because there is only one counter.  The same slot that is read is the
-- one restarted, so pixel n always comes out of the engine pixel n was
-- given to.  No reordering, no tags, no queue.
--------------------------------------------------------------------------
entity mandel_engine_bank is
    generic (
        IMG_W      : natural := 640;
        N_ENGINES  : natural := 16;
        MAX_ITER   : natural := 120
    );
    port (
        clock      : in  std_logic;
        reset      : in  std_logic; 

        -- frame_sync between frames
        frame_sync : in  std_logic;

        -- pixel_req from the display
        pixel_req  : in  std_logic;

        -- Top left corner and pixel pitch, from the viewport.
        x0         : in  std_logic_vector(COORD_WIDTH - 1 downto 0);
        y0         : in  std_logic_vector(COORD_WIDTH - 1 downto 0);
        pixel_step : in  std_logic_vector(COORD_WIDTH - 1 downto 0);

        -- Color of the pixel being requested right now
        pixel      : out std_logic_vector(23 downto 0)
    );
end entity mandel_engine_bank;


architecture rtl of mandel_engine_bank is

    ----------------------------------------------------------------------
    -- Components
    -- TODO: Declare the mandel_engine component.
    ----------------------------------------------------------------------


    ------------------------------------------------------------------------
    -- Signals
    ------------------------------------------------------------------------
    signal cx_r : std_logic_vector(COORD_WIDTH - 1 downto 0);
    signal cy_r : std_logic_vector(COORD_WIDTH - 1 downto 0);
    signal col  : natural range 0 to IMG_W - 1;

    type pixel_array_t is array (0 to N_ENGINES - 1) of std_logic_vector(23 downto 0);
    signal engine_pixel : pixel_array_t;
    signal engine_ready : std_logic_vector(N_ENGINES - 1 downto 0);
    signal engine_start : std_logic_vector(N_ENGINES - 1 downto 0);

    -- counter for which engine's turn it is.
    signal slot : natural range 0 to N_ENGINES - 1;

    -- register the frame_sync input so its leading edge can be detected.
    signal frame_sync_r : std_logic;

    -- High when a point is handed to an engine.
    signal dispatch : std_logic;

begin

    ----------------------------------------------------------------------
    -- The display reads the engine whose turn it is
    ----------------------------------------------------------------------
    pixel <= engine_pixel(slot);

    ----------------------------------------------------------------------
    -- There are exactly two occasions when a point is dispatched to an engine:
    -- 1.  The display is asking for a pixel, read the current engine: 
    --     a. when the engine is read (engine_ready(slot) = '1'), and
    --     b. the display is requesting a pixel (pixel_req = '1')
    -- 2.  In between frames, get a head start on the first N_ENGINES points:
    --     a. when the engine is read (engine_ready(slot) = '1'), and
    --     c. the frame_sync just started (frame_sync = '1'), and
    --     d. we haven't yet handed out the first N_ENGINES points (col < N_ENGINES)
    ----------------------------------------------------------------------
    dispatch_process : process (all) is
        variable dispatch_v : std_logic;
    begin
        dispatch_v := '0';

        -- wait for ready handshake from the engine whose turn it is
        if ( engine_ready(slot) = '1' ) then
            if ( pixel_req = '1' ) then -- display is asking for a pixel
                dispatch_v := '1';
            elsif ( frame_sync_r = '1' and col < N_ENGINES ) then -- new frame, head start
                dispatch_v := '1';
            end if;
        end if;

        dispatch <= dispatch_v;

        -- only the engine whose turn it is gets a start pulse.
        engine_start <= (others => '0');
        engine_start(slot) <= dispatch_v;

    end process dispatch_process;

    ----------------------------------------------------------------------
    -- Whose turn it is, and where on the plane the walk has got to.
    --
    -- Screen position to a point on the plane, without a multiplier: cx
    -- starts at x0 and gains one pixel_step per dispatch, cy starts at y0
    -- and gains one per line.  Two adders, and no slicing -- both sides
    -- are already on the same grid.  
    ----------------------------------------------------------------------
    control_process : process (clock, reset) is
    begin
        if ( reset = '1' ) then
            cx_r         <= (others => '0');
            cy_r         <= (others => '0');
            col          <= 0;
            slot         <= 0;
            frame_sync_r <= '0';

        elsif rising_edge(clock) then
            frame_sync_r <= frame_sync;

            -- Check if the engines are not keeping up with the display. 
            assert not ( pixel_req = '1' and engine_ready(slot) = '0' )
                report "mandel_engine_bank: engine " & integer'image(slot) &
                       " was still working when the display asked for it -- " &
                       "MAX_ITER + 2 <= N_ENGINES * PIX_DIV is violated"
                severity failure;

            -- A new frame starts when frame_sync goes from 0 -> 1
            if ( frame_sync = '1' and frame_sync_r = '0' ) then
                -- go back to the top left corner. 
                cx_r <= x0;
                cy_r <= y0;
                col  <= 0;
                slot <= 0;

            -- a pixel is being requested
            elsif ( dispatch = '1' ) then

                -- Next engine's turn (mod is only efficient when N_ENGINES is a power of 2)
                slot <= (slot + 1) mod N_ENGINES;

                -- Move one pixel further along the raster.
                if ( col = IMG_W - 1 ) then
                    col  <= 0;
                    cx_r <= x0;
                    cy_r <= std_logic_vector(signed(cy_r) + signed(pixel_step));
                else
                    col  <= col + 1;
                    cx_r <= std_logic_vector(signed(cx_r) + signed(pixel_step));
                end if;
            end if;

        end if;
    end process control_process;

    ----------------------------------------------------------------------
    -- TODO: Implement the mandel_engine_bank process using a for-generate loop.  
    -- It should instantiate N_ENGINES instances of mandel_engine, and map each 
    -- signal to an array element.  
    --
    -- Note that you must use the registered values cx_r and cy_r to the engines, 
    -- because they must be consistent across all engines for the entire iteration. 
    ----------------------------------------------------------------------
  

end architecture rtl;
