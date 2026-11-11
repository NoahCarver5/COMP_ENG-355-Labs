library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

use work.trig_pkg.all;

entity vr360_tb is
end entity vr360_tb;

architecture behavioral of vr360_tb is

    ---------------------------------------------------------------------
    -- Component declaration
    ---------------------------------------------------------------------
    component vr360 is
        generic (
            FOCAL_LENGTH : natural;
            ANGLE_WIDTH  : natural;
            IMAGE_WIDTH  : natural;
            IMAGE_HEIGHT : natural;
            OUT_WIDTH    : natural;
            OUT_HEIGHT   : natural;
            PIXEL_WIDTH  : natural;
            ADDR_WIDTH   : natural;
            TRIG_WIDTH   : natural
        );
        port (
            clk         : in    std_logic;
            reset       : in    std_logic;
            rx          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            ry          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rz          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rot_valid   : in    std_logic;
            imu_rx      : in    std_logic;
            byte_stb    : in    std_logic;
            wr_req      : in    std_logic;
            wr_addr     : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
            wr_data     : in    std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            wr_ack      : out   std_logic;
            dram_dq     : inout std_logic_vector(15 downto 0);
            dram_addr   : out   std_logic_vector(12 downto 0);
            dram_ba     : out   std_logic_vector(1 downto 0);
            dram_ldqm   : out   std_logic;
            dram_udqm   : out   std_logic;
            dram_ras_n  : out   std_logic;
            dram_cas_n  : out   std_logic;
            dram_cke    : out   std_logic;
            dram_clk    : out   std_logic;
            dram_we_n   : out   std_logic;
            dram_cs_n   : out   std_logic;
            hex0        : out   std_logic_vector(6 downto 0);
            hex1        : out   std_logic_vector(6 downto 0);
            hex2        : out   std_logic_vector(6 downto 0);
            hex3        : out   std_logic_vector(6 downto 0);
            hex4        : out   std_logic_vector(6 downto 0);
            hex5        : out   std_logic_vector(6 downto 0);
            leds        : out   std_logic_vector(4 downto 0);
            frame_sync  : in    std_logic;
            pixel_req   : in    std_logic;
            pixel       : out   std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            pixel_valid : out   std_logic
        );
    end component;

    ---------------------------------------------------------------------
    -- Constants
    ---------------------------------------------------------------------
    constant CLK_PERIOD      : time := 20 ns;

    constant ANGLE_WIDTH     : natural := 16;
    constant ANGLE_FRAC_BITS : natural := 6;
    constant TRIG_WIDTH      : natural := 16;

    constant IMAGE_WIDTH     : natural := 1024;
    constant IMAGE_HEIGHT    : natural := 512;

    ---------------------------------------------------------------------
    -- THE SIMULATED FRAME IS SMALLER THAN THE REAL ONE.  The hardware
    -- renders 640x480 with FOCAL_LENGTH 320; this renders a quarter of
    -- that in each direction.
    --
    -- Not to save a little time -- to make the test possible at all.
    -- Every output pixel now costs a real SDRAM access: an ACTIVATE, a
    -- READ, the CAS latency, the capture and a PRECHARGE, plus refresh
    -- getting in the way, so about sixteen clocks where the old
    -- combinational stand-in answered in one.  At 640x480 that is five
    -- million clocks for ONE frame and a quarter of a second of
    -- simulated time; five poses is over a second, which runs for the
    -- better part of an hour and looks exactly like a hang.  At 160x120
    -- a pose is about nine milliseconds.
    --
    -- FOCAL_LENGTH SCALES WITH THE WIDTH, and has to.  It is a length in
    -- pixels, so holding it at 320 while the frame shrinks would narrow
    -- the field of view to a quarter and the bitmaps would come out as a
    -- crop of the middle rather than a small version of the same view --
    -- which reads as a rendering bug when nothing is wrong.  What matters
    -- is the ratio: 320/640 and 80/160 are the same lens.
    --
    -- Nothing else about the access pattern changes, so a per-pixel
    -- defect -- a wrong capture latency, a swapped halfword, a dropped
    -- refresh -- shows up here exactly as it does on the board.
    ---------------------------------------------------------------------
    constant OUT_WIDTH       : natural := 160;
    constant OUT_HEIGHT      : natural := 120;
    constant FOCAL_LENGTH    : natural := 80;

    constant PIXEL_WIDTH     : natural := 24;

    constant IMAGE_PIXELS    : natural := IMAGE_WIDTH * IMAGE_HEIGHT;
    constant OUT_PIXELS      : natural := OUT_WIDTH * OUT_HEIGHT;

    -- Clocks to allow for one rendered frame.
    --
    -- A pixel costs one SDRAM read -- ACTIVATE, READ, CAS latency,
    -- capture, PRECHARGE, about fourteen clocks -- plus an auto-refresh
    -- every 390 clocks and the ray_gen pipeline behind it.  Sixteen is
    -- the realistic figure; 24 leaves half again on top.
    --
    -- If it is ever too short the bitmap comes out part rendered, with a
    -- sharp horizontal edge partway down and power-up contents below it.
    -- That is deliberately unmistakable: the failure to avoid is one
    -- that looks like a plausible picture.
    constant CLOCKS_PER_PIXEL : natural := 24;
    constant RENDER_CLOCKS    : natural := OUT_PIXELS * CLOCKS_PER_PIXEL;

    -- Long enough for the 200 us power-up wait and the init sequence.
    -- Reads before that are refused, so a first frame that did not allow
    -- for it would be blank through its top rows for no visible reason.
    constant INIT_CLOCKS      : natural := 12_000;

    constant OUT_X_WIDTH     : natural := log2(OUT_WIDTH);
    constant OUT_Y_WIDTH     : natural := log2(OUT_HEIGHT);
    constant ADDR_WIDTH      : natural := log2(IMAGE_PIXELS);

    constant IMAGE_FILE      : string := "../memory/vr360_image_0_mini.mif";

    ---------------------------------------------------------------------
    -- Signals
    ---------------------------------------------------------------------
    signal clk   : std_logic := '0';
    signal reset : std_logic := '0';

    signal rx : std_logic_vector(ANGLE_WIDTH - 1 downto 0) := (others => '0');
    signal ry : std_logic_vector(ANGLE_WIDTH - 1 downto 0) := (others => '0');
    signal rz : std_logic_vector(ANGLE_WIDTH - 1 downto 0) := (others => '0');
    signal rot_valid : std_logic := '0';

    ----------------------------------------------------------------------
    -- THE MEMORY IS A MODEL NOW, NOT A PROCESS IN HERE.
    --
    -- The controller moved inside vr360, so the testbench no longer
    -- answers read requests itself -- it drives the SDRAM pins and lets
    -- a behavioural memory answer them.  That is the point: the thing
    -- being exercised is the real command sequence, initialisation,
    -- refresh, burst and capture timing included, rather than a process
    -- in here that returns the right pixel by construction.
    --
    -- The old arrangement is exactly how a missing write path went
    -- unnoticed for so long: the testbench served pixels from an array
    -- it had loaded itself, so a design that never wrote anything to the
    -- real memory passed.
    --
    -- The image is loaded through the model's back door rather than
    -- written in through the controller.  Writing it properly would be
    -- half a million accesses of about fourteen clocks each before the
    -- first frame could be rendered -- minutes of simulation to set up a
    -- test that is not about writing.
    ----------------------------------------------------------------------
    signal dram_dq   : std_logic_vector(15 downto 0);
    signal dram_addr : std_logic_vector(12 downto 0);
    signal dram_ba   : std_logic_vector(1 downto 0);
    signal dram_ldqm, dram_udqm              : std_logic;
    signal dram_ras_n, dram_cas_n, dram_we_n : std_logic;
    signal dram_cke, dram_clk, dram_cs_n     : std_logic;

    signal hex0_s, hex1_s, hex2_s : std_logic_vector(6 downto 0);
    signal hex3_s, hex4_s, hex5_s : std_logic_vector(6 downto 0);
    signal leds_s : std_logic_vector(4 downto 0);


    -- The display side.  This testbench stands in for hdmi: it asks for
    -- pixels and collects them, but does not bother with a raster.
    -- STARTS LOW.  Held high it forces frame_reader to park its address
    -- at zero and suppress pixel_valid, so the collect loop below would
    -- wait for a pixel that is never announced -- a hang with no message
    -- and nothing written out.  hdmi pulses this at the start of a
    -- frame; it does not idle high, and neither should the stand-in.
    signal frame_sync  : std_logic := '0';
    signal pixel_req   : std_logic := '0';
    signal pixel       : std_logic_vector(PIXEL_WIDTH - 1 downto 0);
    signal pixel_valid : std_logic;

    type frame_mem_t is array (0 to OUT_PIXELS - 1) of std_logic_vector(PIXEL_WIDTH - 1 downto 0);
    signal frame_mem : frame_mem_t;

    ----------------------------------------------------------------------
    -- Procedure to write a frame to a BMP file.
    ----------------------------------------------------------------------
    procedure write_frame_bmp(
        constant file_name : in string;
        constant frame     : in frame_mem_t
    ) is
        type byte_file_t is file of character;
        file output_file : byte_file_t;
        variable status  : file_open_status;
        variable p       : std_logic_vector(23 downto 0);
        
        -- BMP Header calculations
        constant BYTES_PER_PIXEL : natural := 3;
        -- Calculate row size with padding (must be a multiple of 4 bytes)
        constant ROW_SIZE_RAW    : natural := OUT_WIDTH * BYTES_PER_PIXEL;
        constant PADDING_BYTES   : natural := (4 - (ROW_SIZE_RAW rem 4)) rem 4;
        constant ROW_SIZE_PADDED : natural := ROW_SIZE_RAW + PADDING_BYTES;
        
        constant IMAGE_SIZE      : natural := ROW_SIZE_PADDED * OUT_HEIGHT;
        constant FILE_SIZE       : natural := 54 + IMAGE_SIZE; -- 54 bytes for standard headers
        
        -- Helper procedure to write integers as little-endian binary bytes
        procedure write_le_int(file f: byte_file_t; val: in natural; bytes: in positive) is
            variable temp : natural := val;
        begin
            for i in 1 to bytes loop
                write(f, character'val(temp rem 256));
                temp := temp / 256;
            end loop;
        end procedure;

    begin
        file_open(status, output_file, file_name, write_mode);

        assert status = open_ok
            report "Could not open output BMP file: " & file_name
            severity failure;

        -------------------------------------------------------------------------
        -- 1. BITMAP FILE HEADER (14 bytes)
        -------------------------------------------------------------------------
        write(output_file, character'('B'));          -- Signature 'B'
        write(output_file, character'('M'));          -- Signature 'M'
        write_le_int(output_file, FILE_SIZE, 4);      -- File size in bytes
        write_le_int(output_file, 0, 2);              -- Reserved 1
        write_le_int(output_file, 0, 2);              -- Reserved 2
        write_le_int(output_file, 54, 4);             -- Offset to pixel data (14 + 40)

        -------------------------------------------------------------------------
        -- 2. BITMAP INFO HEADER (40 bytes - BITMAPINFOHEADER)
        -------------------------------------------------------------------------
        write_le_int(output_file, 40, 4);             -- Header size (40 bytes)
        write_le_int(output_file, OUT_WIDTH, 4);      -- Width
        write_le_int(output_file, OUT_HEIGHT, 4);     -- Height (Positive = bottom-up row order)
        write_le_int(output_file, 1, 2);              -- Planes (Must be 1)
        write_le_int(output_file, 24, 2);             -- Bits per pixel (24-bit color)
        write_le_int(output_file, 0, 4);              -- Compression (0 = BI_RGB uncompressed)
        write_le_int(output_file, IMAGE_SIZE, 4);     -- Image data size
        write_le_int(output_file, 2835, 4);           -- H-resolution (2835 px/m ~= 72 dpi)
        write_le_int(output_file, 2835, 4);           -- V-resolution
        write_le_int(output_file, 0, 4);              -- Important colors (0 = all)
        write_le_int(output_file, 0, 4);              -- Number of colors in palette

        -------------------------------------------------------------------------
        -- 3. PIXEL DATA
        -- BMP images default to bottom-up ordering (Row 0 is the bottom row).
        -- If your memory layout is top-down, invert the 'y' loop bounds.
        -------------------------------------------------------------------------
        for y in OUT_HEIGHT - 1 downto 0 loop
            for x in 0 to OUT_WIDTH - 1 loop
                p := frame(y * OUT_WIDTH + x);
                
                -- BMP expects BGR channel ordering natively
                -- p(7 downto 0)   is Blue
                -- p(15 downto 8)  is Green
                -- p(23 downto 16) is Red
                write(output_file, character'val(to_integer(unsigned(p(7 downto 0)))));   -- Blue
                write(output_file, character'val(to_integer(unsigned(p(15 downto 8)))));  -- Green
                write(output_file, character'val(to_integer(unsigned(p(23 downto 16))))); -- Red
            end loop;
            
            -- Write padding bytes for the row if necessary
            for p_idx in 1 to 4 loop
                if p_idx <= PADDING_BYTES then
                    write(output_file, character'val(0));
                end if;
            end loop;
        end loop;

        file_close(output_file);
    end procedure;



begin

    ---------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------
    dut : vr360
        generic map (
            FOCAL_LENGTH    => FOCAL_LENGTH,
            ANGLE_WIDTH     => ANGLE_WIDTH,
            IMAGE_WIDTH     => IMAGE_WIDTH,
            IMAGE_HEIGHT    => IMAGE_HEIGHT,
            OUT_WIDTH       => OUT_WIDTH,
            OUT_HEIGHT      => OUT_HEIGHT,
            PIXEL_WIDTH     => PIXEL_WIDTH,
            ADDR_WIDTH      => ADDR_WIDTH,
            TRIG_WIDTH      => TRIG_WIDTH
        )
        port map (
            clk         => clk,
            reset       => reset,

            rx          => rx,
            ry          => ry,
            rz          => rz,
            rot_valid   => rot_valid,
            -- LEDs only; the bench drives the angles directly, so
            -- there is no serial line and no byte traffic.  Idle
            -- high is what a healthy UART looks like.
            imu_rx      => '1',
            byte_stb    => '0',

            -- No image is written in through the controller: the model
            -- is preloaded.  See the note on the model instance below.
            wr_req      => '0',
            wr_addr     => (others => '0'),
            wr_data     => (others => '0'),
            wr_ack      => open,

            dram_dq     => dram_dq,
            dram_addr   => dram_addr,
            dram_ba     => dram_ba,
            dram_ldqm   => dram_ldqm,
            dram_udqm   => dram_udqm,
            dram_ras_n  => dram_ras_n,
            dram_cas_n  => dram_cas_n,
            dram_cke    => dram_cke,
            dram_clk    => dram_clk,
            dram_we_n   => dram_we_n,
            dram_cs_n   => dram_cs_n,

            hex0        => hex0_s,
            hex1        => hex1_s,
            hex2        => hex2_s,
            hex3        => hex3_s,
            hex4        => hex4_s,
            hex5        => hex5_s,
            leds        => leds_s,

            frame_sync  => frame_sync,
            pixel_req   => pixel_req,
            pixel       => pixel,
            pixel_valid => pixel_valid
        );

    ----------------------------------------------------------------------
    -- The memory.
    --
    -- BOARD_DELAY and HOLD_BUS are what make this bench able to fail the
    -- way hardware fails.  The datasheet's CAS latency is counted at the
    -- memory's own pins; what the FPGA sees is a cycle longer, because
    -- its clock reaches the memory late and the data crosses back.  And
    -- the bus has no pull resistors, so when nobody drives it it holds
    -- its last value rather than going high impedance -- which means a
    -- controller that samples a cycle early reads the PREVIOUS word
    -- instead of obvious rubbish.  A model without both of those passes
    -- happily while the board returns nonsense.
    ----------------------------------------------------------------------
    mem : entity work.sdram_model
        generic map (
            CAS_LATENCY => 2,          -- overridden by the mode register
            ADDR_BITS   => 22,         -- 2**22 words = 2M pixels of model
            VERBOSE     => false,
            BOARD_DELAY => 1,
            HOLD_BUS    => true,
            INIT_FILE   => IMAGE_FILE
        )
        port map (
            dram_clk => dram_clk, dram_cke => dram_cke,
            dram_cs_n => dram_cs_n, dram_ras_n => dram_ras_n,
            dram_cas_n => dram_cas_n, dram_we_n => dram_we_n,
            dram_addr => dram_addr, dram_ba => dram_ba,
            dram_ldqm => dram_ldqm, dram_udqm => dram_udqm,
            dram_dq => dram_dq
        );


    ----------------------------------------------------------------------
    -- Clock process
    ----------------------------------------------------------------------
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    ---------------------------------------------------------------------
    -- Reset
    ---------------------------------------------------------------------
    reset_process : process
    begin
        reset <= '0';
        wait for CLK_PERIOD;

        reset <= '1';
        wait for CLK_PERIOD;

        reset <= '0';
        wait;
    end process;

    ---------------------------------------------------------------------
    -- Test stimulus
    ---------------------------------------------------------------------
    stimulus : process
    
        type rotation_tuple is array (0 to 2) of integer;
        type rotation_array is array (natural range <>) of rotation_tuple;
        constant test_rotations : rotation_array(0 to 4) := (
            (0, 0, 0),
            (30, 0, 0),
            (0, 30, 0),
            (0, 0, 30),
            (-30, 30, -20)
        );

    begin
        -- The panorama is already in the memory model; see above.

        rx <= (others => '0');
        ry <= (others => '0');
        rz <= (others => '0');
        rot_valid <= '0';

        -----------------------------------------------------------------
        -- Wait for reset to complete.
        -----------------------------------------------------------------
        wait until reset = '1';
        wait until reset = '0';
        wait for 2 * CLK_PERIOD;

        -- The SDRAM controller refuses reads until it has run its
        -- power-up wait and initialisation sequence.  Starting a pose
        -- before then just burns part of its render budget waiting.
        wait for INIT_CLOCKS * CLK_PERIOD;

        -----------------------------------------------------------------
        -- Render every requested orientation.
        -----------------------------------------------------------------
        for pose in 0 to test_rotations'high loop

            wait for CLK_PERIOD;

            rx <= std_logic_vector(to_signed((test_rotations(pose)(0) * 2**(ANGLE_WIDTH - 1)) / 180, ANGLE_WIDTH));
            ry <= std_logic_vector(to_signed((test_rotations(pose)(1) * 2**(ANGLE_WIDTH - 1)) / 180, ANGLE_WIDTH));
            rz <= std_logic_vector(to_signed((test_rotations(pose)(2) * 2**(ANGLE_WIDTH - 1)) / 180, ANGLE_WIDTH));         
            rot_valid <= '1';

            wait for CLK_PERIOD;
            rot_valid <= '0';

            -----------------------------------------------------------------
            -- Give the renderer time to fill the frame buffer.
            --
            -- There is no done flag to wait on: vr360's only outputs are
            -- the display side.  RENDER_CLOCKS is an upper bound on one
            -- frame -- if it is short the BMP comes out part rendered,
            -- which is obvious the moment you look at it.
            -----------------------------------------------------------------
            -- One wait, not RENDER_CLOCKS of them.  Resuming this
            -- process on every clock edge costs more simulator time than
            -- the whole design does, and buys nothing: no edge is being
            -- counted, only time allowed to pass.
            wait for RENDER_CLOCKS * CLK_PERIOD;

            -----------------------------------------------------------------
            -- Now read it back out the way hdmi would.
            --
            -- frame_sync parks the read address at zero, then one pixel_req
            -- per pixel.  pixel_valid says when the answer is on pixel,
            -- so nothing here depends on how deep the read path is.
            -----------------------------------------------------------------
            frame_sync <= '1';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            frame_sync <= '0';
            wait until rising_edge(clk);

            for i in 0 to OUT_PIXELS - 1 loop
                pixel_req <= '1';
                wait until rising_edge(clk);
                pixel_req <= '0';

                wait until rising_edge(clk) and pixel_valid = '1';
                frame_mem(i) <= pixel;
            end loop;

            wait for CLK_PERIOD;
            write_frame_bmp("vr360_pose_" & integer'image(pose) & ".bmp", frame_mem);

            report "Completed pose " & integer'image(pose)
                severity note;
        end loop;

        -----------------------------------------------------------------
        -- Stop the clock after every frame has been generated.
        -----------------------------------------------------------------
        report "vr360 testing complete" severity note;
        stop;
    end process;

end architecture behavioral;