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


entity width_converter is
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
end entity width_converter;


architecture structural of width_converter is

begin


    ----------------------------------------------------
    -- BYPASS
    ----------------------------------------------------
    gen_bypass : if (INPUT_WIDTH_G = OUTPUT_WIDTH_G) generate

        m_axis_tdata    <= s_axis_tdata;
        m_axis_tkeep    <= s_axis_tkeep;
        m_axis_tvalid   <= s_axis_tvalid;
        s_axis_tready   <= m_axis_tready;
        m_axis_tlast    <= s_axis_tlast;

    end generate gen_bypass;


    ----------------------------------------------------
    -- UPSCALING
    ----------------------------------------------------
    gen_conv_up : if (OUTPUT_WIDTH_G > INPUT_WIDTH_G) generate

        i_upscale : entity work.upscale
        generic map(
            INPUT_WIDTH_G   => INPUT_WIDTH_G,
            OUTPUT_WIDTH_G  => OUTPUT_WIDTH_G
        )
        port map(
            axis_aclk       => axis_aclk,
            axis_rst        => axis_rst,

            s_axis_tdata    => s_axis_tdata,
            s_axis_tkeep    => s_axis_tkeep,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,

            m_axis_tdata    => m_axis_tdata,
            m_axis_tkeep    => m_axis_tkeep,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast
        );

    end generate gen_conv_up;


    ----------------------------------------------------
    -- DOWNSCALING
    ----------------------------------------------------
    gen_conv_down : if (INPUT_WIDTH_G > OUTPUT_WIDTH_G) generate

        i_downscale : entity work.downscale
        generic map(
            INPUT_WIDTH_G   => INPUT_WIDTH_G,
            OUTPUT_WIDTH_G  => OUTPUT_WIDTH_G
        )
        port map(
            axis_aclk       => axis_aclk,
            axis_rst        => axis_rst,

            s_axis_tdata    => s_axis_tdata,
            s_axis_tkeep    => s_axis_tkeep,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,

            m_axis_tdata    => m_axis_tdata,
            m_axis_tkeep    => m_axis_tkeep,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast
        );

    end generate gen_conv_down;

end architecture structural;
