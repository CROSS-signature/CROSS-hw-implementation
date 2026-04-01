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

entity tdp_bram is
    generic(
        DATA_WIDTH_G  : integer;
        ADDR_WIDTH_G  : integer
    );
    port(
        -- Port a
        clk_a           : in    std_logic;
        port_en_a       : in    std_logic;
        addr_a          : in    std_logic_vector(ADDR_WIDTH_G - 1 downto 0);
        wr_en_a         : in    std_logic;
        wr_data_a       : in    std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        wr_data_par_a   : in    std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        rd_data_a       : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        rd_data_par_a   : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);

        -- Port b
        clk_b           : in  std_logic;
        port_en_b       : in  std_logic;
        addr_b          : in  std_logic_vector(ADDR_WIDTH_G - 1 downto 0);
        wr_en_b         : in  std_logic;
        wr_data_b       : in  std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        wr_data_par_b   : in  std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        rd_data_b       : out std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        rd_data_par_b   : out std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0)
    );
end entity tdp_bram;

architecture behavioral of tdp_bram is


    -- Depth of the memory in number of words addressable by both ports
    constant MEM_DEPTH_C : integer := 2**ADDR_WIDTH_G;

    -- Type and signal declaration for memory instance
    type ram_t is array (0 to MEM_DEPTH_C - 1) of std_logic_vector(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto 0);
    shared variable ram_s : ram_t;

    -- Integer representations of port addresses
    signal addr_a_s : integer;
    signal addr_b_s : integer;

    signal din_a_s  : std_logic_vector(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto 0);
    signal do_a_s  : std_logic_vector(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto 0);

    signal din_b_s  : std_logic_vector(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto 0);
    signal do_b_s  : std_logic_vector(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto 0);
begin


    -- Casting addresses to integer
    addr_a_s <= to_integer(unsigned(addr_a));
    addr_b_s <= to_integer(unsigned(addr_b));


    -- Concatenate data and parity
    din_a_s         <= wr_data_par_a & wr_data_a;
    rd_data_a       <= do_a_s(DATA_WIDTH_G - 1 downto 0);
    rd_data_par_a   <= do_a_s(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto DATA_WIDTH_G);

    -- Port a in write first mode
    p_port_a : process(clk_a)
    begin
        if rising_edge(clk_a) then
            if (port_en_a = '1') then
                if (wr_en_a = '1') then
                    ram_s(addr_a_s) := din_a_s;
                    do_a_s          <= din_a_s;
                else
                    do_a_s          <= ram_s(addr_a_s);
                end if;
            end if;
        end if;
    end process p_port_a;


    -- Concatenate data and parity
    din_b_s         <= wr_data_par_b & wr_data_b;
    rd_data_b       <= do_b_s(DATA_WIDTH_G - 1 downto 0);
    rd_data_par_b   <= do_b_s(DATA_WIDTH_G + DATA_WIDTH_G/8 - 1 downto DATA_WIDTH_G);

    -- Port b in write first mode
    p_port_b : process(clk_b)
    begin
        if rising_edge(clk_b) then
            if (port_en_b = '1') then
                if (wr_en_b = '1') then
                    ram_s(addr_b_s) := din_b_s;
                    do_b_s          <= din_b_s;
                else
                    do_b_s          <= ram_s(addr_b_s);
                end if;
            end if;
        end if;
    end process p_port_b;


end architecture behavioral;
