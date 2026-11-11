library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;

--------------------------------------------------------------------------
-- Last stage of the renderer.
--
--   longitude / latitude  ->  panorama address  ->  SDRAM  ->  frame buffer
--
-- Takes a direction on the sphere, works out which pixel of the panorama
-- it lands on, fetches it, and writes it into the frame buffer at the
-- display position the ray came from.
--
-- Two states, because the only thing worth waiting for is SDRAM.  There
-- is no downstream handshake: the sink is a block RAM, and a RAM is never
-- busy.  Every accepted ray produces exactly one write.
--------------------------------------------------------------------------
entity image_reader is
    generic (
        ANGLE_WIDTH  : natural := 16;
        PIXEL_WIDTH  : natural := 24;
        ADDR_WIDTH   : natural := 10;

        -- Source panorama being sampled.  The width must be a power of two,
        -- because the row stride is a shift rather than a multiply.
        IMAGE_WIDTH  : natural := 1024;
        IMAGE_HEIGHT : natural := 512;

        -- Coordinate widths of the output display.  row/col take no
        -- part in the panorama addressing -- they are carried through to
        -- become the frame buffer write address.
        COL_WIDTH    : natural := 10;
        ROW_WIDTH    : natural := 9;

        -- Output frame width, and the width of an address into it.
        OUT_WIDTH      : natural := 640;
        FB_ADDR_WIDTH  : natural := 19
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        -- ---- from vector_to_angles ----
        longitude : in  std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        latitude  : in  std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        row       : in  std_logic_vector(ROW_WIDTH - 1 downto 0);
        col       : in  std_logic_vector(COL_WIDTH - 1 downto 0);
        valid_in  : in  std_logic;
        ready_in  : out std_logic;

        -- ---- panorama, in SDRAM ----
        -- THE REQUEST IS EXPLICIT NOW.  The old controller free-ran,
        -- continuously reading whatever rd_addr happened to be and
        -- pulsing rd_valid -- so if an access was already in flight for
        -- the PREVIOUS address, the next rd_valid belonged to that one
        -- and this module stored the wrong pixel.  A request the
        -- controller latches on its rising edge cannot be confused with
        -- an access already underway.
        rd_req    : out std_logic;
        rd_addr   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
        rd_data   : in  std_logic_vector(PIXEL_WIDTH - 1 downto 0);
        rd_valid  : in  std_logic;

        -- ---- frame buffer write port ----
        --
        -- addr = row*OUT_WIDTH + col.  All three are driven together in
        -- the cycle SDRAM returns the pixel, so the RAM latches a
        -- matched set on that edge.
        wr_addr   : out std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
        wr_data   : out std_logic_vector(PIXEL_WIDTH - 1 downto 0);
        wr_en     : out std_logic
    );
end entity image_reader;


architecture rtl of image_reader is

    --------------------------------------------------------------------------
    -- Constant Declarations
    --------------------------------------------------------------------------
    constant IMAGE_COL_WIDTH : natural := log2(IMAGE_WIDTH);
    constant IMAGE_ROW_WIDTH : natural := log2(IMAGE_HEIGHT);
    constant LATITUDE_CENTER : integer := 2 ** (ANGLE_WIDTH - 2);
    constant HALF_TURN : unsigned(ANGLE_WIDTH - 1 downto 0) := to_unsigned(2 ** (ANGLE_WIDTH - 1), ANGLE_WIDTH);

    ----------------------------------------------------------
    -- Signal Declarations
    ----------------------------------------------------------

begin


    ----------------------------------------------------------------------
    --
    -- TODO: Implement a clocked process that resets and registers the 
    -- FSM signals across cycles. 
    --
    ----------------------------------------------------------------------


    ----------------------------------------------------------------------
    --
    -- TODO: Implement a combinational FSM process that converts the 
    -- longitude/latitude to a panorama address, fetches the pixel from 
    -- SDRAM, and writes it to the frame buffer.
    --
    -- Requirements:
    -- 1. Assert ready_in.
    -- 2. When valid_in = '1', convert longitude/latitude to pixel (x, y):
    --
    --    * x: add HALF_TURN to longitude so 0 degrees lands at the image
    --      center, then keep the top IMAGE_COL_WIDTH bits (shift right by
    --      ANGLE_WIDTH - IMAGE_COL_WIDTH).  Clamp to IMAGE_WIDTH - 1.
    --
    --      x <= resize(umin(shift_right((unsigned(longitude) + HALF_TURN), 
    --                  ANGLE_WIDTH - IMAGE_COL_WIDTH), 
    --                  to_unsigned(IMAGE_WIDTH - 1, ANGLE_WIDTH)), ANGLE_WIDTH);

    --    * y: +90 degrees is the top row, 0 the center, -90 the bottom.
    --      Compute LATITUDE_CENTER - latitude (as a signed integer, to
    --      avoid 16-bit overflow), clamp it to [0, 2**(ANGLE_WIDTH-1)],
    --      divide by 2**(ANGLE_WIDTH - IMAGE_ROW_WIDTH - 1), and clamp
    --      the result to IMAGE_HEIGHT - 1.
    --
    --      lat_centered := LATITUDE_CENTER - to_integer(signed(latitude));
    --      lat_centered := umin(lat_centered_i, 2 ** (ANGLE_WIDTH - 1));
    --      lat_centered := umax(lat_centered_i, 0);
    --      y <= resize(lat_centered / (2 ** (ANGLE_WIDTH - IMAGE_ROW_WIDTH - 1)), ANGLE_WIDTH), 
    --                  to_unsigned(IMAGE_HEIGHT - 1, ANGLE_WIDTH)), ANGLE_WIDTH);
    --
    -- 3. addr_c = y * IMAGE_WIDTH + x.  IMAGE_WIDTH is a power of two, so
    --    the multiply is a shift left by IMAGE_COL_WIDTH.
    -- 4. Fetch the pixel from SDRAM by asserting rd_req and setting rd_addr, 
    --    then wait for rd_valid = '1'. 
    -- 5. Write the pixel to the frame buffer
    --
    ----------------------------------------------------------------------
    rd_addr  <= (others => '0');
    rd_req   <= '0';
    ready_in <= '0';
    wr_addr  <= (others => '0');
    wr_data  <= (others => '0');
    wr_en    <= '0';



end architecture rtl;
