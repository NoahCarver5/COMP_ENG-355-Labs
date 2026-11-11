library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

--------------------------------------------------------------------------
-- Image writer: PC to SDRAM, straight down the JTAG cable.
--
-- Self contained.  sld_virtual_jtag is a library primitive, so this is
-- one entity with nothing to add to the project file list, no FIFO and
-- no bus.  Out of it come a pixel, an address and a write strobe --
-- exactly what an SDRAM writer wants.
--
-- WHY THIS EXISTS.  A .mif only ever initialises memory inside the
-- FPGA; there is no way to put one into an external SDRAM chip at
-- configuration time.  And the image is far too big to stage in the
-- fabric and copy out -- 4096x2048 at 24 bits is 192 Mbit against 7.33
-- Mbit of on-chip memory.  If it fitted, there would be no reason to
-- have an SDRAM at all.  So it arrives from outside after the FPGA is
-- configured and running, down the cable used to program it.
--
--========================================================================
-- WHY A BLOCK OF PIXELS PER SHIFT, NOT ONE
--========================================================================
--
-- 4096x2048 is 8_388_608 pixels, and each device_virtual_dr_shift is a
-- USB round trip costing a millisecond or two whatever its length.  One
-- shift per pixel is four hours with the cable idle throughout.
--
-- So each shift carries PIXELS_PER_SHIFT pixels: 65_536 round trips
-- instead of 8.4 million, and the transfer becomes bounded by the
-- cable's bit rate rather than its latency.  The cost is a shift
-- register PIXELS_PER_SHIFT*24 bits wide, which is registers this
-- device has in abundance.
--
-- N_PIXELS MUST BE A WHOLE NUMBER OF BLOCKS.  8_388_608 / 128 = 65_536
-- exactly.  A ragged last block would need the host to vary the length
-- of the final shift, and there is no reason to carry that for an image
-- whose dimensions are powers of two.
--
-- SHIFT DIRECTION.  JTAG shifts least significant bit first, so each
-- new bit enters at the TOP and the register walks down.  After a full
-- shift the first bit sent sits in bit 0, which puts the FIRST pixel of
-- the block in the LOW 24 bits -- and draining by shifting right 24 at
-- a time hands them out in the order the host sent them.  Backwards
-- gives a picture with its channels reversed and every value
-- bit-mirrored, which looks like noise rather than an obvious swap.
--
--========================================================================
-- THREE PROCESSES, AND WHY NOT TWO
--========================================================================
--
-- The system side is the usual pair: fsm_process computes the next
-- state and the next value of every register, clocked_process registers
-- them.
--
-- jtag_process is a third, and has to be: it runs on tck, the cable's
-- clock, which is a different clock domain entirely.  Merging it would
-- mean clocking JTAG logic from the system clock, and tck is
-- asynchronous to clk and STOPS between shifts.
--
-- It has no reset, deliberately.  A system reset asserted while the
-- cable is idle would never be released there, because no tck edge
-- arrives to release it; and releasing it asynchronously near a tck
-- edge could glitch the event toggle, manufacturing a phantom shift.
-- The initial values on the declarations cover power-up.
--
--========================================================================
-- CROSSING TO THE SYSTEM CLOCK
--========================================================================
--
-- Events cross as levels that toggle, caught by two flops; a pulse
-- would be missed while tck is stopped.  shift_reg is read only after
-- the toggle has crossed, by which time tck has been stopped for at
-- least two clk periods and it is long settled.
--
-- THE TAP STATE SIGNALS ARE LEVELS, high for as long as the TAP sits in
-- that state -- several tck edges on real hardware.  They are
-- edge-detected here so one visit is one event.  Toggling on every edge
-- instead signalled the system side two or three times per shift, and
-- each of those was a complete write at the next address: every pixel
-- written twice, reading back as every address returning its
-- neighbour's data.  A stub that pulses the state for a single edge
-- hides this completely, which is why it survived simulation.
--
-- THE DRAIN OUTRUNS THE CABLE, so there is no handshake back to the
-- host.  A block is 128 SDRAM writes at roughly 14 clocks each -- about
-- 36 us at 50 MHz -- while shifting the next 3072 bits takes 3 ms even
-- at a pessimistic 1 MHz tck.  Two orders of magnitude of margin.
--
-- ADDRESSING.  The counter starts at zero and steps once per pixel
-- WRITTEN, so the host simply streams the file in order.  Shifting the
-- instruction register to 1 resets it, restarting a load without
-- resetting the board.
--
-- THERE IS NO DONE FLAG, and there is nothing for one to do.  It existed
-- to hold the renderer off until the whole image had arrived, back when
-- the two sides raced for the pins.  They do not: the controller
-- serialises every access through one state machine, so a read and a
-- write cannot be in flight together and there is no hazard to gate.
--
-- What remains without it is that a frame drawn mid-transfer shows
-- whatever has arrived so far -- which is a picture filling in, not a
-- failure, and it is worth being able to see.  The board says so from
-- wr_req itself: the write strobe is already wired out to an LED, which
-- costs no signal here and reports the transfer actually happening
-- rather than a counter's opinion of it.
--
-- The address counter stops at N_PIXELS - 1 rather than wrapping, so a
-- stray extra block lands on the last pixel instead of overwriting the
-- top of the image.
--------------------------------------------------------------------------
entity jtag_sdram_writer is
    generic (
        DATA_WIDTH       : natural := 24;
        ADDR_WIDTH       : natural := 23;       -- 4096*2048 = 2**23
        N_PIXELS         : natural := 8388608;
        PIXELS_PER_SHIFT : natural := 128
    );
    port (
        clk     : in  std_logic;
        reset   : in  std_logic;                -- active high

        -- ---- to the SDRAM controller ----
        wr_req  : out std_logic;
        wr_addr : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
        wr_data : out std_logic_vector(DATA_WIDTH - 1 downto 0);
        wr_ack  : in  std_logic
    );
end entity jtag_sdram_writer;


architecture rtl of jtag_sdram_writer is

    constant SHIFT_BITS : natural := PIXELS_PER_SHIFT * DATA_WIDTH;

    -- ---- JTAG clock domain ----
    signal tck    : std_logic;
    signal tdi    : std_logic;
    signal tdo    : std_logic;
    signal v_sdr  : std_logic;
    signal v_udr  : std_logic;
    signal v_uir  : std_logic;
    signal ir_in  : std_logic_vector(0 downto 0);
    signal ir_out : std_logic_vector(0 downto 0) := (others => '0');

    signal shift_reg : std_logic_vector(SHIFT_BITS - 1 downto 0)
                     := (others => '0');
    signal udr_d    : std_logic := '0';
    signal uir_d    : std_logic := '0';
    signal tck_flag : std_logic := '0';   -- toggles once per block
    signal tck_rst  : std_logic := '0';   -- toggles on an address reset

    -- ---- system clock domain ----
    type sys_state_t is (S_IDLE, S_WRITE);

    signal state,     next_state  : sys_state_t;
    signal flag_meta, flag_meta_c : std_logic;
    signal flag_sync, flag_sync_c : std_logic;
    signal flag_prev, flag_prev_c : std_logic;
    signal rst_meta,  rst_meta_c  : std_logic;
    signal rst_sync,  rst_sync_c  : std_logic;
    signal rst_prev,  rst_prev_c  : std_logic;

    signal buf,      buf_c      : std_logic_vector(SHIFT_BITS - 1 downto 0);
    signal pix_left, pix_left_c : natural range 0 to PIXELS_PER_SHIFT;
    signal addr_cnt, addr_cnt_c : unsigned(ADDR_WIDTH - 1 downto 0);
    signal data_r,   data_c     : std_logic_vector(DATA_WIDTH - 1 downto 0);

    signal flag_evt : std_logic;
    signal rst_evt  : std_logic;

begin

    wr_addr <= std_logic_vector(addr_cnt);
    wr_data <= data_r;
    tdo     <= shift_reg(0);          -- keep the chain continuous

    flag_evt <= flag_sync xor flag_prev;
    rst_evt  <= rst_sync  xor rst_prev;

    u_vjtag : sld_virtual_jtag
        generic map (
            sld_auto_instance_index => "YES",
            sld_instance_index      => 0,
            sld_ir_width            => 1
        )
        port map (
            tck               => tck,
            tdi               => tdi,
            tdo               => tdo,
            ir_in             => ir_in,
            ir_out            => ir_out,
            virtual_state_sdr => v_sdr,
            virtual_state_udr => v_udr,
            virtual_state_uir => v_uir,
            -- Everything else on this primitive is unused here.
            virtual_state_cdr  => open,
            virtual_state_cir  => open,
            virtual_state_e1dr => open,
            virtual_state_e2dr => open,
            virtual_state_pdr  => open,
            jtag_state_cdr     => open,
            jtag_state_cir     => open,
            jtag_state_e1dr    => open,
            jtag_state_e1ir    => open,
            jtag_state_e2dr    => open,
            jtag_state_e2ir    => open,
            jtag_state_pdr     => open,
            jtag_state_pir     => open,
            jtag_state_rti     => open,
            jtag_state_sdr     => open,
            jtag_state_sdrs    => open,
            jtag_state_sir     => open,
            jtag_state_sirs    => open,
            jtag_state_tlr     => open,
            jtag_state_udr     => open,
            jtag_state_uir     => open,
            tms                => open
        );

    ----------------------------------------------------------------------
    -- JTAG clock domain.  A separate clock, so necessarily a separate
    -- process; see the header for why it has no reset.
    ----------------------------------------------------------------------
    jtag_process : process(tck) is
    begin
        if rising_edge(tck) then
            if ( v_sdr = '1' ) then
                -- LSB first: in at the top, walking down.
                shift_reg <= tdi & shift_reg(SHIFT_BITS - 1 downto 1);
            end if;

            -- Rising edge only: one visit to the state is one event,
            -- however many tck edges the TAP spends in it.
            udr_d <= v_udr;
            uir_d <= v_uir;

            if ( v_udr = '1' ) and ( udr_d = '0' ) then
                tck_flag <= not tck_flag;
            end if;

            if ( v_uir = '1' ) and ( uir_d = '0' ) and ( ir_in(0) = '1' ) then
                tck_rst <= not tck_rst;
            end if;
        end if;
    end process jtag_process;

    ----------------------------------------------------------------------
    -- Next state and next values.  Combinational.
    ----------------------------------------------------------------------
    fsm_process : process(all) is
    begin
        -- Hold by default.
        next_state  <= state;
        buf_c       <= buf;
        pix_left_c  <= pix_left;
        addr_cnt_c  <= addr_cnt;
        data_c      <= data_r;

        -- The synchroniser chains advance every clock.
        flag_meta_c <= tck_flag;  flag_sync_c <= flag_meta;  flag_prev_c <= flag_sync;
        rst_meta_c  <= tck_rst;   rst_sync_c  <= rst_meta;   rst_prev_c  <= rst_sync;

        wr_req <= '0';

        case state is

            when S_IDLE =>
                if ( pix_left > 0 ) then
                    -- First pixel of the block sits in the low bits,
                    -- because JTAG shifted it in first.
                    data_c     <= buf(DATA_WIDTH - 1 downto 0);
                    next_state <= S_WRITE;
                end if;

            when S_WRITE =>
                -- Held until acknowledged.  The controller latches the
                -- request on its rising edge, so holding is safe and
                -- releasing early would lose it.
                wr_req <= '1';
                if ( wr_ack = '1' ) then
                    buf_c      <= std_logic_vector(shift_right(unsigned(buf),
                                                               DATA_WIDTH));
                    pix_left_c <= pix_left - 1;

                    -- Stop at the end rather than wrapping: see the
                    -- header.
                    if ( addr_cnt /= N_PIXELS - 1 ) then
                        addr_cnt_c <= addr_cnt + 1;
                    end if;

                    next_state <= S_IDLE;
                end if;

        end case;

        -- ---- a new block has arrived ----
        --
        -- Safe to overwrite buf: the drain finishes about a hundred
        -- times faster than the host can shift the next block in.
        if ( flag_evt = '1' ) then
            buf_c      <= shift_reg;
            pix_left_c <= PIXELS_PER_SHIFT;
        end if;

        -- ---- a restart from the host ----
        --
        -- Outranks everything: the point of it is to abandon whatever
        -- was in progress.
        if ( rst_evt = '1' ) then
            addr_cnt_c <= (others => '0');
            pix_left_c <= 0;
            next_state <= S_IDLE;
        end if;
    end process fsm_process;

    ----------------------------------------------------------------------
    -- State and datapath registers.  Asynchronous reset, synchronous
    -- everything else.
    ----------------------------------------------------------------------
    clocked_process : process(clk, reset) is
    begin
        if reset = '1' then
            state     <= S_IDLE;
            flag_meta <= '0';  flag_sync <= '0';  flag_prev <= '0';
            rst_meta  <= '0';  rst_sync  <= '0';  rst_prev  <= '0';
            buf       <= (others => '0');
            pix_left  <= 0;
            addr_cnt  <= (others => '0');
            data_r    <= (others => '0');

        elsif rising_edge(clk) then
            state     <= next_state;
            flag_meta <= flag_meta_c;  flag_sync <= flag_sync_c;  flag_prev <= flag_prev_c;
            rst_meta  <= rst_meta_c;   rst_sync  <= rst_sync_c;   rst_prev  <= rst_prev_c;
            buf       <= buf_c;
            pix_left  <= pix_left_c;
            addr_cnt  <= addr_cnt_c;
            data_r    <= data_c;
        end if;
    end process clocked_process;

end architecture rtl;
