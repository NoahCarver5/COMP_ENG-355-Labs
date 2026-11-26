library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package whac_pkg is

    -- Game FSM states
    type game_state_t is (IDLE, PLAY, GAME_OVER);

    -- Mole visibility states
    type mole_state_t is (HIDDEN, VISIBLE);

    -- Shared cursor interface (button and camera paths both output this)
    type hand_t is record
        hole_idx : unsigned(2 downto 0);  -- selected hole 0–5
        strike   : std_logic;             -- smash pulse, 1 cycle
    end record;

    -- BCD digit (0–9)
    subtype bcd_digit_t is unsigned(3 downto 0);

    -- Hole layout: 3 columns x 2 rows, indexed 0–5 (row-major)
    -- Fill in pixel coordinates and radius below
    type hole_x_arr_t is array (0 to 5) of integer;
    type hole_y_arr_t is array (0 to 5) of integer;

    constant HOLE_CX : hole_x_arr_t := (160, 320, 480, 160, 320, 480);
    constant HOLE_CY : hole_y_arr_t := (160, 160, 160, 320, 320, 320);
    constant HOLE_R  : integer      := 60;

    -- Display resolution
    constant H_RES : integer := 640;
    constant V_RES : integer := 480;

end package whac_pkg;
