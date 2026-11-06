library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pixel_pkg.all;

--------------------------------------------------------------------------
-- Filter: passthrough.  The default.
--
-- Reads the RGB686 word coming out of the block RAM, unpacks it, and
-- hands it straight on to the display.
--
-- THIS IS THE TEMPLATE.  Every filter has the same six ports and the same
-- shape; only the arithmetic in the middle differs.
--
--     clock, reset            async reset, sync clock
--     data_in, valid_in       RGB686 from the block ram
--     data_out, valid_out     8:8:8 to the display
--
-- valid_in marks the one clock where data_in is a genuinely new pixel.
-- The system clock runs several times faster than the pixel rate, so
-- without it "the value I saw last clock" is usually the SAME pixel.
-- This filter would not care -- it has no memory -- but a filter that
-- remembers the previous pixel does, and the contract is uniform so that
-- every filter drops into the same socket.
--
-- valid_out follows valid_in by exactly one clock, which is the output
-- register.  Every filter has this same one-clock latency, so switching
-- between them cannot shift the picture sideways.
--
-- Note the shape of it.  The ports are plain std_logic_vector, because
-- that is what a port always is.  pixel_t lives inside the process, where
-- it makes the arithmetic readable, and unpack686 / pack888 translate at
-- the boundary.
--------------------------------------------------------------------------
entity filter_threshold is
    port (
        clock     : in  std_logic;
        reset     : in  std_logic;                       -- async, active high

        data_in   : in  std_logic_vector(19 downto 0);   -- RGB686
        valid_in  : in  std_logic;

        data_out  : out std_logic_vector(23 downto 0);   -- 8:8:8
        valid_out : out std_logic
    );
end entity filter_threshold;


architecture rtl of filter_threshold is
begin

    -----------------------------------------------------------------
    -- Clocked process
    -- Passes the pixel straight through, unpacking and repacking it.
    -- Handshaking is done with valid_in and valid_out signals.
    -----------------------------------------------------------------
    clocked_process: process (reset, clock) is
        variable p : pixel_t;
        variable p_red : byte_t;
        variable p_blue : byte_t;
        variable p_green : byte_t;
        variable sum_div : std_logic_vector(7 downto 0);
        variable final_pixel : pixel_t;
    
    begin
        if ( reset = '1' ) then
            data_out  <= (others => '0');
            valid_out <= '0';
        elsif rising_edge(clock) then
            valid_out <= valid_in;

            if ( valid_in = '1' ) then

                p := unpack686(data_in);
                p_green := p.g;
                p_red := p.r;
                p_blue := p.b;

                sum_div := std_logic_vector (resize((unsigned((resize(unsigned(p_green), 10) + resize(unsigned(p_red), 10) + resize(unsigned(p_blue), 10)))/3), 8));

                if (unsigned(sum_div) < 100) then
                    data_out <= (others => '0');
                else 
                    data_out <= (others => '1');
                end if;

            end if;
        end if;
    end process clocked_process;

end architecture rtl;
