library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.trig_pkg.all;


--------------------------------------------------------------------------------
-- Ray generator
--
-- This module generates rays in a raster scan order, starting from the top-left 
-- corner of the image and proceeding to the bottom-right corner. The rays are 
-- generated in a fixed-point format.
--------------------------------------------------------------------------------

entity ray_gen is
    generic (
        FOCAL_LENGTH : natural := 320;
        TRIG_WIDTH   : natural := 16;
        OUT_WIDTH    : natural := 1024;
        OUT_HEIGHT   : natural := 512;
        COL_WIDTH    : natural := log2(OUT_WIDTH);
        ROW_WIDTH    : natural := log2(OUT_HEIGHT)
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        valid_in  : in  std_logic;
        ready_in : out std_logic;

        o0        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o1        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        o2        : out std_logic_vector(TRIG_WIDTH - 1 downto 0);
        row       : out std_logic_vector(ROW_WIDTH - 1 downto 0);
        col       : out std_logic_vector(COL_WIDTH - 1 downto 0);
        valid_out : out std_logic;
        ready_out : in std_logic
    );
end entity ray_gen;


architecture rtl of ray_gen is

    -----------------------------------------------------------
    -- Constant Declarations
    -----------------------------------------------------------
    constant CENTER_X     : natural := OUT_WIDTH / 2;
    constant CENTER_Y     : natural := OUT_HEIGHT / 2;

    -----------------------------------------------------------
    -- Signal Declarations
    -----------------------------------------------------------
    
    type state is (IDLE, WORKING, READY);

    signal x_count_r, x_count_c : std_logic_vector(COL_WIDTH-1 downto 0);
    signal y_count_r, y_count_c : std_logic_vector(ROW_WIDTH-1 downto 0);
    signal valid_out_c, ready_in_c, valid_out_r, ready_in_r : std_logic;
    signal o0_c, o1_c, o2_c, o0_r, o1_r, o2_r : std_logic_vector (TRIG_WIDTH - 1 downto 0);

    signal cur_state : state;
    signal next_state : state;



begin

    -----------------------------------------------------------
    -- Clocked process
    --
    -- TODO: implement the clocked process to reset and update 
    -- state and registers on clock edge.
    -----------------------------------------------------------

    valid_out <= valid_out_r;
    ready_in <= ready_in_r;
    o0 <= o0_r;
    o1 <= o1_r;
    o2 <= o2_r;

    ray_gen_clocked : process(clk, reset) is  
    begin

        if (reset = '1') then
            o0_r <= (others => '0');
            o1_r <= (others => '0');
            o2_r <= (others => '0');
            x_count_r <= (others => '0');
            row <= (others => '0');
            col <= (others => '0');
            y_count_r <= (others => '0');
            cur_state <= IDLE;
            valid_out_r <= '0';
            ready_in_r <= '1';
        elsif (rising_edge(clk)) then
            o0_r <= o0_c;
            o1_r <= o1_c;
            o2_r <= o2_c;
            row <= y_count_r;
            col <= x_count_r;
            x_count_r <= x_count_c;
            y_count_r <= y_count_c;
            valid_out_r <= valid_out_c;
            ready_in_r <= ready_in_c;
            cur_state <= next_state;
        end if;

    end process;



    -----------------------------------------------------------
    -- Combinational process
    --
    -- TODO: implement the combinational FSM process that implements 
    -- the ray generation algorithm using x,y counters to generate
    -- the following output signals:
    --      row: y coordinate in the output image (0..OUT_HEIGHT-1)
    --      col: x coordinate in the output image (0..OUT_WIDTH-1)
    --      o0: x - CENTER_X
    --      o1: CENTER_Y - y
    --      o2: FOCAL_LENGTH
    --      valid_out: high when the ray is valid
    --      ready_in: high when ready to receive a new frame
    -----------------------------------------------------------

    ray_gen_fsm: process(all) is   
    begin

        next_state <= cur_state;
        x_count_c <= x_count_r;
        y_count_c <= y_count_r;

        valid_out_c <= valid_out_r;
        ready_in_c <= ready_in_r;

        o0_c <= o0_r;
        o1_c <= o1_r;
        o2_c <= o2_r;

        case cur_state is
            when IDLE =>

                valid_out_c <= '0';
                ready_in_c <= '1';
                valid_out_c <= '0';
                if (valid_in = '1' and ready_in_r = '1') then
                    next_state <= WORKING;
                    ready_in_c <= '0';
                    x_count_c <= (others => '0');
                    y_count_c <= (others => '0');
                end if;

            when WORKING =>
                
                ready_in_c <= '0';
                o0_c <= std_logic_vector(to_signed(to_integer(unsigned(x_count_r)) - CENTER_X, TRIG_WIDTH));
                o1_c <= std_logic_vector(to_signed(CENTER_Y - to_integer(unsigned(y_count_r)), TRIG_WIDTH));
                o2_c <= std_logic_vector(to_unsigned(FOCAL_LENGTH, TRIG_WIDTH));
                valid_out_c <= '1';
                next_state <= READY;

            when READY =>

                if (ready_out = '0') then

                    x_count_c <= x_count_r;
                    y_count_c <= y_count_r;
                    next_state <= READY;
                
                else
                    
                    valid_out_c <= '0';
                    if (unsigned(x_count_r) = OUT_WIDTH-1) then
                        
                        x_count_c <= (others => '0');
                        if (unsigned(y_count_r) >= OUT_HEIGHT-1) then
                            y_count_c <= (others => '0');
                            next_state <= IDLE;
                        else
                            y_count_c <= std_logic_vector(unsigned(y_count_r) + 1);
                            next_state <= WORKING;
                        end if;
                
                    else
                        x_count_c <= std_logic_vector(unsigned(x_count_r) + 1);
                        next_state <= WORKING;
                end if;
            end if;
        end case;
    end process;
                    


    

end architecture rtl;