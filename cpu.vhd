-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

signal pc_out: std_logic_vector(12 downto 0);
signal pc_inc: std_logic;
signal pc_dec: std_logic;

signal ptr_out: std_logic_vector(12 downto 0);
signal ptr_inc: std_logic;
signal ptr_dec: std_logic;

signal mx1_sel : std_logic;
signal mx2_sel : std_logic_vector(1 downto 0);

signal cnt_out: std_logic_vector(6 downto 0);
signal cnt_inc: std_logic;
signal cnt_dec: std_logic;
signal cnt_one: std_logic;

type fsm_state is (sidle, sfetch0, sfetch1, sdecode, splus, sminus, sright, sleft, sdot, sdot0, scomma, scomma0,
 scomma1, sbraLw, sbraL, sbraL0, sbraL1, sbraL2, sbraRw, sbraR, sbraR0, sbraR1, sbraR2, sbraR3, shalt, sbraLww);
  signal pstate : fsm_state;
  signal nstate : fsm_state;

begin

  pc: process(CLK, RESET)
  begin
    if RESET = '1' then
      pc_out <= (others => '0');
    elsif clk'event and clk = '1' then
      if pc_inc = '1' then
        pc_out <= pc_out + 1;
      elsif pc_dec = '1' then
        pc_out <= pc_out - 1;
      end if;
    end if;
  end process;

  ptr: process(CLK, RESET)
  begin
    if RESET = '1' then
      ptr_out <= "1000000000000";
    elsif clk'event and clk = '1' then
      if ptr_inc = '1' then
        if ptr_out = "1111111111111" then
          ptr_out <= "1000000000000";
        else
          ptr_out <= ptr_out + 1;
          end if;
      elsif ptr_dec = '1' then
        if ptr_out = "1000000000000" then
          ptr_out <= (others => '1');
        else
          ptr_out <= ptr_out - 1;
        end if;
      end if;
    end if;
  end process;

  cnt: process(CLK, RESET)
  begin
    if RESET = '1' then
      cnt_out <= (others => '0');
    elsif clk'event and clk = '1' then
      if cnt_inc = '1' then
        cnt_out <= cnt_out + 1;
      elsif cnt_dec = '1' then
        cnt_out <= cnt_out - 1;
      elsif cnt_one = '1' then
          cnt_out <= "0000001";
      end if;
    end if;
  end process;

  DATA_ADDR <= pc_out when (mx1_sel = '0')
                  else ptr_out;

  DATA_WDATA <= IN_DATA when (mx2_sel = "00") else
       (DATA_RDATA - 1) when (mx2_sel = "01") else
       (DATA_RDATA + 1) when (mx2_sel = "10") else
       (DATA_RDATA) when (mx2_sel = "11");


  --FSM present state
  fsm_pstate: process (RESET, CLK)
  begin
    if (RESET='1') then
      pstate <= sidle;
    elsif (CLK'event) and (CLK='1') then
      if (EN = '1') then
        pstate <= nstate;
      end if;
    end if;
  end process;

  nsl: process (pstate)

  variable c: std_logic_vector (7 downto 0); 

  begin
  -- INIT   
    IN_REQ <= '0';
    OUT_WE <= '0';
    DATA_EN <= '0';
    DATA_RDWR <= '0';
    cnt_inc <= '0';
    cnt_dec <= '0';
    cnt_one <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    pc_inc <= '0';
    pc_dec <= '0';
    
  case pstate is
  -- IDLE
  when sidle =>
    nstate <= sfetch0;

  -- -------------------------INSTRUCTION FETCH

  when sfetch0 =>
    nstate <= sfetch1;
    pc_inc <= '1';
    mx1_sel <= '0';
    DATA_EN <= '1';
  
  when sfetch1 =>
    nstate <= sdecode;

  -- -------------------------INSTRUCTION DECODE
  when sdecode =>
    case DATA_RDATA is
    -- >
    when X"3E" =>
     nstate <= sright;
      
    -- <
    when X"3C" =>
      nstate <= sleft;
      
    -- +
    when X"2B" =>
      nstate <= splus;
      DATA_EN <= '1';
      mx1_sel <= '1';
      
    -- -
    when X"2D" =>
      nstate <= sminus;
      DATA_EN <= '1';
      mx1_sel <= '1';

    -- .
    when X"2E" =>
     nstate <= sdot;
     DATA_EN <= '1';
     mx1_sel <= '1';

    -- ,
    when X"2C" =>
     nstate <= scomma;
     --IN_REQ <= '1';
     DATA_EN <= '1';
     mx1_sel <= '1';

    -- [
    when X"5B" =>
     nstate <= sbraLw;
     DATA_EN <= '1';
     mx1_sel <= '1';

    -- ]
    when X"5D" =>
     nstate <= sbraRw;
     pc_dec <= '1';
     DATA_EN <= '1';
     mx1_sel <= '1';

    -- (
    when X"28" =>
     nstate <= sfetch0;

    -- )
    when X"29" =>
     nstate <= sbraRw;
     pc_dec <= '1';
     DATA_EN <= '1';
     mx1_sel <= '1';

    when X"00" =>
     nstate <= shalt;

    when others =>
      nstate <= sfetch0;
      
    end case;
  
  -- -------------------------INSTRUCTIONs
  when splus =>
    nstate <= sfetch0;
    DATA_RDWR <= '1';
    DATA_EN <= '1';
    mx2_sel <= "10";

  when sminus =>
    nstate <= sfetch0;
    DATA_RDWR <= '1';
    DATA_EN <= '1';
    mx2_sel <= "01";

  when sright =>
    nstate <= sfetch0;
    ptr_inc <= '1';

  when sleft =>
    nstate <= sfetch0;
    ptr_dec <= '1';

  when sdot =>
    nstate <= sdot0;
    
  when sdot0 =>
    if OUT_BUSY = '0' then
      nstate <= sfetch0;
      OUT_DATA <= DATA_RDATA;   
      OUT_WE <= '1';
    else 
      nstate <= sdot;
    end if;

  when scomma =>
    nstate <= scomma0;
    IN_REQ <= '1';
  
  when scomma0 =>
    nstate <= scomma1;
    
  when scomma1 =>
    if IN_VLD = '0' then
      nstate <= scomma;
    else 
      nstate <= sfetch0;
      DATA_RDWR <= '1';
      DATA_EN <= '1';
      mx2_sel <= "00";
    end if;

  -- wait for DATA_RDATA
  when sbraLw =>
    nstate <= sbraL;

  when sbraL =>
    if DATA_RDATA = "0" then
      nstate <= sbraL0;
      cnt_one <= '1';   
    else 
      nstate <= sfetch0;
    end if;

  when sbraL0 =>
    if cnt_out = "0" then
      nstate <= sfetch0;
    else
      nstate <= sbraLww;
      mx1_sel <= '0';
      DATA_EN <= '1';
    end if;

  -- wait for DATA_RDATA
  when sbraLww =>
    nstate <= sbraL1;

  when sbraL1 =>
    c:= DATA_RDATA;
    nstate <= sbral2;

  when sbraL2 =>
    pc_inc <= '1';
    nstate <= sbraL0;
      case c is
        -- [
        when X"5B" =>
          cnt_inc <= '1';

        -- (
        when X"28" =>
          cnt_inc <= '1';

        -- ]
        when X"5D" =>
          cnt_dec <= '1';

        -- )
        when X"29" =>
          cnt_dec <= '1';

        when others =>
      
      end case;

  -- wait for DATA_RDATA
  when sbraRw =>
    nstate <= sbraR;

  when sbraR =>
    if DATA_RDATA = "0" then
      nstate <= sfetch0;
      pc_inc <= '1';    
    else 
      nstate <= sbraR0;
      cnt_one <= '1';
      pc_dec <= '1';
    end if;

  when sbraR0 =>
    if cnt_out = "0" then
      nstate <= sfetch0;
    else
      nstate <= sbraR1;
      mx1_sel <= '0';
      DATA_EN <= '1';
    end if;

  -- wait for DATA_RDATA
  when sbraR1 =>
    nstate <= sbraR2;

  when sbraR2 =>
    nstate <= sbraR3;
    c:= DATA_RDATA;
      case c is
        -- [
        when X"5B" =>
          cnt_dec <= '1';

        -- (
          when X"28" =>
          cnt_dec <= '1';

        -- ]
        when X"5D" =>
          cnt_inc <= '1';

        -- )
        when X"29" =>
          cnt_inc <= '1';

        when others =>
      
      end case;

    when sbraR3 =>
      nstate <= sbraR0;
      if cnt_out = "0" then
        pc_inc <= '1';
      else
        pc_dec <= '1';
      end if;

  when shalt =>
    nstate <= shalt;

  when others =>
    null;

  end case;

  end process;

end behavioral;

