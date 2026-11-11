library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;


--------------------------------------------------------------------------------
-- Vector to angles converter
--
-- This module converts a 3D vector (x, y, z) into spherical coordinates
-- (longitude, latitude).  The input vector is specified in fixed-point format.
--------------------------------------------------------------------------------

entity vector_to_angles is
    generic (
        TRIG_WIDTH   : natural := 16;
        ANGLE_WIDTH  : natural := 16;
        ROW_WIDTH    : natural := 10;
        COL_WIDTH    : natural := 10;

        -- Output frame geometry, used only to bound the largest possible
        -- MAGNITUDE_SQ so the SQRT LUT can be scaled by shifts alone.
        OUT_WIDTH    : natural := 1024;
        OUT_HEIGHT   : natural := 512;
        FOCAL_LENGTH : natural := 320
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        x         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        y         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        z         : in  std_logic_vector(TRIG_WIDTH - 1 downto 0);
        valid_in  : in  std_logic;
        ready_in  : out std_logic;

        row_in    : in  std_logic_vector(ROW_WIDTH - 1 downto 0);
        col_in    : in  std_logic_vector(COL_WIDTH - 1 downto 0);
        row_out   : out std_logic_vector(ROW_WIDTH - 1 downto 0);
        col_out   : out std_logic_vector(COL_WIDTH - 1 downto 0);

        longitude : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        latitude  : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
        valid_out : out std_logic;
        ready_out : in  std_logic
    );
end entity vector_to_angles;


architecture rtl of vector_to_angles is

    --------------------------------------------------------------------
    -- Number of bits required to hold value, rounded up to an even count.
    --
    --   bit_length(3)       = 2
    --   bit_length(589823)  = 20
    --   bit_length(589824)  = 20
    --   bit_length(1048576) = 22
    --
    -- 2**bit_length(v) is always strictly greater than v, and the even
    -- result makes sqrt(2**bit_length(v)) an exact shift.
    --------------------------------------------------------------------
    function bit_length(value : natural) return natural is
        variable v      : natural := value;
        variable result : natural := 0;
    begin
        while v > 0 loop
            v := v / 2;
            result := result + 1;
        end loop;

        if (result mod 2) = 1 then
            result := result + 1;
        end if;

        return result;
    end function;

    --------------------------------------------------------------------
    -- Angle constants
    --
    -- 16-bit angle representation:
    --
    --   0x0000 =   0 degrees
    --   0x2000 =  45 degrees
    --   0x4000 =  90 degrees
    --   0x6000 = 135 degrees
    --   0x8000 = 180 degrees
    --   0xA000 = -135 degrees
    --   0xC000 = -90 degrees
    --------------------------------------------------------------------
    constant HALF_TURN : unsigned(ANGLE_WIDTH - 1 downto 0) := to_unsigned(2**(ANGLE_WIDTH - 1), ANGLE_WIDTH);
    constant QUARTER_TURN : unsigned(ANGLE_WIDTH - 1 downto 0) := to_unsigned(2**(ANGLE_WIDTH - 2), ANGLE_WIDTH);
    constant MAG_SQ_WIDTH : natural := 2 * TRIG_WIDTH + 2;

    --------------------------------------------------------------------
    -- SQRT LUT scaling
    --
    -- The SQRT LUT maps a normalized input 0..1 (address 0..LUT_SIZE-1)
    -- to sqrt(input) in Q1.(TRIG_WIDTH-1).
    --
    -- To use it on MAGNITUDE_SQ = x*x + y*y + z*z, the magnitude squared
    -- is normalized by the smallest power of two larger than its maximum
    -- possible value, and that has an EVEN exponent.  An even exponent is
    -- required so that
    --
    --     sqrt(2**e) = 2**(e/2)
    --
    -- is exact, which makes both the LUT input scaling and the LUT output
    -- scaling plain shifts.
    --
    -- ray_gen emits x in -CENTER_X .. OUT_WIDTH-1-CENTER_X, y likewise
    -- from the row, and a constant z = FOCAL_LENGTH.  The rotation in
    -- mat_vec_mult preserves the vector length, so the rotated ray that
    -- arrives here has the same bound as the camera-space ray.
    --------------------------------------------------------------------
    constant MAX_X : natural := smax(OUT_WIDTH / 2, OUT_WIDTH - 1 - (OUT_WIDTH / 2));
    constant MAX_Y : natural := smax(OUT_HEIGHT / 2, OUT_HEIGHT - 1 - (OUT_HEIGHT / 2));
    constant MAX_MAG_SQ : natural := MAX_X * MAX_X + MAX_Y * MAX_Y + FOCAL_LENGTH * FOCAL_LENGTH;
    constant SQRT_INPUT_SHIFT  : natural := smax(2, bit_length(MAX_MAG_SQ));
    constant SQRT_OUTPUT_SHIFT : natural := SQRT_INPUT_SHIFT / 2;
    constant SQRT_PROD_WIDTH : natural := MAG_SQ_WIDTH + LUT_BITS;
    constant MAG_PROD_WIDTH  : natural := TRIG_WIDTH + SQRT_OUTPUT_SHIFT;

    --------------------------------------------------------------------
    -- Fixed-point square root.
    --
    --   index     = (MAGNITUDE_SQ * (LUT_SIZE-1) + 2**(e-1)) >> e
    --   root      = SQRT_ROM(index)            -- Q1.(TRIG_WIDTH-1)
    --   magnitude = (root << (e/2) + 2**(TRIG_WIDTH-2)) >> (TRIG_WIDTH-1)
    --
    -- with e = SQRT_INPUT_SHIFT.  Multiply, add and shift only; no
    -- division and no real arithmetic.
    --------------------------------------------------------------------
    function sqrt_fixed(
        magnitude_sq : unsigned(MAG_SQ_WIDTH - 1 downto 0)
    ) return unsigned is
        variable scaled  : unsigned(SQRT_PROD_WIDTH - 1 downto 0);
        variable address : std_logic_vector(LUT_BITS - 1 downto 0);
        variable root    : unsigned(MAG_PROD_WIDTH - 1 downto 0);
    begin
        -- Normalize MAGNITUDE_SQ to the LUT address range, with rounding.
        scaled := magnitude_sq * to_unsigned(LUT_SIZE - 1, LUT_BITS);
        scaled := shift_right(
            scaled + to_unsigned(2**(SQRT_INPUT_SHIFT - 1), SQRT_PROD_WIDTH),
            SQRT_INPUT_SHIFT
        );

        -- Rounding in mat_vec_mult can push the rotated vector a little
        -- past the bound, so saturate rather than wrap.
        address := std_logic_vector(resize(
            umin(scaled, to_unsigned(LUT_SIZE - 1, SQRT_PROD_WIDTH)),
            LUT_BITS
        ));

        -- Undo the normalization, then drop the Q1.(TRIG_WIDTH-1) bits.
        root := resize(unsigned(sqrt_lut(address)), MAG_PROD_WIDTH);
        root := shift_left(root, SQRT_OUTPUT_SHIFT) +
                to_unsigned(2**(TRIG_WIDTH - 2), MAG_PROD_WIDTH);

        return resize(shift_right(root, TRIG_WIDTH - 1), TRIG_WIDTH);
    end function;

    --------------------------------------------------------------------
    -- Normalize a ratio into a LUT address.
    --
    --     address = numerator / denominator * LUT_SIZE,  saturated
    --
    -- numerator = denominator maps to LUT_SIZE-1, which the LUT treats
    -- as 1.0.  A numerator above the denominator saturates rather than
    -- wrapping, and a zero denominator returns address 0.
    --
    -- NO DIVISION.  This used to be a literal "scaled / denominator",
    -- and with a variable denominator that is a full restoring divider
    -- -- about 39 ns of ripple, against a 20 ns budget at 50 MHz.  It
    -- was the critical path of the whole design and no amount of
    -- registering around it helped, because the delay was in computing
    -- the ROM's address rather than in the ROM.
    --
    -- Instead: shift the denominator until it has exactly LUT_BITS
    -- significant bits, look its reciprocal up, and multiply.  A
    -- multiply is a DSP block.
    --
    --     d = denominator, with b = bit_length(d)
    --     dn = d normalized to [LUT_SIZE/2, LUT_SIZE-1]
    --     RECIP_ROM(dn) = 2**RECIP_SHIFT / dn
    --
    --     numerator/d ~= numerator * RECIP_ROM(dn) / 2**(RECIP_SHIFT + b - LUT_BITS)
    --
    -- so multiplying by LUT_SIZE = 2**LUT_BITS to get the address
    -- leaves a shift of RECIP_SHIFT + b - 2*LUT_BITS.  Every term is a
    -- shift or a multiply.
    --
    -- The cost is accuracy: dn keeps only LUT_BITS bits of the
    -- denominator, so the answer can differ from a true divide.
    -- Measured over 400k random pairs, the worst case is 2 LSB and 98%
    -- are within 1.  One LSB of this address is 45/1024 = 0.044 deg on
    -- the atan LUT, against 0.14 deg per pixel of viewport, so the
    -- worst case lands inside a single pixel.
    --------------------------------------------------------------------
    function lut_address(
        numerator   : unsigned;
        denominator : unsigned
    ) return std_logic_vector is
        constant PROD_WIDTH : natural := numerator'length + TRIG_WIDTH + 1;
        variable bits   : natural;
        variable dn     : unsigned(LUT_BITS - 1 downto 0);
        variable norm   : unsigned(denominator'length + LUT_BITS - 1 downto 0);
        variable prod   : unsigned(PROD_WIDTH - 1 downto 0);
        variable shift  : integer;
    begin
        if denominator = 0 then
            return std_logic_vector(to_unsigned(0, LUT_BITS));
        end if;

        -- How many significant bits the denominator has.
        bits := 0;
        for i in denominator'range loop
            if denominator(i) = '1' then
                bits := i + 1;
                exit;
            end if;
        end loop;

        -- Normalize to exactly LUT_BITS significant bits, rounding
        -- rather than truncating -- it halves the error for free, and
        -- the saturate below covers the carry out of the top.
        norm := resize(denominator, norm'length);
        if bits > LUT_BITS then
            norm := shift_right(
                norm + to_unsigned(2**(bits - LUT_BITS - 1), norm'length),
                bits - LUT_BITS
            );
        elsif bits < LUT_BITS then
            norm := shift_left(norm, LUT_BITS - bits);
        end if;
        dn := resize(umin(norm, to_unsigned(LUT_SIZE - 1, norm'length)), LUT_BITS);

        -- numerator'length + TRIG_WIDTH bits of product, which is why
        -- PROD_WIDTH is one more than that.  Resize the result, not the
        -- operands: multiplying two PROD_WIDTH values would give twice
        -- that and Quartus rejects the truncation.
        prod := resize(
            numerator * unsigned(reciprocal_lut(std_logic_vector(dn))),
            PROD_WIDTH
        );

        shift := RECIP_SHIFT + bits - 2*LUT_BITS;
        if shift > 0 then
            prod := shift_right(
                prod + to_unsigned(2**(shift - 1), PROD_WIDTH),
                shift
            );
        elsif shift < 0 then
            prod := shift_left(prod, -shift);
        end if;

        return std_logic_vector(resize(
            umin(prod, to_unsigned(LUT_SIZE - 1, PROD_WIDTH)),
            LUT_BITS
        ));
    end function;

    --------------------------------------------------------------------
    -- atan(|numerator| / |denominator|), as an angle.
    --
    -- Valid for |numerator| <= |denominator|; the caller reduces the
    -- octant so the smaller magnitude is always the numerator.
    --------------------------------------------------------------------
    function atan_ratio(
        numerator   : std_logic_vector;
        denominator : std_logic_vector
    ) return unsigned is
    begin
        return resize(unsigned(atan_lut(lut_address(
            unsigned(abs_val(numerator)),
            unsigned(abs_val(denominator))
        ))), ANGLE_WIDTH);
    end function;

    --------------------------------------------------------------------
    -- asin(|numerator| / denominator), as an angle.
    --------------------------------------------------------------------
    function asin_ratio(
        numerator   : std_logic_vector;
        denominator : std_logic_vector
    ) return unsigned is
    begin
        return resize(unsigned(asin_lut(lut_address(
            unsigned(abs_val(numerator)),
            unsigned(denominator)
        ))), ANGLE_WIDTH);
    end function;

    --------------------------------------------------------------------
    -- Signals
    --
    -- THREE STATES, AND WHY.  The long path here is lut_address: it
    -- divides by a variable denominator, and the quotient then indexes a
    -- ROM.  Doing that and the octant arithmetic in one state does not
    -- close timing, so each lookup gets a state to itself and the state
    -- that assembles the answer sees only registered ROM outputs.
    --
    --   S0   magnitude, and the atan lookup
    --   S1   the asin lookup
    --   S2   signs and octants -- muxes and adds, nothing deep
    --
    -- The two lookups cannot share a state.  atan needs only x and z,
    -- which are inputs, but asin needs the magnitude, so it cannot start
    -- until S0 has finished.  That dependency is what forces the third
    -- state rather than any shortage of logic.
    --
    -- S0 runs the square root and the atan lookup at the same time, not
    -- one after the other, so the state costs the longer of the two
    -- rather than their sum.
    --------------------------------------------------------------------
    type state_t is (S0, S1, S2);
    signal state, next_state : state_t;

    signal mag, mag_c : std_logic_vector(TRIG_WIDTH - 1 downto 0);
    signal q_longitude, q_longitude_c : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal q_latitude, q_latitude_c : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal valid, valid_c : std_logic;

    --------------------------------------------------------------------
    -- Registered ROM outputs, and the handful of facts about the input
    -- vector that S2 needs to place them in the right octant.
    --
    -- The signs are captured in S0 rather than read from x, y and z in
    -- S2.  The inputs do hold still while ready_in is low, so reading
    -- them late would work, but registering them keeps everything S2
    -- depends on in flip-flops and leaves no path back to the ports.
    --------------------------------------------------------------------
    signal atan_val, atan_val_c : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal asin_val, asin_val_c : std_logic_vector(ANGLE_WIDTH - 1 downto 0);

    signal lon_swap, lon_swap_c : std_logic;   -- |x| > |z|, so the ratio was inverted
    signal z_zero,  z_zero_c    : std_logic;
    signal z_neg,   z_neg_c     : std_logic;
    signal x_neg,   x_neg_c     : std_logic;
    signal y_neg,   y_neg_c     : std_logic;

begin

    longitude <= q_longitude;
    latitude <= q_latitude;
    valid_out <= valid;

    clocked_process: process(clk, reset)
    begin
        if reset = '1' then
            state <= S0;
            mag <= (others => '0');
            q_longitude <= (others => '0');
            q_latitude <= (others => '0');
            row_out <= (others => '0');
            col_out <= (others => '0');
            valid <= '0';
            atan_val <= (others => '0');
            asin_val <= (others => '0');
            lon_swap <= '0';
            z_zero   <= '0';
            z_neg    <= '0';
            x_neg    <= '0';
            y_neg    <= '0';
        elsif rising_edge(clk) then
            state <= next_state;
            mag <= mag_c;
            q_longitude <= q_longitude_c;
            q_latitude <= q_latitude_c;

            atan_val <= atan_val_c;
            asin_val <= asin_val_c;
            lon_swap <= lon_swap_c;
            z_zero   <= z_zero_c;
            z_neg    <= z_neg_c;
            x_neg    <= x_neg_c;
            y_neg    <= y_neg_c;

            if (state = S0 and valid_in = '1') then
                row_out <= row_in;
                col_out <= col_in;
            end if;
            valid <= valid_c;
        end if;
    end process;


    --------------------------------------------------------------------
    -- Combinational FSM
    --------------------------------------------------------------------

    fsm_process : process(all)

        variable lon_u : unsigned(ANGLE_WIDTH - 1 downto 0);
        variable lat_u : unsigned(ANGLE_WIDTH - 1 downto 0);

        -- The atan LUT covers atan(0..1) only, so the smaller magnitude
        -- has to be the numerator.  Picking the pair first and dividing
        -- once is one divider; calling atan_ratio in both arms of the
        -- test would be two.
        variable num_v : std_logic_vector(TRIG_WIDTH - 1 downto 0);
        variable den_v : std_logic_vector(TRIG_WIDTH - 1 downto 0);

    begin

        next_state <= state;
        mag_c <= mag;
        q_longitude_c <= q_longitude;
        q_latitude_c <= q_latitude;
        valid_c <= valid;
        ready_in <= '0';

        atan_val_c <= atan_val;
        asin_val_c <= asin_val;
        lon_swap_c <= lon_swap;
        z_zero_c   <= z_zero;
        z_neg_c    <= z_neg;
        x_neg_c    <= x_neg;
        y_neg_c    <= y_neg;

        case state is

            --------------------------------------------------------
            -- S0: Capture the vector and compute its magnitude.
            --------------------------------------------------------
            when S0 =>
                valid_c <= '0';
                ready_in <= '1';

                if valid_in = '1' then
                    -- MAGNITUDE = sqrt(x*x + y*y + z*z).  Squaring is
                    -- sign independent, and MAG_SQ_WIDTH holds the sum
                    -- of three 2*TRIG_WIDTH products without overflow,
                    -- so the sum is never negative.
                    mag_c <= std_logic_vector(sqrt_fixed(unsigned(
                        resize(signed(x) * signed(x), MAG_SQ_WIDTH) +
                        resize(signed(y) * signed(y), MAG_SQ_WIDTH) +
                        resize(signed(z) * signed(z), MAG_SQ_WIDTH)
                    )));

                    -- atan(x, z), alongside the square root rather than
                    -- after it: it needs x and z, which are already
                    -- here, so it does not have to wait for MAGNITUDE.
                    if unsigned(abs_val(x)) <= unsigned(abs_val(z)) then
                        num_v := x;
                        den_v := z;
                        lon_swap_c <= '0';
                    else
                        num_v := z;
                        den_v := x;
                        lon_swap_c <= '1';
                    end if;
                    atan_val_c <= std_logic_vector(atan_ratio(num_v, den_v));

                    -- What S2 needs to know about the input vector,
                    -- captured while it is in front of us.
                    if signed(z) = 0 then z_zero_c <= '1'; else z_zero_c <= '0'; end if;
                    if signed(z) < 0 then z_neg_c  <= '1'; else z_neg_c  <= '0'; end if;
                    if signed(x) < 0 then x_neg_c  <= '1'; else x_neg_c  <= '0'; end if;
                    if signed(y) < 0 then y_neg_c  <= '1'; else y_neg_c  <= '0'; end if;

                    next_state <= S1;
                end if;

            --------------------------------------------------------
            -- S1: The asin lookup, on the magnitude S0 registered.
            --     Nothing else happens here -- the divide and the ROM
            --     are the whole state.
            --------------------------------------------------------
            when S1 =>
                asin_val_c <= std_logic_vector(asin_ratio(y, mag));
                next_state <= S2;

            --------------------------------------------------------
            -- S2: Place the two registered lookups in the right octant
            --     and emit them.
            --
            --     Every input to this state is a flip-flop: the two ROM
            --     outputs, the magnitude, and the four sign flags.  No
            --     divide, no ROM, no multiply -- a mux and a couple of
            --     16-bit adds, which is the point of the exercise.
            --------------------------------------------------------
            when S2 =>
                lon_u := (others => '0');
                lat_u := (others => '0');

                -- A zero vector, or a magnitude that rounds to zero,
                -- carries no usable direction.
                if unsigned(mag) /= 0 then

                    -- atan2(x, z), reassembled from the ratio S0 took.
                    if z_zero = '1' then
                        lon_u := QUARTER_TURN;
                    elsif lon_swap = '0' then
                        lon_u := unsigned(atan_val);
                    else
                        lon_u := QUARTER_TURN - unsigned(atan_val);
                    end if;

                    if z_neg = '1' then
                        lon_u := HALF_TURN - lon_u;
                    end if;
                    if x_neg = '1' then
                        lon_u := 0 - lon_u;
                    end if;

                    lat_u := unsigned(asin_val);
                    if y_neg = '1' then
                        lat_u := 0 - lat_u;
                    end if;
                end if;

                q_longitude_c <= std_logic_vector(lon_u);
                q_latitude_c <= std_logic_vector(lat_u);
                valid_c <= '1';

                if ready_out = '1' then
                    next_state <= S0;
                end if;

        end case;
    end process;

end architecture rtl;