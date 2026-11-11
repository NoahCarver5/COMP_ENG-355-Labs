library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram is
    generic(
        REQ_ADDR_WIDTH : natural := 19;
        CLK_FREQ_HZ : natural := 50_000_000;
        INIT_WAIT_US : natural := 200
    );
    port(
        clk        : in    std_logic;
        reset      : in    std_logic;
        rd_addr    : in    std_logic_vector(REQ_ADDR_WIDTH - 1 downto 0);
        rd_data    : out   std_logic_vector(23 downto 0);
        rd_valid   : out   std_logic;

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
end entity sdram;

architecture rtl of sdram is
    type state_t is (
        ST_RESET_WAIT,
        ST_INIT_PRE,
        ST_INIT_AR1,
        ST_INIT_AR2,
        ST_INIT_MRS,
        ST_IDLE,
        ST_ACT0,
        ST_READ0,
        ST_CAP0,
        ST_ACT1,
        ST_READ1,
        ST_CAP1,
        ST_DONE
    );

    constant INIT_WAIT_CYCLES : natural := (CLK_FREQ_HZ / 1_000_000) * INIT_WAIT_US;

    signal state : state_t;
    signal wait_count : natural range 0 to INIT_WAIT_CYCLES;
    signal cmd_wait : natural range 0 to 7;

    signal rd_addr_reg : std_logic_vector(REQ_ADDR_WIDTH - 1 downto 0);
    signal hw_addr0 : unsigned(REQ_ADDR_WIDTH downto 0);
    signal hw_addr1 : unsigned(REQ_ADDR_WIDTH downto 0);

    signal low_word : std_logic_vector(15 downto 0);
    signal high_word : std_logic_vector(15 downto 0);

    signal addr_cmd : std_logic_vector(12 downto 0);
    signal ba_cmd : std_logic_vector(1 downto 0);

    function map_row(addr : unsigned) return std_logic_vector is
        variable result : std_logic_vector(12 downto 0);
    begin
        result := (others => '0');
        if (addr'length >= 18) then
            result := std_logic_vector(addr(17 downto 5));
        else
            result(addr'length - 1 downto 0) := std_logic_vector(addr);
        end if;
        return result;
    end function map_row;

    function map_col(addr : unsigned) return std_logic_vector is
        variable result : std_logic_vector(12 downto 0);
        variable col9 : std_logic_vector(8 downto 0);
    begin
        result := (others => '0');
        col9 := (others => '0');
        if (addr'length >= 5) then
            col9(4 downto 0) := std_logic_vector(addr(4 downto 0));
        else
            col9(addr'length - 1 downto 0) := std_logic_vector(addr);
        end if;

        -- A10=1 enables auto-precharge after each READ command.
        result(10) := '1';
        result(8 downto 0) := col9;
        return result;
    end function map_col;

    function map_bank(addr : unsigned) return std_logic_vector is
        variable result : std_logic_vector(1 downto 0);
    begin
        result := (others => '0');
        if (addr'length >= 20) then
            result := std_logic_vector(addr(19 downto 18));
        elsif (addr'length = 19) then
            result(0) := addr(18);
        end if;
        return result;
    end function map_bank;
begin
    dram_clk <= clk;
    dram_cke <= '1';
    dram_dq <= (others => 'Z');
    dram_ldqm <= '0';
    dram_udqm <= '0';

    process(clk, reset)
    begin
        if (reset = '1') then
            state <= ST_RESET_WAIT;
            wait_count <= 0;
            cmd_wait <= 0;
            rd_addr_reg <= (others => '0');
            low_word <= (others => '0');
            high_word <= (others => '0');
            rd_data <= (others => '0');
            rd_valid <= '0';
            addr_cmd <= (others => '0');
            ba_cmd <= (others => '0');
            dram_cs_n <= '0';
            dram_ras_n <= '1';
            dram_cas_n <= '1';
            dram_we_n <= '1';
            dram_addr <= (others => '0');
            dram_ba <= (others => '0');
        elsif rising_edge(clk) then
            rd_valid <= '0';

            -- Default command is NOP.
            dram_cs_n <= '0';
            dram_ras_n <= '1';
            dram_cas_n <= '1';
            dram_we_n <= '1';
            dram_addr <= addr_cmd;
            dram_ba <= ba_cmd;

            case state is
                when ST_RESET_WAIT =>
                    if (wait_count < INIT_WAIT_CYCLES) then
                        wait_count <= wait_count + 1;
                    else
                        addr_cmd <= (others => '0');
                        addr_cmd(10) <= '1';
                        ba_cmd <= (others => '0');
                        state <= ST_INIT_PRE;
                    end if;

                when ST_INIT_PRE =>
                    -- PRECHARGE ALL
                    dram_ras_n <= '0';
                    dram_cas_n <= '1';
                    dram_we_n <= '0';
                    cmd_wait <= 2;
                    state <= ST_INIT_AR1;

                when ST_INIT_AR1 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        -- AUTO REFRESH
                        dram_ras_n <= '0';
                        dram_cas_n <= '0';
                        dram_we_n <= '1';
                        cmd_wait <= 2;
                        state <= ST_INIT_AR2;
                    end if;

                when ST_INIT_AR2 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        -- AUTO REFRESH
                        dram_ras_n <= '0';
                        dram_cas_n <= '0';
                        dram_we_n <= '1';
                        cmd_wait <= 2;
                        state <= ST_INIT_MRS;
                    end if;

                when ST_INIT_MRS =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        -- MODE REGISTER SET: burst length=1, CAS latency=2.
                        dram_ras_n <= '0';
                        dram_cas_n <= '0';
                        dram_we_n <= '0';
                        addr_cmd <= "0000000100010";
                        ba_cmd <= (others => '0');
                        state <= ST_IDLE;
                    end if;

                when ST_IDLE =>
                    rd_addr_reg <= rd_addr;
                    hw_addr0 <= resize(unsigned(rd_addr), hw_addr0'length) sll 1;
                    hw_addr1 <= (resize(unsigned(rd_addr), hw_addr1'length) sll 1) + 1;

                    addr_cmd <= map_row(hw_addr0);
                    ba_cmd <= map_bank(hw_addr0);
                    state <= ST_ACT0;

                when ST_ACT0 =>
                    -- ACTIVATE row for first halfword.
                    dram_ras_n <= '0';
                    dram_cas_n <= '1';
                    dram_we_n <= '1';
                    cmd_wait <= 1;
                    state <= ST_READ0;

                when ST_READ0 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        -- READ with auto-precharge.
                        dram_ras_n <= '1';
                        dram_cas_n <= '0';
                        dram_we_n <= '1';
                        addr_cmd <= map_col(hw_addr0);
                        ba_cmd <= map_bank(hw_addr0);
                        cmd_wait <= 2;
                        state <= ST_CAP0;
                    end if;

                when ST_CAP0 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        low_word <= dram_dq;
                        addr_cmd <= map_row(hw_addr1);
                        ba_cmd <= map_bank(hw_addr1);
                        state <= ST_ACT1;
                    end if;

                when ST_ACT1 =>
                    dram_ras_n <= '0';
                    dram_cas_n <= '1';
                    dram_we_n <= '1';
                    cmd_wait <= 1;
                    state <= ST_READ1;

                when ST_READ1 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        dram_ras_n <= '1';
                        dram_cas_n <= '0';
                        dram_we_n <= '1';
                        addr_cmd <= map_col(hw_addr1);
                        ba_cmd <= map_bank(hw_addr1);
                        cmd_wait <= 2;
                        state <= ST_CAP1;
                    end if;

                when ST_CAP1 =>
                    if (cmd_wait > 0) then
                        cmd_wait <= cmd_wait - 1;
                    else
                        high_word <= dram_dq;
                        state <= ST_DONE;
                    end if;

                when ST_DONE =>
                    -- 32-bit packed RGB word format in SDRAM: [31:24]=pad, [23:0]=RGB888.
                    rd_data <= high_word(7 downto 0) & low_word;
                    rd_valid <= '1';
                    state <= ST_IDLE;

                when others =>
                    state <= ST_IDLE;
            end case;
        end if;
    end process;
end architecture rtl;
