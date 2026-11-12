library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Frame reader -- the block RAM's display side.
--
--   bram => frame_reader => hdmi
--
-- hdmi asks for one pixel per active clock and expects an answer every
-- time.  This module turns those requests into read addresses and hands
-- the words back.
--
-- WHY THERE IS A BUFFER AT ALL
--
-- hdmi runs a real 640x480 @ 60 Hz raster, so it needs a pixel every
-- 40 ns, forever, with no exceptions.  The renderer upstream cannot do
-- that: every pixel walks through rot_matrix, ray_gen, mat_vec_mult,
-- vector_to_angles and image_reader, each a multi-state machine, and the
-- last of those waits on SDRAM.  Fifteen or more clocks per pixel, and
-- not a constant number.
--
-- The RAM decouples them.  image_reader writes whenever it has something,
-- this module reads whenever the display needs something, and neither
-- ever waits for the other.
--
-- The visible consequence is tearing: catch the renderer mid-frame and
-- the screen shows part of the old one and part of the new.  That is what
-- one buffer buys you.  Two would fix it and cost twice the memory.
--
-- ADDRESSING
--
-- hdmi asks in raster order from the top left, so the address is simply a
-- count of how many pixels it has asked for this frame.  No multiply:
-- row*640 + col is the same number arrived at the hard way.  frame_sync holds
-- the count at zero between frames, which is what keeps this counter and
-- hdmi's own raster counter from drifting apart.
--
-- TIMING
--
-- pixel_valid follows pixel_req by ONE clock.  The counter here and the RAM's
-- own address register are not in series: the RAM latches the value the
-- counter held BEFORE pixel_req advanced it, on that same edge.  So the
-- word is out one clock later, which is comfortably inside the pixel
-- period hdmi allows even at the lowest PIX_DIV.
--------------------------------------------------------------------------
entity frame_reader is
    generic (
        IMG_W       : natural := 640;
        IMG_H       : natural := 480;
        PIXEL_WIDTH : natural := 24;
        ADDR_WIDTH  : natural := 19     -- 640*480 = 307_200 fits in 19 bits
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        -- ---- block ram read port ----
        rd_addr   : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
        rd_data   : in  std_logic_vector(PIXEL_WIDTH - 1 downto 0);

        -- ---- hdmi ----
        frame_sync    : in  std_logic;                  -- holds the address at 0
        pixel_req   : in  std_logic;                  -- next active pixel
        pixel     : out std_logic_vector(PIXEL_WIDTH - 1 downto 0);
        pixel_valid : out std_logic
    );
end entity frame_reader;


architecture rtl of frame_reader is

    ----------------------------------------------------------
    -- Constant Declarations
    ----------------------------------------------------------
    constant N_PIXELS : natural := IMG_W * IMG_H;
    
    ----------------------------------------------------------
    -- Signal Declarations
    ----------------------------------------------------------

    signal rd_addr_comb : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal rd_addr_reg : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal pixel_req_reg : std_logic;
    signal pixel_valid_reg : std_logic;


begin

    ----------------------------------------------------------------------
    --
    -- TODO: Implement a clocked process that generates the read address 
    -- for the block RAM and the pixel_valid signal that goes with the 
    -- pixel it fetches. Here are the requirements:
    -- 1. The rd_addr signal should be reset to zero when either frame_sync 
    --    is asserted or when rd_addr reaches N_PIXELS (the maximum value).
    -- 2. The rd_addr signal should be incremented on each pixel_req. 
    -- 3. The pixel_valid signal should be asserted one clock cycle after 
    --    pixel_req, which is when the pixel (rd_data) is returned and valid. 
    -- 
    ----------------------------------------------------------------------

    frame_reader_clocked : process (reset, clk) is
    begin
        if (reset = '1') then
            rd_addr_reg <= (others => '0');
            pixel_req_reg <= '0';
            pixel_valid_reg <= '0';
        
        elsif (rising_edge(clk)) then

            rd_addr_reg <= rd_addr_comb;
            pixel_req_reg <= pixel_req;
            pixel_valid_reg <= not pixel_req_reg;
        end if;

    end process;


    frame_reader_fsm: process(rd_data, frame_sync) is
    begin
        rd_addr_comb <= std_logic_vector(unsigned(rd_addr) + 1);
        if (frame_sync = '1') then 
            rd_addr_comb <= (others => '0');
        elsif (unsigned(rd_addr_reg) = N_PIXELS-1) then 
            rd_addr_comb <= (others => '0');
        end if;
    end process;

end architecture rtl;
