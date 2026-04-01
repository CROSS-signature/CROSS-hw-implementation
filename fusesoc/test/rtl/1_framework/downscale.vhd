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
use ieee.std_logic_misc.all;


entity downscale is
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
end entity downscale;


architecture behavioral of downscale is

    -- Constant declarations
    constant MAX_CYCLES_C   : integer := INPUT_WIDTH_G / OUTPUT_WIDTH_G;

    -- Signal declarations
    signal m_axis_tvalid_s          : std_logic := '0';
    signal m_axis_tlast_s           : std_logic;

    signal cnt_s                    : integer range 0 to MAX_CYCLES_C - 1 := 0;

    signal current_slice            : std_logic_vector(OUTPUT_WIDTH_G/8 - 1 downto 0);
    signal next_slice               : std_logic_vector(OUTPUT_WIDTH_G/8 - 1 downto 0);

begin

    -- Assertions --
    assert (INPUT_WIDTH_G mod OUTPUT_WIDTH_G = 0)
        report "Currently only aligned widths supported: Input must be multiple of output"
        severity failure;


    -- Define current and next output slice in input data to correctly assert tlast
    current_slice   <=  s_axis_tkeep(OUTPUT_WIDTH_G/8*(cnt_s+1) - 1 downto OUTPUT_WIDTH_G/8*cnt_s);
    next_slice      <=  s_axis_tkeep(OUTPUT_WIDTH_G/8*(cnt_s+2) - 1 downto OUTPUT_WIDTH_G/8*(cnt_s+1)) when (cnt_s < MAX_CYCLES_C-1) else
                        (others => '1');


    ----------------------------------------------------------------
    -- Multiplexer switched with counter
    ----------------------------------------------------------------
    m_axis_tdata    <= s_axis_tdata(OUTPUT_WIDTH_G*(cnt_s+1) - 1 downto OUTPUT_WIDTH_G*cnt_s);
    m_axis_tkeep    <= s_axis_tkeep(OUTPUT_WIDTH_G/8*(cnt_s+1) - 1 downto OUTPUT_WIDTH_G/8*cnt_s);
    m_axis_tvalid   <= m_axis_tvalid_s;
    m_axis_tvalid_s <= s_axis_tvalid;
    m_axis_tlast    <= m_axis_tlast_s;
    m_axis_tlast_s  <= s_axis_tlast when (cnt_s >= MAX_CYCLES_C - 1) or and_reduce(current_slice) = '0'or or_reduce(next_slice) = '0'
                                    else '0';

    s_axis_tready   <= m_axis_tready when (cnt_s >= MAX_CYCLES_C - 1) or (m_axis_tvalid_s = '1' and m_axis_tlast_s = '1') else '0';


    ----------------------------------------------------------------
    -- Counter to switch multiplexer
    ----------------------------------------------------------------
    p_cnt : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
               cnt_s <= 0;
            else
                if (m_axis_tvalid_s = '1' and m_axis_tready = '1') then
                    if (cnt_s >= MAX_CYCLES_C - 1 or m_axis_tlast_s = '1') then
                        cnt_s <= 0;
                    else
                        cnt_s <= cnt_s + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_cnt;

end architecture behavioral;
