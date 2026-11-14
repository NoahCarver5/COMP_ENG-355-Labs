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
    type state is (IDLE, LOOKUP, TWO_TERM, THREE_TERM, ASSEMBLE, READY);
    --------------------------------------------------------------------------------
    -- Signal Declarations
    --------------------------------------------------------------------------------

    signal ready_in_reg, ready_in_c : std_logic;
    signal valid_out_reg, valid_out_c : std_logic;
    signal cur_state : state;
    signal next_state : state;

    signal rx_r, ry_r, rz_r, rx_c, ry_c, rz_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cx_c, sx_c, cy_c, sy_c, sz_c, cz_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cx_r, sx_r, cy_r, sy_r, sz_r, cz_r : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cy_cz_c, cy_sz_c, cy_sx_c, cy_cx_c, cz_sx_c, sz_sx_c, sz_cx_c, cz_cx_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cy_cz_r, cy_sz_r, cy_sx_r, cy_cx_r, cz_sx_r, sz_sx_r, sz_cx_r, cz_cx_r : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cz_sy_sx_c, sz_sy_sx_c, cz_sy_cx_c, sz_sy_cx_c : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal cz_sy_sx_r, sz_sy_sx_r, cz_sy_cx_r, sz_sy_cx_r : std_logic_vector (ANGLE_WIDTH-1 downto 0);
    signal r00_c, r01_c, r02_c, r10_c, r11_c, r12_c, r20_c, r21_c, r22_c : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal r00_r, r01_r, r02_r, r10_r, r11_r, r12_r, r20_r, r21_r, r22_r: std_logic_vector(TRIG_WIDTH - 1 downto 0);





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

    ready_in <= ready_in_reg;
    valid_out <= valid_out_reg;
    r00 <= r00_r;
    r01 <= r01_r;
    r02 <= r02_r;
    r10 <= r10_r;
    r11 <= r11_r;
    r12 <= r12_r;
    r20 <= r20_r;
    r21 <= r21_r;
    r22 <= r22_r;

    rot_matrix_clocked : process(reset, clk) is   
    begin
        if (reset = '1') then
            cur_state <= IDLE;
            ready_in_reg <= '1';
            valid_out_reg <= '0';
            
            rx_r <= (others=>'1');
            ry_r <= (others=>'1');
            rz_r <= (others=>'1');

            cx_r <= (others=>'1');
            cy_r <= (others=>'1');
            cz_r <= (others=>'1');
            sx_r <= (others=>'1');
            sy_r <= (others=>'1');
            sz_r <= (others=>'1');

            cy_cz_r <= (others=>'1');
            cy_cx_r <= (others=>'1');
            cy_sx_r <= (others=>'1');
            cy_sz_r <= (others=>'1');
            sz_cx_r <= (others=>'1');
            sz_sx_r <= (others=>'1');
            cz_cx_r <= (others=>'1');
            cz_sx_r <= (others=>'1');

            cz_sy_cx_r <= (others=>'1');
            sz_sy_sx_r <= (others=>'1');
            cz_sy_sx_r <= (others=>'1');
            sz_sy_cx_r <= (others=>'1');
                        
            r00_r <= (others=>'1');
            r01_r <= (others=>'1');
            r02_r <= (others=>'1');
            r10_r <= (others=>'1');
            r11_r <= (others=>'1');
            r12_r <= (others=>'1');
            r20_r <= (others=>'1');
            r21_r <= (others=>'1');
            r22_r <= (others=>'1');


        elsif (rising_edge(clk)) then

            ready_in_reg <= ready_in_c;
            valid_out_reg <= valid_out_c;

            rx_r <= rx_c;
            ry_r <= ry_c;
            rz_r <= rz_c;

            cx_r <= cx_c;
            cy_r <= cy_c;
            cz_r <= cz_c;
            sx_r <= sx_c;
            sy_r <= sy_c;
            sz_r <= sz_c;

            cy_cz_r <= cy_cz_c;
            cy_cx_r <= cy_cx_c;
            cy_sx_r <= cy_sx_c;
            cy_sz_r <= cy_sz_c;
            sz_cx_r <= sz_cx_c;
            sz_sx_r <= sz_sx_c;
            cz_cx_r <= cz_cx_c;
            cz_sx_r <= cz_sx_c;

            cz_sy_cx_r <= cz_sy_cx_c;
            sz_sy_sx_r <= sz_sy_sx_c;
            cz_sy_sx_r <= cz_sy_sx_c;
            sz_sy_cx_r <= sz_sy_cx_c;

            r00_r <= r00_c;
            r01_r <= r01_c;
            r02_r <= r02_c;
            r10_r <= r10_c;
            r11_r <= r11_c;
            r12_r <= r12_c;
            r20_r <= r20_c;
            r21_r <= r21_c;
            r22_r <= r22_c;
            cur_state <= next_state;
        end if;
    end process;


    rot_matrix_fsm:  process(all) is begin

        ready_in_c <= ready_in_reg;
        valid_out_c <= valid_out_reg;

        rx_c <= rx_r;
        ry_c <= ry_r;
        rz_c <= rz_r;

        cx_c <= cx_r;
        cy_c <= cy_r;
        cz_c <= cz_r;
        sx_c <= sx_r;
        sy_c <= sy_r;
        sz_c <= sz_r;

        cy_cz_c <= cy_cz_r;
        cy_cx_c <= cy_cx_r;
        cy_sx_c <= cy_sx_r;
        cy_sz_c <= cy_sz_r;
        sz_cx_c <= sz_cx_r;
        sz_sx_c <= sz_sx_r;
        cz_cx_c <= cz_cx_r;
        cz_sx_c <= cz_sx_r;

        cz_sy_cx_c <= cz_sy_cx_r;
        sz_sy_sx_c <= sz_sy_sx_r;
        cz_sy_sx_c <= cz_sy_sx_r;
        sz_sy_cx_c <= sz_sy_cx_r;

        r00_c <= r00_r;
        r01_c <= r01_r;
        r02_c <= r02_r;
        r10_c <= r10_r;
        r11_c <= r11_r;
        r12_c <= r12_r;
        r20_c <= r20_r;
        r21_c <= r21_r;
        r22_c <= r22_r;

        next_state <= cur_state;


        case cur_state is
            when IDLE =>
                if (valid_in = '1') then 
                    next_state <= LOOKUP;
                    ready_in_c <= '0';
                else 
                    next_state <= IDLE;
                    ready_in_c <= '1';
                end if;
                rx_c <= rx;
                ry_c <= ry;  
                rz_c <= rz;
            when LOOKUP =>
                
                cx_c <= cos_lut(rx_r);
                cy_c <= cos_lut(ry_r);
                cz_c <= cos_lut(rz_r);

                sx_c <= sin_lut(rx_r);
                sy_c <= sin_lut(ry_r);
                sz_c <= sin_lut(rz_r);

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

            when THREE_TERM =>

                cz_sy_cx_c <= mult_fixed(cz_cx_r, sy_r);
                sz_sy_sx_c <= mult_fixed(sz_sx_r, sy_r);
                cz_sy_sx_c <= mult_fixed(cz_sx_r, sy_r);
                sz_sy_cx_c <= mult_fixed(sz_cx_r, sy_r);

                next_state <= ASSEMBLE;

            when ASSEMBLE =>

                r00_c <= cy_cz_r;
                r01_c <= std_logic_vector(signed(cz_sy_sx_r) - signed(sz_cx_r));
                r02_c <= std_logic_vector(signed(cz_sy_cx_r) + signed(sz_sx_r));
                r10_c <= cy_sz_r;
                r11_c <= std_logic_vector(signed(sz_sy_sx_r) + signed(cz_cx_r));
                r12_c <= std_logic_vector(signed(sz_sy_cx_r) - signed(cz_sx_r));
                r20_c <= std_logic_vector(0 - signed(sy_r));
                r21_c <= cy_sx_r;
                r22_c <= cy_cx_r;

                valid_out_c <= '1';

                next_state <= READY;

            when READY =>

                if (ready_out) then
                    valid_out_c <= '0';
                    ready_in_c <= '1';
                    next_state <= IDLE;
                else
                    next_state <= READY;
                end if;
        
        end case;

    end process;
                

end architecture rtl;