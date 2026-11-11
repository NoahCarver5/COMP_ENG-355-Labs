library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.trig_pkg.all;

--------------------------------------------------------------------------
-- VR360 renderer.  Structural only -- every line below is a component
-- instance or a wire between two of them.
--
-- One orientation in, one rendered frame out:
--
--      rx, ry, rz
--          |
--  +-------v----------+
--  |    rot_matrix    |---------------+
--  +-------+----------+               |
--          |                          | rotation matrix
--  +-------v----------+               |
--  |     ray_gen      |               |
--  +-------+----------+               |
--          | camera ray, row/col      |
--  +-------v----------+               |
--  |   mat_vec_mult   |<--------------+
--  +-------+----------+
--          | world ray, row/col
--  +-------v----------+
--  | vector_to_angles |
--  +-------+----------+
--          | longitude/latitude, row/col
--  +-------v----------+               +------------+
--  |   image_reader   |<------------->| sdram_ctrl |<--> SDRAM
--  +-------+----------+               +------^-----+
--          | pixel, frame buffer addr        |
--  +-------v----------+               image from host
--  |       bram       |
--  +-------+----------+
--          |
--  +-------v----------+
--  |   frame_reader   |<--- pixel_req / frame_sync from hdmi
--  +-------+----------+
--          |
--          +---> pixel to hdmi
--
-- The buffer splits the design in two.  Above it everything runs at
-- its own pace, several clocks per pixel and waiting on SDRAM.  Below
-- it hdmi runs a 640x480 @ 60 Hz raster and wants a pixel every 40 ns.
-- Neither side ever waits for the other.
--------------------------------------------------------------------------
entity vr360 is
    generic (
        FOCAL_LENGTH : natural := 320;
        ANGLE_WIDTH : natural := 16;
        IMAGE_WIDTH : natural := 1024;
        IMAGE_HEIGHT : natural := 512;
        OUT_WIDTH : natural := 1024;
        OUT_HEIGHT : natural := 512;
        PIXEL_WIDTH : natural := 24;
        ADDR_WIDTH : natural := log2(IMAGE_WIDTH * IMAGE_HEIGHT);
        TRIG_WIDTH : natural := 16
    );
    port (
        clk : in std_logic;
        reset : in std_logic;

        -- IMU rotation.
        rx : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        ry : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        rz : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        rot_valid : in std_logic;

        -- ---- IMU bring-up, LEDs only ----
        --
        -- Neither of these affects the picture.  They exist so a board
        -- that is showing nothing can say WHERE the chain broke:
        -- imu_rx is the raw serial line, byte_stb is one clock per byte
        -- the receiver framed.  Without them a silent IMU and an
        -- unplugged one look identical, which is exactly the position
        -- this design was in.
        imu_rx : in std_logic;
        byte_stb : in std_logic;

        -- Image memory.
        -- ---- the image, arriving from the host ----
        --
        -- The writer that drives these lives at the system level,
        -- because it wraps a JTAG primitive with no simulation model.
        -- Passing its signals through means everything in here stays
        -- testable while still owning the memory.
        wr_req : in std_logic;
        wr_addr : in std_logic_vector(ADDR_WIDTH - 1 downto 0);
        wr_data : in std_logic_vector(PIXEL_WIDTH - 1 downto 0);
        wr_ack : out std_logic;

        -- ---- SDRAM ----
        dram_dq : inout std_logic_vector(15 downto 0);
        dram_addr : out std_logic_vector(12 downto 0);
        dram_ba : out std_logic_vector(1 downto 0);
        dram_ldqm : out std_logic;
        dram_udqm : out std_logic;
        dram_ras_n : out std_logic;
        dram_cas_n : out std_logic;
        dram_cke : out std_logic;
        dram_clk : out std_logic;
        dram_we_n : out std_logic;
        dram_cs_n : out std_logic;

        -- ---- what the board shows about what is going on ----
        hex0 : out std_logic_vector(6 downto 0);
        hex1 : out std_logic_vector(6 downto 0);
        hex2 : out std_logic_vector(6 downto 0);
        hex3 : out std_logic_vector(6 downto 0);
        hex4 : out std_logic_vector(6 downto 0);
        hex5 : out std_logic_vector(6 downto 0);
        leds : out std_logic_vector(4 downto 0);

        -- Display output.
        frame_sync  : in  std_logic;                               -- holds address at 0
        pixel_req   : in  std_logic;                               -- next pixel
        pixel       : out std_logic_vector(PIXEL_WIDTH - 1 downto 0);
        pixel_valid : out std_logic                                -- pixel is this one
    );
end entity vr360;


architecture structural of vr360 is

    --------------------------------------------------------------------
    -- Components
    --------------------------------------------------------------------
    component rot_matrix is
        generic (
            ANGLE_WIDTH : natural := 16;
            TRIG_WIDTH : natural := 16
        );
        port (
            clk         : in std_logic;
            reset       : in std_logic;

            rx          : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            ry          : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rz          : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            valid_in    : in std_logic;
            ready_in   : out std_logic;

            r00         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r01         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r02         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r10         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r11         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r12         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r20         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r21         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            r22         : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            valid_out   : out std_logic;
            ready_out   : in std_logic
        );
    end component;


    component ray_gen is
        generic (
            FOCAL_LENGTH : natural := 320;
            TRIG_WIDTH : natural := 16;
            OUT_WIDTH : natural := 1024;
            OUT_HEIGHT : natural := 512;
            COL_WIDTH : natural := 10;
            ROW_WIDTH : natural := 9
        );
        port (
            clk         : in std_logic;
            reset       : in std_logic;
            valid_in    : in std_logic;
            ready_in   : out std_logic;

            o0          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            o1          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            o2          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            row         : out std_logic_vector(ROW_WIDTH - 1 downto 0);
            col         : out std_logic_vector(COL_WIDTH - 1 downto 0);
            valid_out   : out std_logic;
            ready_out   : in std_logic
        );
    end component;


    component mat_vec_mult is
        generic (
            TRIG_WIDTH : natural := 16;
            ROW_WIDTH : natural := 10;
            COL_WIDTH : natural := 10
        );
        port (
            clk         : in std_logic;
            reset       : in std_logic;
            valid_in    : in std_logic;
            ready_in   : out std_logic;

            row_in      : in std_logic_vector(ROW_WIDTH - 1 downto 0);
            col_in      : in std_logic_vector(COL_WIDTH - 1 downto 0);
            row_out     : out std_logic_vector(ROW_WIDTH - 1 downto 0);
            col_out     : out std_logic_vector(COL_WIDTH - 1 downto 0);

            m00         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m01         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m02         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m10         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m11         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m12         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m20         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m21         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            m22         : in std_logic_vector(TRIG_WIDTH - 1 downto 0);

            v0          : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            v1          : in std_logic_vector(TRIG_WIDTH - 1 downto 0);
            v2          : in std_logic_vector(TRIG_WIDTH - 1 downto 0);

            o0          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            o1          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            o2          : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
            valid_out   : out std_logic;
            ready_out   : in std_logic
        );
    end component;


    component vector_to_angles is
        generic (
            TRIG_WIDTH : natural := 16;
            ANGLE_WIDTH : natural := 16;
            ROW_WIDTH : natural := 10;
            COL_WIDTH : natural := 10;
            OUT_WIDTH : natural := 1024;
            OUT_HEIGHT : natural := 512;
            FOCAL_LENGTH : natural := 320
        );
        port (
	        clk       : in  std_logic;
	        reset     : in  std_logic;
	
	        x         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
	        y         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
	        z         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
	        valid_in  : in  std_logic;
	        ready_in  : out std_logic;
	
	        row_in    : in  std_logic_vector(ROW_WIDTH - 1 downto 0);
	        col_in    : in  std_logic_vector(COL_WIDTH - 1 downto 0);
	        row_out   : out std_logic_vector(ROW_WIDTH - 1 downto 0);
	        col_out   : out std_logic_vector(COL_WIDTH - 1 downto 0);
	
	        longitude : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
	        latitude  : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
	        valid_out : out std_logic;
	        ready_out : in  std_logic
        );
    end component;

    component bram is
        generic (
            constant BRAM_BUFFER_SIZE : integer := 1024;
            constant BRAM_ADDR_WIDTH  : integer := 10;
            constant BRAM_DATA_WIDTH  : integer := 32
        );
        port (
            signal clock   : in  std_logic;
            signal rd_addr : in  std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0);
            signal wr_addr : in  std_logic_vector(BRAM_ADDR_WIDTH - 1 downto 0);
            signal wr_en   : in  std_logic;
            signal dout    : out std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0);
            signal din     : in  std_logic_vector(BRAM_DATA_WIDTH - 1 downto 0)
        );
    end component;

    component frame_reader is
        generic (
            IMG_W       : natural := 640;
            IMG_H       : natural := 480;
            PIXEL_WIDTH : natural := 24;
            ADDR_WIDTH  : natural := 19
        );
        port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            rd_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
            rd_data     : in  std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            frame_sync  : in  std_logic;
            pixel_req   : in  std_logic;
            pixel       : out std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            pixel_valid : out std_logic
        );
    end component;

    component sdram_ctrl is
        generic (
            ADDR_WIDTH      : natural := 23;
            CLK_FREQ_HZ     : natural := 50_000_000;
            INIT_WAIT_US    : natural := 200;
            READ_LATENCY    : natural := 3;
            DRAM_CLK_INVERT : boolean := true
        );
        port (
            clk        : in    std_logic;
            reset      : in    std_logic;
            wr_req     : in    std_logic;
            wr_addr    : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
            wr_data    : in    std_logic_vector(23 downto 0);
            wr_ack     : out   std_logic;
            rd_req     : in    std_logic;
            rd_addr    : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
            rd_data    : out   std_logic_vector(23 downto 0);
            rd_ack     : out   std_logic;
            ready      : out   std_logic;
            dram_dq    : inout std_logic_vector(15 downto 0);
            dram_addr  : out   std_logic_vector(12 downto 0);
            dram_ba    : out   std_logic_vector(1 downto 0);
            dram_ldqm  : out   std_logic;
            dram_udqm  : out   std_logic;
            dram_ras_n : out   std_logic;
            dram_cas_n : out   std_logic;
            dram_cke   : out   std_logic;
            dram_clk   : out   std_logic;
            dram_we_n  : out   std_logic;
            dram_cs_n  : out   std_logic
        );
    end component;

    component digit_display is
        port (
            clk  : in  std_logic;
            rst  : in  std_logic;
            din  : in  std_logic_vector(3 downto 0);
            dout : out std_logic_vector(6 downto 0)
        );
    end component;

    component image_reader is
        generic (
            ANGLE_WIDTH : natural := 16;
            PIXEL_WIDTH : natural := 24;
            ADDR_WIDTH : natural := 10;
            IMAGE_WIDTH  : natural := 1024;
            IMAGE_HEIGHT : natural := 512;
            COL_WIDTH    : natural := 10;
            ROW_WIDTH    : natural := 9;
            OUT_WIDTH    : natural := 640;
            FB_ADDR_WIDTH : natural := 19
        );
        port (
            clk         : in std_logic;
            reset       : in std_logic;

            longitude   : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            latitude    : in std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            row         : in std_logic_vector(ROW_WIDTH - 1 downto 0);
            col         : in std_logic_vector(COL_WIDTH - 1 downto 0);
            valid_in    : in std_logic;
            ready_in    : out std_logic;

            rd_req      : out std_logic;
            rd_addr     : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
            rd_data     : in std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            rd_valid    : in std_logic;

            wr_addr     : out std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
            wr_data     : out std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            wr_en       : out std_logic
        );
    end component;

    ---------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------
    constant OUT_COL_WIDTH   : natural := log2(OUT_WIDTH);
    constant OUT_ROW_WIDTH   : natural := log2(OUT_HEIGHT);


    --------------------------------------------------------------------
    -- Rotation matrix signals
    --------------------------------------------------------------------
    signal m00 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m01 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m02 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m10 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m11 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m12 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m20 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m21 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal m22 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal matrix_valid : std_logic;
    signal matrix_rdy : std_logic;


    --------------------------------------------------------------------
    -- Ray signals
    --------------------------------------------------------------------
    signal ray_v0 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal ray_v1 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal ray_v2 : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal ray_valid : std_logic;
    signal ray_rdy : std_logic;

    --------------------------------------------------------------------
    -- Rotated ray signals
    --------------------------------------------------------------------
    signal x_rot : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal y_rot : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal z_rot : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal vector_valid : std_logic;
    signal vector_rdy : std_logic;

    --------------------------------------------------------------------
    -- Angle signals
    --------------------------------------------------------------------
    signal longitude : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal latitude : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal angle_valid : std_logic;
    signal angle_rdy : std_logic;

    --------------------------------------------------------------------
    -- Row/col signals
    --------------------------------------------------------------------
    signal row_0, row_1, row_2 : std_logic_vector(OUT_ROW_WIDTH - 1 downto 0);
    signal col_0, col_1, col_2 : std_logic_vector(OUT_COL_WIDTH - 1 downto 0);

    --------------------------------------------------------------------
    -- Frame buffer
    --------------------------------------------------------------------
    constant N_PIXELS : natural := OUT_WIDTH * OUT_HEIGHT;
    constant FB_ADDR_WIDTH : natural := log2(N_PIXELS);

    -- THE FRAME BUFFER STORES 20 BITS PER PIXEL, NOT 24.
    --
    -- Everything else in this design carries RGB888: that is what the
    -- panorama is in SDRAM and what the HDMI transmitter wants back.  The
    -- narrower format exists only between the write port and the read port
    -- of the bram below, because the frame buffer is the one thing here
    -- big enough for its width to decide whether the design fits at all.
    --
    -- 640 x 480 is 307,200 pixels, and the device has 7.33 Mbit of
    -- embedded memory in 358 M20K blocks.  (Those are MEASURED, off a
    -- real fit report: "Total block memory bits 4,935,680 / 7,331,840".
    -- An earlier version of this comment said 8.42 Mbit in 411 blocks,
    -- which is where the 24 bpp arithmetic below used to come out
    -- merely tight rather than impossible.)
    --
    --   24 bpp  7.37 Mbit of data -- already more than the 7.33 the
    --           device HAS, before packing is even considered.  And
    --           M20K cannot be 24 bits wide, so packing makes it worse:
    --           the 4096 x 5 mode is five blocks abreast for 25 bits,
    --           75 deep = 375, and 1024 x 20 is two abreast = 600.
    --
    --           Quartus picks neither.  Asked to build it, the fitter
    --           chooses 2048 x 24 slices and reports
    --
    --             Error (170019): Project requires 450 M20K RAM blocks,
    --             but the selected device can contain only 358
    --
    --           That is a measurement, not an estimate: it came from
    --           synthesising a design containing nothing but this bram
    --           at 307,200 x 24 on this exact part.
    --
    --   20 bpp  6.14 Mbit in 1024 x 20 mode: one block wide, 300 deep,
    --           300 blocks, and not one bit wasted.  20 is exactly
    --           M20K's native width at that depth.
    --
    -- So 20 bits is not a compromise picked to save memory -- it is the
    -- number the memory is actually built out of, and 21 would cost a
    -- second block per word.  Note that RGB565 would cost the same 300
    -- blocks, since 16 and 20 both take one block abreast; the extra
    -- four bits of colour are free.
    --
    -- Green keeps all eight bits because the eye resolves it best; red and
    -- blue give up their bottom two.
    constant FB_PIXEL_WIDTH : natural := 20;

    -- RGB888 -> RGB686.  Drop the low 2 bits of red and blue.
    function to_rgb686(p : std_logic_vector(23 downto 0))
        return std_logic_vector is
    begin
        return p(23 downto 18) & p(15 downto 8) & p(7 downto 2);
    end function to_rgb686;

    -- RGB686 -> RGB888.  The two bits that come back are copies of the
    -- channel's own top two, not zeros: that keeps full-scale full scale,
    -- so 6 ones expand to 8 ones and white stays white rather than
    -- drifting to 0xFC.
    function from_rgb686(w : std_logic_vector(FB_PIXEL_WIDTH - 1 downto 0))
        return std_logic_vector is
        variable r6 : std_logic_vector(5 downto 0);
        variable g8 : std_logic_vector(7 downto 0);
        variable b6 : std_logic_vector(5 downto 0);
    begin
        r6 := w(19 downto 14);
        g8 := w(13 downto 6);
        b6 := w(5 downto 0);
        return (r6 & r6(5 downto 4)) & g8 & (b6 & b6(5 downto 4));
    end function from_rgb686;

    -- image_reader -> bram
    signal fb_wr_addr : std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
    signal fb_wr_data : std_logic_vector(PIXEL_WIDTH - 1 downto 0);
    signal fb_wr_en   : std_logic;

    -- bram <-> frame_reader
    signal fb_rd_addr : std_logic_vector(FB_ADDR_WIDTH - 1 downto 0);
    signal fb_rd_data : std_logic_vector(PIXEL_WIDTH - 1 downto 0);

    -- The same two pixels in stored form, either side of the bram.
    -- ---- the memory, now owned here ----
    signal rd_req_s  : std_logic;
    signal rd_addr_s : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    signal rd_data_s : std_logic_vector(PIXEL_WIDTH - 1 downto 0);
    signal rd_valid_s : std_logic;

    -- ---- activity, for the LEDs ----
    signal byte_beat  : std_logic;   -- toggles per byte received
    signal frame_beat : std_logic;   -- toggles per accepted angle frame
    signal valid_d    : std_logic;

    constant TICK_MAX : natural := 50_000_000 / 2 - 1;
    signal tick_count : natural range 0 to TICK_MAX;
    signal clk_alive  : std_logic;

    -- ---- the write indicator ----
    --
    -- STRETCHED, because wr_req is a handful of clocks per pixel and the
    -- gaps between blocks are milliseconds.  Wired straight to a pin it
    -- would be a 2 MHz flicker at a duty cycle low enough to look like a
    -- dim, steady glow -- indistinguishable from off across a room.  Any
    -- write within the last sixtieth of a second holds it on, so a
    -- transfer in progress is solid and it goes out shortly after the
    -- last pixel lands.
    constant WR_HOLD  : natural := 50_000_000 / 16;
    signal wr_timer   : natural range 0 to WR_HOLD;
    signal wr_active  : std_logic;

    signal fb_wr_word : std_logic_vector(FB_PIXEL_WIDTH - 1 downto 0);
    signal fb_rd_word : std_logic_vector(FB_PIXEL_WIDTH - 1 downto 0);

    signal rot_rdy : std_logic;

begin

    --------------------------------------------------------------------
    -- Stage 1: Calculate rotation matrix.
    --------------------------------------------------------------------
    u_rotation_matrix : rot_matrix
        generic map (
            ANGLE_WIDTH => ANGLE_WIDTH,
            TRIG_WIDTH => TRIG_WIDTH
        )
        port map (
            clk => clk,
            reset => reset,

            rx => rx,
            ry => ry,
            rz => rz,
            valid_in => rot_valid,
            ready_in => rot_rdy,

            r00 => m00,
            r01 => m01,
            r02 => m02,
            r10 => m10,
            r11 => m11,
            r12 => m12,
            r20 => m20,
            r21 => m21,
            r22 => m22,
            valid_out => matrix_valid,
            ready_out => matrix_rdy
        );


    --------------------------------------------------------------------
    -- Stage 2: Generate one camera-space ray per output pixel.
    --------------------------------------------------------------------
    u_ray_gen : ray_gen
        generic map (
            FOCAL_LENGTH => FOCAL_LENGTH,
            TRIG_WIDTH => TRIG_WIDTH,
            OUT_WIDTH => OUT_WIDTH,
            OUT_HEIGHT => OUT_HEIGHT,
            COL_WIDTH => OUT_COL_WIDTH,
            ROW_WIDTH => OUT_ROW_WIDTH
        )
        port map (
            clk => clk,
            reset => reset,
            valid_in => matrix_valid,
            ready_in => matrix_rdy,

            o0 => ray_v0,
            o1 => ray_v1,
            o2 => ray_v2,
            row => row_0,
            col => col_0,
            valid_out => ray_valid,
            ready_out => ray_rdy
        );


    --------------------------------------------------------------------
    -- Stage 3: Rotate camera-space ray into world space.
    --------------------------------------------------------------------
    u_mat_vec_mult : mat_vec_mult
        generic map (
            TRIG_WIDTH => TRIG_WIDTH,
            ROW_WIDTH => OUT_ROW_WIDTH,
            COL_WIDTH => OUT_COL_WIDTH
        )
        port map (
            clk => clk,
            reset => reset,
            valid_in => ray_valid,
            ready_in => ray_rdy,

            row_in => row_0,
            col_in => col_0,
            row_out => row_1,
            col_out => col_1,

            m00 => m00,
            m01 => m01,
            m02 => m02,
            m10 => m10,
            m11 => m11,
            m12 => m12,
            m20 => m20,
            m21 => m21,
            m22 => m22,

            v0 => ray_v0,
            v1 => ray_v1,
            v2 => ray_v2,

            o0 => x_rot,
            o1 => y_rot,
            o2 => z_rot,
            valid_out => vector_valid,
            ready_out => vector_rdy
        );


    --------------------------------------------------------------------
    -- Stage 4: Convert world-space ray to spherical coordinates.
    --------------------------------------------------------------------
    u_vector_to_angles : vector_to_angles
        generic map (
            TRIG_WIDTH => TRIG_WIDTH,
            ANGLE_WIDTH => ANGLE_WIDTH,
            ROW_WIDTH => OUT_ROW_WIDTH,
            COL_WIDTH => OUT_COL_WIDTH,
            OUT_WIDTH => OUT_WIDTH,
            OUT_HEIGHT => OUT_HEIGHT,
            FOCAL_LENGTH => FOCAL_LENGTH
        )
        port map (
            clk => clk,
            reset => reset,

            row_in => row_1,
            col_in => col_1,
            row_out => row_2,
            col_out => col_2,

            x => x_rot,
            y => y_rot,
            z => z_rot,
            valid_in => vector_valid,
            ready_in => vector_rdy,

            longitude => longitude,
            latitude => latitude,
            valid_out => angle_valid,
            ready_out => angle_rdy
        );


    --------------------------------------------------------------------
    -- Stage 5: Convert spherical coordinates to image address.
    --------------------------------------------------------------------
    u_image_reader : image_reader
        generic map (
            ANGLE_WIDTH => ANGLE_WIDTH,
            PIXEL_WIDTH => PIXEL_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            IMAGE_WIDTH => IMAGE_WIDTH,
            IMAGE_HEIGHT => IMAGE_HEIGHT,
            COL_WIDTH => OUT_COL_WIDTH,
            ROW_WIDTH => OUT_ROW_WIDTH,
            OUT_WIDTH => OUT_WIDTH,
            FB_ADDR_WIDTH => FB_ADDR_WIDTH
        )
        port map (
            clk => clk,
            reset => reset,

            row => row_2,
            col => col_2,
            longitude => longitude,
            latitude => latitude,
            valid_in => angle_valid,
            ready_in => angle_rdy,
            
            rd_req => rd_req_s,
            rd_addr => rd_addr_s,
            rd_data => rd_data_s,
            rd_valid => rd_valid_s,

            wr_addr => fb_wr_addr,
            wr_data => fb_wr_data,
            wr_en   => fb_wr_en
        );

    --------------------------------------------------------------------
    -- Stage 6: frame buffer.
    --
    -- One frame at 20 bits per pixel:  640 x 480 x 20 = 6.14 Mbit, which
    -- is 300 M20K blocks exactly.  See FB_PIXEL_WIDTH above for why 20
    -- and not 24.
    --
    -- Sized from OUT_WIDTH * OUT_HEIGHT, not 2**FB_ADDR_WIDTH.  The address
    -- is 19 bits and 2**19 words would ask for 10.5 Mbit.
    --
    -- The pack and unpack sit here rather than inside bram, image_reader or
    -- frame_reader, so that the stored format stays a private detail of
    -- this one stage: every port either side of it still speaks RGB888.
    --------------------------------------------------------------------
    -- to_rgb686 takes a 24-bit argument by name, so a PIXEL_WIDTH that is
    -- not 24 would otherwise fail as a bare width mismatch here.
    assert PIXEL_WIDTH = 24
        report "vr360: the frame buffer pack/unpack assume RGB888, so " &
               "PIXEL_WIDTH must be 24 (got " & natural'image(PIXEL_WIDTH) & ")"
        severity failure;

    fb_wr_word <= to_rgb686(fb_wr_data);
    fb_rd_data <= from_rgb686(fb_rd_word);

    u_frame_buffer : bram
        generic map (
            BRAM_BUFFER_SIZE => N_PIXELS,
            BRAM_ADDR_WIDTH  => FB_ADDR_WIDTH,
            BRAM_DATA_WIDTH  => FB_PIXEL_WIDTH
        )
        port map (
            clock   => clk,
            wr_addr => fb_wr_addr,
            wr_en   => fb_wr_en,
            din     => fb_wr_word,
            rd_addr => fb_rd_addr,
            dout    => fb_rd_word
        );

    --------------------------------------------------------------------
    -- Stage 7: frame reader.
    --
    -- Turns hdmi's pixel_req into read addresses and hands the pixels back.
    --------------------------------------------------------------------
    u_frame_reader : frame_reader
        generic map (
            IMG_W       => OUT_WIDTH,
            IMG_H       => OUT_HEIGHT,
            PIXEL_WIDTH => PIXEL_WIDTH,
            ADDR_WIDTH  => FB_ADDR_WIDTH
        )
        port map (
            clk         => clk,
            reset       => reset,

            rd_addr     => fb_rd_addr,
            rd_data     => fb_rd_data,

            frame_sync  => frame_sync,
            pixel_req   => pixel_req,
            pixel       => pixel,
            pixel_valid => pixel_valid
        );

    ----------------------------------------------------------------------
    -- The memory.
    --
    -- Two clients, one chip: the host filling it through wr_*, and
    -- image_reader emptying it one ray at a time.  The arbitration lives
    -- inside the controller because only one set of pins exists.
    --
    -- NEITHER SIDE WAITS FOR THE OTHER, and neither needs to.  The
    -- controller runs one state machine over one set of pins, so a read
    -- and a write are serialised by construction -- there is no window in
    -- which both are in flight and so nothing to arbitrate at this level.
    --
    -- A frame drawn while the image is still arriving therefore shows
    -- whatever has been written so far: the picture fills in rather than
    -- appearing at once.  leds(3) says when that is happening.
    ----------------------------------------------------------------------
    u_sdram : sdram_ctrl
        generic map (
            ADDR_WIDTH  => ADDR_WIDTH,
            CLK_FREQ_HZ => 50_000_000
        )
        port map (
            clk        => clk,
            reset      => reset,

            wr_req     => wr_req,
            wr_addr    => wr_addr,
            wr_data    => wr_data,
            wr_ack     => wr_ack,

            rd_req     => rd_req_s,
            rd_addr    => rd_addr_s,
            rd_data    => rd_data_s,
            rd_ack     => rd_valid_s,

            ready      => open,

            dram_dq    => dram_dq,
            dram_addr  => dram_addr,
            dram_ba    => dram_ba,
            dram_ldqm  => dram_ldqm,
            dram_udqm  => dram_udqm,
            dram_ras_n => dram_ras_n,
            dram_cas_n => dram_cas_n,
            dram_cke   => dram_cke,
            dram_clk   => dram_clk,
            dram_we_n  => dram_we_n,
            dram_cs_n  => dram_cs_n
        );

    ----------------------------------------------------------------------
    -- Seven-segment displays: the high byte of each angle.
    --
    --   hex5 hex4 = roll    hex3 hex2 = pitch    hex1 hex0 = yaw
    --
    -- The HIGH byte, not the low one.  These are binary angle measure,
    -- so the top bits are the degrees and the bottom bits the fraction
    -- -- and a display showing the fraction looks exactly like a
    -- free-running counter, which is how it was first misread.
    ----------------------------------------------------------------------
    rx_hex1_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => rx(ANGLE_WIDTH - 1 downto ANGLE_WIDTH - 4),
                  dout => hex5);
    rx_hex0_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => rx(ANGLE_WIDTH - 5 downto ANGLE_WIDTH - 8),
                  dout => hex4);
    ry_hex1_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => ry(ANGLE_WIDTH - 1 downto ANGLE_WIDTH - 4),
                  dout => hex3);
    ry_hex0_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => ry(ANGLE_WIDTH - 5 downto ANGLE_WIDTH - 8),
                  dout => hex2);
    rz_hex1_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => rz(ANGLE_WIDTH - 1 downto ANGLE_WIDTH - 4),
                  dout => hex1);
    rz_hex0_inst : digit_display
        port map (clk => clk, rst => reset,
                  din => rz(ANGLE_WIDTH - 5 downto ANGLE_WIDTH - 8),
                  dout => hex0);

    ----------------------------------------------------------------------
    -- Activity LEDs.
    --
    -- Each axis toggles its own LED whenever its angle changes, so a
    -- sensor that is answering but stuck reads differently from one that
    -- is not answering at all.  clk_alive is the control: it blinks once
    -- a second regardless, so a dark board means no clock rather than no
    -- data.  wr_active says the host is writing the image in.
    --
    -- THE PINS ARE ACTIVE LOW: driving one to zero lights the LED.  For
    -- the three beats and clk_alive that does not matter, because they
    -- toggle and either polarity is a visible blink.  For wr_active it
    -- does -- it is a level, and getting it backwards gives an LED that
    -- is on whenever nothing is happening -- so it is inverted here
    -- explicitly.
    --
    -- There are five LEDs and six things worth showing, so the IMU
    -- frame beat is the one left out: three axis beats already say
    -- whether data is arriving, and clk_alive already says whether the
    -- board is running.  Neither says anything about the transfer.
    ----------------------------------------------------------------------
    activity_process : process (reset, clk) is
    begin
        if ( reset = '1' ) then
            byte_beat  <= '0';
            frame_beat <= '0';
            valid_d    <= '0';
            tick_count <= 0;
            clk_alive  <= '0';
            wr_timer   <= 0;
            wr_active  <= '0';
        elsif rising_edge(clk) then
            -- Retriggerable one-shot on the write strobe.
            if ( wr_req = '1' ) then
                wr_timer <= WR_HOLD;
            elsif ( wr_timer /= 0 ) then
                wr_timer <= wr_timer - 1;
            end if;
            wr_active <= '0';
            if ( wr_req = '1' ) or ( wr_timer /= 0 ) then
                wr_active <= '1';
            end if;

            -- One toggle per byte and one per accepted frame.  A
            -- toggle rather than a pulse because a pulse a few clocks
            -- long is invisible; toggling makes the LED blur at the
            -- byte rate and blink at the frame rate.
            if ( byte_stb = '1' ) then
                byte_beat <= not byte_beat;
            end if;

            valid_d <= rot_valid;
            if ( rot_valid = '1' ) and ( valid_d = '0' ) then
                frame_beat <= not frame_beat;
            end if;

            if ( tick_count = TICK_MAX ) then
                tick_count <= 0;
                clk_alive  <= not clk_alive;
            else
                tick_count <= tick_count + 1;
            end if;
        end if;
    end process activity_process;

    ----------------------------------------------------------------------
    -- READ THESE IN ORDER.  Each one only means something if the one
    -- before it is behaving, so they localise a fault instead of merely
    -- reporting one:
    --
    --   leds(4) clk_alive   blinks ~1 Hz.  Dark or solid means the
    --                       design is not running at all; nothing below
    --                       is worth reading.
    --   leds(0) imu_rx      the raw serial line, driven straight out.
    --                       A UART idles HIGH and the pin is ACTIVE LOW,
    --                       so this is DARK when the line is healthy and
    --                       LIT SOLID when it is stuck low -- unplugged,
    --                       shorted, or the module unpowered.  It
    --                       flickers faintly while data flows.
    --   leds(1) byte_beat   blurs when the receiver is framing bytes.
    --                       Dark with a healthy line means the baud rate
    --                       is wrong or nothing is transmitting.
    --   leds(2) frame_beat  blinks per ACCEPTED angle frame.  Dark while
    --                       leds(1) blurs means bytes arrive but no
    --                       frame passes its checksum -- the one case a
    --                       plain "no data" indicator cannot tell apart.
    --   leds(3) wr_active   lit while the host writes the image in.
    --
    -- This replaced one LED per axis.  Three lamps all saying "an angle
    -- changed" is one fact spread across three pins, and it cannot
    -- distinguish a dead cable from a bad checksum -- which is exactly
    -- the distinction needed when the displays sit at zero.
    ----------------------------------------------------------------------
    leds(0) <= imu_rx;
    leds(1) <= byte_beat;
    leds(2) <= frame_beat;
    leds(3) <= not wr_active;
    leds(4) <= clk_alive;

end architecture structural;