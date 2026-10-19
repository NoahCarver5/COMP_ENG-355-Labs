library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gesture_controller is
    port(
        clk     : in  std_logic;
        reset   : in  std_logic;
        sel     : in  std_logic_vector(9 downto 0);
        pos     : out std_logic_vector(14 downto 0)
    );
end entity gesture_controller;

architecture rtl of gesture_controller is

    ----------------------------------------------------------------
    -- Type and constant declarations
    ----------------------------------------------------------------
    constant ANIMATION_PERIOD : natural := 10000000;

    subtype servo_position is std_logic_vector(2 downto 0);
    type servo_pose_t is array (0 to 4) of servo_position;

    -- pose_to_vector packs pose(0) into pos(14:12), which drives pwm(4), so
    -- pose indices map to fingers in reverse order of the pwm outputs:
    --   pose(0) = pinky  (pwm 4)
    --   pose(1) = ring   (pwm 3)
    --   pose(2) = middle (pwm 2)
    --   pose(3) = index  (pwm 1)
    --   pose(4) = thumb  (pwm 0)
    -- "000" is closed and "100" is open for every finger.

    ----------------------------------------------------------------
    -- TODO: define the poses for the five gestures here. 
    ----------------------------------------------------------------
    constant closed_pose : servo_pose_t := (
        0 => "000",
        1 => "000",
        2 => "000",
        3 => "000",
        4 => "000"
    );

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------
    signal animation_count  : natural range 0 to ANIMATION_PERIOD - 1;
    signal step             : natural range 0 to 9;
    signal active_pose      : servo_pose_t;

    ----------------------------------------------------------------
    -- Function declarations
    ----------------------------------------------------------------
    function pose_to_vector(pose : servo_pose_t) return std_logic_vector is
        variable result : std_logic_vector(14 downto 0);
    begin
        result(14 downto 12) := pose(0);
        result(11 downto 9)  := pose(1);
        result(8 downto 6)   := pose(2);
        result(5 downto 3)   := pose(3);
        result(2 downto 0)   := pose(4);
        return result;
    end function pose_to_vector;

    -- combine two poses so a finger is open if it is open in either pose.
    function mask_pose(a, b : servo_pose_t) return servo_pose_t is
        variable result : servo_pose_t;
    begin
        for i in servo_pose_t'range loop
            result(i) := a(i) or b(i);
        end loop;
        return result;
    end function mask_pose;

begin

    -- convert the active pose to a 15-bit vector for output.
    pos <= pose_to_vector(active_pose);

    ---------------------------------------------------------
    -- main clocked process to handle counter management.
    ---------------------------------------------------------
    counter_process: process(clk, reset)
    begin
        if (reset = '1') then
            animation_count <= 0;
            step            <= 0;
        elsif ( rising_edge(clk) ) then
            if (animation_count /= ANIMATION_PERIOD - 1) then
                animation_count <= animation_count + 1;
            else
                animation_count <= 0;
                if (step /= 9) then
                    step <= step + 1;
                else
                    step <= 0;
                end if;
            end if;
        end if;
    end process counter_process;


    -----------------------------------------------------------------------
    -- main combinational process for gesture management.
    --
    -- TODO: implement the gesture selection logic here using sequential
    -- statements. The process should set the active_pose signal to the 
    -- pose type based on the sel input and current step of the animation. 
    -- Use the mask_pose function to combine poses for gestures that require
    -- multiple fingers to be open. The default pose should be closed_pose.
    -----------------------------------------------------------------------
    gesture_process: process()
    begin

        active_pose <= closed_pose;  -- default to closed pose

    end process gesture_process;


end architecture rtl;