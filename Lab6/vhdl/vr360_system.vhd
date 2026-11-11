library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;

entity vr360_system is
    port(
        clk_50        : in    std_logic;
        reset_n       : in    std_logic;

        -- ---- I2C to the IMU ----
        imu_uart_rx   : in    std_logic;

        -- Activity, ACTIVE LOW -- the board lights an LED by pulling
        -- its pin down, so these are inverted where they are driven.
        leds          : out   std_logic_vector(4 downto 0);

        hex0          : out   std_logic_vector(6 downto 0);
        hex1          : out   std_logic_vector(6 downto 0);
        hex2          : out   std_logic_vector(6 downto 0);
        hex3          : out   std_logic_vector(6 downto 0);
        hex4          : out   std_logic_vector(6 downto 0);
        hex5          : out   std_logic_vector(6 downto 0);

        dram_dq       : inout std_logic_vector(15 downto 0);
        dram_addr     : out   std_logic_vector(12 downto 0);
        dram_ba       : out   std_logic_vector(1 downto 0);
        dram_ldqm     : out   std_logic;
        dram_udqm     : out   std_logic;
        dram_ras_n    : out   std_logic;
        dram_cas_n    : out   std_logic;
        dram_cke      : out   std_logic;
        dram_clk      : out   std_logic;
        dram_we_n     : out   std_logic;
        dram_cs_n     : out   std_logic;

        -- ---- HDMI TX ----
        hdmi_tx_clk   : out   std_logic;
        hdmi_tx_d     : out   std_logic_vector(23 downto 0);
        hdmi_tx_hs    : out   std_logic;
        hdmi_tx_vs    : out   std_logic;
        hdmi_tx_de    : out   std_logic;
        hdmi_tx_int   : in    std_logic;   -- active low (hot plug)

        -- ---- I2C, to configure the HDMI transmitter ----
        hdmi_i2c_scl  : out   std_logic;
        hdmi_i2c_sda  : inout std_logic
    );
end entity vr360_system;


architecture structural of vr360_system is

    ----------------------------------------------------------------------
    -- STRUCTURAL ONLY -- pure wiring, no logic.
    --
    --       imu_uart_rx                   host PC (JTAG)
    --            |                               |
    --      +-----v-----+               +---------v---------+
    --      |    imu    |               | jtag_sdram_writer |
    --      +-----+-----+               +----+---------^----+
    --            | rx_s, ry_s, rz_s,        | wr_*_s  | wr_ack_s
    --            | rot_valid_s              |         |
    --      +-----v--------------------------v---------+-------+
    --      |                      vr360                       |
    --      |  renderer, sdram_ctrl, frame buffer, hex, leds   |
    --      +---+----------+---------+---------+---------^-----+
    --          | dram_*   | hex0..5 | leds    | pixel_s | frame_sync_s,
    --          |          |         |         |         | pixel_req_s
    --      +---v---+  7-segment    LEDs   +---v---------+-----+
    --      | SDRAM |                      |       hdmi        |
    --      | chip  |                      |    640x480 @ 60   |
    --      +-------+                      +---------+---------+
    --                                               | hdmi_tx_*, hdmi_i2c_*
    --                                               v
    --                                            monitor
    --
    -- Four peripherals and the wires between them.  Everything that
    -- decides anything -- the renderer, the memory controller, the frame
    -- buffer, the displays, the LEDs -- lives inside vr360, so this file
    -- says what the board is made of and nothing about how it behaves.
    --
    -- THE IMAGE WRITER IS HERE AND NOWHERE DEEPER.  It wraps
    -- sld_virtual_jtag, a hard block with no simulation model, so
    -- anything containing it cannot be simulated.  Keeping it at the top
    -- leaves vr360 and everything under it testable; this module is
    -- taken as given and verified on hardware.
    ----------------------------------------------------------------------

    constant CLK_FREQUENCY : natural := 50_000_000;
    constant ANGLE_WIDTH   : natural := 16;
    constant IMAGE_WIDTH   : natural := 4096;
    constant IMAGE_HEIGHT  : natural := 2048;
    constant OUT_WIDTH     : natural := 640;
    constant OUT_HEIGHT    : natural := 480;
    constant PIXEL_WIDTH   : natural := 24;
    constant FOCAL_LENGTH  : natural := 640;
    constant TRIG_WIDTH    : natural := 16;
    constant ADDR_WIDTH    : natural := log2(IMAGE_WIDTH * IMAGE_HEIGHT);
    constant IMU_BAUD_RATE : natural := 115_200;

    --------------------------------------------------------------------
    -- Components
    --------------------------------------------------------------------
    component imu is
        generic (
            CLK_FREQ    : natural := 50_000_000;
            BAUD_RATE   : natural := 115_200;
            ANGLE_WIDTH : natural := 16
        );
        port (
            clk        : in  std_logic;
            reset      : in  std_logic;
            uart_rx    : in  std_logic;
            rx         : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            ry         : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rz         : out std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            data_valid : out std_logic;
            byte_stb   : out std_logic;
            byte_data  : out std_logic_vector(7 downto 0);
            frame_stb  : out std_logic;
            frame_func : out std_logic_vector(7 downto 0)
        );
    end component;

    component vr360 is
        generic (
            FOCAL_LENGTH : natural;
            ANGLE_WIDTH  : natural;
            IMAGE_WIDTH  : natural;
            IMAGE_HEIGHT : natural;
            OUT_WIDTH    : natural;
            OUT_HEIGHT   : natural;
            PIXEL_WIDTH  : natural;
            ADDR_WIDTH   : natural;
            TRIG_WIDTH   : natural
        );
        port (
            clk         : in    std_logic;
            reset       : in    std_logic;
            rx          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            ry          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rz          : in    std_logic_vector(ANGLE_WIDTH - 1 downto 0);
            rot_valid   : in    std_logic;
            imu_rx      : in    std_logic;
            byte_stb    : in    std_logic;
            wr_req      : in    std_logic;
            wr_addr     : in    std_logic_vector(ADDR_WIDTH - 1 downto 0);
            wr_data     : in    std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            wr_ack      : out   std_logic;
            dram_dq     : inout std_logic_vector(15 downto 0);
            dram_addr   : out   std_logic_vector(12 downto 0);
            dram_ba     : out   std_logic_vector(1 downto 0);
            dram_ldqm   : out   std_logic;
            dram_udqm   : out   std_logic;
            dram_ras_n  : out   std_logic;
            dram_cas_n  : out   std_logic;
            dram_cke    : out   std_logic;
            dram_clk    : out   std_logic;
            dram_we_n   : out   std_logic;
            dram_cs_n   : out   std_logic;
            hex0        : out   std_logic_vector(6 downto 0);
            hex1        : out   std_logic_vector(6 downto 0);
            hex2        : out   std_logic_vector(6 downto 0);
            hex3        : out   std_logic_vector(6 downto 0);
            hex4        : out   std_logic_vector(6 downto 0);
            hex5        : out   std_logic_vector(6 downto 0);
            leds        : out   std_logic_vector(4 downto 0);
            frame_sync  : in    std_logic;
            pixel_req   : in    std_logic;
            pixel       : out   std_logic_vector(PIXEL_WIDTH - 1 downto 0);
            pixel_valid : out   std_logic
        );
    end component;

    component jtag_sdram_writer is
        generic (
            DATA_WIDTH       : natural := 24;
            ADDR_WIDTH       : natural := 23;
            N_PIXELS         : natural := 8388608;
            PIXELS_PER_SHIFT : natural := 128
        );
        port (
            clk     : in  std_logic;
            reset   : in  std_logic;
            wr_req  : out std_logic;
            wr_addr : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
            wr_data : out std_logic_vector(DATA_WIDTH - 1 downto 0);
            wr_ack  : in  std_logic
        );
    end component;

    component hdmi is
        generic (
            CLK_FREQUENCY : natural := 50_000_000;
            PIX_DIV       : natural := 2;
            H_ACTIVE      : natural := 640;
            V_ACTIVE      : natural := 480
        );
        port (
            clock       : in    std_logic;
            reset       : in    std_logic;
            frame_sync  : out   std_logic;
            pixel_req   : out   std_logic;
            pixel       : in    std_logic_vector(23 downto 0);
            hdmi_tx_clk : out   std_logic;
            hdmi_tx_d   : out   std_logic_vector(23 downto 0);
            hdmi_tx_hs  : out   std_logic;
            hdmi_tx_vs  : out   std_logic;
            hdmi_tx_de  : out   std_logic;
            hdmi_tx_int : in    std_logic;
            i2c_scl     : out   std_logic;
            i2c_sda     : inout std_logic
        );
    end component;

    --------------------------------------------------------------------
    -- Interconnect
    --------------------------------------------------------------------
    signal reset : std_logic;

    signal rx_s, ry_s, rz_s : std_logic_vector(ANGLE_WIDTH - 1 downto 0);
    signal rot_valid_s      : std_logic;
    signal byte_stb_s       : std_logic;   -- LEDs only

    signal wr_req_s  : std_logic;
    signal wr_ack_s  : std_logic;
    signal wr_addr_s : std_logic_vector(ADDR_WIDTH - 1 downto 0);
    signal wr_data_s : std_logic_vector(PIXEL_WIDTH - 1 downto 0);

    signal frame_sync_s : std_logic;
    signal pixel_req_s  : std_logic;
    signal pixel_s      : std_logic_vector(PIXEL_WIDTH - 1 downto 0);

begin

    -- The board reset is active low; everything inside is active high.
    reset <= not reset_n;

    imu_inst : imu
        generic map (
            CLK_FREQ    => CLK_FREQUENCY,
            BAUD_RATE   => IMU_BAUD_RATE,
            ANGLE_WIDTH => ANGLE_WIDTH
        )
        port map (
            clk        => clk_50,
            reset      => reset,
            uart_rx    => imu_uart_rx,
            rx         => rx_s,
            ry         => ry_s,
            rz         => rz_s,
            data_valid => rot_valid_s,
            byte_stb   => byte_stb_s,
            byte_data  => open,
            frame_stb  => open,
            frame_func => open
        );

    vr360_inst : vr360
        generic map (
            FOCAL_LENGTH => FOCAL_LENGTH,
            ANGLE_WIDTH  => ANGLE_WIDTH,
            IMAGE_WIDTH  => IMAGE_WIDTH,
            IMAGE_HEIGHT => IMAGE_HEIGHT,
            OUT_WIDTH    => OUT_WIDTH,
            OUT_HEIGHT   => OUT_HEIGHT,
            PIXEL_WIDTH  => PIXEL_WIDTH,
            ADDR_WIDTH   => ADDR_WIDTH,
            TRIG_WIDTH   => TRIG_WIDTH
        )
        port map (
            clk         => clk_50,
            reset       => reset,

            rx          => rx_s,
            ry          => ry_s,
            rz          => rz_s,
            rot_valid   => rot_valid_s,
            imu_rx      => imu_uart_rx,
            byte_stb    => byte_stb_s,

            wr_req      => wr_req_s,
            wr_addr     => wr_addr_s,
            wr_data     => wr_data_s,
            wr_ack      => wr_ack_s,

            dram_dq     => dram_dq,
            dram_addr   => dram_addr,
            dram_ba     => dram_ba,
            dram_ldqm   => dram_ldqm,
            dram_udqm   => dram_udqm,
            dram_ras_n  => dram_ras_n,
            dram_cas_n  => dram_cas_n,
            dram_cke    => dram_cke,
            dram_clk    => dram_clk,
            dram_we_n   => dram_we_n,
            dram_cs_n   => dram_cs_n,

            hex0        => hex0,
            hex1        => hex1,
            hex2        => hex2,
            hex3        => hex3,
            hex4        => hex4,
            hex5        => hex5,
            leds        => leds,

            frame_sync  => frame_sync_s,
            pixel_req   => pixel_req_s,
            pixel       => pixel_s,
            pixel_valid => open
        );

    jtag_writer_inst : jtag_sdram_writer
        generic map (
            DATA_WIDTH       => PIXEL_WIDTH,
            ADDR_WIDTH       => ADDR_WIDTH,
            N_PIXELS         => IMAGE_WIDTH * IMAGE_HEIGHT,
            PIXELS_PER_SHIFT => 128
        )
        port map (
            clk     => clk_50,
            reset   => reset,
            wr_req  => wr_req_s,
            wr_addr => wr_addr_s,
            wr_data => wr_data_s,
            wr_ack  => wr_ack_s
        );

    hdmi_inst : hdmi
        generic map (
            CLK_FREQUENCY => CLK_FREQUENCY,
            PIX_DIV       => 2,
            H_ACTIVE      => OUT_WIDTH,
            V_ACTIVE      => OUT_HEIGHT
        )
        port map (
            clock       => clk_50,
            reset       => reset,

            frame_sync  => frame_sync_s,
            pixel_req   => pixel_req_s,
            pixel       => pixel_s,

            hdmi_tx_clk => hdmi_tx_clk,
            hdmi_tx_d   => hdmi_tx_d,
            hdmi_tx_hs  => hdmi_tx_hs,
            hdmi_tx_vs  => hdmi_tx_vs,
            hdmi_tx_de  => hdmi_tx_de,
            hdmi_tx_int => hdmi_tx_int,

            i2c_scl     => hdmi_i2c_scl,
            i2c_sda     => hdmi_i2c_sda
        );

end architecture structural;
