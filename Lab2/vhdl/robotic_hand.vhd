library ieee;
use ieee.std_logic_1164.all;

entity robotic_hand is
    port(
        clk   : in  std_logic;
        rst_n : in  std_logic;
        sw    : in  std_logic_vector(9 downto 0);
        pwm   : out std_logic_vector(4 downto 0);
        led   : out std_logic_vector(9 downto 0)
    );
end entity robotic_hand;

architecture structure of robotic_hand is

    ----------------------------------------------------------------
    -- Signal declarations
    ----------------------------------------------------------------
    -- the thumb servo on pwm(0) is mounted reversed, so its travel is mirrored.
    constant THUMB_SERVO : natural := 0;

    signal rst : std_logic;

    ----------------------------------------------------------------
    -- Component Declarations
    --
    -- TODO: declare the gesture_controller and pwm_servo components here.
    ----------------------------------------------------------------
    
    
begin

    ----------------------------------------------------------------
    -- Component instantiations
    --
    -- TODO: instantiate the gesture_controller and five pwm_servo 
    -- components here.  Use a generate loop to instantiate the five
    -- pwm_servo components.  The thumb servo on pwm(0) is mounted
    -- reversed, so its travel is mirrored.  Use the THUMB_SERVO
    -- constant to identify the thumb servo in the generate loop.
    ----------------------------------------------------------------

    
    ----------------------------------------------------------------
    -- Concurrent statements
    --
    -- TODO: Add concurrent statements to drive the led outputs. 
    ----------------------------------------------------------------
    rst <= not rst_n;

end architecture structure;