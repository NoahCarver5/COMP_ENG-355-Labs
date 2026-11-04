

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

--------------------------------------------------------------------------
-- Simple dual-port block RAM: one write port, one read port, one clock.
--
-- Read latency: ONE clock.  The read address is registered, and the
-- memory lookup itself is combinational.  Read that number out of this
-- file rather than guessing it -- everything downstream depends on it.
--
-- The array is sized from BRAM_BUFFER_SIZE, not 2**BRAM_ADDR_WIDTH.  At
-- 20 bits wide that is the difference between a 640x480 frame costing
-- 6.14 Mbit and a full 2**19 addresses costing 10.5 Mbit -- and the
-- device only has 7.33 Mbit, so sizing it the lazy way does not fit.
--------------------------------------------------------------------------
entity bram is
generic
(
	constant BRAM_BUFFER_SIZE : integer := 1024;
	constant BRAM_ADDR_WIDTH : integer := 10;
	constant BRAM_DATA_WIDTH : integer := 32
);
port
(
	signal clock : in std_logic;
	signal rd_addr : in std_logic_vector ((BRAM_ADDR_WIDTH - 1) downto 0);
	signal wr_addr : in std_logic_vector ((BRAM_ADDR_WIDTH - 1) downto 0);
	signal wr_en : in std_logic;
	signal dout : out std_logic_vector ((BRAM_DATA_WIDTH - 1) downto 0);
	signal din : in std_logic_vector ((BRAM_DATA_WIDTH - 1) downto 0)
);
end entity bram;


architecture behavior of bram is 
    ------------------------------------------------------------------------
    -- Type and signal declarations
    ------------------------------------------------------------------------

begin

    ------------------------------------------------------------------------
    -- TODO: Implement the clocked read and write process
    ------------------------------------------------------------------------


end architecture behavior;
