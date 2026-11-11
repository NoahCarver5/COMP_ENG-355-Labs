library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;

--------------------------------------------------------------------------------
-- Rotation matrix generator
--
-- This module generates a 3x3 rotation matrix from three input angles: Rx, Ry, Rz.
-- The angles are specified in fixed-point format, with the binary point between 
-- bits ANGLE_WIDTH-1 and ANGLE_WIDTH-2.  The output rotation matrix is also in 
-- fixed-point format, with  binary point between bits TRIG_WIDTH-1 and TRIG_WIDTH-2.  
-- The rotation matrix is generated using the following formula: R = Rz * Ry * Rx
--------------------------------------------------------------------------------

entity rot_matrix is
    generic (
        ANGLE_WIDTH : natural := 16;
        TRIG_WIDTH  : natural := 16
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        rx        : in  std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        ry        : in  std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        rz        : in  std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        valid_in  : in  std_logic;
        ready_in : out std_logic;

        r00       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r01       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r02       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r10       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r11       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r12       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r20       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r21       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        r22       : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        valid_out : out std_logic;
        ready_out : in std_logic
    );
end entity rot_matrix;


architecture rtl of rot_matrix is

    --------------------------------------------------------------------------------
    -- Constant Declarations
    --------------------------------------------------------------------------------

    --------------------------------------------------------------------------------
    -- Signal Declarations
    --------------------------------------------------------------------------------


begin

    --------------------------------------------------------------------------------
    -- Clocked process
    --
    -- TODO: implement the clocked process to reset and update 
    -- state and registers on clock edge.
    --------------------------------------------------------------------------------


    --------------------------------------------------------------------------------
    -- Combinational process
    --
    -- TODO: implement the combinational FSM process that 
    -- implements the rotation matrix algorithm using sine and 
    -- cosine values to generate the following output rotation 
    -- matrix signals:
    --      r00, r01, r02, r10, r11, r12, r20, r21, r22: the 3x3 rotation matrix
    --      valid_out: high when the rotation matrix is valid
    --      ready_in: high when ready to receive a new set of angles
    --
    -- The algorithm should be split across several states to ensure that timing
    -- requirements are met. The matrix operations are implemented as follows.
    --
    -- Shorthand:  
    --      sx = sin(rx), cx = cos(rx)
    --      sy = sin(ry), cy = cos(ry)
    --      sz = sin(rz), cz = cos(rz)
    --
    -- One rotation about each axis:
    --
    --          | 1   0    0  |        |  cy  0  sy |        | cz  -sz  0 |
    --     Rx = | 0   cx  -sx |   Ry = |  0   1  0  |   Rz = | sz   cz  0 |
    --          | 0   sx   cx |        | -sy  0  cy |        | 0    0   1 |
    --
    -- The full rotation applies Rx first, then Ry, then Rz:
    --
    --     R = Rz * Ry * Rx
    --
    --       | r00 r01 r02 |   | cy*cz   cz*sy*sx - sz*cx   cz*sy*cx + sz*sx |
    --     = | r10 r11 r12 | = | cy*sz   sz*sy*sx + cz*cx   sz*sy*cx - cz*sx |
    --       | r20 r21 r22 |   | -sy     cy*sx              cy*cx            |
    --
    -- For sin and cos, use the provided sin_lut() and cos_lut() functions. 
    -- For multiplication, use the provided mult_fixed() function.  The result
    -- of mult_fixed() is 2**TRIG_WIDTH too large, so the result must be shifted 
    -- right by TRIG_WIDTH bits to get the correct value.
    --------------------------------------------------------------------------------

    r00 <= (others => '0');
    r01 <= (others => '0');
    r02 <= (others => '0');
    r10 <= (others => '0');
    r11 <= (others => '0');
    r12 <= (others => '0');
    r20 <= (others => '0');
    r21 <= (others => '0');
    r22 <= (others => '0');
    valid_out <= '0';
    ready_in <= '0';

end architecture rtl;