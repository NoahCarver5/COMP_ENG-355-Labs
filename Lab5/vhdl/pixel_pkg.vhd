library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- Shared pixel type and RGB686 conversion.
--
-- Every filter module works on pixel_t, so this package is the one place
-- the pixel format is defined.  Add a filter and you inherit it.
--
-- WHY 6:8:6 AND NOT 5:6:5
--
-- The frame buffer is built from M20K blocks, and an M20K is natively
-- 1024 words of TWENTY bits.  At 640x480 the buffer is 307_200 words,
-- which is 300 blocks at any width from 1 to 20 -- the block count is
-- set by the depth, not the width.  RGB565 therefore paid for 20 bits
-- per pixel and used 16 of them.
--
-- 6:8:6 spends all 20 for the same 300 blocks.  Green takes the two
-- extra bits because that is where the eye reads most of the luminance,
-- and because green arrives with the precision to spare: the demosaic
-- averages two green samples per pixel while red and blue are each a
-- single sample.
--
-- 22 bits would not fit.  Past 20 a pixel needs a second M20K and the
-- buffer doubles to 600 blocks, against 358 on the device.
--------------------------------------------------------------------------
package pixel_pkg is

    subtype byte_t is std_logic_vector(7 downto 0);

    type pixel_t is record
        r : byte_t;
        g : byte_t;
        b : byte_t;
    end record;

    constant PIXEL_BLACK : pixel_t := (r => (others => '0'),
                                       g => (others => '0'),
                                       b => (others => '0'));

    constant PIXEL_WHITE : pixel_t := (r => (others => '1'),
                                       g => (others => '1'),
                                       b => (others => '1'));

    -- Bit replication, not zero fill: 63 -> 255, never 63 -> 252.
    function expand6 (v : std_logic_vector(5 downto 0)) return byte_t;

    -- One RGB686 word from the frame buffer to three 8-bit channels.
    function unpack686 (word : std_logic_vector(19 downto 0)) return pixel_t;

    -- ...and back down to RGB686 on the way into the frame buffer.
    --
    -- This one still throws bits away: 8:8:8 does not fit in 20 bits, so
    -- the low 2 bits of red and blue are dropped.  Green survives whole.
    -- That loss is the price of a 300-block frame buffer, and it is why
    -- even the passthrough filter does not return the image bit for bit.
    function pack686 (p : pixel_t) return std_logic_vector;

    -- The 24-bit bus the camera and the display speak, split into
    -- channels.  pack888 is its inverse.
    function unpack888 (word : std_logic_vector(23 downto 0)) return pixel_t;

    -- ...and back out to a flat 24-bit bus for the display.
    --
    -- Ports are always std_logic / std_logic_vector.  pixel_t exists to
    -- make the arithmetic readable INSIDE a module; these two functions
    -- are the translation at its edges, and they cost nothing in the
    -- netlist -- they are just a renaming of bits.
    function pack888 (p : pixel_t) return std_logic_vector;

end package pixel_pkg;


package body pixel_pkg is

    function expand6 (v : std_logic_vector(5 downto 0)) return byte_t is
    begin
        return v & v(5 downto 4);
    end function;

    function unpack686 (word : std_logic_vector(19 downto 0)) return pixel_t is
        -- An alias is a name for bits that already exist
        alias r6 : std_logic_vector(5 downto 0) is word(19 downto 14);
        alias g8 : std_logic_vector(7 downto 0) is word(13 downto  6);
        alias b6 : std_logic_vector(5 downto 0) is word( 5 downto  0);
    begin
        -- Green came in whole, so it goes back out whole.
        return (r => expand6(r6),
                g => g8,
                b => expand6(b6));
    end function;

    function pack686 (p : pixel_t) return std_logic_vector is
        -- Keep the top bits of red and blue; expand6 puts them back by
        -- replication on the way out.  Green is stored as it arrived.
        alias r8 : byte_t is p.r;
        alias g8 : byte_t is p.g;
        alias b8 : byte_t is p.b;
    begin
        return r8(7 downto 2) & g8 & b8(7 downto 2);
    end function;

    function unpack888 (word : std_logic_vector(23 downto 0)) return pixel_t is
        variable w : std_logic_vector(23 downto 0) := word;
        alias r8 : std_logic_vector(7 downto 0) is w(23 downto 16);
        alias g8 : std_logic_vector(7 downto 0) is w(15 downto  8);
        alias b8 : std_logic_vector(7 downto 0) is w( 7 downto  0);
    begin
        return (r => r8, g => g8, b => b8);
    end function;

    function pack888 (p : pixel_t) return std_logic_vector is
    begin
        return std_logic_vector(p.r) &
               std_logic_vector(p.g) &
               std_logic_vector(p.b);
    end function;

end package body pixel_pkg;
