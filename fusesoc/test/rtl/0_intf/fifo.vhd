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
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity fifo is
    generic(
        WIDTH_G         : integer;
        DEPTH_G         : integer
    );
    port(
        axis_aclk       : in    std_logic;
        axis_rst        : in    std_logic;

        -- Input Port
        s_axis_tdata    : in    std_logic_vector(WIDTH_G - 1 downto 0);
        s_axis_tkeep    : in    std_logic_vector(WIDTH_G/8 - 1 downto 0);
        s_axis_tvalid   : in    std_logic;
        s_axis_tready   : out   std_logic;
        s_axis_tlast    : in    std_logic;

        -- Output Port
        m_axis_tdata    : out   std_logic_vector(WIDTH_G - 1 downto 0);
        m_axis_tkeep    : out   std_logic_vector(WIDTH_G/8 - 1 downto 0);
        m_axis_tvalid   : out   std_logic;
        m_axis_tready   : in    std_logic;
        m_axis_tlast    : out   std_logic
    );
end entity fifo;

architecture behavioral of fifo is

    -- Memory type and signal definition
    type mem_t is array (0 to DEPTH_G - 1) of std_logic_vector(WIDTH_G+WIDTH_G/8 - 1 downto 0);
    signal mem_s            : mem_t;

    -- Internal handshake signals
    signal s_axis_tready_s  : std_logic := '0';
    signal m_axis_tvalid_s  : std_logic := '0';

    -- Internal flags
    signal empty_s          : std_logic;
    signal full_s           : std_logic;
    signal wr_ptr_s         : integer range 0 to DEPTH_G - 1;
    signal rd_ptr_s         : integer range 0 to DEPTH_G - 1;

    signal entries_s        : integer range 0 to DEPTH_G;

begin

    -- Output data
    m_axis_tdata    <= mem_s(rd_ptr_s)(WIDTH_G-1 downto 0);
    m_axis_tkeep    <= mem_s(rd_ptr_s)(WIDTH_G+WIDTH_G/8 - 2 downto WIDTH_G) & '1';
    m_axis_tvalid   <= m_axis_tvalid_s;
    m_axis_tlast    <= mem_s(rd_ptr_s)(WIDTH_G+WIDTH_G/8-1);
    s_axis_tready   <= s_axis_tready_s;

    -- Set flags
    full_s          <= '1' when (entries_s >= DEPTH_G)  else '0';
    empty_s         <= '1' when (entries_s <= 0)        else '0';
    s_axis_tready_s <= not full_s;
    m_axis_tvalid_s <= not empty_s;


    -- Counting the numbers of entries, setting rd-/wr-pointers and
    -- writing the data into the memory.
    p_ptr : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                wr_ptr_s    <= 0;
                rd_ptr_s    <= 0;
                entries_s   <= 0;
            else

                -- Increase entry counter if data is written but not read
                -- Decrease entry counter if data is read but not written
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1'
                and (m_axis_tvalid_s = '0' or m_axis_tready = '0')) then
                    entries_s <= entries_s + 1;
                elsif ((s_axis_tvalid = '0' or s_axis_tready_s = '0')
                and m_axis_tvalid_s = '1' and m_axis_tready = '1') then
                    entries_s <= entries_s - 1;
                end if;

                -- Write into memory and increase write pointer
                if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                    mem_s(wr_ptr_s) <= s_axis_tlast & s_axis_tkeep(WIDTH_G/8-1 downto 1) & s_axis_tdata;
                    if (wr_ptr_s >= DEPTH_G - 1) then
                        wr_ptr_s <= 0;
                    else
                        wr_ptr_s <= wr_ptr_s + 1;
                    end if;
                end if;

                -- Increase read pointer if data is read
                if (m_axis_tvalid_s = '1' and m_axis_tready = '1') then
                    if (rd_ptr_s >= DEPTH_G - 1) then
                        rd_ptr_s <= 0;
                    else
                        rd_ptr_s <= rd_ptr_s + 1;
                    end if;
                end if;

            end if;
        end if;
    end process p_ptr;

end architecture behavioral;
