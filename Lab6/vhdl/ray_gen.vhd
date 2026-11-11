library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;


--------------------------------------------------------------------------------
-- Ray generator
--
-- This module generates rays in a raster scan order, starting from the top-left 
-- corner of the image and proceeding to the bottom-right corner. The rays are 
-- generated in a fixed-point format.
--------------------------------------------------------------------------------

entity ray_gen is
    generic (
        FOCAL_LENGTH : natural := 320;
        TRIG_WIDTH   : natural := 16;
        OUT_WIDTH    : natural := 1024;
        OUT_HEIGHT   : natural := 512;
        COL_WIDTH    : natural := log2(OUT_WIDTH);
        ROW_WIDTH    : natural := log2(OUT_HEIGHT)
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        valid_in  : in  std_logic;
        ready_in : out std_logic;

        o0        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o1        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o2        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        row       : out std_logic_vector(ROW_WIDTH - 1 downto 0);
        col       : out std_logic_vector(COL_WIDTH - 1 downto 0);
        valid_out : out std_logic;
        ready_out : in std_logic
    );
end entity ray_gen;


architecture rtl of ray_gen is

    -----------------------------------------------------------
    -- Constant Declarations
    -----------------------------------------------------------
    constant CENTER_X     : natural := OUT_WIDTH / 2;
    constant CENTER_Y     : natural := OUT_HEIGHT / 2;

    -----------------------------------------------------------
    -- Signal Declarations
    -----------------------------------------------------------


begin

    -----------------------------------------------------------
    -- Clocked process
    --
    -- TODO: implement the clocked process to reset and update 
    -- state and registers on clock edge.
    -----------------------------------------------------------


    -----------------------------------------------------------
    -- Combinational process
    --
    -- TODO: implement the combinational FSM process that implements 
    -- the ray generation algorithm using x,y counters to generate
    -- the following output signals:
    --      row: y coordinate in the output image (0..OUT_HEIGHT-1)
    --      col: x coordinate in the output image (0..OUT_WIDTH-1)
    --      o0: x - CENTER_X
    --      o1: CENTER_Y - y
    --      o2: FOCAL_LENGTH
    --      valid_out: high when the ray is valid
    --      ready_in: high when ready to receive a new frame
    -----------------------------------------------------------

    o0 <= (others => '0');
    o1 <= (others => '0');
    o2 <= (others => '0');
    row <= (others => '0');
    col <= (others => '0');
    valid_out <= '0';
    ready_in <= '0';
    

end architecture rtl;