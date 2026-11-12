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
    type state is (IDLE, LOOKUP, TWO_TERM, THREE_TERM, ASSEMBLE);
    --------------------------------------------------------------------------------
    -- Signal Declarations
    --------------------------------------------------------------------------------

    signal ready_in_reg : std_logic;
    signal cur_state : state;
    signal next_state : state;

    signal cx_c, sx_c, cy_c, sy_c, sz_c, cz_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cx_r, sx_r, cy_r, sy_r, sz_r, cz_r : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cy_cz_c, cy_sz_c, cy_sx_c, cy_cx_c, cz_sx_c, sz_sx_c, sz_cx_c, cz_cx_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal r00_c, r01_c, r02_c, r10_c, r11_c, r12_c, r20_c, r21_c, r22_c : std_logic_vector(TRIG_WIDTH - 1 downto 0);



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

    rot_matrix_fsm:  process(valid_in) is begin

        ready_in_reg <= '0';

        case cur_state is
            when IDLE =>
                if (valid_in = '1') then next_state <= LOOKUP;
                else next_state <= IDLE;
                end if;
                ready_in_reg <= '1';
            when LOOKUP =>
                
                cx_c <= cos_lut(rx);
                cy_c <= cos_lut(ry);
                cz_c <= cos_lut(rz);

                sx_c <= sin_lut(rx);
                sy_c <= sin_lut(ry);
                sz_c <= sin_lut(rz);

                next_state <= TWO_TERM;

            when TWO_TERM =>

                cy_cz_c <= mult_fixed(cy_r, cz_r);
                cy_cx_c <= mult_fixed(cy_r, cx_r);
                cy_sx_c <= mult_fixed(cy_r, sx_r);
                cy_sz_c <= mult_fixed(cy_r, sz_r);
                sz_cx_c <= mult_fixed(sz_r, cx_r);
                sz_sx_c <= mult_fixed(sz_r, sx_r);
                cz_cx_c <= mult_fixed(cz_r, cx_r);
                cz_sx_c <= mult_fixed(cz_r, sx_r);

                next_state <= THREE_TERM;

            when THREE_TER<

                

        end case;

    end process;
                

end architecture rtl;