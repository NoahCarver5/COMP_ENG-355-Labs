library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

package trig_pkg is

    ----------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------
    constant ANGLE_WIDTH : natural := 16;
    constant TRIG_WIDTH  : natural := 16;
    constant LUT_BITS    : natural := 10;
    constant LUT_SIZE    : natural := 2**LUT_BITS;

    ----------------------------------------------------------------
    -- ROMs
    ----------------------------------------------------------------
    type lut_array_t is array (natural range <>) of
        std_logic_vector(TRIG_WIDTH - 1 downto 0);

    constant SIN_ROM    : lut_array_t(0 to LUT_SIZE - 1);
    constant ASIN_ROM   : lut_array_t(0 to LUT_SIZE - 1);
    constant ATAN_ROM   : lut_array_t(0 to LUT_SIZE - 1);
    constant SQRT_ROM   : lut_array_t(0 to LUT_SIZE - 1);

    -- Reciprocal of a NORMALIZED denominator.  Entry i holds
    -- 2**RECIP_SHIFT / i, and only i in [LUT_SIZE/2, LUT_SIZE-1] is
    -- ever addressed -- see reciprocal_lut below.
    constant RECIP_SHIFT : natural := 24;
    constant RECIP_ROM  : lut_array_t(0 to LUT_SIZE - 1);

    -----------------------------------------------------------------
    -- Functions
    -----------------------------------------------------------------
    function sin_lut(
        angle : std_logic_vector(ANGLE_WIDTH - 1 downto 0)
    ) return std_logic_vector;

    function cos_lut(
        angle : std_logic_vector(ANGLE_WIDTH - 1 downto 0)
    ) return std_logic_vector;

    function atan_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector;

    function asin_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector;
    
    function sqrt_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector;

    function reciprocal_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector;

    function abs_val(
        value : std_logic_vector
    ) return std_logic_vector;

    function smax(
        a : signed;
        b : signed
    ) return signed;

    function smax(
        a : integer;
        b : integer
    ) return integer;

    function smin(
        a : signed;
        b : signed
    ) return signed;    
    
    function umax(
        a : unsigned;
        b : unsigned
    ) return unsigned;

    function umin(
        a : unsigned;
        b : unsigned
    ) return unsigned;    
    
    function log2(
        value : natural
    ) return natural;

    function mult_fixed(
        a : std_logic_vector; 
        b : std_logic_vector
    ) return std_logic_vector;

end package trig_pkg;


package body trig_pkg is

    --------------------------------------------------------------------
    -- Fixed-point multiplication.
    --
    -- Both inputs are signed fixed-point values.
    --
    -- Each operand has (length - 1) fractional bits.
    --
    -- The result is returned as a TRIG_WIDTH-bit value with
    -- (TRIG_WIDTH - 1) fractional bits.
    --
    -- The shift amount is derived from the operand widths rather
    -- than being hard-coded.
    --------------------------------------------------------------------
    function mult_fixed(
        a : std_logic_vector;
        b : std_logic_vector
    ) return std_logic_vector is

        constant A_FRAC_BITS : natural := a'length - 1;
        constant B_FRAC_BITS : natural := b'length - 1;
        constant OUT_FRAC_BITS : natural := TRIG_WIDTH - 1;
        constant SHIFT_BITS : natural := A_FRAC_BITS + B_FRAC_BITS - OUT_FRAC_BITS;
        variable product : signed(a'length + b'length - 1 downto 0);
    begin
        product := signed(a) * signed(b);

        -- Round before shifting.
        if SHIFT_BITS > 0 then
            product := product + to_signed(2**(SHIFT_BITS - 1), product'length);
        end if;

        return std_logic_vector(resize(shift_right(product, SHIFT_BITS), TRIG_WIDTH));

    end function;

   
    --------------------------------------------------------------------
    -- Sine lookup
    --
    -- The complete 16-bit angle represents 360 degrees:
    --
    --   0x0000 =   0 degrees
    --   0x4000 =  90 degrees
    --   0x8000 = 180 degrees
    --   0xC000 = -90 degrees
    --
    -- The upper LUT_BITS are used as the LUT address.
    --------------------------------------------------------------------
    function sin_lut(
        angle : std_logic_vector(ANGLE_WIDTH - 1 downto 0)
    ) return std_logic_vector is
        variable index : natural;
    begin
        index := to_integer(unsigned(angle(ANGLE_WIDTH - 1 downto ANGLE_WIDTH - LUT_BITS)));
        return SIN_ROM(index);
    end function;

    --------------------------------------------------------------------
    -- Cosine lookup
    --
    -- cos(x) = sin(x + 90 degrees)
    --
    -- 90 degrees corresponds to:
    --
    --   2^(ANGLE_WIDTH - 2)
    --
    --------------------------------------------------------------------
    function cos_lut(
        angle : std_logic_vector(ANGLE_WIDTH - 1 downto 0)
    ) return std_logic_vector is
        variable shifted_angle : unsigned(ANGLE_WIDTH - 1 downto 0);
    begin
        shifted_angle := unsigned(angle) + to_unsigned(2**(ANGLE_WIDTH - 2), ANGLE_WIDTH);
        return sin_lut(std_logic_vector(shifted_angle));
    end function;

    --------------------------------------------------------------------
    -- Arctangent lookup
    --
    -- value is assumed to represent a value from 0 to 1.
    --
    -- LUT address:
    --
    --   0x000 -> value = 0
    --   0x3FF -> value ~= 1
    --
    -- The LUT output uses the same angle representation.
    --------------------------------------------------------------------
    function atan_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector is
        variable index : natural;
    begin
        index := to_integer(unsigned(value));
        return ATAN_ROM(index);
    end function;


    --------------------------------------------------------------------
    -- Arcsine lookup
    --
    -- The complete 16-bit angle represents 360 degrees:
    --
    --   0x0000 =   0 degrees
    --   0x4000 =  90 degrees
    --   0x8000 = 180 degrees
    --   0xC000 = -90 degrees
    --
    -- The upper LUT_BITS are used as the LUT address.
    --------------------------------------------------------------------
    function asin_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector is
        variable index : natural;
    begin
        index := to_integer(unsigned(value));
        return ASIN_ROM(index);
    end function;

    ---------------------------------------------------------------------
    -- Square root lookup
    --
    -- The input is a value from 0 to 1.
    --
    -- The ROM represents:
    --
    --       sqrt(index / 1024)
    --
    -- in Q1.15.
    --------------------------------------------------------------------
    function sqrt_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector is
        variable index : natural;
    begin
        index := to_integer(unsigned(value));
        return SQRT_ROM(index);
    end function;

    --------------------------------------------------------------------
    -- Reciprocal of a normalized denominator.
    --
    -- The index must already have its top bit set -- that is, it must
    -- lie in [LUT_SIZE/2, LUT_SIZE-1].  The caller gets it there by
    -- shifting the denominator until it has exactly LUT_BITS
    -- significant bits, and accounts for that shift afterwards.
    --
    -- Returns 2**RECIP_SHIFT / index.  The lower half of the ROM is
    -- zero, so an unnormalized index returns zero rather than a wrong
    -- answer.
    --------------------------------------------------------------------
    function reciprocal_lut(
        value : std_logic_vector(LUT_BITS - 1 downto 0)
    ) return std_logic_vector is
        variable index : natural;
    begin
        index := to_integer(unsigned(value));
        return RECIP_ROM(index);
    end function;

    --------------------------------------------------------------------
    -- Absolute value for a signed std_logic_vector.
    --------------------------------------------------------------------
    function abs_val(
        value : std_logic_vector
    ) return std_logic_vector is
    begin
        if signed(value) < 0 then
            return std_logic_vector(-signed(value));
        else
            return value;
        end if;
    end function;

    --------------------------------------------------------------------
    -- Maximum value for a signed std_logic_vector.
    --------------------------------------------------------------------
    function smax(
        a : signed;
        b : signed
    ) return signed is
    begin
        if (a < b) then
            return b;
        else
            return a;
        end if;
    end function;

    --------------------------------------------------------------------
    -- Maximum of two integers.
    --
    -- Overload for plain integer/natural expressions, so constants can
    -- be sized without converting to signed first.
    --------------------------------------------------------------------
    function smax(
        a : integer;
        b : integer
    ) return integer is
    begin
        if (a < b) then
            return b;
        else
            return a;
        end if;
    end function;

    --------------------------------------------------------------------
    -- Maximum value for an unsigned std_logic_vector.
    --------------------------------------------------------------------
    function umax(
        a : unsigned;
        b : unsigned
    ) return unsigned is
    begin
        if (a < b) then
            return b;
        else
            return a;
        end if;
    end function;

    --------------------------------------------------------------------
    -- Minimum value for a signed std_logic_vector.
    --------------------------------------------------------------------
    function smin(
        a : signed;
        b : signed
    ) return signed is
    begin
        if (a > b) then
            return b;
        else
            return a;
        end if;
    end function;

    function umin(
        a : unsigned;
        b : unsigned
    ) return unsigned is
    begin
        if (a > b) then
            return b;
        else
            return a;
        end if;
    end function;

    --------------------------------------------------------------------
    -- Base-2 logarithm.
    --
    -- Examples:
    --
    --   log2(1024) = 10
    --   log2(512)  = 9
    --   log2(320)  = 9
    --   log2(180)  = 8
    --------------------------------------------------------------------
    function log2(
        value : natural
    ) return natural is
        variable v      : natural;
        variable result : natural := 0;
    begin
        if value <= 1 then
            return 1;
        end if;
        v := value - 1;
        while v > 0 loop
            v := v / 2;
            result := result + 1;
        end loop;
        return result;
    end function;

    ---------------------------------------------------------------------
    -- ROM declarations
    ---------------------------------------------------------------------
    constant SIN_ROM : lut_array_t(0 to LUT_SIZE - 1) := (
        X"0000", X"00C9", X"0192", X"025B", X"0324", X"03ED", X"04B6", X"057F",
        X"0648", X"0711", X"07D9", X"08A2", X"096A", X"0A33", X"0AFB", X"0BC4",
        X"0C8C", X"0D54", X"0E1C", X"0EE3", X"0FAB", X"1072", X"113A", X"1201",
        X"12C8", X"138F", X"1455", X"151C", X"15E2", X"16A8", X"176E", X"1833",
        X"18F9", X"19BE", X"1A82", X"1B47", X"1C0B", X"1CCF", X"1D93", X"1E57",
        X"1F1A", X"1FDD", X"209F", X"2161", X"2223", X"22E5", X"23A6", X"2467",
        X"2528", X"25E8", X"26A8", X"2767", X"2826", X"28E5", X"29A3", X"2A61",
        X"2B1F", X"2BDC", X"2C99", X"2D55", X"2E11", X"2ECC", X"2F87", X"3041",
        X"30FB", X"31B5", X"326E", X"3326", X"33DF", X"3496", X"354D", X"3604",
        X"36BA", X"376F", X"3824", X"38D9", X"398C", X"3A40", X"3AF2", X"3BA5",
        X"3C56", X"3D07", X"3DB8", X"3E68", X"3F17", X"3FC5", X"4073", X"4121",
        X"41CE", X"427A", X"4325", X"43D0", X"447A", X"4524", X"45CD", X"4675",
        X"471C", X"47C3", X"4869", X"490F", X"49B4", X"4A58", X"4AFB", X"4B9D",
        X"4C3F", X"4CE0", X"4D81", X"4E20", X"4EBF", X"4F5D", X"4FFB", X"5097",
        X"5133", X"51CE", X"5268", X"5302", X"539B", X"5432", X"54C9", X"5560",
        X"55F5", X"568A", X"571D", X"57B0", X"5842", X"58D3", X"5964", X"59F3",
        X"5A82", X"5B0F", X"5B9C", X"5C28", X"5CB3", X"5D3E", X"5DC7", X"5E4F",
        X"5ED7", X"5F5D", X"5FE3", X"6068", X"60EB", X"616E", X"61F0", X"6271",
        X"62F1", X"6370", X"63EE", X"646C", X"64E8", X"6563", X"65DD", X"6656",
        X"66CF", X"6746", X"67BC", X"6832", X"68A6", X"6919", X"698B", X"69FD",
        X"6A6D", X"6ADC", X"6B4A", X"6BB7", X"6C23", X"6C8E", X"6CF8", X"6D61",
        X"6DC9", X"6E30", X"6E96", X"6EFB", X"6F5E", X"6FC1", X"7022", X"7083",
        X"70E2", X"7140", X"719D", X"71F9", X"7254", X"72AE", X"7307", X"735E",
        X"73B5", X"740A", X"745F", X"74B2", X"7504", X"7555", X"75A5", X"75F3",
        X"7641", X"768D", X"76D8", X"7722", X"776B", X"77B3", X"77FA", X"783F",
        X"7884", X"78C7", X"7909", X"794A", X"7989", X"79C8", X"7A05", X"7A41",
        X"7A7C", X"7AB6", X"7AEE", X"7B26", X"7B5C", X"7B91", X"7BC5", X"7BF8",
        X"7C29", X"7C59", X"7C88", X"7CB6", X"7CE3", X"7D0E", X"7D39", X"7D62",
        X"7D89", X"7DB0", X"7DD5", X"7DFA", X"7E1D", X"7E3E", X"7E5F", X"7E7E",
        X"7E9C", X"7EB9", X"7ED5", X"7EEF", X"7F09", X"7F21", X"7F37", X"7F4D",
        X"7F61", X"7F74", X"7F86", X"7F97", X"7FA6", X"7FB4", X"7FC1", X"7FCD",
        X"7FD8", X"7FE1", X"7FE9", X"7FF0", X"7FF5", X"7FF9", X"7FFD", X"7FFE",
        X"7FFF", X"7FFE", X"7FFD", X"7FF9", X"7FF5", X"7FF0", X"7FE9", X"7FE1",
        X"7FD8", X"7FCD", X"7FC1", X"7FB4", X"7FA6", X"7F97", X"7F86", X"7F74",
        X"7F61", X"7F4D", X"7F37", X"7F21", X"7F09", X"7EEF", X"7ED5", X"7EB9",
        X"7E9C", X"7E7E", X"7E5F", X"7E3E", X"7E1D", X"7DFA", X"7DD5", X"7DB0",
        X"7D89", X"7D62", X"7D39", X"7D0E", X"7CE3", X"7CB6", X"7C88", X"7C59",
        X"7C29", X"7BF8", X"7BC5", X"7B91", X"7B5C", X"7B26", X"7AEE", X"7AB6",
        X"7A7C", X"7A41", X"7A05", X"79C8", X"7989", X"794A", X"7909", X"78C7",
        X"7884", X"783F", X"77FA", X"77B3", X"776B", X"7722", X"76D8", X"768D",
        X"7641", X"75F3", X"75A5", X"7555", X"7504", X"74B2", X"745F", X"740A",
        X"73B5", X"735E", X"7307", X"72AE", X"7254", X"71F9", X"719D", X"7140",
        X"70E2", X"7083", X"7022", X"6FC1", X"6F5E", X"6EFB", X"6E96", X"6E30",
        X"6DC9", X"6D61", X"6CF8", X"6C8E", X"6C23", X"6BB7", X"6B4A", X"6ADC",
        X"6A6D", X"69FD", X"698B", X"6919", X"68A6", X"6832", X"67BC", X"6746",
        X"66CF", X"6656", X"65DD", X"6563", X"64E8", X"646C", X"63EE", X"6370",
        X"62F1", X"6271", X"61F0", X"616E", X"60EB", X"6068", X"5FE3", X"5F5D",
        X"5ED7", X"5E4F", X"5DC7", X"5D3E", X"5CB3", X"5C28", X"5B9C", X"5B0F",
        X"5A82", X"59F3", X"5964", X"58D3", X"5842", X"57B0", X"571D", X"568A",
        X"55F5", X"5560", X"54C9", X"5432", X"539B", X"5302", X"5268", X"51CE",
        X"5133", X"5097", X"4FFB", X"4F5D", X"4EBF", X"4E20", X"4D81", X"4CE0",
        X"4C3F", X"4B9D", X"4AFB", X"4A58", X"49B4", X"490F", X"4869", X"47C3",
        X"471C", X"4675", X"45CD", X"4524", X"447A", X"43D0", X"4325", X"427A",
        X"41CE", X"4121", X"4073", X"3FC5", X"3F17", X"3E68", X"3DB8", X"3D07",
        X"3C56", X"3BA5", X"3AF2", X"3A40", X"398C", X"38D9", X"3824", X"376F",
        X"36BA", X"3604", X"354D", X"3496", X"33DF", X"3326", X"326E", X"31B5",
        X"30FB", X"3041", X"2F87", X"2ECC", X"2E11", X"2D55", X"2C99", X"2BDC",
        X"2B1F", X"2A61", X"29A3", X"28E5", X"2826", X"2767", X"26A8", X"25E8",
        X"2528", X"2467", X"23A6", X"22E5", X"2223", X"2161", X"209F", X"1FDD",
        X"1F1A", X"1E57", X"1D93", X"1CCF", X"1C0B", X"1B47", X"1A82", X"19BE",
        X"18F9", X"1833", X"176E", X"16A8", X"15E2", X"151C", X"1455", X"138F",
        X"12C8", X"1201", X"113A", X"1072", X"0FAB", X"0EE3", X"0E1C", X"0D54",
        X"0C8C", X"0BC4", X"0AFB", X"0A33", X"096A", X"08A2", X"07D9", X"0711",
        X"0648", X"057F", X"04B6", X"03ED", X"0324", X"025B", X"0192", X"00C9",
        X"0000", X"FF37", X"FE6E", X"FDA5", X"FCDC", X"FC13", X"FB4A", X"FA81",
        X"F9B8", X"F8EF", X"F827", X"F75E", X"F696", X"F5CD", X"F505", X"F43C",
        X"F374", X"F2AC", X"F1E4", X"F11D", X"F055", X"EF8E", X"EEC6", X"EDFF",
        X"ED38", X"EC71", X"EBAB", X"EAE4", X"EA1E", X"E958", X"E892", X"E7CD",
        X"E707", X"E642", X"E57E", X"E4B9", X"E3F5", X"E331", X"E26D", X"E1A9",
        X"E0E6", X"E023", X"DF61", X"DE9F", X"DDDD", X"DD1B", X"DC5A", X"DB99",
        X"DAD8", X"DA18", X"D958", X"D899", X"D7DA", X"D71B", X"D65D", X"D59F",
        X"D4E1", X"D424", X"D367", X"D2AB", X"D1EF", X"D134", X"D079", X"CFBF",
        X"CF05", X"CE4B", X"CD92", X"CCDA", X"CC21", X"CB6A", X"CAB3", X"C9FC",
        X"C946", X"C891", X"C7DC", X"C727", X"C674", X"C5C0", X"C50E", X"C45B",
        X"C3AA", X"C2F9", X"C248", X"C198", X"C0E9", X"C03B", X"BF8D", X"BEDF",
        X"BE32", X"BD86", X"BCDB", X"BC30", X"BB86", X"BADC", X"BA33", X"B98B",
        X"B8E4", X"B83D", X"B797", X"B6F1", X"B64C", X"B5A8", X"B505", X"B463",
        X"B3C1", X"B320", X"B27F", X"B1E0", X"B141", X"B0A3", X"B005", X"AF69",
        X"AECD", X"AE32", X"AD98", X"ACFE", X"AC65", X"ABCE", X"AB37", X"AAA0",
        X"AA0B", X"A976", X"A8E3", X"A850", X"A7BE", X"A72D", X"A69C", X"A60D",
        X"A57E", X"A4F1", X"A464", X"A3D8", X"A34D", X"A2C2", X"A239", X"A1B1",
        X"A129", X"A0A3", X"A01D", X"9F98", X"9F15", X"9E92", X"9E10", X"9D8F",
        X"9D0F", X"9C90", X"9C12", X"9B94", X"9B18", X"9A9D", X"9A23", X"99AA",
        X"9931", X"98BA", X"9844", X"97CE", X"975A", X"96E7", X"9675", X"9603",
        X"9593", X"9524", X"94B6", X"9449", X"93DD", X"9372", X"9308", X"929F",
        X"9237", X"91D0", X"916A", X"9105", X"90A2", X"903F", X"8FDE", X"8F7D",
        X"8F1E", X"8EC0", X"8E63", X"8E07", X"8DAC", X"8D52", X"8CF9", X"8CA2",
        X"8C4B", X"8BF6", X"8BA1", X"8B4E", X"8AFC", X"8AAB", X"8A5B", X"8A0D",
        X"89BF", X"8973", X"8928", X"88DE", X"8895", X"884D", X"8806", X"87C1",
        X"877C", X"8739", X"86F7", X"86B6", X"8677", X"8638", X"85FB", X"85BF",
        X"8584", X"854A", X"8512", X"84DA", X"84A4", X"846F", X"843B", X"8408",
        X"83D7", X"83A7", X"8378", X"834A", X"831D", X"82F2", X"82C7", X"829E",
        X"8277", X"8250", X"822B", X"8206", X"81E3", X"81C2", X"81A1", X"8182",
        X"8164", X"8147", X"812B", X"8111", X"80F7", X"80DF", X"80C9", X"80B3",
        X"809F", X"808C", X"807A", X"8069", X"805A", X"804C", X"803F", X"8033",
        X"8028", X"801F", X"8017", X"8010", X"800B", X"8007", X"8003", X"8002",
        X"8001", X"8002", X"8003", X"8007", X"800B", X"8010", X"8017", X"801F",
        X"8028", X"8033", X"803F", X"804C", X"805A", X"8069", X"807A", X"808C",
        X"809F", X"80B3", X"80C9", X"80DF", X"80F7", X"8111", X"812B", X"8147",
        X"8164", X"8182", X"81A1", X"81C2", X"81E3", X"8206", X"822B", X"8250",
        X"8277", X"829E", X"82C7", X"82F2", X"831D", X"834A", X"8378", X"83A7",
        X"83D7", X"8408", X"843B", X"846F", X"84A4", X"84DA", X"8512", X"854A",
        X"8584", X"85BF", X"85FB", X"8638", X"8677", X"86B6", X"86F7", X"8739",
        X"877C", X"87C1", X"8806", X"884D", X"8895", X"88DE", X"8928", X"8973",
        X"89BF", X"8A0D", X"8A5B", X"8AAB", X"8AFC", X"8B4E", X"8BA1", X"8BF6",
        X"8C4B", X"8CA2", X"8CF9", X"8D52", X"8DAC", X"8E07", X"8E63", X"8EC0",
        X"8F1E", X"8F7D", X"8FDE", X"903F", X"90A2", X"9105", X"916A", X"91D0",
        X"9237", X"929F", X"9308", X"9372", X"93DD", X"9449", X"94B6", X"9524",
        X"9593", X"9603", X"9675", X"96E7", X"975A", X"97CE", X"9844", X"98BA",
        X"9931", X"99AA", X"9A23", X"9A9D", X"9B18", X"9B94", X"9C12", X"9C90",
        X"9D0F", X"9D8F", X"9E10", X"9E92", X"9F15", X"9F98", X"A01D", X"A0A3",
        X"A129", X"A1B1", X"A239", X"A2C2", X"A34D", X"A3D8", X"A464", X"A4F1",
        X"A57E", X"A60D", X"A69C", X"A72D", X"A7BE", X"A850", X"A8E3", X"A976",
        X"AA0B", X"AAA0", X"AB37", X"ABCE", X"AC65", X"ACFE", X"AD98", X"AE32",
        X"AECD", X"AF69", X"B005", X"B0A3", X"B141", X"B1E0", X"B27F", X"B320",
        X"B3C1", X"B463", X"B505", X"B5A8", X"B64C", X"B6F1", X"B797", X"B83D",
        X"B8E4", X"B98B", X"BA33", X"BADC", X"BB86", X"BC30", X"BCDB", X"BD86",
        X"BE32", X"BEDF", X"BF8D", X"C03B", X"C0E9", X"C198", X"C248", X"C2F9",
        X"C3AA", X"C45B", X"C50E", X"C5C0", X"C674", X"C727", X"C7DC", X"C891",
        X"C946", X"C9FC", X"CAB3", X"CB6A", X"CC21", X"CCDA", X"CD92", X"CE4B",
        X"CF05", X"CFBF", X"D079", X"D134", X"D1EF", X"D2AB", X"D367", X"D424",
        X"D4E1", X"D59F", X"D65D", X"D71B", X"D7DA", X"D899", X"D958", X"DA18",
        X"DAD8", X"DB99", X"DC5A", X"DD1B", X"DDDD", X"DE9F", X"DF61", X"E023",
        X"E0E6", X"E1A9", X"E26D", X"E331", X"E3F5", X"E4B9", X"E57E", X"E642",
        X"E707", X"E7CD", X"E892", X"E958", X"EA1E", X"EAE4", X"EBAB", X"EC71",
        X"ED38", X"EDFF", X"EEC6", X"EF8E", X"F055", X"F11D", X"F1E4", X"F2AC",
        X"F374", X"F43C", X"F505", X"F5CD", X"F696", X"F75E", X"F827", X"F8EF",
        X"F9B8", X"FA81", X"FB4A", X"FC13", X"FCDC", X"FDA5", X"FE6E", X"FF37"
    );

    constant ATAN_ROM : lut_array_t(0 to LUT_SIZE - 1) := (
        X"0000", X"000A", X"0014", X"001F", X"0029", X"0033", X"003D", X"0047",
        X"0052", X"005C", X"0066", X"0070", X"007A", X"0085", X"008F", X"0099",
        X"00A3", X"00AD", X"00B8", X"00C2", X"00CC", X"00D6", X"00E0", X"00EA",
        X"00F5", X"00FF", X"0109", X"0113", X"011D", X"0128", X"0132", X"013C",
        X"0146", X"0150", X"015B", X"0165", X"016F", X"0179", X"0183", X"018D",
        X"0198", X"01A2", X"01AC", X"01B6", X"01C0", X"01CB", X"01D5", X"01DF",
        X"01E9", X"01F3", X"01FD", X"0208", X"0212", X"021C", X"0226", X"0230",
        X"023A", X"0245", X"024F", X"0259", X"0263", X"026D", X"0277", X"0282",
        X"028C", X"0296", X"02A0", X"02AA", X"02B4", X"02BE", X"02C9", X"02D3",
        X"02DD", X"02E7", X"02F1", X"02FB", X"0305", X"0310", X"031A", X"0324",
        X"032E", X"0338", X"0342", X"034C", X"0357", X"0361", X"036B", X"0375",
        X"037F", X"0389", X"0393", X"039D", X"03A8", X"03B2", X"03BC", X"03C6",
        X"03D0", X"03DA", X"03E4", X"03EE", X"03F8", X"0402", X"040D", X"0417",
        X"0421", X"042B", X"0435", X"043F", X"0449", X"0453", X"045D", X"0467",
        X"0471", X"047B", X"0486", X"0490", X"049A", X"04A4", X"04AE", X"04B8",
        X"04C2", X"04CC", X"04D6", X"04E0", X"04EA", X"04F4", X"04FE", X"0508",
        X"0512", X"051C", X"0526", X"0530", X"053A", X"0544", X"054F", X"0559",
        X"0563", X"056D", X"0577", X"0581", X"058B", X"0595", X"059F", X"05A9",
        X"05B3", X"05BD", X"05C7", X"05D1", X"05DB", X"05E5", X"05EF", X"05F9",
        X"0603", X"060C", X"0616", X"0620", X"062A", X"0634", X"063E", X"0648",
        X"0652", X"065C", X"0666", X"0670", X"067A", X"0684", X"068E", X"0698",
        X"06A2", X"06AC", X"06B6", X"06C0", X"06C9", X"06D3", X"06DD", X"06E7",
        X"06F1", X"06FB", X"0705", X"070F", X"0719", X"0723", X"072C", X"0736",
        X"0740", X"074A", X"0754", X"075E", X"0768", X"0772", X"077B", X"0785",
        X"078F", X"0799", X"07A3", X"07AD", X"07B6", X"07C0", X"07CA", X"07D4",
        X"07DE", X"07E8", X"07F1", X"07FB", X"0805", X"080F", X"0819", X"0822",
        X"082C", X"0836", X"0840", X"084A", X"0853", X"085D", X"0867", X"0871",
        X"087A", X"0884", X"088E", X"0898", X"08A1", X"08AB", X"08B5", X"08BF",
        X"08C8", X"08D2", X"08DC", X"08E6", X"08EF", X"08F9", X"0903", X"090C",
        X"0916", X"0920", X"0929", X"0933", X"093D", X"0947", X"0950", X"095A",
        X"0964", X"096D", X"0977", X"0981", X"098A", X"0994", X"099D", X"09A7",
        X"09B1", X"09BA", X"09C4", X"09CE", X"09D7", X"09E1", X"09EA", X"09F4",
        X"09FE", X"0A07", X"0A11", X"0A1A", X"0A24", X"0A2E", X"0A37", X"0A41",
        X"0A4A", X"0A54", X"0A5D", X"0A67", X"0A70", X"0A7A", X"0A84", X"0A8D",
        X"0A97", X"0AA0", X"0AAA", X"0AB3", X"0ABD", X"0AC6", X"0AD0", X"0AD9",
        X"0AE3", X"0AEC", X"0AF6", X"0AFF", X"0B09", X"0B12", X"0B1B", X"0B25",
        X"0B2E", X"0B38", X"0B41", X"0B4B", X"0B54", X"0B5E", X"0B67", X"0B70",
        X"0B7A", X"0B83", X"0B8D", X"0B96", X"0B9F", X"0BA9", X"0BB2", X"0BBB",
        X"0BC5", X"0BCE", X"0BD8", X"0BE1", X"0BEA", X"0BF4", X"0BFD", X"0C06",
        X"0C10", X"0C19", X"0C22", X"0C2C", X"0C35", X"0C3E", X"0C48", X"0C51",
        X"0C5A", X"0C63", X"0C6D", X"0C76", X"0C7F", X"0C88", X"0C92", X"0C9B",
        X"0CA4", X"0CAD", X"0CB7", X"0CC0", X"0CC9", X"0CD2", X"0CDC", X"0CE5",
        X"0CEE", X"0CF7", X"0D00", X"0D0A", X"0D13", X"0D1C", X"0D25", X"0D2E",
        X"0D37", X"0D41", X"0D4A", X"0D53", X"0D5C", X"0D65", X"0D6E", X"0D77",
        X"0D81", X"0D8A", X"0D93", X"0D9C", X"0DA5", X"0DAE", X"0DB7", X"0DC0",
        X"0DC9", X"0DD2", X"0DDB", X"0DE5", X"0DEE", X"0DF7", X"0E00", X"0E09",
        X"0E12", X"0E1B", X"0E24", X"0E2D", X"0E36", X"0E3F", X"0E48", X"0E51",
        X"0E5A", X"0E63", X"0E6C", X"0E75", X"0E7E", X"0E87", X"0E90", X"0E99",
        X"0EA1", X"0EAA", X"0EB3", X"0EBC", X"0EC5", X"0ECE", X"0ED7", X"0EE0",
        X"0EE9", X"0EF2", X"0EFB", X"0F03", X"0F0C", X"0F15", X"0F1E", X"0F27",
        X"0F30", X"0F39", X"0F41", X"0F4A", X"0F53", X"0F5C", X"0F65", X"0F6D",
        X"0F76", X"0F7F", X"0F88", X"0F91", X"0F99", X"0FA2", X"0FAB", X"0FB4",
        X"0FBC", X"0FC5", X"0FCE", X"0FD7", X"0FDF", X"0FE8", X"0FF1", X"0FFA",
        X"1002", X"100B", X"1014", X"101C", X"1025", X"102E", X"1036", X"103F",
        X"1048", X"1050", X"1059", X"1062", X"106A", X"1073", X"107B", X"1084",
        X"108D", X"1095", X"109E", X"10A6", X"10AF", X"10B8", X"10C0", X"10C9",
        X"10D1", X"10DA", X"10E2", X"10EB", X"10F4", X"10FC", X"1105", X"110D",
        X"1116", X"111E", X"1127", X"112F", X"1138", X"1140", X"1149", X"1151",
        X"1159", X"1162", X"116A", X"1173", X"117B", X"1184", X"118C", X"1194",
        X"119D", X"11A5", X"11AE", X"11B6", X"11BE", X"11C7", X"11CF", X"11D8",
        X"11E0", X"11E8", X"11F1", X"11F9", X"1201", X"120A", X"1212", X"121A",
        X"1223", X"122B", X"1233", X"123B", X"1244", X"124C", X"1254", X"125D",
        X"1265", X"126D", X"1275", X"127E", X"1286", X"128E", X"1296", X"129E",
        X"12A7", X"12AF", X"12B7", X"12BF", X"12C7", X"12D0", X"12D8", X"12E0",
        X"12E8", X"12F0", X"12F8", X"1301", X"1309", X"1311", X"1319", X"1321",
        X"1329", X"1331", X"1339", X"1341", X"1349", X"1352", X"135A", X"1362",
        X"136A", X"1372", X"137A", X"1382", X"138A", X"1392", X"139A", X"13A2",
        X"13AA", X"13B2", X"13BA", X"13C2", X"13CA", X"13D2", X"13DA", X"13E2",
        X"13EA", X"13F2", X"13FA", X"1402", X"1409", X"1411", X"1419", X"1421",
        X"1429", X"1431", X"1439", X"1441", X"1449", X"1451", X"1458", X"1460",
        X"1468", X"1470", X"1478", X"1480", X"1487", X"148F", X"1497", X"149F",
        X"14A7", X"14AE", X"14B6", X"14BE", X"14C6", X"14CE", X"14D5", X"14DD",
        X"14E5", X"14ED", X"14F4", X"14FC", X"1504", X"150B", X"1513", X"151B",
        X"1522", X"152A", X"1532", X"153A", X"1541", X"1549", X"1551", X"1558",
        X"1560", X"1567", X"156F", X"1577", X"157E", X"1586", X"158E", X"1595",
        X"159D", X"15A4", X"15AC", X"15B3", X"15BB", X"15C3", X"15CA", X"15D2",
        X"15D9", X"15E1", X"15E8", X"15F0", X"15F7", X"15FF", X"1606", X"160E",
        X"1615", X"161D", X"1624", X"162C", X"1633", X"163B", X"1642", X"1649",
        X"1651", X"1658", X"1660", X"1667", X"166F", X"1676", X"167D", X"1685",
        X"168C", X"1694", X"169B", X"16A2", X"16AA", X"16B1", X"16B8", X"16C0",
        X"16C7", X"16CE", X"16D6", X"16DD", X"16E4", X"16EC", X"16F3", X"16FA",
        X"1701", X"1709", X"1710", X"1717", X"171E", X"1726", X"172D", X"1734",
        X"173B", X"1743", X"174A", X"1751", X"1758", X"175F", X"1767", X"176E",
        X"1775", X"177C", X"1783", X"178A", X"1792", X"1799", X"17A0", X"17A7",
        X"17AE", X"17B5", X"17BC", X"17C4", X"17CB", X"17D2", X"17D9", X"17E0",
        X"17E7", X"17EE", X"17F5", X"17FC", X"1803", X"180A", X"1811", X"1818",
        X"181F", X"1826", X"182D", X"1834", X"183B", X"1842", X"1849", X"1850",
        X"1857", X"185E", X"1865", X"186C", X"1873", X"187A", X"1881", X"1888",
        X"188F", X"1896", X"189D", X"18A4", X"18AA", X"18B1", X"18B8", X"18BF",
        X"18C6", X"18CD", X"18D4", X"18DB", X"18E1", X"18E8", X"18EF", X"18F6",
        X"18FD", X"1904", X"190A", X"1911", X"1918", X"191F", X"1926", X"192C",
        X"1933", X"193A", X"1941", X"1947", X"194E", X"1955", X"195C", X"1962",
        X"1969", X"1970", X"1976", X"197D", X"1984", X"198B", X"1991", X"1998",
        X"199F", X"19A5", X"19AC", X"19B3", X"19B9", X"19C0", X"19C6", X"19CD",
        X"19D4", X"19DA", X"19E1", X"19E8", X"19EE", X"19F5", X"19FB", X"1A02",
        X"1A08", X"1A0F", X"1A16", X"1A1C", X"1A23", X"1A29", X"1A30", X"1A36",
        X"1A3D", X"1A43", X"1A4A", X"1A50", X"1A57", X"1A5D", X"1A64", X"1A6A",
        X"1A71", X"1A77", X"1A7E", X"1A84", X"1A8B", X"1A91", X"1A98", X"1A9E",
        X"1AA4", X"1AAB", X"1AB1", X"1AB8", X"1ABE", X"1AC4", X"1ACB", X"1AD1",
        X"1AD8", X"1ADE", X"1AE4", X"1AEB", X"1AF1", X"1AF7", X"1AFE", X"1B04",
        X"1B0A", X"1B11", X"1B17", X"1B1D", X"1B24", X"1B2A", X"1B30", X"1B37",
        X"1B3D", X"1B43", X"1B49", X"1B50", X"1B56", X"1B5C", X"1B62", X"1B69",
        X"1B6F", X"1B75", X"1B7B", X"1B82", X"1B88", X"1B8E", X"1B94", X"1B9A",
        X"1BA1", X"1BA7", X"1BAD", X"1BB3", X"1BB9", X"1BBF", X"1BC6", X"1BCC",
        X"1BD2", X"1BD8", X"1BDE", X"1BE4", X"1BEA", X"1BF0", X"1BF7", X"1BFD",
        X"1C03", X"1C09", X"1C0F", X"1C15", X"1C1B", X"1C21", X"1C27", X"1C2D",
        X"1C33", X"1C39", X"1C3F", X"1C45", X"1C4B", X"1C51", X"1C57", X"1C5D",
        X"1C63", X"1C69", X"1C6F", X"1C75", X"1C7B", X"1C81", X"1C87", X"1C8D",
        X"1C93", X"1C99", X"1C9F", X"1CA5", X"1CAB", X"1CB1", X"1CB7", X"1CBD",
        X"1CC3", X"1CC9", X"1CCE", X"1CD4", X"1CDA", X"1CE0", X"1CE6", X"1CEC",
        X"1CF2", X"1CF8", X"1CFD", X"1D03", X"1D09", X"1D0F", X"1D15", X"1D1B",
        X"1D20", X"1D26", X"1D2C", X"1D32", X"1D38", X"1D3D", X"1D43", X"1D49",
        X"1D4F", X"1D54", X"1D5A", X"1D60", X"1D66", X"1D6B", X"1D71", X"1D77",
        X"1D7D", X"1D82", X"1D88", X"1D8E", X"1D94", X"1D99", X"1D9F", X"1DA5",
        X"1DAA", X"1DB0", X"1DB6", X"1DBB", X"1DC1", X"1DC7", X"1DCC", X"1DD2",
        X"1DD8", X"1DDD", X"1DE3", X"1DE8", X"1DEE", X"1DF4", X"1DF9", X"1DFF",
        X"1E05", X"1E0A", X"1E10", X"1E15", X"1E1B", X"1E20", X"1E26", X"1E2C",
        X"1E31", X"1E37", X"1E3C", X"1E42", X"1E47", X"1E4D", X"1E52", X"1E58",
        X"1E5D", X"1E63", X"1E68", X"1E6E", X"1E73", X"1E79", X"1E7E", X"1E84",
        X"1E89", X"1E8F", X"1E94", X"1E9A", X"1E9F", X"1EA4", X"1EAA", X"1EAF",
        X"1EB5", X"1EBA", X"1EC0", X"1EC5", X"1ECA", X"1ED0", X"1ED5", X"1EDB",
        X"1EE0", X"1EE5", X"1EEB", X"1EF0", X"1EF5", X"1EFB", X"1F00", X"1F05",
        X"1F0B", X"1F10", X"1F15", X"1F1B", X"1F20", X"1F25", X"1F2B", X"1F30",
        X"1F35", X"1F3B", X"1F40", X"1F45", X"1F4A", X"1F50", X"1F55", X"1F5A",
        X"1F60", X"1F65", X"1F6A", X"1F6F", X"1F75", X"1F7A", X"1F7F", X"1F84",
        X"1F89", X"1F8F", X"1F94", X"1F99", X"1F9E", X"1FA3", X"1FA9", X"1FAE",
        X"1FB3", X"1FB8", X"1FBD", X"1FC2", X"1FC8", X"1FCD", X"1FD2", X"1FD7",
        X"1FDC", X"1FE1", X"1FE6", X"1FEC", X"1FF1", X"1FF6", X"1FFB", X"2000"
    );

    constant ASIN_ROM : lut_array_t(0 to LUT_SIZE - 1) := (
        X"0000", X"000A", X"0014", X"001F", X"0029", X"0033", X"003D", X"0047",
        X"0052", X"005C", X"0066", X"0070", X"007A", X"0085", X"008F", X"0099",
        X"00A3", X"00AD", X"00B8", X"00C2", X"00CC", X"00D6", X"00E0", X"00EB",
        X"00F5", X"00FF", X"0109", X"0113", X"011E", X"0128", X"0132", X"013C",
        X"0146", X"0151", X"015B", X"0165", X"016F", X"0179", X"0184", X"018E",
        X"0198", X"01A2", X"01AC", X"01B7", X"01C1", X"01CB", X"01D5", X"01DF",
        X"01EA", X"01F4", X"01FE", X"0208", X"0212", X"021D", X"0227", X"0231",
        X"023B", X"0245", X"0250", X"025A", X"0264", X"026E", X"0279", X"0283",
        X"028D", X"0297", X"02A1", X"02AC", X"02B6", X"02C0", X"02CA", X"02D4",
        X"02DF", X"02E9", X"02F3", X"02FD", X"0308", X"0312", X"031C", X"0326",
        X"0331", X"033B", X"0345", X"034F", X"0359", X"0364", X"036E", X"0378",
        X"0382", X"038D", X"0397", X"03A1", X"03AB", X"03B6", X"03C0", X"03CA",
        X"03D4", X"03DE", X"03E9", X"03F3", X"03FD", X"0407", X"0412", X"041C",
        X"0426", X"0430", X"043B", X"0445", X"044F", X"0459", X"0464", X"046E",
        X"0478", X"0482", X"048D", X"0497", X"04A1", X"04AC", X"04B6", X"04C0",
        X"04CA", X"04D5", X"04DF", X"04E9", X"04F3", X"04FE", X"0508", X"0512",
        X"051D", X"0527", X"0531", X"053B", X"0546", X"0550", X"055A", X"0564",
        X"056F", X"0579", X"0583", X"058E", X"0598", X"05A2", X"05AD", X"05B7",
        X"05C1", X"05CB", X"05D6", X"05E0", X"05EA", X"05F5", X"05FF", X"0609",
        X"0614", X"061E", X"0628", X"0632", X"063D", X"0647", X"0651", X"065C",
        X"0666", X"0670", X"067B", X"0685", X"068F", X"069A", X"06A4", X"06AE",
        X"06B9", X"06C3", X"06CD", X"06D8", X"06E2", X"06EC", X"06F7", X"0701",
        X"070B", X"0716", X"0720", X"072B", X"0735", X"073F", X"074A", X"0754",
        X"075E", X"0769", X"0773", X"077D", X"0788", X"0792", X"079D", X"07A7",
        X"07B1", X"07BC", X"07C6", X"07D0", X"07DB", X"07E5", X"07F0", X"07FA",
        X"0804", X"080F", X"0819", X"0824", X"082E", X"0838", X"0843", X"084D",
        X"0858", X"0862", X"086C", X"0877", X"0881", X"088C", X"0896", X"08A1",
        X"08AB", X"08B5", X"08C0", X"08CA", X"08D5", X"08DF", X"08EA", X"08F4",
        X"08FF", X"0909", X"0913", X"091E", X"0928", X"0933", X"093D", X"0948",
        X"0952", X"095D", X"0967", X"0972", X"097C", X"0987", X"0991", X"099C",
        X"09A6", X"09B1", X"09BB", X"09C6", X"09D0", X"09DB", X"09E5", X"09F0",
        X"09FA", X"0A05", X"0A0F", X"0A1A", X"0A24", X"0A2F", X"0A39", X"0A44",
        X"0A4E", X"0A59", X"0A63", X"0A6E", X"0A78", X"0A83", X"0A8D", X"0A98",
        X"0AA3", X"0AAD", X"0AB8", X"0AC2", X"0ACD", X"0AD7", X"0AE2", X"0AEC",
        X"0AF7", X"0B02", X"0B0C", X"0B17", X"0B21", X"0B2C", X"0B37", X"0B41",
        X"0B4C", X"0B56", X"0B61", X"0B6C", X"0B76", X"0B81", X"0B8B", X"0B96",
        X"0BA1", X"0BAB", X"0BB6", X"0BC1", X"0BCB", X"0BD6", X"0BE0", X"0BEB",
        X"0BF6", X"0C00", X"0C0B", X"0C16", X"0C20", X"0C2B", X"0C36", X"0C40",
        X"0C4B", X"0C56", X"0C60", X"0C6B", X"0C76", X"0C81", X"0C8B", X"0C96",
        X"0CA1", X"0CAB", X"0CB6", X"0CC1", X"0CCB", X"0CD6", X"0CE1", X"0CEC",
        X"0CF6", X"0D01", X"0D0C", X"0D17", X"0D21", X"0D2C", X"0D37", X"0D42",
        X"0D4C", X"0D57", X"0D62", X"0D6D", X"0D77", X"0D82", X"0D8D", X"0D98",
        X"0DA3", X"0DAD", X"0DB8", X"0DC3", X"0DCE", X"0DD9", X"0DE3", X"0DEE",
        X"0DF9", X"0E04", X"0E0F", X"0E1A", X"0E24", X"0E2F", X"0E3A", X"0E45",
        X"0E50", X"0E5B", X"0E66", X"0E70", X"0E7B", X"0E86", X"0E91", X"0E9C",
        X"0EA7", X"0EB2", X"0EBD", X"0EC8", X"0ED2", X"0EDD", X"0EE8", X"0EF3",
        X"0EFE", X"0F09", X"0F14", X"0F1F", X"0F2A", X"0F35", X"0F40", X"0F4B",
        X"0F56", X"0F61", X"0F6C", X"0F77", X"0F82", X"0F8D", X"0F98", X"0FA3",
        X"0FAE", X"0FB9", X"0FC4", X"0FCF", X"0FDA", X"0FE5", X"0FF0", X"0FFB",
        X"1006", X"1011", X"101C", X"1027", X"1032", X"103D", X"1048", X"1053",
        X"105E", X"1069", X"1074", X"107F", X"108A", X"1096", X"10A1", X"10AC",
        X"10B7", X"10C2", X"10CD", X"10D8", X"10E3", X"10EF", X"10FA", X"1105",
        X"1110", X"111B", X"1126", X"1132", X"113D", X"1148", X"1153", X"115E",
        X"1169", X"1175", X"1180", X"118B", X"1196", X"11A2", X"11AD", X"11B8",
        X"11C3", X"11CF", X"11DA", X"11E5", X"11F0", X"11FC", X"1207", X"1212",
        X"121D", X"1229", X"1234", X"123F", X"124B", X"1256", X"1261", X"126D",
        X"1278", X"1283", X"128F", X"129A", X"12A5", X"12B1", X"12BC", X"12C8",
        X"12D3", X"12DE", X"12EA", X"12F5", X"1301", X"130C", X"1317", X"1323",
        X"132E", X"133A", X"1345", X"1351", X"135C", X"1368", X"1373", X"137E",
        X"138A", X"1395", X"13A1", X"13AC", X"13B8", X"13C4", X"13CF", X"13DB",
        X"13E6", X"13F2", X"13FD", X"1409", X"1414", X"1420", X"142C", X"1437",
        X"1443", X"144E", X"145A", X"1466", X"1471", X"147D", X"1488", X"1494",
        X"14A0", X"14AB", X"14B7", X"14C3", X"14CE", X"14DA", X"14E6", X"14F2",
        X"14FD", X"1509", X"1515", X"1520", X"152C", X"1538", X"1544", X"154F",
        X"155B", X"1567", X"1573", X"157F", X"158A", X"1596", X"15A2", X"15AE",
        X"15BA", X"15C6", X"15D1", X"15DD", X"15E9", X"15F5", X"1601", X"160D",
        X"1619", X"1625", X"1630", X"163C", X"1648", X"1654", X"1660", X"166C",
        X"1678", X"1684", X"1690", X"169C", X"16A8", X"16B4", X"16C0", X"16CC",
        X"16D8", X"16E4", X"16F0", X"16FC", X"1708", X"1714", X"1721", X"172D",
        X"1739", X"1745", X"1751", X"175D", X"1769", X"1775", X"1782", X"178E",
        X"179A", X"17A6", X"17B2", X"17BF", X"17CB", X"17D7", X"17E3", X"17EF",
        X"17FC", X"1808", X"1814", X"1821", X"182D", X"1839", X"1845", X"1852",
        X"185E", X"186A", X"1877", X"1883", X"1890", X"189C", X"18A8", X"18B5",
        X"18C1", X"18CE", X"18DA", X"18E6", X"18F3", X"18FF", X"190C", X"1918",
        X"1925", X"1931", X"193E", X"194A", X"1957", X"1963", X"1970", X"197D",
        X"1989", X"1996", X"19A2", X"19AF", X"19BC", X"19C8", X"19D5", X"19E2",
        X"19EE", X"19FB", X"1A08", X"1A14", X"1A21", X"1A2E", X"1A3B", X"1A47",
        X"1A54", X"1A61", X"1A6E", X"1A7A", X"1A87", X"1A94", X"1AA1", X"1AAE",
        X"1ABB", X"1AC7", X"1AD4", X"1AE1", X"1AEE", X"1AFB", X"1B08", X"1B15",
        X"1B22", X"1B2F", X"1B3C", X"1B49", X"1B56", X"1B63", X"1B70", X"1B7D",
        X"1B8A", X"1B97", X"1BA4", X"1BB1", X"1BBE", X"1BCC", X"1BD9", X"1BE6",
        X"1BF3", X"1C00", X"1C0D", X"1C1B", X"1C28", X"1C35", X"1C42", X"1C50",
        X"1C5D", X"1C6A", X"1C77", X"1C85", X"1C92", X"1C9F", X"1CAD", X"1CBA",
        X"1CC8", X"1CD5", X"1CE2", X"1CF0", X"1CFD", X"1D0B", X"1D18", X"1D26",
        X"1D33", X"1D41", X"1D4E", X"1D5C", X"1D6A", X"1D77", X"1D85", X"1D92",
        X"1DA0", X"1DAE", X"1DBB", X"1DC9", X"1DD7", X"1DE4", X"1DF2", X"1E00",
        X"1E0E", X"1E1B", X"1E29", X"1E37", X"1E45", X"1E53", X"1E61", X"1E6F",
        X"1E7C", X"1E8A", X"1E98", X"1EA6", X"1EB4", X"1EC2", X"1ED0", X"1EDE",
        X"1EEC", X"1EFA", X"1F08", X"1F17", X"1F25", X"1F33", X"1F41", X"1F4F",
        X"1F5D", X"1F6C", X"1F7A", X"1F88", X"1F96", X"1FA5", X"1FB3", X"1FC1",
        X"1FD0", X"1FDE", X"1FEC", X"1FFB", X"2009", X"2018", X"2026", X"2034",
        X"2043", X"2051", X"2060", X"206F", X"207D", X"208C", X"209A", X"20A9",
        X"20B8", X"20C6", X"20D5", X"20E4", X"20F3", X"2101", X"2110", X"211F",
        X"212E", X"213D", X"214C", X"215B", X"2169", X"2178", X"2187", X"2196",
        X"21A5", X"21B4", X"21C4", X"21D3", X"21E2", X"21F1", X"2200", X"220F",
        X"221F", X"222E", X"223D", X"224C", X"225C", X"226B", X"227A", X"228A",
        X"2299", X"22A9", X"22B8", X"22C8", X"22D7", X"22E7", X"22F6", X"2306",
        X"2315", X"2325", X"2335", X"2345", X"2354", X"2364", X"2374", X"2384",
        X"2394", X"23A3", X"23B3", X"23C3", X"23D3", X"23E3", X"23F3", X"2403",
        X"2413", X"2424", X"2434", X"2444", X"2454", X"2464", X"2475", X"2485",
        X"2495", X"24A6", X"24B6", X"24C7", X"24D7", X"24E8", X"24F8", X"2509",
        X"2519", X"252A", X"253B", X"254B", X"255C", X"256D", X"257E", X"258E",
        X"259F", X"25B0", X"25C1", X"25D2", X"25E3", X"25F4", X"2605", X"2617",
        X"2628", X"2639", X"264A", X"265C", X"266D", X"267E", X"2690", X"26A1",
        X"26B3", X"26C4", X"26D6", X"26E7", X"26F9", X"270B", X"271D", X"272E",
        X"2740", X"2752", X"2764", X"2776", X"2788", X"279A", X"27AC", X"27BE",
        X"27D1", X"27E3", X"27F5", X"2807", X"281A", X"282C", X"283F", X"2851",
        X"2864", X"2877", X"2889", X"289C", X"28AF", X"28C2", X"28D5", X"28E8",
        X"28FB", X"290E", X"2921", X"2934", X"2947", X"295A", X"296E", X"2981",
        X"2995", X"29A8", X"29BC", X"29CF", X"29E3", X"29F7", X"2A0B", X"2A1F",
        X"2A33", X"2A47", X"2A5B", X"2A6F", X"2A83", X"2A97", X"2AAC", X"2AC0",
        X"2AD5", X"2AE9", X"2AFE", X"2B13", X"2B27", X"2B3C", X"2B51", X"2B66",
        X"2B7B", X"2B91", X"2BA6", X"2BBB", X"2BD1", X"2BE6", X"2BFC", X"2C11",
        X"2C27", X"2C3D", X"2C53", X"2C69", X"2C7F", X"2C95", X"2CAB", X"2CC2",
        X"2CD8", X"2CEF", X"2D05", X"2D1C", X"2D33", X"2D4A", X"2D61", X"2D78",
        X"2D8F", X"2DA7", X"2DBE", X"2DD6", X"2DED", X"2E05", X"2E1D", X"2E35",
        X"2E4D", X"2E66", X"2E7E", X"2E97", X"2EAF", X"2EC8", X"2EE1", X"2EFA",
        X"2F13", X"2F2D", X"2F46", X"2F60", X"2F79", X"2F93", X"2FAD", X"2FC8",
        X"2FE2", X"2FFD", X"3017", X"3032", X"304D", X"3068", X"3084", X"309F",
        X"30BB", X"30D7", X"30F3", X"3110", X"312C", X"3149", X"3166", X"3183",
        X"31A0", X"31BE", X"31DC", X"31FA", X"3218", X"3237", X"3256", X"3275",
        X"3294", X"32B4", X"32D4", X"32F4", X"3315", X"3335", X"3357", X"3378",
        X"339A", X"33BC", X"33DF", X"3402", X"3425", X"3449", X"346D", X"3492",
        X"34B7", X"34DC", X"3502", X"3529", X"3550", X"3577", X"35A0", X"35C8",
        X"35F2", X"361C", X"3647", X"3672", X"369E", X"36CB", X"36F9", X"3728",
        X"3758", X"3789", X"37BB", X"37EE", X"3823", X"3858", X"3890", X"38C9",
        X"3904", X"3940", X"397F", X"39C1", X"3A05", X"3A4C", X"3A97", X"3AE7",
        X"3B3B", X"3B96", X"3BF8", X"3C65", X"3CE1", X"3D74", X"3E33", X"4000"
    );

    constant SQRT_ROM : lut_array_t(0 to LUT_SIZE - 1) := (
        X"0000", X"0400", X"05A9", X"06EE", X"0801", X"08F3", X"09CD", X"0A96",
        X"0B52", X"0C01", X"0CA8", X"0D46", X"0DDD", X"0E6E", X"0EF9", X"0F80",
        X"1002", X"1080", X"10FA", X"1172", X"11E6", X"1257", X"12C5", X"1331",
        X"139B", X"1402", X"1468", X"14CB", X"152D", X"158D", X"15EB", X"1648",
        X"16A3", X"16FD", X"1756", X"17AD", X"1803", X"1858", X"18AB", X"18FE",
        X"194F", X"19A0", X"19EF", X"1A3E", X"1A8C", X"1AD8", X"1B24", X"1B6F",
        X"1BBA", X"1C03", X"1C4C", X"1C94", X"1CDC", X"1D22", X"1D68", X"1DAE",
        X"1DF2", X"1E37", X"1E7A", X"1EBD", X"1F00", X"1F41", X"1F83", X"1FC3",
        X"2004", X"2044", X"2083", X"20C2", X"2100", X"213E", X"217B", X"21B8",
        X"21F5", X"2231", X"226D", X"22A8", X"22E3", X"231E", X"2358", X"2392",
        X"23CB", X"2404", X"243D", X"2475", X"24AD", X"24E5", X"251D", X"2554",
        X"258A", X"25C1", X"25F7", X"262D", X"2662", X"2698", X"26CD", X"2701",
        X"2736", X"276A", X"279E", X"27D1", X"2805", X"2838", X"286B", X"289D",
        X"28D0", X"2902", X"2934", X"2965", X"2997", X"29C8", X"29F9", X"2A29",
        X"2A5A", X"2A8A", X"2ABA", X"2AEA", X"2B1A", X"2B49", X"2B79", X"2BA8",
        X"2BD6", X"2C05", X"2C34", X"2C62", X"2C90", X"2CBE", X"2CEC", X"2D19",
        X"2D47", X"2D74", X"2DA1", X"2DCE", X"2DFA", X"2E27", X"2E53", X"2E7F",
        X"2EAB", X"2ED7", X"2F03", X"2F2E", X"2F5A", X"2F85", X"2FB0", X"2FDB",
        X"3006", X"3030", X"305B", X"3085", X"30AF", X"30D9", X"3103", X"312D",
        X"3157", X"3180", X"31A9", X"31D3", X"31FC", X"3225", X"324D", X"3276",
        X"329F", X"32C7", X"32EF", X"3318", X"3340", X"3368", X"338F", X"33B7",
        X"33DF", X"3406", X"342D", X"3455", X"347C", X"34A3", X"34CA", X"34F0",
        X"3517", X"353E", X"3564", X"358A", X"35B1", X"35D7", X"35FD", X"3623",
        X"3649", X"366E", X"3694", X"36B9", X"36DF", X"3704", X"3729", X"374E",
        X"3773", X"3798", X"37BD", X"37E2", X"3807", X"382B", X"3850", X"3874",
        X"3898", X"38BC", X"38E0", X"3904", X"3928", X"394C", X"3970", X"3994",
        X"39B7", X"39DB", X"39FE", X"3A21", X"3A44", X"3A68", X"3A8B", X"3AAE",
        X"3AD1", X"3AF3", X"3B16", X"3B39", X"3B5B", X"3B7E", X"3BA0", X"3BC3",
        X"3BE5", X"3C07", X"3C29", X"3C4B", X"3C6D", X"3C8F", X"3CB1", X"3CD3",
        X"3CF4", X"3D16", X"3D37", X"3D59", X"3D7A", X"3D9C", X"3DBD", X"3DDE",
        X"3DFF", X"3E20", X"3E41", X"3E62", X"3E83", X"3EA3", X"3EC4", X"3EE5",
        X"3F05", X"3F26", X"3F46", X"3F67", X"3F87", X"3FA7", X"3FC7", X"3FE7",
        X"4008", X"4027", X"4047", X"4067", X"4087", X"40A7", X"40C6", X"40E6",
        X"4106", X"4125", X"4145", X"4164", X"4183", X"41A3", X"41C2", X"41E1",
        X"4200", X"421F", X"423E", X"425D", X"427C", X"429B", X"42B9", X"42D8",
        X"42F7", X"4315", X"4334", X"4352", X"4371", X"438F", X"43AD", X"43CC",
        X"43EA", X"4408", X"4426", X"4444", X"4462", X"4480", X"449E", X"44BC",
        X"44DA", X"44F7", X"4515", X"4533", X"4550", X"456E", X"458B", X"45A9",
        X"45C6", X"45E4", X"4601", X"461E", X"463B", X"4659", X"4676", X"4693",
        X"46B0", X"46CD", X"46EA", X"4707", X"4723", X"4740", X"475D", X"477A",
        X"4796", X"47B3", X"47CF", X"47EC", X"4808", X"4825", X"4841", X"485E",
        X"487A", X"4896", X"48B2", X"48CF", X"48EB", X"4907", X"4923", X"493F",
        X"495B", X"4977", X"4993", X"49AE", X"49CA", X"49E6", X"4A02", X"4A1D",
        X"4A39", X"4A55", X"4A70", X"4A8C", X"4AA7", X"4AC3", X"4ADE", X"4AF9",
        X"4B15", X"4B30", X"4B4B", X"4B66", X"4B82", X"4B9D", X"4BB8", X"4BD3",
        X"4BEE", X"4C09", X"4C24", X"4C3F", X"4C5A", X"4C74", X"4C8F", X"4CAA",
        X"4CC5", X"4CDF", X"4CFA", X"4D15", X"4D2F", X"4D4A", X"4D64", X"4D7F",
        X"4D99", X"4DB4", X"4DCE", X"4DE8", X"4E03", X"4E1D", X"4E37", X"4E51",
        X"4E6B", X"4E86", X"4EA0", X"4EBA", X"4ED4", X"4EEE", X"4F08", X"4F22",
        X"4F3B", X"4F55", X"4F6F", X"4F89", X"4FA3", X"4FBC", X"4FD6", X"4FF0",
        X"5009", X"5023", X"503D", X"5056", X"5070", X"5089", X"50A2", X"50BC",
        X"50D5", X"50EF", X"5108", X"5121", X"513A", X"5154", X"516D", X"5186",
        X"519F", X"51B8", X"51D1", X"51EA", X"5203", X"521C", X"5235", X"524E",
        X"5267", X"5280", X"5299", X"52B2", X"52CA", X"52E3", X"52FC", X"5315",
        X"532D", X"5346", X"535E", X"5377", X"5390", X"53A8", X"53C1", X"53D9",
        X"53F1", X"540A", X"5422", X"543B", X"5453", X"546B", X"5483", X"549C",
        X"54B4", X"54CC", X"54E4", X"54FC", X"5515", X"552D", X"5545", X"555D",
        X"5575", X"558D", X"55A5", X"55BD", X"55D4", X"55EC", X"5604", X"561C",
        X"5634", X"564C", X"5663", X"567B", X"5693", X"56AA", X"56C2", X"56DA",
        X"56F1", X"5709", X"5720", X"5738", X"574F", X"5767", X"577E", X"5796",
        X"57AD", X"57C4", X"57DC", X"57F3", X"580A", X"5822", X"5839", X"5850",
        X"5867", X"587E", X"5896", X"58AD", X"58C4", X"58DB", X"58F2", X"5909",
        X"5920", X"5937", X"594E", X"5965", X"597C", X"5993", X"59AA", X"59C0",
        X"59D7", X"59EE", X"5A05", X"5A1C", X"5A32", X"5A49", X"5A60", X"5A76",
        X"5A8D", X"5AA4", X"5ABA", X"5AD1", X"5AE7", X"5AFE", X"5B15", X"5B2B",
        X"5B41", X"5B58", X"5B6E", X"5B85", X"5B9B", X"5BB2", X"5BC8", X"5BDE",
        X"5BF5", X"5C0B", X"5C21", X"5C37", X"5C4E", X"5C64", X"5C7A", X"5C90",
        X"5CA6", X"5CBC", X"5CD2", X"5CE8", X"5CFF", X"5D15", X"5D2B", X"5D41",
        X"5D57", X"5D6C", X"5D82", X"5D98", X"5DAE", X"5DC4", X"5DDA", X"5DF0",
        X"5E06", X"5E1B", X"5E31", X"5E47", X"5E5D", X"5E72", X"5E88", X"5E9E",
        X"5EB3", X"5EC9", X"5EDF", X"5EF4", X"5F0A", X"5F1F", X"5F35", X"5F4A",
        X"5F60", X"5F75", X"5F8B", X"5FA0", X"5FB6", X"5FCB", X"5FE1", X"5FF6",
        X"600B", X"6021", X"6036", X"604B", X"6060", X"6076", X"608B", X"60A0",
        X"60B5", X"60CB", X"60E0", X"60F5", X"610A", X"611F", X"6134", X"6149",
        X"615E", X"6173", X"6188", X"619D", X"61B2", X"61C7", X"61DC", X"61F1",
        X"6206", X"621B", X"6230", X"6245", X"625A", X"626F", X"6283", X"6298",
        X"62AD", X"62C2", X"62D7", X"62EB", X"6300", X"6315", X"6329", X"633E",
        X"6353", X"6367", X"637C", X"6390", X"63A5", X"63BA", X"63CE", X"63E3",
        X"63F7", X"640C", X"6420", X"6435", X"6449", X"645E", X"6472", X"6486",
        X"649B", X"64AF", X"64C3", X"64D8", X"64EC", X"6500", X"6515", X"6529",
        X"653D", X"6551", X"6566", X"657A", X"658E", X"65A2", X"65B6", X"65CB",
        X"65DF", X"65F3", X"6607", X"661B", X"662F", X"6643", X"6657", X"666B",
        X"667F", X"6693", X"66A7", X"66BB", X"66CF", X"66E3", X"66F7", X"670B",
        X"671F", X"6733", X"6746", X"675A", X"676E", X"6782", X"6796", X"67AA",
        X"67BD", X"67D1", X"67E5", X"67F8", X"680C", X"6820", X"6834", X"6847",
        X"685B", X"686F", X"6882", X"6896", X"68A9", X"68BD", X"68D0", X"68E4",
        X"68F8", X"690B", X"691F", X"6932", X"6946", X"6959", X"696C", X"6980",
        X"6993", X"69A7", X"69BA", X"69CE", X"69E1", X"69F4", X"6A08", X"6A1B",
        X"6A2E", X"6A42", X"6A55", X"6A68", X"6A7B", X"6A8F", X"6AA2", X"6AB5",
        X"6AC8", X"6ADB", X"6AEF", X"6B02", X"6B15", X"6B28", X"6B3B", X"6B4E",
        X"6B61", X"6B74", X"6B88", X"6B9B", X"6BAE", X"6BC1", X"6BD4", X"6BE7",
        X"6BFA", X"6C0D", X"6C20", X"6C33", X"6C46", X"6C58", X"6C6B", X"6C7E",
        X"6C91", X"6CA4", X"6CB7", X"6CCA", X"6CDD", X"6CEF", X"6D02", X"6D15",
        X"6D28", X"6D3B", X"6D4D", X"6D60", X"6D73", X"6D86", X"6D98", X"6DAB",
        X"6DBE", X"6DD0", X"6DE3", X"6DF6", X"6E08", X"6E1B", X"6E2D", X"6E40",
        X"6E53", X"6E65", X"6E78", X"6E8A", X"6E9D", X"6EAF", X"6EC2", X"6ED4",
        X"6EE7", X"6EF9", X"6F0C", X"6F1E", X"6F31", X"6F43", X"6F56", X"6F68",
        X"6F7A", X"6F8D", X"6F9F", X"6FB2", X"6FC4", X"6FD6", X"6FE9", X"6FFB",
        X"700D", X"701F", X"7032", X"7044", X"7056", X"7068", X"707B", X"708D",
        X"709F", X"70B1", X"70C3", X"70D6", X"70E8", X"70FA", X"710C", X"711E",
        X"7130", X"7142", X"7155", X"7167", X"7179", X"718B", X"719D", X"71AF",
        X"71C1", X"71D3", X"71E5", X"71F7", X"7209", X"721B", X"722D", X"723F",
        X"7251", X"7263", X"7275", X"7286", X"7298", X"72AA", X"72BC", X"72CE",
        X"72E0", X"72F2", X"7303", X"7315", X"7327", X"7339", X"734B", X"735C",
        X"736E", X"7380", X"7392", X"73A3", X"73B5", X"73C7", X"73D9", X"73EA",
        X"73FC", X"740E", X"741F", X"7431", X"7443", X"7454", X"7466", X"7477",
        X"7489", X"749B", X"74AC", X"74BE", X"74CF", X"74E1", X"74F2", X"7504",
        X"7515", X"7527", X"7538", X"754A", X"755B", X"756D", X"757E", X"7590",
        X"75A1", X"75B3", X"75C4", X"75D5", X"75E7", X"75F8", X"7609", X"761B",
        X"762C", X"763E", X"764F", X"7660", X"7672", X"7683", X"7694", X"76A5",
        X"76B7", X"76C8", X"76D9", X"76EA", X"76FC", X"770D", X"771E", X"772F",
        X"7740", X"7752", X"7763", X"7774", X"7785", X"7796", X"77A7", X"77B9",
        X"77CA", X"77DB", X"77EC", X"77FD", X"780E", X"781F", X"7830", X"7841",
        X"7852", X"7863", X"7874", X"7885", X"7896", X"78A7", X"78B8", X"78C9",
        X"78DA", X"78EB", X"78FC", X"790D", X"791E", X"792F", X"7940", X"7951",
        X"7962", X"7973", X"7983", X"7994", X"79A5", X"79B6", X"79C7", X"79D8",
        X"79E8", X"79F9", X"7A0A", X"7A1B", X"7A2C", X"7A3C", X"7A4D", X"7A5E",
        X"7A6F", X"7A7F", X"7A90", X"7AA1", X"7AB2", X"7AC2", X"7AD3", X"7AE4",
        X"7AF4", X"7B05", X"7B16", X"7B26", X"7B37", X"7B48", X"7B58", X"7B69",
        X"7B79", X"7B8A", X"7B9B", X"7BAB", X"7BBC", X"7BCC", X"7BDD", X"7BED",
        X"7BFE", X"7C0F", X"7C1F", X"7C30", X"7C40", X"7C51", X"7C61", X"7C72",
        X"7C82", X"7C92", X"7CA3", X"7CB3", X"7CC4", X"7CD4", X"7CE5", X"7CF5",
        X"7D05", X"7D16", X"7D26", X"7D37", X"7D47", X"7D57", X"7D68", X"7D78",
        X"7D88", X"7D99", X"7DA9", X"7DB9", X"7DCA", X"7DDA", X"7DEA", X"7DFA",
        X"7E0B", X"7E1B", X"7E2B", X"7E3B", X"7E4C", X"7E5C", X"7E6C", X"7E7C",
        X"7E8D", X"7E9D", X"7EAD", X"7EBD", X"7ECD", X"7EDD", X"7EEE", X"7EFE",
        X"7F0E", X"7F1E", X"7F2E", X"7F3E", X"7F4E", X"7F5E", X"7F6F", X"7F7F",
        X"7F8F", X"7F9F", X"7FAF", X"7FBF", X"7FCF", X"7FDF", X"7FEF", X"7FFF"
    );


    constant RECIP_ROM : lut_array_t(0 to LUT_SIZE - 1) := (
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
        X"8000", X"7FC0", X"7F80", X"7F41", X"7F02", X"7EC3", X"7E84", X"7E46",
        X"7E08", X"7DCA", X"7D8C", X"7D4F", X"7D12", X"7CD5", X"7C98", X"7C5B",
        X"7C1F", X"7BE3", X"7BA7", X"7B6C", X"7B30", X"7AF5", X"7ABA", X"7A7F",
        X"7A45", X"7A0A", X"79D0", X"7997", X"795D", X"7923", X"78EA", X"78B1",
        X"7878", X"7840", X"7808", X"77CF", X"7797", X"7760", X"7728", X"76F1",
        X"76BA", X"7683", X"764C", X"7615", X"75DF", X"75A9", X"7573", X"753D",
        X"7507", X"74D2", X"749D", X"7468", X"7433", X"73FE", X"73CA", X"7395",
        X"7361", X"732D", X"72FA", X"72C6", X"7293", X"7260", X"722D", X"71FA",
        X"71C7", X"7195", X"7162", X"7130", X"70FE", X"70CC", X"709B", X"7069",
        X"7038", X"7007", X"6FD6", X"6FA5", X"6F75", X"6F44", X"6F14", X"6EE4",
        X"6EB4", X"6E84", X"6E54", X"6E25", X"6DF6", X"6DC7", X"6D98", X"6D69",
        X"6D3A", X"6D0C", X"6CDD", X"6CAF", X"6C81", X"6C53", X"6C25", X"6BF8",
        X"6BCA", X"6B9D", X"6B70", X"6B43", X"6B16", X"6AE9", X"6ABC", X"6A90",
        X"6A64", X"6A38", X"6A0C", X"69E0", X"69B4", X"6988", X"695D", X"6932",
        X"6907", X"68DC", X"68B1", X"6886", X"685B", X"6831", X"6807", X"67DC",
        X"67B2", X"6788", X"675E", X"6735", X"670B", X"66E2", X"66B9", X"668F",
        X"6666", X"663E", X"6615", X"65EC", X"65C4", X"659B", X"6573", X"654B",
        X"6523", X"64FB", X"64D3", X"64AB", X"6484", X"645D", X"6435", X"640E",
        X"63E7", X"63C0", X"6399", X"6373", X"634C", X"6326", X"62FF", X"62D9",
        X"62B3", X"628D", X"6267", X"6241", X"621C", X"61F6", X"61D1", X"61AB",
        X"6186", X"6161", X"613C", X"6117", X"60F2", X"60CE", X"60A9", X"6085",
        X"6060", X"603C", X"6018", X"5FF4", X"5FD0", X"5FAC", X"5F89", X"5F65",
        X"5F41", X"5F1E", X"5EFB", X"5ED8", X"5EB5", X"5E92", X"5E6F", X"5E4C",
        X"5E29", X"5E07", X"5DE4", X"5DC2", X"5D9F", X"5D7D", X"5D5B", X"5D39",
        X"5D17", X"5CF5", X"5CD4", X"5CB2", X"5C91", X"5C6F", X"5C4E", X"5C2D",
        X"5C0C", X"5BEA", X"5BCA", X"5BA9", X"5B88", X"5B67", X"5B47", X"5B26",
        X"5B06", X"5AE5", X"5AC5", X"5AA5", X"5A85", X"5A65", X"5A45", X"5A25",
        X"5A06", X"59E6", X"59C6", X"59A7", X"5988", X"5968", X"5949", X"592A",
        X"590B", X"58EC", X"58CD", X"58AF", X"5890", X"5871", X"5853", X"5834",
        X"5816", X"57F8", X"57DA", X"57BB", X"579D", X"577F", X"5762", X"5744",
        X"5726", X"5708", X"56EB", X"56CD", X"56B0", X"5693", X"5676", X"5658",
        X"563B", X"561E", X"5601", X"55E4", X"55C8", X"55AB", X"558E", X"5572",
        X"5555", X"5539", X"551D", X"5500", X"54E4", X"54C8", X"54AC", X"5490",
        X"5474", X"5458", X"543D", X"5421", X"5405", X"53EA", X"53CE", X"53B3",
        X"5398", X"537C", X"5361", X"5346", X"532B", X"5310", X"52F5", X"52DA",
        X"52BF", X"52A5", X"528A", X"526F", X"5255", X"523A", X"5220", X"5206",
        X"51EC", X"51D1", X"51B7", X"519D", X"5183", X"5169", X"514F", X"5136",
        X"511C", X"5102", X"50E9", X"50CF", X"50B6", X"509C", X"5083", X"506A",
        X"5050", X"5037", X"501E", X"5005", X"4FEC", X"4FD3", X"4FBA", X"4FA1",
        X"4F89", X"4F70", X"4F57", X"4F3F", X"4F26", X"4F0E", X"4EF6", X"4EDD",
        X"4EC5", X"4EAD", X"4E95", X"4E7C", X"4E64", X"4E4C", X"4E35", X"4E1D",
        X"4E05", X"4DED", X"4DD5", X"4DBE", X"4DA6", X"4D8F", X"4D77", X"4D60",
        X"4D48", X"4D31", X"4D1A", X"4D03", X"4CEC", X"4CD4", X"4CBD", X"4CA6",
        X"4C90", X"4C79", X"4C62", X"4C4B", X"4C34", X"4C1E", X"4C07", X"4BF1",
        X"4BDA", X"4BC4", X"4BAD", X"4B97", X"4B81", X"4B6A", X"4B54", X"4B3E",
        X"4B28", X"4B12", X"4AFC", X"4AE6", X"4AD0", X"4ABA", X"4AA4", X"4A8F",
        X"4A79", X"4A63", X"4A4E", X"4A38", X"4A23", X"4A0D", X"49F8", X"49E3",
        X"49CD", X"49B8", X"49A3", X"498E", X"4979", X"4963", X"494E", X"4939",
        X"4925", X"4910", X"48FB", X"48E6", X"48D1", X"48BD", X"48A8", X"4893",
        X"487F", X"486A", X"4856", X"4841", X"482D", X"4819", X"4805", X"47F0",
        X"47DC", X"47C8", X"47B4", X"47A0", X"478C", X"4778", X"4764", X"4750",
        X"473C", X"4728", X"4715", X"4701", X"46ED", X"46DA", X"46C6", X"46B2",
        X"469F", X"468B", X"4678", X"4665", X"4651", X"463E", X"462B", X"4618",
        X"4604", X"45F1", X"45DE", X"45CB", X"45B8", X"45A5", X"4592", X"457F",
        X"456C", X"455A", X"4547", X"4534", X"4521", X"450F", X"44FC", X"44EA",
        X"44D7", X"44C5", X"44B2", X"44A0", X"448D", X"447B", X"4469", X"4456",
        X"4444", X"4432", X"4420", X"440E", X"43FC", X"43EA", X"43D8", X"43C6",
        X"43B4", X"43A2", X"4390", X"437E", X"436D", X"435B", X"4349", X"4337",
        X"4326", X"4314", X"4303", X"42F1", X"42E0", X"42CE", X"42BD", X"42AB",
        X"429A", X"4289", X"4277", X"4266", X"4255", X"4244", X"4233", X"4222",
        X"4211", X"41FF", X"41EE", X"41DE", X"41CD", X"41BC", X"41AB", X"419A",
        X"4189", X"4178", X"4168", X"4157", X"4146", X"4136", X"4125", X"4115",
        X"4104", X"40F4", X"40E3", X"40D3", X"40C2", X"40B2", X"40A2", X"4091",
        X"4081", X"4071", X"4061", X"4050", X"4040", X"4030", X"4020", X"4010"
    );

end package body trig_pkg;