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
use ieee.std_logic_misc.and_reduce;

entity prng_wrapper is
    generic (
        INPUT_WIDTH_G       : integer;
        SEED_WIDTH_G        : integer;
        NUM_PRNG_G          : integer;
        KEYSTREAM_WIDTH_G   : integer
    );
    port (
        axis_aclk           : in    std_logic;
        axis_rst            : in    std_logic;

        s_axis_tdata        : in    std_logic_vector(INPUT_WIDTH_G - 1 downto 0);
        s_axis_tkeep        : in    std_logic_vector(INPUT_WIDTH_G/8 - 1 downto 0);
        s_axis_tvalid       : in    std_logic;
        s_axis_tready       : out   std_logic;
        s_axis_tlast        : in    std_logic;

        -- Signal width is PRNG_KEYSTREAM_WIDTH_C x NUM_PRNG_C
        -- Every PRNG is assigned with one such PRNG_DATA_WIDTH_C wide slice
        m_axis_rnd_tdata    : out   std_logic_vector(NUM_PRNG_G*KEYSTREAM_WIDTH_G - 1 downto 0);
        m_axis_rnd_tvalid   : out   std_logic;
        m_axis_rnd_tready   : in    std_logic
    );
end entity prng_wrapper;

architecture structural of prng_wrapper is

    -- Signals from memory to memory controller
    signal m_axis_conv_tdata_s  : std_logic_vector(SEED_WIDTH_G - 1 downto 0);
    signal m_axis_conv_tvalid_s : std_logic := '0';
    signal m_axis_conv_tready_s : std_logic := '0';

    signal s_axis_seed_tvalid_s : std_logic_vector(NUM_PRNG_G - 1 downto 0) := (others => '0');
    signal s_axis_seed_tready_s : std_logic_vector(NUM_PRNG_G - 1 downto 0) := (others => '0');

    signal m_axis_rnd_tvalid_s  : std_logic_vector(NUM_PRNG_G - 1 downto 0) := (others => '0');
    signal m_axis_rnd_tready_s  : std_logic_vector(NUM_PRNG_G - 1 downto 0) := (others => '0');

    signal seed_cnt_s           : integer range 0 to NUM_PRNG_G - 1 := 0;

begin

    ------------------------------------------------------
    -- Width Converter
    ------------------------------------------------------
    i_prng_wc : entity work.width_converter
    generic map(
        INPUT_WIDTH_G   => INPUT_WIDTH_G,
        OUTPUT_WIDTH_G  => SEED_WIDTH_G
    )
    port map(
        axis_aclk       => axis_aclk,
        axis_rst        => axis_rst,

        s_axis_tdata    => s_axis_tdata,
        s_axis_tkeep    => s_axis_tkeep,
        s_axis_tvalid   => s_axis_tvalid,
        s_axis_tready   => s_axis_tready,
        s_axis_tlast    => s_axis_tlast,

        m_axis_tdata    => m_axis_conv_tdata_s,
        m_axis_tkeep    => open,
        m_axis_tvalid   => m_axis_conv_tvalid_s,
        m_axis_tready   => m_axis_conv_tready_s,
        m_axis_tlast    => open
    );


    ------------------------------------------------------
    -- PRNG Instances
    ------------------------------------------------------
    gen_prngs : for I in 0 to NUM_PRNG_G - 1 generate
        i_prng : entity work.prng
        generic map(
            SEED_WIDTH_G    => SEED_WIDTH_G,
            RND_WIDTH_G     => KEYSTREAM_WIDTH_G
        )
        port map(
            axis_aclk           => axis_aclk,
            axis_rst            => axis_rst,
            s_axis_seed_tdata   => m_axis_conv_tdata_s,
            s_axis_seed_tvalid  => s_axis_seed_tvalid_s(I),
            s_axis_seed_tready  => s_axis_seed_tready_s(I),
            m_axis_rnd_tdata    => m_axis_rnd_tdata(KEYSTREAM_WIDTH_G*(I+1) - 1 downto KEYSTREAM_WIDTH_G*I),
            m_axis_rnd_tvalid   => m_axis_rnd_tvalid_s(I),
            m_axis_rnd_tready   => m_axis_rnd_tready_s(I)
        );

        -- Every prng is acknowledged by single ready signal, all prngs must be valid to be sync
        m_axis_rnd_tready_s(I)  <= m_axis_rnd_tready and and_reduce(m_axis_rnd_tvalid_s);

        -- Current prng is seeded
        s_axis_seed_tvalid_s(I) <= m_axis_conv_tvalid_s when (seed_cnt_s = I) else '0';
    end generate gen_prngs;

    -- Output is valid if all prngs are initialized
    m_axis_rnd_tvalid <= and_reduce(m_axis_rnd_tvalid_s);

    -- Width converter is acknowledged by current prng
    m_axis_conv_tready_s <= s_axis_seed_tready_s(seed_cnt_s);


    ------------------------------------------------------
    -- SEED Counter
    ------------------------------------------------------
    p_seed_cnt : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                seed_cnt_s <= 0;
            else
                if (m_axis_conv_tvalid_s = '1' and m_axis_conv_tready_s = '1') then
                    if (seed_cnt_s >= NUM_PRNG_G - 1) then
                        seed_cnt_s <= 0;
                    else
                        seed_cnt_s <= seed_cnt_s + 1;
                    end if;
                end if;
            end if;
        end if;
    end process p_seed_cnt;

end architecture structural;
