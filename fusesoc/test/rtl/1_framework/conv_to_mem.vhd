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
use work.framework_pkg.log2_ceil;


entity conv_to_mem is
    generic(
        CONVERTER_IN_WIDTH_G    : integer;
        CONVERTER_OUT_WIDTH_G   : integer;
        MEMORY_DEPTH_G          : integer
    );
    port(
        axis_aclk           : in    std_logic;
        axis_rst            : in    std_logic;

        s_axis_tdata        : in    std_logic_vector(CONVERTER_IN_WIDTH_G - 1 downto 0);
        s_axis_tkeep        : in    std_logic_vector(CONVERTER_IN_WIDTH_G/8 - 1 downto 0);
        s_axis_tvalid       : in    std_logic;
        s_axis_tready       : out   std_logic;
        s_axis_tlast        : in    std_logic;

        -- Interface to DUT
        -- STREAM
        m_axis_tdata        : out   std_logic_vector(CONVERTER_OUT_WIDTH_G - 1 downto 0);
        m_axis_tkeep        : out   std_logic_vector(CONVERTER_OUT_WIDTH_G/8 - 1 downto 0);
        m_axis_tvalid       : out   std_logic;
        m_axis_tready       : in    std_logic;
        m_axis_tlast        : out   std_logic
    );
end entity conv_to_mem;


architecture structural of conv_to_mem is

    -- Signals from width converter to memory
    signal m_axis_tdata_s       : std_logic_vector(CONVERTER_OUT_WIDTH_G - 1 downto 0);
    signal m_axis_tkeep_s       : std_logic_vector(CONVERTER_OUT_WIDTH_G/8 - 1 downto 0);
    signal m_axis_tvalid_s      : std_logic := '0';
    signal m_axis_tready_s      : std_logic := '0';
    signal m_axis_tlast_s       : std_logic;

    component fifo_ram_wrapper
        generic ( DW : natural; DEPTH : natural; REG_OUT : natural );
        port (
            clk                : in std_logic;
            rst_n              : in std_logic;

            s_axis_tdata       : in std_logic_vector(DW-1 downto 0);
            s_axis_tkeep       : in std_logic_vector(DW/8-1 downto 0);
            s_axis_tvalid      : in std_logic;
            s_axis_tready      : out std_logic;
            s_axis_tlast       : in std_logic;

            m_axis_tdata       : out std_logic_vector(DW-1 downto 0);
            m_axis_tkeep       : out std_logic_vector(DW/8-1 downto 0);
            m_axis_tvalid      : out std_logic;
            m_axis_tready      : in std_logic;
            m_axis_tlast       : out std_logic
        );
    end component fifo_ram_wrapper;

begin


    ------------------------------------------------------
    -- Width Converter
    ------------------------------------------------------
    i_width_conv : entity work.width_converter
    generic map(
        INPUT_WIDTH_G   => CONVERTER_IN_WIDTH_G,
        OUTPUT_WIDTH_G  => CONVERTER_OUT_WIDTH_G
    )
    port map(
        axis_aclk       => axis_aclk,
        axis_rst        => axis_rst,
        s_axis_tdata    => s_axis_tdata,
        s_axis_tkeep    => s_axis_tkeep,
        s_axis_tvalid   => s_axis_tvalid,
        s_axis_tready   => s_axis_tready,
        s_axis_tlast    => s_axis_tlast,
        m_axis_tdata    => m_axis_tdata_s,
        m_axis_tkeep    => m_axis_tkeep_s,
        m_axis_tvalid   => m_axis_tvalid_s,
        m_axis_tready   => m_axis_tready_s,
        m_axis_tlast    => m_axis_tlast_s
    );


    ------------------------------------------------------
    -- FIFO
    ------------------------------------------------------
    i_fifo : fifo_ram_wrapper
    generic map(
        DW      => CONVERTER_OUT_WIDTH_G,
        DEPTH   => MEMORY_DEPTH_G,
        REG_OUT => 1
    )
    port map(
        clk             => axis_aclk,
        rst_n           => not axis_rst,
        s_axis_tdata    => m_axis_tdata_s,
        s_axis_tkeep    => m_axis_tkeep_s,
        s_axis_tvalid   => m_axis_tvalid_s,
        s_axis_tready   => m_axis_tready_s,
        s_axis_tlast    => m_axis_tlast_s,
        m_axis_tdata    => m_axis_tdata,
        m_axis_tkeep    => m_axis_tkeep,
        m_axis_tvalid   => m_axis_tvalid,
        m_axis_tready   => m_axis_tready,
        m_axis_tlast    => m_axis_tlast
    );


end architecture structural;
