library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;


--------------------------------------------------------------------------------
-- Matrix-vector multiplier
--
-- This module rotates each ray by multiplying it by the 3x3 rotation matrix R:
-- o = R * v.  The matrix inputs m00..m22 come from rot_matrix and stay fixed
-- for the whole frame.  The ray inputs v0..v2 come from ray_gen and change for
-- every pixel.  The rotated ray o0..o2 goes to vector_to_angles.
--
-- The matrix elements are Q1.15 fixed point (between -1 and +1).  The ray
-- components are signed integers, in pixels.  mult_fixed(m, v) returns
-- (m * v) / 2^15, rounded, which cancels the matrix's scale factor, so each
-- product, and each output component, is an integer like the ray.
--
-- Each output component is the dot product of one row of R with the ray:
--
--          R (Q1.15)              v (int)       o (int)
--    +-----------------+        +-----+       +-----+
--    | m00   m01   m02 |        | v0  |       | o0  |   o0 = m00*v0 + m01*v1 + m02*v2
--    | m10   m11   m12 |   x    | v1  |   =   | o1  |   o1 = m10*v0 + m11*v1 + m12*v2
--    | m20   m21   m22 |        | v2  |       | o2  |   o2 = m20*v0 + m21*v1 + m22*v2
--    +-----------------+        +-----+       +-----+
--
-- Column j of R is always multiplied by ray component vj.  The work breaks
-- down into the following tasks:
--
--    1. Accept a ray: raise ready_in, and take v0..v2 when valid_in is high.
--       Register row_in and col_in at the same time, so row_out and col_out
--       stay with the ray they belong to.
--
--    2. Multiply: nine products, one per matrix element.  They are
--       independent, so they can all be computed at once (one DSP block each).
--
--          v0          v1          v2
--          |           |           |
--     m00--(x)    m01--(x)    m02--(x)   ->  p00   p01   p02
--     m10--(x)    m11--(x)    m12--(x)   ->  p10   p11   p12
--     m20--(x)    m21--(x)    m22--(x)   ->  p20   p21   p22
--
--    3. Add: sum the three products in each row to get one output component.
--
--     p00 + p01 + p02  ->  o0
--     p10 + p11 + p12  ->  o1
--     p20 + p21 + p22  ->  o2
--
--    4. Send the result: raise valid_out and hold o0..o2 until ready_out is
--       high, then return to accepting the next ray.
--
-- Register the products before adding them, so that no clock cycle contains
-- both a multiply and an add.
--------------------------------------------------------------------------------

entity mat_vec_mult is
    generic (
        TRIG_WIDTH : natural := 16;
        ROW_WIDTH : natural := 10;
        COL_WIDTH : natural := 10
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        valid_in  : in  std_logic;
        ready_in  : out std_logic;

        row_in    : in  std_logic_vector(ROW_WIDTH - 1 downto 0);
        col_in    : in  std_logic_vector(COL_WIDTH - 1 downto 0);
        row_out   : out std_logic_vector(ROW_WIDTH - 1 downto 0);
        col_out   : out std_logic_vector(COL_WIDTH - 1 downto 0);

        m00       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m01       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m02       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m10       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m11       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m12       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m20       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m21       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        m22       : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);

        v0        : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        v1        : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        v2        : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);

        o0        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o1        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o2        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        valid_out : out std_logic;
        ready_out : in std_logic
    );
end entity mat_vec_mult;


architecture rtl of mat_vec_mult is

    ----------------------------------------------------------------------
    -- Constant Declarations
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- Signal Declarations
    ----------------------------------------------------------------------

begin

    ----------------------------------------------------------------------
    --
    -- TODO: Implement a clocked process that resets and registers the 
    -- FSM signals across cycles. 
    --
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    --
    -- TODO: Implement a combinational FSM process that computes o = M * v.  
    --
    --  1. Assert ready_in = '1' and wait for valid_in = '1'.
    --  2. Compute the 9 products in parallel with mult_fixed (from trig_pkg):
    --        p[i,j] = mult_fixed(m[i,j], v[j]) for i, j in 0..2
    --  3. Add the result into each of the 3 output elements:
    --        q[i] = p[i,0] + p[i,1] + p[i,2] for i in 0..2
    --  4. row_out and col_out should be registered copies of row_in and 
    --     col_in, respectively.
    ----------------------------------------------------------------------
    valid_out <= '0';
    ready_in  <= '0';
    o0        <= (others => '0');
    o1        <= (others => '0');
    o2        <= (others => '0');
    row_out   <= row_in;
    col_out   <= col_in;

end architecture rtl;