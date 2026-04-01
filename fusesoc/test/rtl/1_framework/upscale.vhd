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


entity upscale is
    generic(
        INPUT_WIDTH_G   : integer;
        OUTPUT_WIDTH_G  : integer
    );
    port(
        axis_aclk       : in    std_logic;
        axis_rst        : in    std_logic;

        s_axis_tdata    : in    std_logic_vector(INPUT_WIDTH_G - 1 downto 0);
        s_axis_tkeep    : in    std_logic_vector(INPUT_WIDTH_G/8 - 1 downto 0);
        s_axis_tvalid   : in    std_logic;
        s_axis_tready   : out   std_logic;
        s_axis_tlast    : in    std_logic;

        m_axis_tdata    : out   std_logic_vector(OUTPUT_WIDTH_G - 1 downto 0);
        m_axis_tkeep    : out   std_logic_vector(OUTPUT_WIDTH_G/8 - 1 downto 0);
        m_axis_tvalid   : out   std_logic;
        m_axis_tready   : in    std_logic;
        m_axis_tlast    : out   std_logic
    );
end entity upscale;


architecture behavioral of upscale is

    -- Constant declarations
    constant MAX_CYCLES_C   : integer := OUTPUT_WIDTH_G / INPUT_WIDTH_G;

    -- Signal declarations
    signal s_axis_tready_s  : std_logic := '0';

    signal cnt_s            : integer range 0 to MAX_CYCLES_C - 1 := 0;
    signal data_build_reg_s : std_logic_vector(OUTPUT_WIDTH_G - INPUT_WIDTH_G - 1 downto 0);
    signal keep_build_reg_s : std_logic_vector((OUTPUT_WIDTH_G - INPUT_WIDTH_G)/8 - 1 downto 0);

begin

    -- Assertions --
    assert (OUTPUT_WIDTH_G mod INPUT_WIDTH_G = 0)
        report "Currently only aligned widths supported: Output must be multiple of input"
        severity failure;

    s_axis_tready   <= s_axis_tready_s;


    ----------------------------------------------------------------
    -- Multiplexer switched with counter
    ----------------------------------------------------------------
    m_axis_tvalid   <= s_axis_tvalid when (cnt_s >= MAX_CYCLES_C - 1) or (s_axis_tlast = '1') else '0';
    s_axis_tready_s <= m_axis_tready when (cnt_s >= MAX_CYCLES_C - 1) or (s_axis_tlast = '1') else '1';
    m_axis_tlast    <= s_axis_tlast;

    -- Filling data: current slice with input, previous slices with buildreg, rest is don't care
    p_mux_data : process(all)
    begin
        m_axis_tdata                                                                <= (others => '-');
        m_axis_tdata(INPUT_WIDTH_G*cnt_s - 1 downto 0)                              <= data_build_reg_s(INPUT_WIDTH_G*cnt_s - 1 downto 0);
        m_axis_tdata(INPUT_WIDTH_G*(cnt_s+1) - 1 downto INPUT_WIDTH_G*cnt_s)        <= s_axis_tdata;
    end process p_mux_data;

    -- Same for keep, except that no don't cares but zeros must be used for unfilled slices
    p_mux_keep : process(all)
    begin
        m_axis_tkeep                                                                <= (0 => '1', others => '0');
        m_axis_tkeep(INPUT_WIDTH_G/8*cnt_s - 1 downto 0)                            <= keep_build_reg_s(INPUT_WIDTH_G/8*cnt_s - 1 downto 0);
        m_axis_tkeep(INPUT_WIDTH_G/8*(cnt_s+1) - 1 downto INPUT_WIDTH_G/8*cnt_s)    <= s_axis_tkeep;
    end process p_mux_keep;


    ----------------------------------------------------------------
    -- Buildreg
    ----------------------------------------------------------------
    p_buildreg : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                keep_build_reg_s <= (others => '0');
            else
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                    if (cnt_s < MAX_CYCLES_C - 1) then
                        data_build_reg_s(INPUT_WIDTH_G*(cnt_s + 1) - 1 downto INPUT_WIDTH_G*cnt_s)      <= s_axis_tdata;
                        keep_build_reg_s(INPUT_WIDTH_G/8*(cnt_s + 1) - 1 downto INPUT_WIDTH_G/8*cnt_s)  <= s_axis_tkeep;
                    else
                        keep_build_reg_s <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
    end process p_buildreg;

    ----------------------------------------------------------------
    -- Counter to switch multiplexer
    ----------------------------------------------------------------
    p_cnt : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                cnt_s <= 0;
            else
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                    if (cnt_s >= MAX_CYCLES_C - 1 or s_axis_tlast = '1') then
                        cnt_s <= 0;
                    else
                        cnt_s <= cnt_s + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_cnt;

end architecture behavioral;
