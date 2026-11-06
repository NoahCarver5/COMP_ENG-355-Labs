

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
	
	type mem_type is array (0 to BRAM_BUFFER_SIZE-1) of std_logic_vector(BRAM_DATA_WIDTH-1 downto 0);
	signal rd_addr_r : std_logic_vector((BRAM_ADDR_WIDTH -1) downto 0);
	signal mem : mem_type;

    ------------------------------------------------------------------------
    -- Type and signal declarations
    ------------------------------------------------------------------------

begin

	dout <= mem(to_integer(unsigned(rd_addr_r)));

	process(clock) begin
		if rising_edge(clock) then
			rd_addr_r <= rd_addr;
			if (wr_en = '1') then
				mem(to_integer(unsigned(wr_addr))) <= din;  
			end if;  
		end if;
	end process;
    ------------------------------------------------------------------------
    -- TODO: Implement the clocked read and write process
    ------------------------------------------------------------------------


end architecture behavior;
