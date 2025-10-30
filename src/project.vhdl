library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tt_um_VHDL_FSM is
    port (
        ui_in   : in  std_logic_vector(7 downto 0);
        uo_out  : out std_logic_vector(7 downto 0);
        uio_in  : in  std_logic_vector(7 downto 0);
        uio_out : out std_logic_vector(7 downto 0);
        uio_oe  : out std_logic_vector(7 downto 0);
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end tt_um_VHDL_FSM;

architecture rtl of tt_um_VHDL_FSM is
    -- Internal wiring
    component vending_machine_mp is
        Port (
    clk           : in  std_logic;
    reset         : in  std_logic;                    -- sync, active-high
    coin          : in  std_logic;                    -- +1 credit per pulse
    btn           : in  std_logic_vector(3 downto 0); -- 0000 wait, 0001 cancel, 0010 refund, 0011..1111 products

    dispense_product : out std_logic;                 -- 1-cycle vend strobe
    product_num      : out std_logic_vector(3 downto 0); -- holds 1..13; aligned with dispense_product
    change           : out std_logic                  -- 1-cycle pulse per coin returned (with 1-cycle gaps)
        );
    end component;

    signal reset_s        : std_logic;
    signal coin_s         : std_logic;
    signal btn_s          : std_logic_vector(3 downto 0);

    signal dispense_s     : std_logic;
    signal product_num_s  : std_logic_vector(3 downto 0);
    signal change_s       : std_logic;
begin
    -- Active-high sync reset for FSM; also hold in reset when tile not enabled
    reset_s <= (not rst_n) or (not ena);

    -- Map fixed inputs
    coin_s <= ui_in(0);
    btn_s  <= ui_in(4 downto 1);

    -- Instantiate the vending machine FSM (direct entity instantiation)
    u_fsm : entity work.vending_machine_mp(rtl)
        port map (
            clk              => clk,
            reset            => reset_s,
            coin             => coin_s,
            btn              => btn_s,
            dispense_product => dispense_s,
            product_num      => product_num_s,
            change           => change_s
        );

    -- Pack outputs (drive zeros when not enabled)
    uo_out(0)             <= dispense_s when ena = '1' else '0';
    uo_out(4 downto 1)    <= product_num_s when ena = '1' else (others => '0');
    uo_out(5)             <= change_s when ena = '1' else '0';
    uo_out(7 downto 6)    <= (others => '0');

    -- Unused bidir pads: drive low and disable output enables
    uio_out               <= (others => '0');
    uio_oe                <= (others => '0');
end rtl;
