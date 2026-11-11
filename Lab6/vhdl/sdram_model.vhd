--------------------------------------------------------------------------
-- sdram_model.vhd -- SIMULATION ONLY.  NEVER ADD THIS TO THE PROJECT.
--
-- It is not RTL and will not synthesise.  Like vr360_tb.vhd it lives
-- here beside the design but is absent from vr360.qsf, which is what
-- keeps it out of the fitter.
--
--========================================================================
-- WHY THE TESTBENCH CANNOT JUST ANSWER READ REQUESTS
--========================================================================
--
-- It used to, and that was the problem.  A process handed back
-- image_mem(rd_addr) with rd_valid high, one clock, always correct --
-- so the renderer got the right pixel for every address whether or not
-- the design could actually talk to the memory chip.  The first sign of
-- trouble was a wrong picture on hardware, which is the most expensive
-- place to find it.
--
-- That port no longer exists in any case.  The controller is inside
-- vr360 now, so the only memory interface crossing the DUT boundary is
-- the forty SDRAM pins.  Anything standing in for the memory has to
-- decode ACTIVATE, READ, WRITE and PRECHARGE off those pins, hold a row
-- open per bank and count out the CAS latency -- and that is an SDRAM
-- model however short it is written, which is why it is a file rather
-- than a process in the bench.
--
-- THE TWO GENERICS THAT LOOK OPTIONAL ARE THE IMPORTANT ONES.
--
--   BOARD_DELAY -- the datasheet counts CAS latency at the memory's own
--   pins.  What the FPGA sees is a cycle longer, because its clock
--   reaches the chip late and the data has to cross back.
--
--   HOLD_BUS -- there are no pull resistors on dq, so when nobody drives
--   it the bus keeps its last value instead of going high impedance.  A
--   controller that samples one cycle early therefore reads the PREVIOUS
--   word rather than obvious rubbish.
--
-- Leave either out and a wrong capture latency passes in simulation and
-- fails on the board.  They are the reason this model is worth having.
--------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

--------------------------------------------------------------------------
-- Behavioural SDRAM, enough of one to settle an argument.
--
-- Not a datasheet model: no timing checks, no refresh requirement, no
-- bank state machine.  It decodes the command truth table, remembers
-- what was written, and returns it CAS_LATENCY clocks after a READ.
-- That is exactly the set of behaviours the question "which halfword
-- ends up in which register" depends on, and leaving out the rest
-- keeps the answer readable.
--
-- It DOES report what it is asked to do, because the point of running
-- it is to see the order of operations rather than to check a slack
-- number.
--
-- Memory is a small array indexed by the low bits of the full address,
-- so a testbench must keep its addresses inside 2**ADDR_BITS.  A full
-- 512 Mbit array would be 32M entries of simulation memory.
--
-- INIT_FILE is a backdoor: it loads a .mif straight into the array at
-- time zero.  Writing an image in through the controller one pixel at a
-- time would be half a million accesses of about fourteen clocks each
-- before the first frame could be rendered, which is minutes of
-- simulation to set up a test that is not about writing.
--------------------------------------------------------------------------
entity sdram_model is
    generic (
        CAS_LATENCY : natural := 2;
        ADDR_BITS   : natural := 16;      -- of simulated storage
        VERBOSE     : boolean := true;

        -- EXTRA CYCLES BEFORE READ DATA APPEARS, on top of CAS latency.
        --
        -- The datasheet's CAS latency is counted at the memory's own
        -- pins.  What the FPGA sees is longer: its clock reaches the
        -- memory late, the data crosses the board coming back, and the
        -- input register needs setup before its own edge.  On a board
        -- where dram_clk is forwarded straight from the system clock
        -- with no phase shift, that round trip routinely pushes the
        -- data a whole cycle past where CAS latency alone would put it.
        BOARD_DELAY : natural := 0;

        -- WHAT THE BUS DOES WHEN NOBODY DRIVES IT.
        --
        -- 'Z' is the truthful answer for one memory in isolation, and
        -- the reason a testbench can pass while hardware fails: a real
        -- bus with no pull resistors holds its last value for a good
        -- while on trace capacitance alone.  So a controller that
        -- samples a cycle early reads the PREVIOUS access's data rather
        -- than obvious garbage -- a plausible wrong answer instead of a
        -- visibly broken one.
        HOLD_BUS    : boolean := false;

        -- A .mif loaded straight into the array at time zero, or ""
        -- for an empty memory.  See the note above for why.
        INIT_FILE   : string := ""
    );
    port (
        dram_clk   : in    std_logic;
        dram_cke   : in    std_logic;
        dram_cs_n  : in    std_logic;
        dram_ras_n : in    std_logic;
        dram_cas_n : in    std_logic;
        dram_we_n  : in    std_logic;
        dram_addr  : in    std_logic_vector(12 downto 0);
        dram_ba    : in    std_logic_vector(1 downto 0);
        dram_ldqm  : in    std_logic;
        dram_udqm  : in    std_logic;
        dram_dq    : inout std_logic_vector(15 downto 0)
    );
end entity sdram_model;


architecture behavioural of sdram_model is

    constant MEM_SIZE : natural := 2 ** ADDR_BITS;

    type mem_t is array (0 to MEM_SIZE - 1) of std_logic_vector(15 downto 0);

    ----------------------------------------------------------------------
    -- Preload, laid out exactly as the controller writes.
    --
    -- A 24-bit pixel occupies TWO 16-bit words, and which half goes
    -- where is not arbitrary:
    --
    --     word 2p     = G & B      the low halfword
    --     word 2p+1   = 0x00 & R   the high halfword, top byte padded
    --
    -- Getting that backwards here would make the model disagree with the
    -- hardware about what a pixel looks like in memory -- and a
    -- testbench that disagrees with the board about something this
    -- central is worse than no testbench, because it makes correct RTL
    -- look broken.
    --
    -- THE TWO RADIXES ARE DECLARED SEPARATELY AND ARE ROUTINELY
    -- DIFFERENT.  The panorama files are ADDRESS_RADIX=UNS with
    -- DATA_RADIX=HEX, so reading addresses as hex would put pixel 10 at
    -- address 16 and shear the whole image -- silently, because every
    -- value read would still be a legal colour.
    ----------------------------------------------------------------------
    impure function load_mif (fn : string) return mem_t is
        file     f        : text;
        variable status   : file_open_status;
        variable l        : line;
        variable m        : mem_t := (others => (others => '0'));
        variable ch       : character;
        variable good     : boolean;
        variable in_body  : boolean := false;
        variable a_hex    : boolean := false;   -- ADDRESS_RADIX
        variable d_hex    : boolean := true;    -- DATA_RADIX
        variable buf      : string(1 to 256);
        variable n        : natural;
        variable colon    : natural;
        variable semi     : natural;
        variable addr     : natural;
        variable val      : natural;

        -- Digits in whichever base, stopping at the first character
        -- that is not one.
        function parse (str : string; lo, hi : natural; hex : boolean)
            return natural is
            variable acc : natural := 0;
            variable d   : integer;
        begin
            for i in lo to hi loop
                case str(i) is
                    when '0' to '9' => d := character'pos(str(i))
                                          - character'pos('0');
                    when 'a' to 'f' => d := character'pos(str(i))
                                          - character'pos('a') + 10;
                    when 'A' to 'F' => d := character'pos(str(i))
                                          - character'pos('A') + 10;
                    when others     => d := -1;
                end case;
                if d < 0 or (not hex and d > 9) then
                    return acc;
                end if;
                if hex then
                    acc := acc * 16 + d;
                else
                    acc := acc * 10 + d;
                end if;
            end loop;
            return acc;
        end function;

        function find (str : string; n : natural; c : character)
            return natural is
        begin
            for i in 1 to n loop
                if str(i) = c then
                    return i;
                end if;
            end loop;
            return 0;
        end function;

        function contains (str : string; n : natural; pat : string)
            return boolean is
        begin
            if n < pat'length then
                return false;
            end if;
            for i in 1 to n - pat'length + 1 loop
                if str(i to i + pat'length - 1) = pat then
                    return true;
                end if;
            end loop;
            return false;
        end function;
    begin
        if fn = "" then
            return m;
        end if;

        file_open(status, f, fn, read_mode);
        if status /= open_ok then
            report "sdram_model: cannot open " & fn severity warning;
            return m;
        end if;

        while not endfile(f) loop
            readline(f, l);
            n := 0;
            loop
                read(l, ch, good);
                exit when not good or n = buf'length;
                n := n + 1;
                buf(n) := ch;
            end loop;

            if not in_body then
                if contains(buf, n, "ADDRESS_RADIX") then
                    a_hex := contains(buf, n, "HEX");
                end if;
                if contains(buf, n, "DATA_RADIX") then
                    d_hex := contains(buf, n, "HEX");
                end if;
                if contains(buf, n, "BEGIN") then
                    in_body := true;
                end if;
            else
                exit when contains(buf, n, "END");
                colon := find(buf, n, ':');
                semi  := find(buf, n, ';');
                if colon > 0 and semi > colon then
                    -- Skip leading spaces on each field.
                    addr := 0;
                    for i in 1 to colon - 1 loop
                        if buf(i) /= ' ' and buf(i) /= HT then
                            addr := parse(buf, i, colon - 1, a_hex);
                            exit;
                        end if;
                    end loop;
                    val := 0;
                    for i in colon + 1 to semi - 1 loop
                        if buf(i) /= ' ' and buf(i) /= HT then
                            val := parse(buf, i, semi - 1, d_hex);
                            exit;
                        end if;
                    end loop;

                    if 2 * addr + 1 < MEM_SIZE then
                        m(2 * addr)     := std_logic_vector(
                                               to_unsigned(val mod 65536, 16));
                        m(2 * addr + 1) := std_logic_vector(
                                               to_unsigned((val / 65536) mod 256, 16));
                    end if;
                end if;
            end if;
        end loop;

        file_close(f);
        return m;
    end function;

    -- Rows stay open per bank, as they do in the real part: a READ or
    -- WRITE carries only a column, so the row has to have been
    -- remembered from the ACTIVATE.
    type row_t is array (0 to 3) of integer;

    signal dq_drv : std_logic_vector(15 downto 0) := (others => 'Z');

    ----------------------------------------------------------------------
    -- SAMPLE WHAT WAS STABLE BEFORE THE EDGE, NOT WHAT LANDS ON IT.
    --
    -- dram_clk is the controller's own clock, so in simulation both the
    -- controller's outputs and this model's clock update at the same
    -- time, one delta apart.  A process waking on rising_edge(dram_clk)
    -- would read the values the controller assigned ON that edge --
    -- which are the command for the NEXT period, making the model run a
    -- cycle ahead of the hardware it stands for.  Every access then
    -- appears to use the previous access's address.
    --
    -- Real parts do not have this problem: the FPGA drives its outputs
    -- some nanoseconds AFTER the edge and the memory samples them at the
    -- NEXT one.  Delaying the sampled copies by a picosecond reproduces
    -- that ordering exactly, because a delta cycle takes no simulation
    -- time at all -- at the model's edge these still hold the value from
    -- before it.
    --
    -- Transport rather than inertial delay: a one-clock command must not
    -- be swallowed as a glitch.
    --
    -- ONE NANOSECOND, NOT ONE PICOSECOND.  The delay only has to be
    -- non-zero and shorter than a clock period, and at the default 1 ns
    -- simulator resolution a picosecond rounds away -- leaving the
    -- ordering to depend on delta cycles, which is exactly the fragility
    -- this is here to remove.  At a 20 ns period, 1 ns is unambiguous
    -- and needs no -t switch to be correct.
    ----------------------------------------------------------------------
    signal cs_n_s, ras_n_s, cas_n_s, we_n_s, cke_s : std_logic;
    signal addr_s : std_logic_vector(12 downto 0);
    signal ba_s   : std_logic_vector(1 downto 0);
    signal dq_s   : std_logic_vector(15 downto 0);

    ----------------------------------------------------------------------
    -- CAS latency, counted in the units that matter.
    --
    -- The contract is: a READ latched at edge N has its data SAMPLED by
    -- the controller at edge N+CL.  For the data to be sampled at edge
    -- N+CL it must be ON the bus during the period before it, which
    -- means the driving register is assigned at edge N+CL-1.
    --
    -- So the countdown is CL-1 edges long, not CL.  Getting this off by
    -- one makes the model hold the bus at Z exactly when the controller
    -- looks at it, and every read comes back as high impedance -- which
    -- is a model bug that looks precisely like a controller bug.
    ----------------------------------------------------------------------
    signal drive_cnt  : natural range 0 to 15 := 0;

    ----------------------------------------------------------------------
    -- BURST SUPPORT.
    --
    -- One command, several words on consecutive clocks.  The length
    -- comes from the mode register rather than a generic, so the model
    -- follows whatever the controller actually programmed -- which is
    -- how it caught a controller asking for bursts of 4 while its
    -- comment claimed 1.
    ----------------------------------------------------------------------
    -- Mode register A2-A0, as an actual length.  One place, so the
    -- burst the model obeys and the burst it reports cannot drift apart.
    function burst_decode (f : std_logic_vector(2 downto 0)) return natural is
    begin
        case to_integer(unsigned(f)) is
            when 0      => return 1;
            when 1      => return 2;
            when 2      => return 4;
            when others => return 8;
        end case;
    end function burst_decode;

    signal burst_len : natural range 1 to 8 := 1;

    -- CAS LATENCY FROM THE MODE REGISTER, not from a generic.
    --
    -- The controller programs it, so the model must follow it, exactly
    -- as it follows the burst length.  Hard-coding it meant the
    -- simulation needed a different capture latency from the board --
    -- and a testbench that disagrees with the hardware about a number
    -- this central is worse than no testbench, because it makes the
    -- right setting look wrong.
    signal cas_lat : natural range 1 to 7 := CAS_LATENCY;

    signal rd_left : natural range 0 to 8 := 0;
    signal rd_cur  : natural := 0;

    signal wr_left : natural range 0 to 8 := 0;
    signal wr_cur  : natural := 0;

begin

    dram_dq <= dq_drv;

    cs_n_s  <= transport dram_cs_n  after 1 ns;
    ras_n_s <= transport dram_ras_n after 1 ns;
    cas_n_s <= transport dram_cas_n after 1 ns;
    we_n_s  <= transport dram_we_n  after 1 ns;
    cke_s   <= transport dram_cke   after 1 ns;
    addr_s  <= transport dram_addr  after 1 ns;
    ba_s    <= transport dram_ba    after 1 ns;
    dq_s    <= transport dram_dq    after 1 ns;

    -- mem is shared between the command decode and the burst engine, so
    -- it is a process-level variable reached through a small helper
    -- rather than being declared inside either.
    process (dram_clk) is
        variable mem      : mem_t := load_mif(INIT_FILE);

        impure function mem_read (a : natural) return std_logic_vector is
        begin
            return mem(a mod MEM_SIZE);
        end function;

        variable open_row : row_t := (others => -1);
        variable bank     : integer;
        variable col      : integer;
        variable full     : integer;
        variable cmd      : std_logic_vector(2 downto 0);
    begin
        if rising_edge(dram_clk) then

            -- Read data: first word after the latency, the rest on
            -- consecutive clocks with the bus driven throughout.
            if drive_cnt > 1 then
                drive_cnt <= drive_cnt - 1;
                if not HOLD_BUS then
                    dq_drv <= (others => 'Z');
                end if;
            elsif drive_cnt = 1 then
                dq_drv <= mem_read(rd_cur);
                if VERBOSE then
                    report "  drive word from addr " & integer'image(rd_cur)
                         & " = " & to_hstring(mem_read(rd_cur));
                end if;
                rd_cur <= rd_cur + 1;
                if rd_left > 1 then
                    rd_left   <= rd_left - 1;
                    drive_cnt <= 1;            -- next word, next clock
                else
                    rd_left   <= 0;
                    drive_cnt <= 0;
                end if;
            else
                if not HOLD_BUS then
                    dq_drv <= (others => 'Z');
                end if;
            end if;

            -- Write data: beats after the first arrive on the clocks
            -- following the command.
            if wr_left > 0 then
                mem(wr_cur mod MEM_SIZE) := dq_s;
                wr_cur  <= wr_cur + 1;
                wr_left <= wr_left - 1;
            end if;

            -- The is_x guard is not cosmetic.  On the first clock edge
            -- the controller's outputs have not been driven yet, so the
            -- command and bank bits are still 'U'; decoding them warns
            -- about a metavalue on every single run at t = 20 ns.  A
            -- warning that always fires is a warning nobody reads, and
            -- the next one to appear -- an address going 'U' mid-render,
            -- say -- would look exactly like it and be skipped over.
            --
            -- is_x is qualified and the command bits are tested one at a
            -- time: unqualified it is ambiguous between std_logic_1164
            -- and numeric_std, and a bare concatenation gives the
            -- compiler no way to pick between them either.
            if cke_s = '1' and cs_n_s = '0'
               and (ras_n_s = '0' or ras_n_s = '1')
               and (cas_n_s = '0' or cas_n_s = '1')
               and (we_n_s  = '0' or we_n_s  = '1')
               and not ieee.std_logic_1164.is_x(ba_s) then
                cmd  := ras_n_s & cas_n_s & we_n_s;
                bank := to_integer(unsigned(ba_s));

                case cmd is

                    when "011" =>                          -- ACTIVATE
                        open_row(bank) := to_integer(unsigned(addr_s));
                        if VERBOSE then
                            report "ACTIVATE bank " & integer'image(bank)
                                 & " row " & integer'image(open_row(bank));
                        end if;

                    when "101" =>                          -- READ
                        col  := to_integer(unsigned(addr_s(9 downto 0)));
                        assert open_row(bank) >= 0
                            report "READ with no row open in bank "
                                 & integer'image(bank)
                            severity error;
                        full := ((bank * 8192 + open_row(bank)) * 1024 + col)
                                mod MEM_SIZE;
                        rd_cur    <= full;
                        rd_left   <= burst_len;
                        drive_cnt <= cas_lat + BOARD_DELAY - 1;
                        if VERBOSE then
                            report "READ  col " & integer'image(col)
                                 & " -> addr " & integer'image(full)
                                 & " = " & to_hstring(mem(full));
                        end if;
                        if addr_s(10) = '1' then
                            open_row(bank) := -1;          -- auto-precharge
                        end if;

                    when "100" =>                          -- WRITE
                        col  := to_integer(unsigned(addr_s(9 downto 0)));
                        assert open_row(bank) >= 0
                            report "WRITE with no row open in bank "
                                 & integer'image(bank)
                            severity error;
                        full := ((bank * 8192 + open_row(bank)) * 1024 + col)
                                mod MEM_SIZE;
                        mem(full) := dq_s;
                        wr_cur  <= full + 1;
                        wr_left <= burst_len - 1;
                        if VERBOSE then
                            report "WRITE col " & integer'image(col)
                                 & " -> addr " & integer'image(full)
                                 & " = " & to_hstring(dq_s);
                        end if;
                        if addr_s(10) = '1' then
                            open_row(bank) := -1;
                        end if;

                    when "010" =>                          -- PRECHARGE
                        if addr_s(10) = '1' then
                            open_row := (others => -1);
                        else
                            open_row(bank) := -1;
                        end if;

                    when "001" =>                          -- AUTO REFRESH
                        null;

                    when "000" =>                          -- MODE REGISTER SET
                        burst_len <= burst_decode(addr_s(2 downto 0));
                        cas_lat <= to_integer(unsigned(addr_s(6 downto 4)));
                        -- Report the decoded LENGTH, not the field.
                        -- A2-A0 = "001" is a burst of TWO, and printing
                        -- the raw 1 next to a controller that issues
                        -- one command per pair of words reads as a
                        -- disagreement that is not there.
                        report "MRS burst="
                             & integer'image(burst_decode(addr_s(2 downto 0)))
                             & " cas="
                             & integer'image(to_integer(unsigned(addr_s(6 downto 4))));

                    when others =>
                        null;                              -- NOP
                end case;
            end if;
        end if;
    end process;

end architecture behavioural;
