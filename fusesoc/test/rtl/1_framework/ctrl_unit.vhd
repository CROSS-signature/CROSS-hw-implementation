-- Copyright 2026, Technical University of Munich
-- Copyright 2026, Politecnico di Milano.
-- SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
--
-- Licensed under the Solderpad Hardware License v 2.1 (the "License");
-- you may not use this file except in compliance with the License, or,
-- at your option, the Apache License version 2.0. You may obtain a
-- copy of the License at
--
-- https://solderpad.org/licenses/SHL-2.1/
--
-- Unless required by applicable law or agreed to in writing, any work
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- ----------
--
-- CROSS - Codes and Restricted Objects Signature Scheme
--
-- @version 1.0 (April 2026)
--
-- @author     Patrick Karl <patrick.karl@tum.de>
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.framework_pkg;


entity ctrl_unit is
    generic(
        SECRET_EN_G             : boolean;
        CTRL_WIDTH_G            : integer;
        DATA_WIDTH_G            : integer
    );
    port(
        axis_aclk               : in    std_logic;
        axis_rst                : in    std_logic;

        ctrl_vec                : out   std_logic_vector(CTRL_WIDTH_G - 1 downto 0);
        ctrl_vec_clear          : in   std_logic_vector(CTRL_WIDTH_G - 1 downto 0);

        s_axis_tdata            : in    std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        s_axis_tvalid           : in    std_logic;
        s_axis_tready           : out   std_logic;

        m_axis_prng_tdata       : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        m_axis_prng_tkeep       : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_prng_tvalid      : out   std_logic;
        m_axis_prng_tready      : in    std_logic;
        m_axis_prng_tlast       : out   std_logic;

        m_axis_secret_tdata     : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        m_axis_secret_tkeep     : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_secret_tvalid    : out   std_logic;
        m_axis_secret_tready    : in    std_logic;
        m_axis_secret_tlast     : out   std_logic;

        m_axis_public_tdata     : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        m_axis_public_tkeep     : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_public_tvalid    : out   std_logic;
        m_axis_public_tready    : in    std_logic;
        m_axis_public_tlast     : out   std_logic
    );
end entity ctrl_unit;


architecture behavioral of ctrl_unit is

    -- Constant declarations
    alias LEN_SIZE_C                : integer is framework_pkg.LEN_SIZE_BITS_C;
    constant CNT_LEN_C              : integer := LEN_SIZE_C - framework_pkg.log2_ceil(DATA_WIDTH_G/8);
    constant LEN_CYCLES_C           : integer := framework_pkg.iif(LEN_SIZE_C > DATA_WIDTH_G, LEN_SIZE_C/8 - DATA_WIDTH_G/8, 0);

    -- Signal declarations
    type state_t is (IDLE, GET_LEN, PRNG, SECRET, PUBLIC, CTRL);
    signal state_s                  : state_t := IDLE;
    signal n_state_s                : state_t;

    signal s_axis_tready_s          : std_logic := '0';

    signal m_axis_prng_tvalid_s     : std_logic := '0';
    signal m_axis_prng_tlast_s      : std_logic;

    signal m_axis_secret_tvalid_s   : std_logic := '0';
    signal m_axis_secret_tlast_s    : std_logic;

    signal m_axis_public_tvalid_s   : std_logic := '0';
    signal m_axis_public_tlast_s    : std_logic;

    signal n_type_s, type_s         : std_logic_vector(7 downto 0);

    signal cnt_s                    : unsigned(CNT_LEN_C - 1 downto 0);
    signal len_s                    : std_logic_vector(LEN_SIZE_C - 1 downto 0);

begin

    -- Assertions --
    assert CTRL_WIDTH_G >= 0
        report "Negative CTRL_WIDTH_G not allowed!"
        severity failure;

    assert (DATA_WIDTH_G mod 8 = 0)
        report "DATA_WIDTH_G must be multiple of 8!"
        severity failure;

    assert (CTRL_WIDTH_G = 0 or CTRL_WIDTH_G = 8)
        report "CTRL_WIDTH_G must be 0 or 8, rest not supported at the moment!"
        severity failure;

    s_axis_tready           <= s_axis_tready_s;

    m_axis_prng_tdata       <= s_axis_tdata;
    m_axis_prng_tvalid      <= m_axis_prng_tvalid_s;
    m_axis_prng_tlast       <= m_axis_prng_tlast_s;

    m_axis_secret_tdata     <= s_axis_tdata;
    m_axis_secret_tvalid    <= m_axis_secret_tvalid_s;
    m_axis_secret_tlast     <= m_axis_secret_tlast_s;

    m_axis_public_tdata     <= s_axis_tdata;
    m_axis_public_tvalid    <= m_axis_public_tvalid_s;
    m_axis_public_tlast     <= m_axis_public_tlast_s;


    -----------------------------------------------------------------
    -- FSM
    -----------------------------------------------------------------
    --! Register
    p_reg : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                state_s <= IDLE;
            else
                state_s <= n_state_s;
                type_s  <= n_type_s;
            end if;
        end if;
    end process p_reg;


    -- Next state logic
    p_next_state : process(all)
    begin
        -- Default preventing latch
        n_state_s <= state_s;

        case state_s is
            -- If data arrives, latch type and get the length next or directly go
            -- to control state.
            when IDLE =>
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                    if (s_axis_tdata(7 downto 0) = framework_pkg.CTRL_TYPE_C) then
                        n_state_s <= CTRL;
                    else
                        n_state_s <= GET_LEN;
                    end if;
                end if;

            -- Get the 32-bit length and traverse to state indicated by type_s
            when GET_LEN =>
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1' and cnt_s >= LEN_CYCLES_C) then
                    if (type_s = framework_pkg.PRNG_TYPE_C) then
                        n_state_s <= PRNG;
                    end if;
                    if (type_s = framework_pkg.SECRET_TYPE_C and SECRET_EN_G) then
                        n_state_s <= SECRET;
                    end if;
                    if (type_s = framework_pkg.PUBLIC_TYPE_C) then
                        n_state_s <= PUBLIC;
                    end if;
                end if;

            when PRNG =>
                if (m_axis_prng_tvalid_s = '1' and m_axis_prng_tready = '1' and m_axis_prng_tlast_s = '1') then
                    n_state_s <= IDLE;
                end if;

            when SECRET =>
                if (m_axis_secret_tvalid_s = '1' and m_axis_secret_tready = '1' and m_axis_secret_tlast_s = '1') then
                    n_state_s <= IDLE;
                end if;

            when PUBLIC =>
                if (m_axis_public_tvalid_s = '1' and m_axis_public_tready = '1' and m_axis_public_tlast_s = '1') then
                    n_state_s <= IDLE;
                end if;

            when CTRL =>
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                    n_state_s <= IDLE;
                end if;

            when others =>
                n_state_s <= IDLE;

        end case;
    end process p_next_state;


    -- Output logic
    p_output : process(all)
    begin
        -- Defaults preventing latches
        s_axis_tready_s         <= '0';

        m_axis_prng_tkeep       <= (0 => '1', others => '0');
        m_axis_prng_tvalid_s    <= '0';
        m_axis_prng_tlast_s     <= '0';

        m_axis_secret_tkeep     <= (0 => '1', others => '0');
        m_axis_secret_tvalid_s  <= '0';
        m_axis_secret_tlast_s   <= '0';

        m_axis_public_tkeep     <= (0 => '1', others => '0');
        m_axis_public_tvalid_s  <= '0';
        m_axis_public_tlast_s   <= '0';

        n_type_s                <= type_s;

        case state_s is
            when IDLE =>
                n_type_s        <= s_axis_tdata(7 downto 0);
                s_axis_tready_s <= '1';

            when GET_LEN =>
                s_axis_tready_s <= '1';

            -- Connect input to prng output, assert corresponding tkeeps and set tlast
            when PRNG =>
                s_axis_tready_s         <= m_axis_prng_tready;
                m_axis_prng_tvalid_s    <= s_axis_tvalid;
                for i in 0 to (DATA_WIDTH_G/8 - 1) loop
                    if (cnt_s*DATA_WIDTH_G/8 + i > unsigned(len_s) - 1) then
                        m_axis_prng_tkeep(i) <= '0';
                    else
                        m_axis_prng_tkeep(i) <= '1';
                    end if;
                end loop;
                if (cnt_s >= (unsigned(len_s) + DATA_WIDTH_G/8 - 1)/(DATA_WIDTH_G/8) - 1) then
                    m_axis_prng_tlast_s <= '1';
                end if;

            -- Connect input to secret output, assert corresponding tkeeps and set tlast
            when SECRET =>
                s_axis_tready_s         <= m_axis_secret_tready;
                m_axis_secret_tvalid_s  <= s_axis_tvalid;
                for i in 0 to (DATA_WIDTH_G/8 - 1) loop
                    if (cnt_s*DATA_WIDTH_G/8 + i > unsigned(len_s) - 1) then
                        m_axis_secret_tkeep(i) <= '0';
                    else
                        m_axis_secret_tkeep(i) <= '1';
                    end if;
                end loop;
                if (cnt_s >= (unsigned(len_s) + DATA_WIDTH_G/8 - 1)/(DATA_WIDTH_G/8) - 1) then
                    m_axis_secret_tlast_s <= '1';
                end if;

            -- Connect input to public output, assert corresponding tkeeps and set tlast
            when PUBLIC =>
                s_axis_tready_s         <= m_axis_public_tready;
                m_axis_public_tvalid_s  <= s_axis_tvalid;
                for i in 0 to (DATA_WIDTH_G/8 - 1) loop
                    if (cnt_s*DATA_WIDTH_G/8 + i > unsigned(len_s) - 1) then
                        m_axis_public_tkeep(i) <= '0';
                    else
                        m_axis_public_tkeep(i) <= '1';
                    end if;
                end loop;
                if (cnt_s >= (unsigned(len_s) + DATA_WIDTH_G/8 - 1)/(DATA_WIDTH_G/8) - 1) then
                    m_axis_public_tlast_s <= '1';
                end if;

            when CTRL =>
                s_axis_tready_s <= '1';

            when others =>
                null;

        end case;
    end process p_output;


    -----------------------------------------------------------------
    -- Counter Logic + Length/ctrl registering
    -----------------------------------------------------------------
    p_cnt : process(axis_aclk)
        variable cnt_v : unsigned(CNT_LEN_C - 1 downto 0);
    begin
        if rising_edge(axis_aclk) then
            case state_s is

                -- Get the length and store it in len_s
                when GET_LEN =>
                    cnt_v := cnt_s;
                    if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                        for i in 0 to (DATA_WIDTH_G/8 - 1) loop
                            if (cnt_v < LEN_SIZE_C/8) then
                                len_s(8*(to_integer(cnt_v)+1) - 1 downto 8*to_integer(cnt_v)) <= s_axis_tdata(8*(i+1) - 1 downto 8*i);
                                cnt_v := cnt_v + 1;
                            end if;
                        end loop;
                        if (cnt_s >= LEN_CYCLES_C) then
                            cnt_v := (others => '0');
                        end if;
                    end if;
                    cnt_s <= cnt_v;

                -- Count the cycles required to receive len_s bytes
                when PRNG | SECRET | PUBLIC =>
                    if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                        if (cnt_s >= (unsigned(len_s) + DATA_WIDTH_G/8 - 1) / (DATA_WIDTH_G/8) - 1) then
                            cnt_s <= (others => '0');
                        else
                            cnt_s <= cnt_s + 1;
                        end if;
                    end if;

                when others =>
                    cnt_s <= (others => '0');

            end case;
        end if;
    end process p_cnt;

GEN_CTRL : if (CTRL_WIDTH_G > 0) generate
    p_ctrl : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                ctrl_vec <= (others => '0');
            else
                case state_s is
                    when CTRL =>
                        if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                            ctrl_vec <= s_axis_tdata(7 downto 0);
                        end if;

                    when others =>
                        for i in 0 to (CTRL_WIDTH_G - 1) loop
                            if (ctrl_vec_clear(i) = '1') then
                                ctrl_vec(i) <= '0';
                            end if;
                        end loop;

                end case;
            end if;
        end if;
    end process p_ctrl;

end generate GEN_CTRL;


end architecture behavioral;
