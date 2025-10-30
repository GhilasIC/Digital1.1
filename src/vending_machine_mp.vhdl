library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vending_machine_mp is
  port (
    clk           : in  std_logic;
    reset         : in  std_logic;                    -- sync, active-high
    coin          : in  std_logic;                    -- +1 credit per pulse
    btn           : in  std_logic_vector(3 downto 0); -- 0000 wait, 0001 cancel, 0010 refund, 0011..1111 products

    dispense_product : out std_logic;                 -- 1-cycle vend strobe
    product_num      : out std_logic_vector(3 downto 0); -- holds 1..13; aligned with dispense_product
    change           : out std_logic                  -- 1-cycle pulse per coin returned (with 1-cycle gaps)
  );
end entity;

architecture rtl of vending_machine_mp is
  -- Command encodings
  constant CMD_WAIT   : std_logic_vector(3 downto 0) := "0000";
  constant CMD_CANCEL : std_logic_vector(3 downto 0) := "0001";
  constant CMD_REFUND : std_logic_vector(3 downto 0) := "0010";

  -- FSM with spaced change pulses
  type state_t is (
    st_select,
    st_vend,
    st_mc_pulse, st_mc_gap,
    st_refund_pulse, st_refund_gap
  );
  signal state, next_state : state_t := st_select;

  -- Datapath
  signal credit, next_credit       : unsigned(2 downto 0) := (others => '0');  -- 0..7
  signal sel_idx, next_sel_idx     : unsigned(3 downto 0) := (others => '0');  -- 0..12 used
  signal sel_valid, next_sel_valid : std_logic := '0';

  -- Input sampling for edge detect (init to 0 to avoid U)
  signal coin_q : std_logic := '0';
  signal btn_q  : std_logic_vector(3 downto 0) := (others => '0');

  -- Derived pulses
  signal coin_pulse : std_logic;
  signal btn_press  : std_logic;  -- 0000 -> nonzero edge

  -- Latched product number (persists until next coin or button)
  signal product_num_r : std_logic_vector(3 downto 0) := (others => '0');

  -- Price for current selection
  function price_of(idx : unsigned(3 downto 0)) return unsigned is
    variable i : integer := to_integer(idx);
  begin
    if i <= 3 then        -- 0..3
      return to_unsigned(1, 3);
    elsif i <= 7 then     -- 4..7
      return to_unsigned(2, 3);
    else                  -- 8..12
      return to_unsigned(3, 3);
    end if;
  end function;

  -- Helpers for product codes
  function is_product_code(b : std_logic_vector(3 downto 0)) return boolean is
  begin
    return unsigned(b) >= to_unsigned(3, 4);  -- "0011".."1111"
  end function;

  function product_idx(b : std_logic_vector(3 downto 0)) return unsigned is
  begin
    return unsigned(b) - to_unsigned(3, 4);   -- "0011"->0 ... "1111"->12
  end function;

begin
  ----------------------------------------------------------------------------
  -- 1) Input sampling (sync reset) + simple edge detect
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        coin_q <= '0';
        btn_q  <= (others => '0');
      else
        coin_q <= coin;
        btn_q  <= btn;
      end if;
    end if;
  end process;

  coin_pulse <= coin and not coin_q;
  btn_press  <= '1' when (btn /= CMD_WAIT and btn_q = CMD_WAIT) else '0';

  ----------------------------------------------------------------------------
  -- 2) State/data registers (sync reset) + product_num latch/clear (aligned)
  ----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state         <= st_select;
        credit        <= (others => '0');
        sel_idx       <= (others => '0');
        sel_valid     <= '0';
        product_num_r <= (others => '0');                   -- CLEAR on reset
      else
        -- state/data regs
        state     <= next_state;
        credit    <= next_credit;
        sel_idx   <= next_sel_idx;
        sel_valid <= next_sel_valid;

        -- Load product number on ENTRY to st_vend so it aligns with dispense_product
        if next_state = st_vend then
          product_num_r <= std_logic_vector(unsigned(sel_idx) + to_unsigned(1,4)); -- 1..13
        -- Clear when a new interaction starts (next coin or next button press)
        elsif (coin_pulse = '1') or (btn_press = '1') then
          product_num_r <= (others => '0');
        else
          product_num_r <= product_num_r;                   -- HOLD
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- 3) Next-state / datapath (combinational)
  ----------------------------------------------------------------------------
  process(state, credit, sel_idx, sel_valid, coin_pulse, btn_press, btn)
    variable price_v : unsigned(2 downto 0);
  begin
    -- Defaults (hold)
    next_state     <= state;
    next_credit    <= credit;
    next_sel_idx   <= sel_idx;
    next_sel_valid <= sel_valid;

    -- Coin accumulation (cap at 7)
    if coin_pulse = '1' then
      if credit < to_unsigned(7,3) then
        next_credit <= credit + 1;
      end if;
    end if;

    -- Command on 0000 -> nonzero
    if btn_press = '1' then
      if    btn = CMD_CANCEL then
        next_sel_valid <= '0';                 -- clear selection, keep credit
      elsif btn = CMD_REFUND then
        if credit > 0 then
          next_state <= st_refund_pulse;       -- start refunding with a pulse
        else
          next_state <= st_select;
        end if;
      elsif is_product_code(btn) then
        if product_idx(btn) <= to_unsigned(12,4) then
          next_sel_idx   <= product_idx(btn);  -- 0..12
          next_sel_valid <= '1';
        end if;
      end if;
    end if;

    price_v := price_of(sel_idx);

    case state is
      when st_select =>
        if sel_valid = '1' and (credit >= price_v) then
          next_state <= st_vend;
        end if;

      when st_vend =>
        -- subtract price, clear selection, decide about change path
        next_credit    <= credit - price_v;
        next_sel_valid <= '0';
        if (credit - price_v) > 0 then
          next_state <= st_mc_pulse;           -- start change with a pulse
        else
          next_state <= st_select;
        end if;

      -- ==== Change (leftover) with gaps ====
      when st_mc_pulse =>
        if credit > 0 then
          next_credit <= credit - 1;           -- one coin returned now
        end if;
        if (credit > 1) then
          next_state <= st_mc_gap;             -- gap before next pulse
        else
          next_state <= st_select;
        end if;

      when st_mc_gap =>
        if credit > 0 then
          next_state <= st_mc_pulse;
        else
          next_state <= st_select;
        end if;

      -- ==== Refund with gaps ====
      when st_refund_pulse =>
        if credit > 0 then
          next_credit <= credit - 1;
        end if;
        if (credit > 1) then
          next_state <= st_refund_gap;
        else
          next_state <= st_select;
        end if;

      when st_refund_gap =>
        if credit > 0 then
          next_state <= st_refund_pulse;
        else
          next_state <= st_select;
        end if;
    end case;
  end process;

  ----------------------------------------------------------------------------
  -- 4) Moore outputs
  ----------------------------------------------------------------------------
  dispense_product <= '1' when state = st_vend else '0';
  product_num      <= product_num_r;  -- persists until next coin or button event
  change           <= '1' when (state = st_mc_pulse or state = st_refund_pulse)
                     else '0';

end architecture;
fsm.txt
Affichage de fsm.txt en cours...
