library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- IMU orientation, over the module's UART.
--
-- Yahboom 9-axis IMU.  The module free-runs, streaming frames from the
-- moment it powers up -- 25 Hz by default -- so there is no command to
-- send and uart_tx is not wired.  Changing the output rate or the
-- algorithm type needs the host-to-module half of the protocol, which
-- is not implemented here because the defaults are usable.
--
-- FRAME FORMAT -- VARIABLE LENGTH
--
--     0   0x7E            header, first byte
--     1   0x23            header, second byte
--     2   LENGTH          TOTAL bytes in the frame, this one included
--     3   FUNCTION        which message this is
--     4   ..              payload, LENGTH-5 bytes
--         LENGTH-1        SUM, low 8 bits of every byte before it
--
-- The length byte is what ends a frame; there is no terminator.  The
-- module sends several FUNCTIONs and only 0x26 is wanted here, so the
-- rest are counted through to keep the parser aligned and then dropped.
--
-- EULER ANGLES -- FUNCTION 0x26, LENGTH 0x11
--
--     4..7    ROLL     32-bit float, little endian
--     8..11   PITCH
--    12..15   YAW
--
-- IEEE-754 SINGLES IN RADIANS, which is the part that costs real logic.
-- trig_pkg wants binary angle measure, where the whole 16-bit range is
-- one turn, so every angle has to be unpacked and rescaled:
--
--     BAM = radians * 65536 / (2*pi) = radians * 10430.38
--
-- See float_to_bam below.
--
-- AN EARLIER VERSION OF THIS FILE SPOKE A DIFFERENT PROTOCOL -- a 0x55
-- header carrying 16-bit fixed point that happened to already BE binary
-- angle measure, so it needed no conversion at all.  That protocol
-- belongs to a different module in the same family.  The giveaway was
-- bytes arriving cleanly at the right baud while no frame ever passed
-- its checksum: the UART was fine and the parser was reading a format
-- that was not on the wire.
--------------------------------------------------------------------------
entity imu is
    generic (
        CLK_FREQ    : natural := 50_000_000;

        -- Must match the module.  Changing the module's rate needs the
        -- transmit half of the protocol, which is not here.
        BAUD_RATE   : natural := 115_200;

        ANGLE_WIDTH : natural := 16
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;

        -- Serial in from the module.  Idles high; asynchronous to clk.
        uart_rx    : in  std_logic;

        rx         : out std_logic_vector(ANGLE_WIDTH-1 downto 0);  -- roll
        ry         : out std_logic_vector(ANGLE_WIDTH-1 downto 0);  -- pitch
        rz         : out std_logic_vector(ANGLE_WIDTH-1 downto 0);  -- yaw
        data_valid : out std_logic;

        -- ---- bring-up observability, all safe to leave open ----
        byte_stb   : out std_logic;                      -- one clock per byte
        byte_data  : out std_logic_vector(7 downto 0);   -- that byte
        frame_stb  : out std_logic;                      -- good sum, ANY function
        frame_func : out std_logic_vector(7 downto 0)    -- its function word
    );
end entity imu;


architecture rtl of imu is

    ----------------------------------------------------------------------
    -- Serial timing.  One bit is this many clocks; the start bit is
    -- sampled at half of it so every later sample lands mid-bit.
    ----------------------------------------------------------------------
    constant BIT_TICKS  : natural := CLK_FREQ / BAUD_RATE;
    constant HALF_TICKS : natural := BIT_TICKS / 2;

    constant HDR1       : std_logic_vector(7 downto 0) := x"7E";
    constant HDR2       : std_logic_vector(7 downto 0) := x"23";
    constant FUNC_EULER : std_logic_vector(7 downto 0) := x"26";

    -- The Euler frame carries three 4-byte floats.  Longer messages are
    -- counted through without being stored, so this only has to hold
    -- the one that matters rather than the longest the module sends.
    constant EULER_DATA : natural := 12;

    -- Header, header, length, function, sum is five bytes, so that is
    -- the shortest legal frame.  A length outside this range means the
    -- byte landed in the wrong place and the frame is abandoned.
    constant LEN_MIN : natural := 5;
    constant LEN_MAX : natural := 40;

    ----------------------------------------------------------------------
    -- Float to binary angle measure.
    --
    --     value = (-1)**sign * 1.mantissa * 2**(exponent-127)
    --     BAM   = value * 65536 / (2*pi)
    --
    -- Folded together, with the significand taken as a 24-bit integer
    -- so that its 2**-23 is already accounted for in the exponent:
    --
    --     BAM = significand * K * 2**(exponent - 156)
    --
    -- where K = round(65536/(2*pi) * 2**SCALE_BITS).  The extra
    -- SCALE_BITS buys back precision the bare constant 10430 would
    -- lose -- it is 0.004% light, about a count of drift at the
    -- extremes.  156 is 127 + 23 + SCALE_BITS.
    --
    -- One multiply and a variable shift.  The shift is a barrel
    -- shifter, which is the whole cost of this function.
    ----------------------------------------------------------------------
    constant SCALE_BITS : natural := 6;
    constant K          : natural := 667544;     -- 65536/(2*pi) * 64
    constant EXP_BIAS   : natural := 156;        -- 127 + 23 + SCALE_BITS

    function float_to_bam (
        w : std_logic_vector(31 downto 0)
    ) return std_logic_vector is
        variable e    : integer;
        variable sig  : unsigned(23 downto 0);
        variable prod : unsigned(43 downto 0);
        variable sh   : integer;
        variable mag  : unsigned(ANGLE_WIDTH-1 downto 0);
    begin
        e   := to_integer(unsigned(w(30 downto 23)));
        mag := (others => '0');

        -- Exponent zero is a true zero or a denormal; either way the
        -- angle rounds to nothing and mag stays clear.
        if e /= 0 then
            sig  := '1' & unsigned(w(22 downto 0));   -- implicit leading one
            prod := sig * to_unsigned(K, 20);
            sh   := EXP_BIAS - e;

            if sh >= prod'length then
                mag := (others => '0');               -- too small to register
            elsif sh <= 0 then
                mag := (others => '1');               -- past a full turn
            else
                -- Dropping the top bits is deliberate: an angle is
                -- modular, so past one turn it should wrap, not clip.
                mag := resize(shift_right(prod, sh), ANGLE_WIDTH);
            end if;
        end if;

        if w(31) = '1' then
            return std_logic_vector(-signed(mag));
        else
            return std_logic_vector(signed(mag));
        end if;
    end function float_to_bam;

    ----------------------------------------------------------------------
    -- Receiver
    ----------------------------------------------------------------------
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state : rx_state_t := RX_IDLE;

    -- uart_rx arrives from off board and changes nowhere near a clock
    -- edge, so two flops before anything looks at it.
    signal rx_meta : std_logic := '1';
    signal rx_sync : std_logic := '1';

    signal tick_count : natural range 0 to BIT_TICKS := 0;
    signal bit_index  : natural range 0 to 7 := 0;

    signal rx_shift : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_stb   : std_logic := '0';

    ----------------------------------------------------------------------
    -- Frame parser
    ----------------------------------------------------------------------
    type fr_state_t is (F_HDR1, F_HDR2, F_LEN, F_FUNC, F_DATA, F_SUM);
    signal fr_state : fr_state_t := F_HDR1;

    signal data_len   : natural range 0 to LEN_MAX := 0;
    signal data_index : natural range 0 to LEN_MAX := 0;
    signal func_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal check_sum  : unsigned(7 downto 0) := (others => '0');

    type byte_array_t is array (0 to EULER_DATA-1) of std_logic_vector(7 downto 0);
    signal payload : byte_array_t := (others => (others => '0'));

    signal rx_reg : std_logic_vector(ANGLE_WIDTH-1 downto 0) := (others => '0');
    signal ry_reg : std_logic_vector(ANGLE_WIDTH-1 downto 0) := (others => '0');
    signal rz_reg : std_logic_vector(ANGLE_WIDTH-1 downto 0) := (others => '0');

    signal valid_reg : std_logic := '0';
    signal fstb_reg  : std_logic := '0';

    -- One little-endian float out of the payload.  Byte 4*i is the
    -- least significant, so the word is assembled highest byte first.
    function payload_float (
        b : byte_array_t;
        i : natural
    ) return std_logic_vector is
    begin
        return b(4*i + 3) & b(4*i + 2) & b(4*i + 1) & b(4*i);
    end function payload_float;

begin

    rx <= rx_reg;
    ry <= ry_reg;
    rz <= rz_reg;
    data_valid <= valid_reg;

    byte_stb   <= rx_stb;
    byte_data  <= rx_byte;
    frame_stb  <= fstb_reg;
    frame_func <= func_reg;

    ----------------------------------------------------------------------
    -- UART receiver: 8 data bits, no parity, one stop bit.
    --
    -- RX_START re-checks the line at the middle of the start bit and
    -- gives up if it has gone back high, so a glitch on an idle line
    -- does not produce a byte.
    ----------------------------------------------------------------------
    receive_process : process (reset, clk) is
    begin
        if ( reset = '1' ) then
            rx_meta    <= '1';
            rx_sync    <= '1';
            rx_state   <= RX_IDLE;
            tick_count <= 0;
            bit_index  <= 0;
            rx_shift   <= (others => '0');
            rx_byte    <= (others => '0');
            rx_stb     <= '0';

        elsif rising_edge(clk) then
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;

            rx_stb <= '0';

            case rx_state is

                when RX_IDLE =>
                    tick_count <= 0;
                    bit_index  <= 0;
                    if ( rx_sync = '0' ) then          -- start bit edge
                        rx_state <= RX_START;
                    end if;

                when RX_START =>
                    if ( tick_count = HALF_TICKS ) then
                        tick_count <= 0;
                        if ( rx_sync = '0' ) then      -- still low: real
                            rx_state <= RX_DATA;
                        else
                            rx_state <= RX_IDLE;       -- glitch
                        end if;
                    else
                        tick_count <= tick_count + 1;
                    end if;

                when RX_DATA =>
                    if ( tick_count = BIT_TICKS - 1 ) then
                        tick_count <= 0;
                        -- Least significant bit first, so shift down.
                        rx_shift <= rx_sync & rx_shift(7 downto 1);
                        if ( bit_index = 7 ) then
                            rx_state <= RX_STOP;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        tick_count <= tick_count + 1;
                    end if;

                when RX_STOP =>
                    if ( tick_count = BIT_TICKS - 1 ) then
                        tick_count <= 0;
                        -- A framing error means the byte is not
                        -- trustworthy, so it is simply not announced.
                        if ( rx_sync = '1' ) then
                            rx_byte <= rx_shift;
                            rx_stb  <= '1';
                        end if;
                        rx_state <= RX_IDLE;
                    else
                        tick_count <= tick_count + 1;
                    end if;

            end case;
        end if;
    end process receive_process;

    ----------------------------------------------------------------------
    -- Frame parser
    --
    -- The payload is stored only for the Euler frame; anything else is
    -- counted and summed to stay aligned, then discarded.  That keeps
    -- the buffer at twelve bytes rather than sizing it for the longest
    -- message the module can send.
    --
    -- valid_reg drops as soon as a new frame starts and returns only if
    -- that frame is a 0x26 whose checksum agrees, so it marks "the
    -- angles below are a complete, verified reading" and holds long
    -- enough for rot_matrix to take it on its own schedule.
    ----------------------------------------------------------------------
    parse_process : process (reset, clk) is
    begin
        if ( reset = '1' ) then
            fr_state   <= F_HDR1;
            data_len   <= 0;
            data_index <= 0;
            func_reg   <= (others => '0');
            check_sum  <= (others => '0');
            payload    <= (others => (others => '0'));
            rx_reg     <= (others => '0');
            ry_reg     <= (others => '0');
            rz_reg     <= (others => '0');
            valid_reg  <= '0';
            fstb_reg   <= '0';

        elsif rising_edge(clk) then
            fstb_reg <= '0';

            if ( rx_stb = '1' ) then
                case fr_state is

                    when F_HDR1 =>
                        if ( rx_byte = HDR1 ) then
                            check_sum <= unsigned(HDR1);
                            valid_reg <= '0';
                            fr_state  <= F_HDR2;
                        end if;

                    when F_HDR2 =>
                        if ( rx_byte = HDR2 ) then
                            check_sum <= check_sum + unsigned(HDR2);
                            fr_state  <= F_LEN;
                        elsif ( rx_byte = HDR1 ) then
                            -- Two 0x7E in a row: the second one is the
                            -- real header, so stay here rather than
                            -- throwing both away.
                            check_sum <= unsigned(HDR1);
                        else
                            fr_state <= F_HDR1;
                        end if;

                    when F_LEN =>
                        if ( to_integer(unsigned(rx_byte)) >= LEN_MIN ) and
                           ( to_integer(unsigned(rx_byte)) <= LEN_MAX ) then
                            data_len  <= to_integer(unsigned(rx_byte)) - LEN_MIN;
                            check_sum <= check_sum + unsigned(rx_byte);
                            fr_state  <= F_FUNC;
                        else
                            fr_state <= F_HDR1;     -- not a length byte
                        end if;

                    when F_FUNC =>
                        func_reg   <= rx_byte;
                        check_sum  <= check_sum + unsigned(rx_byte);
                        data_index <= 0;
                        if ( data_len = 0 ) then
                            fr_state <= F_SUM;
                        else
                            fr_state <= F_DATA;
                        end if;

                    when F_DATA =>
                        if ( func_reg = FUNC_EULER ) and
                           ( data_index < EULER_DATA ) then
                            payload(data_index) <= rx_byte;
                        end if;
                        check_sum <= check_sum + unsigned(rx_byte);
                        if ( data_index = data_len - 1 ) then
                            fr_state <= F_SUM;
                        else
                            data_index <= data_index + 1;
                        end if;

                    when F_SUM =>
                        if ( unsigned(rx_byte) = check_sum ) then
                            fstb_reg <= '1';        -- any good frame
                            if ( func_reg = FUNC_EULER ) then
                                rx_reg <= float_to_bam(payload_float(payload, 0));
                                ry_reg <= float_to_bam(payload_float(payload, 1));
                                rz_reg <= float_to_bam(payload_float(payload, 2));
                                valid_reg <= '1';
                            end if;
                        end if;
                        -- Whatever the outcome, hunt for the next header.
                        fr_state <= F_HDR1;

                end case;
            end if;
        end if;
    end process parse_process;

end architecture rtl;
