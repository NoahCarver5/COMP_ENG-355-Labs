library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pixel_pkg.all;

--------------------------------------------------------------------------
-- Video store -- WRITE SIDE ONLY.
--
-- Takes the camera's video stream and writes it into the frame buffer.
-- Nothing else: it never reads, and it knows nothing about the display.
-- The filters pull frames back out on their own schedule, which is what
-- lets the two sides run at completely unrelated rates.
--
-- Camera pixels arrive in raster order, so the address is simply how many
-- have arrived this frame: clear the counter at the start of a frame,
-- step it once per valid pixel.  addr = row*640 + col is the same number,
-- computed the hard way, and needs a multiplier to get there.
--
-- PIXEL FORMAT
--
-- In at 24 bits, out at 20.  The camera and the display both speak
-- 8:8:8, but the frame buffer stores 6:8:6.  20 is not an arbitrary
-- squeeze -- it is exactly one M20K word, so 640 x 480 costs 300 blocks
-- and a 21st bit would cost 300 more.  Keeping all 24 would need 600
-- blocks against 358 on the device.
--
-- unpack888 splits the bus into channels and pack686 drops the low two
-- bits of red and blue; the filters put those back with expand6 on the
-- way out.  Green makes the trip untouched.
--
-- CLOCK DOMAIN
--
-- The camera runs at 25 MHz and the system clock is much faster, so
-- cam_clk arrives here as an ORDINARY SIGNAL, not as a clock.  Two flops
-- and an edge detector turn it into one single-cycle tick per camera
-- pixel clock, and everything this module drives lives in the system
-- clock domain.
--
-- That requires the system clock to be at least 4x the camera clock, so
-- each half period is sampled at least twice.  100 MHz against 25 MHz
-- satisfies it exactly.  cam_de and cam_pixel hold for a whole camera
-- period, so sampling them on the tick lands in the middle of that
-- window.
--
-- The pixel travels through here with its address, so the RAM gets a
-- matched {wr_addr, wr_data, wr_en} triple and the data cannot drift out
-- of step with the address it belongs to.
--------------------------------------------------------------------------
entity video_store is
    generic (
        ADDR_W : natural := 19          -- 640*480 = 307_200 fits in 19 bits
    );
    port (
        clock     : in  std_logic;      -- system clock, >= 4x cam_clk
        reset     : in  std_logic;      -- active high

        -- ---- camera stream, 25 MHz ----
        cam_clk   : in  std_logic;                       -- sampled, not a clock
        cam_vs    : in  std_logic;                       -- frame valid
        cam_de    : in  std_logic;                       -- pixel valid
        cam_pixel : in  std_logic_vector(23 downto 0);   -- RGB888

        -- ---- to the block ram ----
        wr_addr   : out std_logic_vector(ADDR_W - 1 downto 0);
        wr_data   : out std_logic_vector(19 downto 0);   -- RGB686
        wr_en     : out std_logic
    );
end entity video_store;


architecture rtl of video_store is

    -- Two flops to catch metastability, a third to see the rising edge.
    signal cam_sync : std_logic_vector(2 downto 0);
    signal cam_tick : std_logic;

    signal cam_vs_d : std_logic;
    signal wr_cnt   : std_logic_vector(ADDR_W - 1 downto 0);

begin

    ----------------------------------------------------------------------
    -- Camera clock recovery.  One tick per rising edge of cam_clk; this
    -- is the entire clock domain crossing on the write side.
    ----------------------------------------------------------------------
    clock_sync : process (clock) is
    begin
        if rising_edge(clock) then
            if reset = '1' then
                cam_sync <= (others => '0');
            else
                cam_sync <= cam_sync(1 downto 0) & cam_clk;
            end if;
        end if;
    end process clock_sync;

    cam_tick <= cam_sync(1) and not cam_sync(2);

    ----------------------------------------------------------------------
    -- Write the frame
    --
    -- The camera free-runs, so the buffer is written forever while the
    -- filters read it.  Where the write pointer crosses the read pointer
    -- the picture tears: a moving horizontal seam.  That is the honest
    -- behaviour of a single buffer -- double buffering would fix it and
    -- needs 600 M20K blocks, against the 358 this device has.  (One
    -- 640x480 buffer at 20 bits is 300 blocks; two is every block on
    -- the die and then some.)
    --
    -- Address, data and enable are registered together, so they leave
    -- this module aligned.
    ----------------------------------------------------------------------
    write_process : process (clock) is
        variable p : pixel_t;
    begin
        if rising_edge(clock) then
            if reset = '1' then
                wr_cnt    <= (others => '0');
                cam_vs_d  <= '0';
                wr_en     <= '0';
                wr_addr   <= (others => '0');
                wr_data   <= (others => '0');
            else
                wr_en <= '0';
                if cam_tick = '1' then
                    cam_vs_d <= cam_vs;
                    if (cam_vs_d = '0') and (cam_vs = '1') then   -- frame start
                        wr_cnt <= (others => '0');
                    elsif cam_de = '1' then
                        -- This pixel goes to the address the counter
                        -- holds, squeezed down to what the buffer stores.
                        p := unpack888(cam_pixel);
                        wr_data <= pack686(p);
                        wr_addr <= wr_cnt;
                        wr_en   <= '1';
                        wr_cnt  <= std_logic_vector(unsigned(wr_cnt) + to_unsigned(1, ADDR_W));
                    end if;
                end if;
            end if;
        end if;
    end process write_process;

end architecture rtl;
