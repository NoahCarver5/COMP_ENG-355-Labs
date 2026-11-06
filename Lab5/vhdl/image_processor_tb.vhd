library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

--------------------------------------------------------------------------
-- Testbench for image_processor.
--
-- Reads a real 640x480 BMP, streams it into the camera port exactly as
-- the D8M would, then runs the display side once per filter and writes
-- each result to its own BMP.
--
--   input bmp ==> camera port ==> frame buffer ==> filter ==> output_n.bmp
--
-- There are no assertions on the pixels.  Checking is done by opening the
-- output images and looking at them, which for this kind of filter catches
-- more than a comparison against a model would: a swapped color channel,
-- an off-by-one address, a wrapped highlight and a sideways shift are all
-- instantly visible and all awkward to assert on.
--
-- hdmi is NOT instantiated.  The display side of it is three signals --
-- a pixel rate enable, a request and a blanking flag -- and generating
-- them here keeps the testbench pointed at image_processor alone.
--
-- Outputs are numbered straight through: output_0.bmp is the first image
-- with filter 0, output_1.bmp is the first image with filter 1, and so on
-- across every image.
--
-- RUNTIME.  Every captured frame is 307,200 pixels asked for one at a
-- time, a few clocks each, plus the same again to stream the image in --
-- roughly a million and a half clocks per filter.  Lower N_FILTERS while
-- iterating.
--------------------------------------------------------------------------
entity image_processor_tb is
end entity image_processor_tb;

architecture behavioral of image_processor_tb is

    ---------------------------------------------------------------------
    -- Configuration.  Must match image_processor_system.
    ---------------------------------------------------------------------
    constant IMG_W     : natural := 640;
    constant IMG_H     : natural := 480;
    constant N_PIXELS  : natural := IMG_W * IMG_H;
    constant ADDR_W    : natural := 19;
    constant N_FILTERS : natural := 8;

    -- The board holds a key for 2**20 clocks -- 10.5 ms -- before a
    -- press counts.  Simulating that costs 10 ms of simulated time per
    -- press and proves nothing extra, so the DUT is built with a short
    -- one here. 2**5 still exercises the counter, the hold and the
    -- release rather than bypassing them.
    constant DEBOUNCE_TICKS : natural := 2**5;

    constant SYS_PERIOD : time := 10 ns;    -- 100 MHz system clock
    constant CAM_PERIOD : time := 40 ns;    -- 25 MHz sensor clock

    -- Pixel periods of vertical blanking between frames.  Only has to be
    -- long enough for frame_sync to reset the read address; the real raster
    -- spends far longer there, and simulating that is wasted time.
    constant BLANK_PERIODS : natural := 16;
    constant FRAME_PERIODS : natural := N_PIXELS + BLANK_PERIODS;

    -- Input images, in the sim directory.  All names must be the same
    -- length -- an array of strings is a constrained type in VHDL.
    constant IMAGE_FILE : string := "u2_0.bmp";

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
    -- Read a 24-bit uncompressed BMP into a frame.
    --
    -- BMP stores its rows bottom up and its channels as B, G, R.  Rows
    -- are padded out to a multiple of four bytes; at 640 x 3 = 1920 there
    -- is none, but the arithmetic is here so another width still works.
    ---------------------------------------------------------------------
    procedure read_bmp (constant file_name : in  string;
                        variable img       : out frame_t) is
        file f            : char_file_t;
        variable status   : file_open_status;
        variable ch       : character;
        variable header   : integer_vector(0 to 53);
        variable offset   : natural;
        variable w, h     : natural;
        variable bpp      : natural;
        variable padding  : natural;
        variable r, g, b  : natural;
        variable row      : natural;
    begin
        file_open(status, f, file_name, read_mode);
        assert status = open_ok
            report "Could not open input image: " & file_name
            severity failure;

        -- The 14-byte file header and the 40-byte info header together.
        for i in header'range loop
            read(f, ch);
            header(i) := character'pos(ch);
        end loop;

        assert (header(0) = character'pos('B')) and
               (header(1) = character'pos('M'))
            report file_name & " is not a BMP"
            severity failure;

        offset := header(10) + header(11) * 256
                + header(12) * 65536 + header(13) * 16777216;

        w := header(18) + header(19) * 256
           + header(20) * 65536 + header(21) * 16777216;

        h := header(22) + header(23) * 256
           + header(24) * 65536 + header(25) * 16777216;

        bpp := header(28) + header(29) * 256;

        assert (w = IMG_W) and (h = IMG_H)
            report file_name & " is " & integer'image(w) & "x" &
                   integer'image(h) & ", expected " &
                   integer'image(IMG_W) & "x" & integer'image(IMG_H)
            severity failure;

        assert bpp = 24
            report file_name & " is " & integer'image(bpp) &
                   " bits per pixel, expected 24"
            severity failure;

        -- Anything between the headers and the pixel data.
        for i in 54 to offset - 1 loop
            read(f, ch);
        end loop;

        padding := (4 - ((IMG_W * 3) mod 4)) mod 4;

        -- Bottom up: the first row in the file is the last on screen.
        for y in 0 to IMG_H - 1 loop
            row := IMG_H - 1 - y;
            for x in 0 to IMG_W - 1 loop
                read(f, ch);  b := character'pos(ch);
                read(f, ch);  g := character'pos(ch);
                read(f, ch);  r := character'pos(ch);

                img(row * IMG_W + x) :=
                    std_logic_vector(to_unsigned(r, 8)) &
                    std_logic_vector(to_unsigned(g, 8)) &
                    std_logic_vector(to_unsigned(b, 8));
            end loop;
            for i in 1 to padding loop
                read(f, ch);
            end loop;
        end loop;

        file_close(f);
        report "Read " & file_name severity note;
    end procedure read_bmp;

    ---------------------------------------------------------------------
    -- Write a frame out as a 24-bit uncompressed BMP.
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
    component image_processor is
        generic (
            IMG_W           : natural := 640;
            IMG_H           : natural := 480;
            ADDR_W          : natural := 19;
            N_FILTERS       : natural := 8;
            DEBOUNCE_TICKS  : natural := 2**20
        );
        port (
            clock       : in  std_logic;
            reset       : in  std_logic;
            cam_clk     : in  std_logic;
            cam_vs      : in  std_logic;
            cam_de      : in  std_logic;
            cam_pixel   : in  std_logic_vector(23 downto 0);
            keys_n      : in  std_logic_vector(1 downto 0);
            hex0        : out std_logic_vector(6 downto 0);
            hex1        : out std_logic_vector(6 downto 0);
            frame_sync  : in  std_logic;
            pixel_req   : in  std_logic;
            pixel       : out std_logic_vector(23 downto 0);
            pixel_valid : out std_logic
        );
    end component;

    ---------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------
    signal clock        : std_logic := '0';
    signal cam_clk      : std_logic := '0';
    signal reset        : std_logic := '1';

    signal cam_vs       : std_logic := '0';
    signal cam_de       : std_logic := '0';
    signal cam_pixel    : std_logic_vector(23 downto 0) := (others => '0');

    signal keys_n       : std_logic_vector(1 downto 0) := (others => '1');
    signal hex0         : std_logic_vector(6 downto 0);
    signal hex1         : std_logic_vector(6 downto 0);

    signal pixel_req    : std_logic := '0';
    signal frame_sync   : std_logic := '1';
    signal pixel        : std_logic_vector(23 downto 0);
    signal pixel_valid  : std_logic;

    -- Four phase handshake between the two halves of the testbench.
    -- Both loop 0 to N_FILTERS, and neither can start an iteration until
    -- the other has finished the previous one, so they are always on the
    -- same filter.
    --
    --   frame_ready   input  -> output : filter selected, frame streamed
    --   frame_done    output -> input  : frame captured and written
    signal frame_ready : std_logic := '0';
    signal frame_done  : std_logic := '0';

begin

    ---------------------------------------------------------------------
    -- TODO: Instantiate the image_processor
    ---------------------------------------------------------------------

    dut : image_processor  generic map (
            IMG_W => IMG_W,
            IMG_H => IMG_H,
            ADDR_W => ADDR_W,
            N_FILTERS => N_FILTERS,
            DEBOUNCE_TICKS => DEBOUNCE_TICKS
        )
        port map(
            clock => clock,
            reset  => reset,
            cam_clk => cam_clk,
            cam_vs => cam_vs,
            cam_de => cam_de,
            cam_pixel => cam_pixel,
            keys_n => keys_n,
            hex0 => hex0,
            hex1 => hex1,
            frame_sync => frame_sync,
            pixel_req => pixel_req,
            pixel => pixel,
            pixel_valid => pixel_valid
        );

    ---------------------------------------------------------------------
    -- TODO: Implement the clock processes for the system and camera clocks
    -- using the SYS_PERIOD and CAM_PERIOD.
    ---------------------------------------------------------------------

    sys_clock : process is
    begin
        clock <= '0';
        wait for SYS_PERIOD / 2;
        clock <= '1';
        wait for SYS_PERIOD / 2;
    end process sys_clock;

    cam_clock : process is            
    begin
        wait for 3 ns;
        cam_clk <= '0';
        wait for CAM_PERIOD/2;
        cam_clk <= '1';
        wait for CAM_PERIOD/2;
    end process cam_clock;

    ---------------------------------------------------------------------
    -- TODO: Implement the reset process.  The board reset is active low; 
    -- but everything internal is active high.  The reset should be held 
    -- for a few cycles.
    ---------------------------------------------------------------------
    sys_reset : process is
    begin
        reset <= '0';
        wait for SYS_PERIOD / 2;
        reset <= '1';
        wait for 3*SYS_PERIOD;
        reset <= '0';
        wait;
    end process sys_reset;

    ---------------------------------------------------------------------
    -- TODO: Implement the input process to read the BMP and stream it into
    -- the camera port.  The input process should loop over all filters,
    -- and for each filter, stream the image in, then wait for the output
    -- process to finish capturing the frame and writing it to a BMP.
    --
    -- Step 1: Wait for the reset to finish before starting the input stream.
    
    -- Step 2: Read the BMP file into the image_frame variable using the read_bmp procudure.

    -- Step 3: Loop over all filters:
    --         3a: Stream the image into the camera port, one pixel per cam_clk. 
    --         3b: Assert frame_ready to indicate that the frame is ready for processing.
    --         3c: Wait for frame_done to be asserted by the output process, indicating 
    --             that the frame has been processed, then deassert frame_ready.
    --         3d: Advance the filter by simulating a key press and release on keys_n.
    ---------------------------------------------------------------------
    input_process : process is
        variable image_frame : frame_t;
    begin
        wait for 3.5*SYS_PERIOD;
        read_bmp(IMAGE_FILE, image_frame);
        -- TODO: Implement the input process as described in the comments above.
        for i in 0 to N_FILTERS -1 loop

            wait until rising_edge(cam_clk); 
            cam_vs <= '1'; 
            wait until rising_edge(cam_clk); 
            cam_de <= '1'; 

            for i in 0 to N_PIXELS - 1 loop 
                cam_pixel <= image_frame(i); 
                wait until rising_edge(cam_clk); 
            end loop; 

            cam_de <= '0'; 
            cam_vs <= '0'; 

            wait until rising_edge(cam_clk);
            
            frame_ready <= '1';

            wait until (frame_done = '1');

            frame_ready <= '0';
            
            wait until (frame_done = '0');

            keys_n <= "10";

            for i in 0 to DEBOUNCE_TICKS+6 loop
                
                wait until rising_edge(clock);

            end loop;

            keys_n <= "11";

            
        end loop; --    end process input_process;
        wait;
        end process input_process;

    ---------------------------------------------------------------------
    -- Output: read a whole frame back out, one filter at a time.
    --
    -- This is the display side.  It stands in for hdmi and does the job
    -- with two signals: frame_sync to park the read address at zero, and one
    -- pixel_req per pixel.  There is no raster and no blanking interval,
    -- because nothing here needs a picture to arrive at 60 Hz -- it only
    -- needs the pixels, in order.
    --
    -- Ask for a pixel, wait until it turns up, store it, ask for the
    -- next.  No pacing and no pipelining: this is not trying to be a
    -- 25 MHz raster, it just needs the pixels in order.
    --
    -- The wait is on pixel_valid, NOT on a fixed number of clocks.  pixel
    -- and pixel_valid leave the same register, so sampling both on the
    -- same edge always gives a matched pair -- however many stages the
    -- read path grows.  Add a pipeline stage to a filter and this loop
    -- does not change.
    --
    -- The frame is collected into dst and written once at the end, so the
    -- file is one continuous write rather than 307,200 small ones.
    ---------------------------------------------------------------------
    output_process : process is
        variable dst : frame_t;
    begin
        for N in 0 to N_FILTERS - 1 loop

            -- Wait for the input side to select the filter and finish
            -- streaming, so the buffer holds a whole frame and not half
            -- of two.
            wait until frame_ready = '1';
            wait until rising_edge(clock);

            -- Park the read address at zero.
            frame_sync <= '1';
            wait until rising_edge(clock);
            wait until rising_edge(clock);
            frame_sync <= '0';
            wait until rising_edge(clock);

            -- Ask, wait for the answer, store it, ask again.
            for n in 0 to N_PIXELS - 1 loop
                pixel_req <= '1';
                wait until rising_edge(clock);
                pixel_req <= '0';
                wait until rising_edge(clock) and pixel_valid = '1';        
                dst(n) := pixel;
            end loop;

            write_bmp("output_" & integer'image(N) & ".bmp", dst);

            -- Release the input side to stream the next one.
            frame_done <= '1';
            wait until frame_ready = '0';
            frame_done <= '0';

        end loop;

        report "Image processor testing complete" severity note;
        stop;
    end process output_process;

end architecture behavioral;
