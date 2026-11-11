library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--------------------------------------------------------------------------
-- SDRAM controller -- READ AND WRITE.
--
-- An earlier version of this file could only read, and that was the
-- whole problem: nothing ever put the panorama into the memory, so the
-- renderer read whatever the chip powered up holding.  Every other part
-- of the design could be correct and the picture still rubbish -- and in
-- simulation the gap was invisible, because the testbench preloaded a
-- memory model and never noticed the hardware had no such thing.
--
-- TWO CLIENTS, ONE CHIP.  The host fills the memory through wr_*, and
-- image_reader empties it one ray at a time, and only one set of pins
-- exists -- so the arbitration lives here rather than in the top level.
-- Writes win, because the loader only runs while an image is arriving
-- and a starved renderer merely repeats a frame.
--

--========================================================================
-- THE TIMING HERE IS MEASURED, NOT ARGUED
--========================================================================
--
-- Three numbers govern when this board works, and they are not
-- independent.  Sweeping all three against a known pattern gave four
-- working combinations, every one of them obeying:
--
--     capture latency = CAS latency + clk_inv - 1
--
-- This uses the most generous: clock forwarded INVERTED, CAS latency 3,
-- capture latency 3.  With those, 100_000 known pixels written and read
-- back came out byte for byte identical.
--
-- None of the three can be changed on its own.  Raising CAS latency
-- without raising the capture point, or dropping the clock inversion
-- without lowering it, reads the second write beat for BOTH halves of a
-- pixel: green comes back zero and red and blue trade places, so white
-- turns pink and a blue sky turns red.
--
-- ONE COMMAND PER PIXEL.  A pixel is 24 bits and the bus is 16, so it
-- occupies two consecutive words: hw_addr = pixel << 1, always EVEN, so
-- the pair always sits in one aligned two-word block of one row.  A
-- BURST OF TWO moves it with a single command, and the two words go
-- back to back with the bus driven right through -- which is what keeps
-- the second half from being treated differently from the first.
--
-- ADDRESS MAPPING.  IS42VM16320E: 4 banks x 8192 rows x 1024 columns x
-- 16 bits, a 25-bit word address.  Confirmed against Terasic's own
-- controller for this board, which splits it identically:
--
--     col  = hw_addr[9:0]      row = hw_addr[22:10]
--     bank = hw_addr[24:23]
--
-- THE OLD MAPPING USED col = hw_addr[4:0] -- five bits, 32 of the 1024
-- columns, reaching 2**20 words in total: half a megapixel out of the
-- 8.4 this panorama needs, with everything above aliasing back over the
-- bottom.  A renderer reading through that gets a picture that pans
-- coherently, because the arithmetic upstream is fine, but whose rows
-- come from the wrong places -- which looks exactly like a stride or
-- shear bug in the renderer and is not one.
--
-- REFRESH IS NOT OPTIONAL.  A cell holds its charge for 64 ms and the
-- part has 8192 rows, so one AUTO REFRESH every 7.8 us keeps them all
-- alive.  ACTIVATING a row refreshes it as a side effect, which is how
-- a design with no refresh logic can appear to work and then rot.
--
-- ONE ACCESS PER REQUEST.  Requests are latched on their RISING EDGE,
-- never sampled as a level.  A requester cannot drop its request until
-- it has seen the ack, so for at least one clock afterwards a level
-- still looks new -- and the access runs again, at whatever address the
-- requester has meanwhile advanced to.  On hardware that wrote every
-- pixel twice.
--
-- STRUCTURE.  Two processes: fsm_process computes the next state and
-- the next value of every register, clocked_process registers them.
--------------------------------------------------------------------------
entity sdram_ctrl is
    generic(
        ADDR_WIDTH   : natural := 23;         -- pixel addresses
        CLK_FREQ_HZ  : natural := 50_000_000;
        INIT_WAIT_US : natural := 200;

        -- Measured on this board; see the note above.
        READ_LATENCY : natural := 3;
        DRAM_CLK_INVERT : boolean := true
    );
    port(
        clk        : in    std_logic;
        reset      : in    std_logic;

        -- ---- write side: pixels arriving from the cable ----
        wr_req     : in    std_logic;
        wr_addr    : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
        wr_data    : in    std_logic_vector(23 downto 0);
        wr_ack     : out   std_logic;

        -- ---- read side: the renderer, one ray at a time ----
        rd_req     : in    std_logic;
        rd_addr    : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
        rd_data    : out   std_logic_vector(23 downto 0);
        rd_ack     : out   std_logic;

        ready      : out   std_logic;         -- initialisation finished

        dram_dq    : inout std_logic_vector(15 downto 0);
        dram_addr  : out   std_logic_vector(12 downto 0);
        dram_ba    : out   std_logic_vector(1 downto 0);
        dram_ldqm  : out   std_logic;
        dram_udqm  : out   std_logic;
        dram_ras_n : out   std_logic;
        dram_cas_n : out   std_logic;
        dram_cke   : out   std_logic;
        dram_clk   : out   std_logic;
        dram_we_n  : out   std_logic;
        dram_cs_n  : out   std_logic
    );
end entity sdram_ctrl;


architecture rtl of sdram_ctrl is

    type state_t is (
        ST_RESET_WAIT, ST_INIT_PRE, ST_INIT_AR1, ST_INIT_AR2, ST_INIT_MRS,
        ST_IDLE, ST_ACT, ST_CMD, ST_CAP0, ST_CAP1, ST_PRE, ST_DONE
    );

    constant INIT_WAIT_CYCLES : natural :=
        (CLK_FREQ_HZ / 1_000_000) * INIT_WAIT_US;

    -- 64 ms / 8192 rows = 7.8 us.
    constant REFRESH_INTERVAL : natural := (CLK_FREQ_HZ / 1_000_000) * 78 / 10;

    constant HW_WIDTH : natural := 25;

    signal state,         next_state      : state_t;
    signal wait_count,    wait_count_c    : natural range 0 to INIT_WAIT_CYCLES;
    signal cmd_wait,      cmd_wait_c      : natural range 0 to 15;
    signal refresh_count, refresh_count_c : natural range 0 to REFRESH_INTERVAL - 1;
    signal refresh_pend,  refresh_pend_c  : natural range 0 to 7;

    signal hw_addr,   hw_addr_c   : unsigned(HW_WIDTH - 1 downto 0);
    signal low_word,  low_word_c  : std_logic_vector(15 downto 0);
    signal high_word, high_word_c : std_logic_vector(15 downto 0);
    signal wdata_reg, wdata_reg_c : std_logic_vector(23 downto 0);
    signal we_reg,    we_reg_c    : std_logic;

    signal addr_cmd, addr_cmd_c : std_logic_vector(12 downto 0);
    signal ba_cmd,   ba_cmd_c   : std_logic_vector(1 downto 0);

    signal dq_out, dq_out_c : std_logic_vector(15 downto 0);
    signal dq_oe,  dq_oe_c  : std_logic;

    signal rdata, rdata_c : std_logic_vector(23 downto 0);
    signal wack,  wack_c  : std_logic;
    signal rack,  rack_c  : std_logic;

    signal ras_n, ras_n_c : std_logic;
    signal cas_n, cas_n_c : std_logic;
    signal we_n,  we_n_c  : std_logic;
    signal cs_n,  cs_n_c  : std_logic;

    -- Request edge detection.
    signal wr_req_d, wr_req_d_c : std_logic;
    signal rd_req_d, rd_req_d_c : std_logic;
    signal wr_pend,  wr_pend_c  : std_logic;
    signal rd_pend,  rd_pend_c  : std_logic;

    function to_hw (p : unsigned) return unsigned is
    begin
        return resize(p, HW_WIDTH) sll 1;
    end function;

    function map_row (a : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(a(22 downto 10));
    end function;

    -- A10 stays low: auto-precharge would close the row before the
    -- second word of the burst had come out of it.
    function map_col (a : unsigned) return std_logic_vector is
        variable r : std_logic_vector(12 downto 0);
    begin
        r := (others => '0');
        r(9 downto 0) := std_logic_vector(a(9 downto 0));
        return r;
    end function;

    function map_bank (a : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(a(24 downto 23));
    end function;

begin

    -- INVERTED.  The memory then samples commands and write data half a
    -- cycle after the FPGA drives them -- 10 ns of setup and 10 ns of
    -- hold at 50 MHz -- instead of at the same instant they change.
    dram_clk  <= not clk when DRAM_CLK_INVERT else clk;

    dram_cke  <= '1';
    dram_ldqm <= '0';
    dram_udqm <= '0';
    dram_addr <= addr_cmd;
    dram_ba   <= ba_cmd;
    dram_dq   <= dq_out when dq_oe = '1' else (others => 'Z');

    dram_ras_n <= ras_n;
    dram_cas_n <= cas_n;
    dram_we_n  <= we_n;
    dram_cs_n  <= cs_n;

    wr_ack  <= wack;
    rd_ack  <= rack;
    rd_data <= rdata;

    ready <= '1' when state /= ST_RESET_WAIT and state /= ST_INIT_PRE
                  and state /= ST_INIT_AR1   and state /= ST_INIT_AR2
                  and state /= ST_INIT_MRS else '0';

    ----------------------------------------------------------------------
    -- Next state and next values.  Combinational.
    ----------------------------------------------------------------------
    fsm_process : process(all) is
        -- A variable, so the interval tick and the moment a refresh is
        -- taken cannot cancel each other out within one evaluation.
        variable took_refresh : boolean;
    begin
        next_state      <= state;
        wait_count_c    <= wait_count;
        cmd_wait_c      <= cmd_wait;
        refresh_count_c <= refresh_count;
        refresh_pend_c  <= refresh_pend;
        hw_addr_c       <= hw_addr;
        low_word_c      <= low_word;
        high_word_c     <= high_word;
        wdata_reg_c     <= wdata_reg;
        we_reg_c        <= we_reg;
        addr_cmd_c      <= addr_cmd;
        ba_cmd_c        <= ba_cmd;
        dq_out_c        <= dq_out;
        rdata_c         <= rdata;
        wr_pend_c       <= wr_pend;
        rd_pend_c       <= rd_pend;

        -- One clock wide by default.
        ras_n_c <= '1';
        cas_n_c <= '1';
        we_n_c  <= '1';
        cs_n_c  <= '0';
        dq_oe_c <= '0';
        wack_c  <= '0';
        rack_c  <= '0';

        took_refresh := false;

        case state is

            when ST_RESET_WAIT =>
                if (wait_count = INIT_WAIT_CYCLES) then
                    next_state <= ST_INIT_PRE;
                else
                    wait_count_c <= wait_count + 1;
                end if;

            when ST_INIT_PRE =>
                ras_n_c        <= '0';            -- PRECHARGE ALL
                we_n_c         <= '0';
                addr_cmd_c     <= (others => '0');
                addr_cmd_c(10) <= '1';
                cmd_wait_c     <= 3;
                next_state     <= ST_INIT_AR1;

            when ST_INIT_AR1 =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    ras_n_c    <= '0';            -- AUTO REFRESH
                    cas_n_c    <= '0';
                    cmd_wait_c <= 7;
                    next_state <= ST_INIT_AR2;
                end if;

            when ST_INIT_AR2 =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    ras_n_c    <= '0';            -- AUTO REFRESH
                    cas_n_c    <= '0';
                    cmd_wait_c <= 7;
                    next_state <= ST_INIT_MRS;
                end if;

            when ST_INIT_MRS =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    -- Field by field, because a packed literal here once
                    -- said burst length 4 while the comment beside it
                    -- said 1.
                    --   A2-A0  burst length   001 = 2
                    --   A3     burst type       0 = sequential
                    --   A6-A4  CAS latency    011 = 3, measured
                    --   A8-A7  operating mode  00 = standard
                    --   A9     write burst      0 = same as read
                    ras_n_c    <= '0';
                    cas_n_c    <= '0';
                    we_n_c     <= '0';
                    addr_cmd_c <= (others => '0');
                    addr_cmd_c(2 downto 0) <= "001";
                    addr_cmd_c(6 downto 4) <= "011";
                    ba_cmd_c   <= "00";
                    cmd_wait_c <= 3;
                    next_state <= ST_IDLE;
                end if;

            when ST_IDLE =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;

                elsif (refresh_pend > 0) then
                    -- Every access precharges on its way out, so all
                    -- banks are already closed here.
                    ras_n_c      <= '0';
                    cas_n_c      <= '0';
                    took_refresh := true;
                    cmd_wait_c   <= 4;            -- tRFC

                elsif (wr_pend = '1') then
                    -- Writes win.  The loader only runs while an image
                    -- is arriving, and reads are gated off until it
                    -- finishes anyway.
                    wr_pend_c   <= '0';
                    we_reg_c    <= '1';
                    wdata_reg_c <= wr_data;
                    hw_addr_c   <= to_hw(unsigned(wr_addr));
                    addr_cmd_c  <= map_row(to_hw(unsigned(wr_addr)));
                    ba_cmd_c    <= map_bank(to_hw(unsigned(wr_addr)));
                    next_state  <= ST_ACT;

                elsif (rd_pend = '1') then
                    -- No gate on whether the image is complete.  The FSM
                    -- serialises everything -- one access is chosen here,
                    -- run to completion, and only then is another chosen
                    -- -- so a read and a write can never be in flight
                    -- together and there is no hazard to prevent.
                    --
                    -- While a load is running, writes win and the
                    -- renderer mostly starves, so the picture assembles
                    -- as the image arrives.  That is better feedback
                    -- than a black screen, not worse.
                    rd_pend_c  <= '0';
                    we_reg_c   <= '0';
                    hw_addr_c  <= to_hw(unsigned(rd_addr));
                    addr_cmd_c <= map_row(to_hw(unsigned(rd_addr)));
                    ba_cmd_c   <= map_bank(to_hw(unsigned(rd_addr)));
                    next_state <= ST_ACT;
                end if;

            when ST_ACT =>
                ras_n_c    <= '0';                -- ACTIVATE
                cmd_wait_c <= 1;                  -- tRCD
                next_state <= ST_CMD;

            when ST_CMD =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    cas_n_c    <= '0';            -- READ or WRITE, burst of 2
                    addr_cmd_c <= map_col(hw_addr);
                    ba_cmd_c   <= map_bank(hw_addr);
                    if (we_reg = '1') then
                        we_n_c     <= '0';
                        dq_out_c   <= wdata_reg(15 downto 0);
                        dq_oe_c    <= '1';
                        cmd_wait_c <= 0;
                    else
                        cmd_wait_c <= READ_LATENCY;
                    end if;
                    next_state <= ST_CAP0;
                end if;

            when ST_CAP0 =>
                if (we_reg = '1') then
                    -- Second beat, the very next clock.
                    dq_out_c   <= x"00" & wdata_reg(23 downto 16);
                    dq_oe_c    <= '1';
                    cmd_wait_c <= 2;              -- tWR
                    next_state <= ST_PRE;
                elsif (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    low_word_c <= dram_dq;
                    next_state <= ST_CAP1;
                end if;

            when ST_CAP1 =>
                high_word_c <= dram_dq;
                cmd_wait_c  <= 0;
                next_state  <= ST_PRE;

            when ST_PRE =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    ras_n_c        <= '0';        -- PRECHARGE ALL
                    we_n_c         <= '0';
                    addr_cmd_c     <= (others => '0');
                    addr_cmd_c(10) <= '1';
                    cmd_wait_c     <= 2;         -- tRP
                    next_state     <= ST_DONE;
                end if;

            when ST_DONE =>
                if (cmd_wait > 0) then
                    cmd_wait_c <= cmd_wait - 1;
                else
                    if (we_reg = '1') then
                        wack_c <= '1';
                    else
                        rdata_c <= high_word(7 downto 0) & low_word;
                        rack_c  <= '1';
                    end if;
                    -- ONE DEAD CLOCK before looking at the requests
                    -- again.  The ack goes out on this edge, so the
                    -- requester cannot have dropped its request yet.
                    cmd_wait_c <= 1;
                    next_state <= ST_IDLE;
                end if;

        end case;

        -- Refresh interval counter.  It runs in every state once the
        -- chip is up, because the memory's need does not pause for an
        -- access -- a burst takes about fourteen clocks against an
        -- interval of 390, so demand raised mid-access is serviced on
        -- the way back through ST_IDLE.
        --
        -- IT DOES NOT RUN BEFORE THE CHIP IS INITIALISED.  A refresh
        -- ahead of the init sequence is meaningless: the memory is not
        -- yet in a state to accept one, and the sequence issues its own
        -- two auto-refreshes as part of bringing it up.  Counting demand
        -- through the 200 us power-up wait accrued twenty-five refreshes
        -- that nothing could ever service, and refresh_pend is three
        -- bits wide.  In simulation that is a range violation at the
        -- eighth.  ON THE BOARD IT IS WORSE AND SILENT: the counter
        -- wraps to zero, so eight pending refreshes become none, and the
        -- symptom is rows quietly decaying in whichever bank went
        -- longest without one -- a few wrong pixels that move about,
        -- which reads as noise rather than as a missing refresh.
        if (ready = '1') then
            if (refresh_count = REFRESH_INTERVAL - 1) then
                refresh_count_c <= 0;
                -- Saturate rather than wrap.  Pending should never reach
                -- two in normal operation; if it somehow did, dropping
                -- one refresh is a far smaller loss than wrapping and
                -- dropping eight.
                if not took_refresh and refresh_pend < 7 then
                    refresh_pend_c <= refresh_pend + 1;
                end if;
            else
                refresh_count_c <= refresh_count + 1;
                if took_refresh then
                    refresh_pend_c <= refresh_pend - 1;
                end if;
            end if;
        end if;

        -- Request edge detection, after the case so a request arriving
        -- as one is taken is remembered rather than lost.
        wr_req_d_c <= wr_req;
        rd_req_d_c <= rd_req;
        if (wr_req = '1') and (wr_req_d = '0') then
            wr_pend_c <= '1';
        end if;
        if (rd_req = '1') and (rd_req_d = '0') then
            rd_pend_c <= '1';
        end if;
    end process fsm_process;

    ----------------------------------------------------------------------
    -- State and datapath registers.  Asynchronous reset, synchronous
    -- everything else.
    ----------------------------------------------------------------------
    clocked_process : process(clk, reset) is
    begin
        if reset = '1' then
            state         <= ST_RESET_WAIT;
            wait_count    <= 0;
            cmd_wait      <= 0;
            refresh_count <= 0;
            refresh_pend  <= 0;
            hw_addr       <= (others => '0');
            low_word      <= (others => '0');
            high_word     <= (others => '0');
            wdata_reg     <= (others => '0');
            we_reg        <= '0';
            addr_cmd      <= (others => '0');
            ba_cmd        <= (others => '0');
            dq_out        <= (others => '0');
            dq_oe         <= '0';
            rdata         <= (others => '0');
            wack          <= '0';
            rack          <= '0';
            ras_n         <= '1';
            cas_n         <= '1';
            we_n          <= '1';
            cs_n          <= '0';
            wr_req_d      <= '0';
            rd_req_d      <= '0';
            wr_pend       <= '0';
            rd_pend       <= '0';

        elsif rising_edge(clk) then
            state         <= next_state;
            wait_count    <= wait_count_c;
            cmd_wait      <= cmd_wait_c;
            refresh_count <= refresh_count_c;
            refresh_pend  <= refresh_pend_c;
            hw_addr       <= hw_addr_c;
            low_word      <= low_word_c;
            high_word     <= high_word_c;
            wdata_reg     <= wdata_reg_c;
            we_reg        <= we_reg_c;
            addr_cmd      <= addr_cmd_c;
            ba_cmd        <= ba_cmd_c;
            dq_out        <= dq_out_c;
            dq_oe         <= dq_oe_c;
            rdata         <= rdata_c;
            wack          <= wack_c;
            rack          <= rack_c;
            ras_n         <= ras_n_c;
            cas_n         <= cas_n_c;
            we_n          <= we_n_c;
            cs_n          <= cs_n_c;
            wr_req_d      <= wr_req_d_c;
            rd_req_d      <= rd_req_d_c;
            wr_pend       <= wr_pend_c;
            rd_pend       <= rd_pend_c;
        end if;
    end process clocked_process;

end architecture rtl;
