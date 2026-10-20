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
    signal pos : std_logic_vector(14 downto 0);


    ----------------------------------------------------------------
    -- Component Declarations
    --
    -- TODO: declare the gesture_controller and pwm_servo components here.
    ----------------------------------------------------------------

    component gesture_controller is
        port (
            clk     : in  std_logic;
            reset   : in  std_logic;
            sel     : in  std_logic_vector(9 downto 0);
            pos     : out std_logic_vector(14 downto 0)
        );

    end component gesture_controller;

    component pwm_servo is
        generic(
            INVERT : boolean := false
        );
        port(
        clk   : in  std_logic;
        reset : in  std_logic;
        deg   : in  std_logic_vector(2 downto 0);
        pwm   : out std_logic
    );

    end component pwm_servo;
    
    
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

    gesture_controller_inst: gesture_controller
    port map(clk => clk, reset => rst, sel => sw, pos => pos);

    pwm_servos : for i in 0 to 4 generate
    begin
        servo_i : pwm_servo
            generic map(
                INVERT => (i = THUMB_SERVO)
            )
            port map(
                clk => clk,
                reset => rst,
                deg => pos(3*i+2 downto 3*i),
                pwm => pwm(i)
            );
    end generate pwm_servos;

    
    ----------------------------------------------------------------
    -- Concurrent statements
    --
    -- TODO: Add concurrent statements to drive the led outputs. 
    ----------------------------------------------------------------
    rst <= not rst_n;
    led <= sw;

end architecture structure;