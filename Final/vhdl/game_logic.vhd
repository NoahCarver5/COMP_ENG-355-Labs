library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.whac_pkg.all;

entity game_logic is
    generic(
        CLK_FREQUENCY : natural := 100_000_000;
        TICK_LENGTH : natural := 20_000_000;
        HOLE_SEED : std_logic_vector(5 downto 0) := "101010";
        TIME_SEED : std_logic_vector(6 downto 0) := "1010101"
        );
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        hand : in  hand_t;  -- active-low, KEY[3:0]
        game_state : out game_state_t;
        mole_state_array : out mole_state_array_t;
        score : out bcd_pair_t;
        time_left : out bcd_pair_t
    );
end entity game_logic;

architecture rtl of game_logic is

    constant NUM_MOLES      : positive := mole_state_array_t'length;
    constant MAX_ACTIVE     : positive := 2;
    constant START_SECONDS  : natural  := 30;
    constant HIT_TIME_BONUS : natural  := 1;   -- seconds added per hit (0 disables)
    constant MIN_MOLE_TICKS : natural  := 3;   -- moles stay 3..10 ticks (0.6 - 2.0 s)

    type mole_time_array_t is array (0 to NUM_MOLES - 1) of natural range 0 to 255;

    -- (1) = tens, (0) = ones
    function to_bcd (n : natural range 0 to 99) return bcd_pair_t is
        variable r : bcd_pair_t;
    begin
        r(0) := to_unsigned(n mod 10, 4);
        r(1) := to_unsigned(n / 10, 4);
        return r;
    end function;

    signal cur_state, next_state : game_state_t;
    signal next_score, cur_score : natural range 0 to 99;
    signal next_mole_state, cur_mole_state : mole_state_array_t;
    signal next_mole_time, cur_mole_time : mole_time_array_t;
    signal next_time_left, cur_time_left : natural range 0 to 99;
    signal moles_active : std_logic_vector (2 downto 0);
    signal tick_cnt : natural range 0 to TICK_LENGTH-1;
    signal second_cnt : natural range 0 to CLK_FREQUENCY-1;
    signal hole_lfsr : std_logic_vector(5 downto 0);
    signal time_lfsr : std_logic_vector(6 downto 0);

begin

    game_state       <= cur_state;
    mole_state_array <= cur_mole_state;
    score            <= to_bcd(cur_score);
    time_left        <= to_bcd(cur_time_left);

    lfsr_generation : process(clk, rst) begin

        if (rst = '1') then
            hole_lfsr <= HOLE_SEED;
            time_lfsr <= TIME_SEED;
        elsif (rising_edge(clk)) then
            hole_lfsr <= hole_lfsr (4 downto 0) & (hole_lfsr(5) xor hole_lfsr(4));
            time_lfsr <= time_lfsr (5 downto 0) & (time_lfsr(6) xor time_lfsr(5));
        end if;
    end process lfsr_generation;

    -- number of moles currently showing
    count_active : process(all)
        variable n : natural range 0 to NUM_MOLES;
    begin
        n := 0;
        for i in 0 to NUM_MOLES - 1 loop
            if (cur_mole_state(i) = VISIBLE) then
                n := n + 1;
            end if;
        end loop;
        moles_active <= std_logic_vector(to_unsigned(n, 3));
    end process count_active;

    game_state_clocked: process (clk, rst) begin

        if (rst = '1') then
            cur_state <= IDLE;
            cur_score <= 0;
            cur_mole_state <= (others => HIDDEN);
            cur_mole_time <= (others => 0);
            cur_time_left <= 0;
            second_cnt <= 0;
            tick_cnt <= 0;

        elsif rising_edge(clk) then
            cur_state <= next_state;
            cur_score <= next_score;
            cur_mole_state <= next_mole_state;
            cur_mole_time <= next_mole_time;
            cur_time_left <= next_time_left;

            -- counters only run while playing, so the first second is a full second
            if (cur_state = PLAY) then
                if tick_cnt = TICK_LENGTH-1 then
                    tick_cnt <= 0;
                else
                    tick_cnt <= tick_cnt + 1;
                end if;

                if second_cnt = CLK_FREQUENCY -1 then
                    second_cnt <= 0;
                else
                    second_cnt <= second_cnt + 1;
                end if;
            else
                tick_cnt <= 0;
                second_cnt <= 0;
            end if;

        end if;

    end process game_state_clocked;

    game_state_fsm : process(all)
        variable v_score : natural range 0 to 99;
        variable v_time  : natural range 0 to 99;
        variable hole    : natural range 0 to NUM_MOLES - 1;
        variable idx     : natural range 0 to 7;
    begin

        next_state <= cur_state;
        next_mole_state <= cur_mole_state;
        next_mole_time <= cur_mole_time;
        next_score <= cur_score;
        next_time_left <= cur_time_left;

        case cur_state is
            when IDLE =>
                if (hand.strike = '1') then
                    next_state <= PLAY;
                    next_score <= 0;
                    next_time_left <= START_SECONDS;
                end if;

            when PLAY =>
                -- score / time are built up in variables so a strike and the
                -- one-second countdown can land on the same clock
                v_score := cur_score;
                v_time  := cur_time_left;

                if (second_cnt = CLK_FREQUENCY - 1) then

                    -- a second boundary is also a mole tick (CLK_FREQUENCY is a
                    -- multiple of TICK_LENGTH), so age the moles here too
                    for i in 0 to NUM_MOLES - 1 loop
                        if (cur_mole_state(i) = VISIBLE) then
                            if (cur_mole_time(i) <= 1) then
                                next_mole_state(i) <= HIDDEN;
                                next_mole_time(i) <= 0;
                            else
                                next_mole_time(i) <= cur_mole_time(i) - 1;
                            end if;
                        end if;
                    end loop;

                    -- once per second: try to show a new mole
                    hole := to_integer(unsigned(hole_lfsr)) mod NUM_MOLES;
                    if (unsigned(moles_active) < MAX_ACTIVE) then
                        if (cur_mole_state(hole) = HIDDEN) then
                            next_mole_state(hole) <= VISIBLE;
                            next_mole_time(hole) <= MIN_MOLE_TICKS
                                                    + to_integer(unsigned(time_lfsr(2 downto 0)));
                        end if;
                    end if;

                    -- once per second: countdown
                    if (v_time > 0) then
                        v_time := v_time - 1;
                    end if;

                elsif (tick_cnt = TICK_LENGTH - 1) then

                    -- every other mole tick: age the moles
                    for i in 0 to NUM_MOLES - 1 loop
                        if (cur_mole_state(i) = VISIBLE) then
                            if (cur_mole_time(i) <= 1) then
                                next_mole_state(i) <= HIDDEN;
                                next_mole_time(i) <= 0;
                            else
                                next_mole_time(i) <= cur_mole_time(i) - 1;
                            end if;
                        end if;
                    end loop;

                end if;

                -- strike (after the block above so a hit wins over an expiry)
                idx := to_integer(hand.hole_idx);
                if (hand.strike = '1') and (idx < NUM_MOLES) then
                    if (cur_mole_state(idx) = VISIBLE) then
                        next_mole_state(idx) <= HIDDEN;
                        next_mole_time(idx) <= 0;
                        if (v_score = 99) then
                            v_score := 99;
                        else
                            v_score := v_score + 1;
                        end if;

                        if (v_time + HIT_TIME_BONUS > 99) then
                            v_time := 99;
                        else
                            v_time := v_time + HIT_TIME_BONUS;
                        end if;
                    else
                        if (v_score = 0) then
                            v_score := 0;
                        else
                            v_score := v_score - 1;
                        end if;
                    end if;
                end if;

                next_score <= v_score;
                next_time_left <= v_time;

                if (v_time = 0) then
                    next_state <= GAME_OVER;
                    next_mole_state <= (others => HIDDEN);
                    next_mole_time <= (others => 0);
                end if;

            when GAME_OVER =>
                if (hand.strike = '1') then
                    next_state <= IDLE;
                end if;

        end case;

    end process game_state_fsm;

end architecture rtl;
