library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tla2518_adc is
    generic(
        -- Number of FPGA clock cycles per half SPI clock period.
        -- 50 MHz clock / (2 * 25) = 1 MHz SPI clock
        CLOCK_DIVIDER : positive := 25;

        -- Number of FPGA clock cycles between ADC readings.
        -- 50 MHz * 4 seconds = 200,000,000 cycles
        PAUSE_CYCLES  : positive := 200_000_000
    );

    port(
        -- FPGA clock and reset
        clk      : in  std_logic;
        reset_n  : in  std_logic;

        -- TLA2518 SPI interface
        adc_dout : in  std_logic;
        adc_din  : out std_logic;
        adc_sclk : out std_logic;
        adc_cs_n : out std_logic;

        -- Latest 12-bit ADC value
        sample   : out std_logic_vector(11 downto 0)
    );

end entity tla2518_adc;


architecture rtl of tla2518_adc is

    ----------------------------------------------------------------
    -- SPI timing
    --
    -- CLOCK_DIVIDER is the number of FPGA clock cycles for each
    -- half-period of SCLK.
    --
    -- Example: 50 MHz / (2 * 25) = 1 MHz SCLK
    ----------------------------------------------------------------
    constant HALF_PERIOD_CYCLES : positive := CLOCK_DIVIDER;

    ----------------------------------------------------------------
    -- State Machine
    ----------------------------------------------------------------
    type state_t is (idle, transfer, finish);
    signal state : state_t := idle;

    ----------------------------------------------------------------
    -- SPI clock divider
    ----------------------------------------------------------------
    signal half_count : natural range 0 to HALF_PERIOD_CYCLES - 1;

    ----------------------------------------------------------------
    -- Pause counter: Used to control how frequently a new ADC conversion is read.
    --
    -- At 50 MHz:
    --     50,000,000 cycles = 1 second
    --    200,000,000 cycles = 4 seconds
    ----------------------------------------------------------------
    signal pause_count : natural range 0 to PAUSE_CYCLES - 1;

    ----------------------------------------------------------------
    -- Number of ADC bits received
    -- TLA2518 outputs 12 bits when averaging is disabled.
    ----------------------------------------------------------------
    signal bit_count : natural range 0 to 11;

    ----------------------------------------------------------------
    -- SPI signals
    ----------------------------------------------------------------
    signal sclk_reg   : std_logic;
    signal cs_reg     : std_logic;
    signal din_reg    : std_logic;

    ----------------------------------------------------------------
    -- 12-bit SPI receive shift register
    ----------------------------------------------------------------
    signal shift_reg : std_logic_vector(11 downto 0);

    ----------------------------------------------------------------
    -- Output ADC value
    ----------------------------------------------------------------
    signal sample_reg : std_logic_vector(11 downto 0);

begin

    ----------------------------------------------------------------
    -- Physical outputs
    ----------------------------------------------------------------
    adc_din  <= din_reg;
    adc_sclk <= sclk_reg;
    adc_cs_n <= cs_reg;
    sample   <= sample_reg;

    ----------------------------------------------------------------
    -- TLA2518 SPI controller
    ----------------------------------------------------------------
    process(clk, reset_n)
        variable next_shift : std_logic_vector(11 downto 0);
    begin
        if (reset_n = '0') then
            state       <= idle;
            half_count  <= 0;
            pause_count <= 0;
            bit_count   <= 0;
            sclk_reg    <= '0';
            cs_reg      <= '1';
            din_reg     <= '0';
            shift_reg   <= (others => '0');
            sample_reg  <= (others => '0');
        elsif ( rising_edge(clk) ) then
            case state is
                ------------------------------------------------
                -- IDLE
                -- CS is HIGH.
                -- The TLA2518 conversion was started by the previous rising edge of CS.
                -- We wait several seconds before reading the result and starting the next conversion.
                ------------------------------------------------
                when idle =>
                    sclk_reg <= '0';
                    cs_reg   <= '1';
                    din_reg  <= '0';
                    half_count <= 0;
                    if (pause_count = PAUSE_CYCLES - 1) then
                        -- Begin SPI transaction. CS falling edge starts the SPI frame.
                        pause_count <= 0;
                        bit_count <= 0;
                        shift_reg <= (others => '0');
                        cs_reg <= '0';
                        state <= transfer;
                    else
                        pause_count <= pause_count + 1;
                    end if;

                ------------------------------------------------
                -- TRANSFER
                -- SPI-00:
                --     CPOL = 0
                --     CPHA = 0
                -- SCLK is LOW when CS falls.
                -- TLA2518 data is captured on the rising edge.
                ------------------------------------------------
                when transfer =>
                    cs_reg <= '0';
                    din_reg <= '0';
                    if half_count = HALF_PERIOD_CYCLES - 1 then
                        half_count <= 0;
                        ------------------------------------------------
                        -- SCLK LOW -> HIGH
                        -- Capture one ADC data bit.
                        ------------------------------------------------
                        if sclk_reg = '0' then
                            sclk_reg <= '1';
                            ------------------------------------------------
                            -- TLA2518 sends the ADC result MSB first.
                            ------------------------------------------------
                            next_shift := shift_reg(10 downto 0) & adc_dout;
                            shift_reg <= next_shift;
                            if bit_count = 11 then
                                ------------------------------------------------
                                -- The complete 12-bit conversion is now available.
                                -- Update the entire output bus at once.
                                ------------------------------------------------
                                sample_reg <= next_shift;
                                bit_count <= 0;
                                state <= finish;
                            else
                                bit_count <= bit_count + 1;
                            end if;

                        ------------------------------------------------
                        -- SCLK HIGH -> LOW
                        ------------------------------------------------
                        else
                            sclk_reg <= '0';
                        end if;
                    else
                        half_count <= half_count + 1;
                    end if;

                ------------------------------------------------
                -- FINISH
                -- Finish SPI transaction.
                -- Hold the last SCLK high for a half period, drive
                -- it LOW, then wait another half period before
                -- raising CS (TLA2518 requires at least 6 ns from
                -- the last SCLK falling edge to CS rising).
                -- CS rising edge starts the next TLA2518 conversion.
                ------------------------------------------------
                when finish =>
                    din_reg <= '0';
                    if half_count = HALF_PERIOD_CYCLES - 1 then
                        half_count <= 0;
                        if sclk_reg = '1' then
                            -- Last SCLK HIGH -> LOW
                            sclk_reg <= '0';
                        else
                            -- Half period later: CS HIGH
                            cs_reg <= '1';
                            pause_count <= 0;
                            state <= idle;
                        end if;
                    else
                        half_count <= half_count + 1;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;