library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Lab 5 -- Image Processor.  Structural only.
--
--                +-------------+          +------+
--   cam_clk ---->|             |--wr_en-->|      |
--   cam_vs ----->| video_store |-wr_addr->|      |
--   cam_de ----->|    WRITE    |-wr_data->|      |
--   cam_pixel -->|             |  20bits  |      |
--    24bits      +-------------+          | bram |
--                                         |      |
--                +-------------+          |      |
--   pixel_req -->|             |-rd_addr->|      |
--   frame_sync ->|   filters   |<-rd_data-|      |
--   keys_n ----->|     READ    |  20bits  |      |
--                |             |          +------+
--                +-------------+
--                   |      |
--                 pixel   hex
--
-- The two sides never talk to each other. The video_store only writes: it
-- takes whatever the camera sends and writes it in the buffer in RGB686 (20 bits)
-- format.  The filters only reads: it asks for whatever the display wants 
-- and pipes it out. The BRAM buffer has read and write paths, and is the 
-- only thing between them, which is exactly why they can run at unrelated rates.
-- 
-- The display side is not a clock domain at all: hdmi divides the system
-- clock down to the pixel rate and hands over pixel_req, so filters simply
-- runs at pixel rate on the system clock.
--
-- The camera side genuinely is a second domain -- its clock comes from
-- the MIPI bridge, not our PLL -- so video_store samples cam_clk as an
-- ordinary signal and makes one tick per pixel.  That is the only clock
-- domain crossing in the whole design.
--------------------------------------------------------------------------
entity image_processor is
    generic (
        IMG_W           : natural := 640;
        IMG_H           : natural := 480;
        ADDR_W          : natural := 19;
        N_FILTERS       : natural := 8;
        DEBOUNCE_TICKS  : natural := 2**20
    );
    port (
        -- ---- system ----
        clock       : in  std_logic;
        reset       : in  std_logic;                       -- active high

        -- ---- camera side (write), 25 MHz ----
        cam_clk     : in  std_logic;                       -- sampled, not a clock
        cam_vs      : in  std_logic;                       -- frame valid
        cam_de      : in  std_logic;                       -- pixel valid
        cam_pixel   : in  std_logic_vector(23 downto 0);   -- RGB888

        -- ---- control ----
        keys_n      : in  std_logic_vector(1 downto 0);    -- ACTIVE LOW: 0 next, 1 prev
        
        -- ---- HEX digital display ----
        hex0        : out std_logic_vector(6 downto 0);    -- filter number,
        hex1        : out std_logic_vector(6 downto 0);    -- two digits

        -- ---- display side (read), same clock, pixel rate enable ----
        pixel_req   : in  std_logic;                        -- next active pixel
        frame_sync  : in  std_logic;                        -- holds address at 0

        pixel       : out std_logic_vector(23 downto 0);    -- RGB888
        pixel_valid : out std_logic                         -- pixel is this one
    );
end entity image_processor;


architecture structural of image_processor is

    --------------------------------------------------------------------
    -- Constant Declarations
    --------------------------------------------------------------------
    constant BRAM_BUFFER_SIZE   : integer := IMG_W * IMG_H;
    constant BRAM_ADDR_WIDTH    : integer := ADDR_W;
    constant BRAM_DATA_WIDTH    : integer := 20;  -- RGB686

    --------------------------------------------------------------------
    -- Component Declarations
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    -- Signal Declarations
    --------------------------------------------------------------------

begin

    --------------------------------------------------------------------
    -- TODO: Instantiate and wire together the components: 
    -- video_store, bram, filters, and digital display components.
    --------------------------------------------------------------------

end architecture structural;
