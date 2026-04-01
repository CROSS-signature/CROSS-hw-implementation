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
use work.framework_pkg.all;


entity framework_subsystem is
    generic(
        INTF_DATA_WIDTH_G           : integer;
        SECRET_EN_G                 : boolean;
        RND_DATA_WIDTH_G            : integer;
        RND_MEMORY_DEPTH_G          : integer;
        SECRET_DATA_WIDTH_G         : integer;
        SECRET_MEMORY_DEPTH_G       : integer;
        PUBLIC_DATA_WIDTH_G         : integer;
        PUBLIC_MEMORY_DEPTH_0_G     : integer;
        PUBLIC_MEMORY_DEPTH_1_G     : integer;
        CTRL_DATA_WIDTH_G           : integer
    );
    port(
        axis_aclk               : in    std_logic;
        axis_rst                : in    std_logic;

        -- Ports to Interface
        s_axis_intf_tdata       : in    std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
        s_axis_intf_tvalid      : in    std_logic;
        s_axis_intf_tready      : out   std_logic;

        m_axis_intf_tdata       : out   std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
        m_axis_intf_tkeep       : out   std_logic_vector(INTF_DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_intf_tvalid      : out   std_logic;
        m_axis_intf_tready      : in    std_logic;
        m_axis_intf_tlast       : out   std_logic;

        -- Ports to DUT
        -- CTRL
        ctrl_vec                : out   std_logic_vector(CTRL_DATA_WIDTH_G - 1 downto 0);
        ctrl_vec_clear          : in    std_logic_vector(CTRL_DATA_WIDTH_G - 1 downto 0);

        -- PRNG
        m_axis_prng_tdata       : out   std_logic_vector(RND_DATA_WIDTH_G - 1 downto 0);
        m_axis_prng_tkeep       : out   std_logic_vector(RND_DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_prng_tvalid      : out   std_logic;
        m_axis_prng_tready      : in    std_logic;
        m_axis_prng_tlast       : out   std_logic;

        -- SECRET
        m_axis_secret_tdata     : out   std_logic_vector(SECRET_DATA_WIDTH_G - 1 downto 0);
        m_axis_secret_tkeep     : out   std_logic_vector(SECRET_DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_secret_tvalid    : out   std_logic;
        m_axis_secret_tready    : in    std_logic;
        m_axis_secret_tlast     : out   std_logic;

        -- PUBLIC 0
        m_axis_public_tdata_0   : out   std_logic_vector(PUBLIC_DATA_WIDTH_G - 1 downto 0);
        m_axis_public_tkeep_0   : out   std_logic_vector(PUBLIC_DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_public_tvalid_0  : out   std_logic;
        m_axis_public_tready_0  : in    std_logic;
        m_axis_public_tlast_0   : out   std_logic;

        -- PUBLIC 1
        s_axis_public_tdata_1   : in   std_logic_vector(PUBLIC_DATA_WIDTH_G - 1 downto 0);
        s_axis_public_tkeep_1   : in   std_logic_vector(PUBLIC_DATA_WIDTH_G/8 - 1 downto 0);
        s_axis_public_tvalid_1  : in   std_logic;
        s_axis_public_tready_1  : out  std_logic;
        s_axis_public_tlast_1   : in   std_logic
    );
end entity framework_subsystem;


architecture structural of framework_subsystem is

    -- Signals from ctrl_unit to prng wrapper
    signal m_axis_ctrl_prng_tdata_s     : std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
    signal m_axis_ctrl_prng_tkeep_s     : std_logic_vector(INTF_DATA_WIDTH_G/8 - 1 downto 0);
    signal m_axis_ctrl_prng_tvalid_s    : std_logic := '0';
    signal m_axis_ctrl_prng_tready_s    : std_logic := '0';
    signal m_axis_ctrl_prng_tlast_s     : std_logic;

    -- Signals from ctrl_unit to secret memory
    signal m_axis_ctrl_secret_tdata_s   : std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
    signal m_axis_ctrl_secret_tkeep_s   : std_logic_vector(INTF_DATA_WIDTH_G/8 - 1 downto 0);
    signal m_axis_ctrl_secret_tvalid_s  : std_logic := '0';
    signal m_axis_ctrl_secret_tready_s  : std_logic := '0';
    signal m_axis_ctrl_secret_tlast_s   : std_logic;

    -- Signals from ctrl_unit to public
    signal m_axis_ctrl_public_tdata_s   : std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
    signal m_axis_ctrl_public_tkeep_s   : std_logic_vector(INTF_DATA_WIDTH_G/8 - 1 downto 0);
    signal m_axis_ctrl_public_tvalid_s  : std_logic := '0';
    signal m_axis_ctrl_public_tready_s  : std_logic := '0';
    signal m_axis_ctrl_public_tlast_s   : std_logic;

    signal m_axis_prng_tvalid_s         : std_logic := '0';
    signal m_axis_secret_tvalid_s       : std_logic := '0';
    signal m_axis_public_tvalid_0_s     : std_logic := '0';
    signal m_axis_prng_tready_s         : std_logic := '0';
    signal m_axis_secret_tready_s       : std_logic := '0';
    signal m_axis_public_tready_0_s     : std_logic := '0';

    signal m_axis_intf_tvalid_s         : std_logic := '0';

begin

    m_axis_intf_tvalid          <= m_axis_intf_tvalid_s;

    m_axis_prng_tvalid          <= m_axis_prng_tvalid_s;
    m_axis_secret_tvalid        <= m_axis_secret_tvalid_s;
    m_axis_public_tvalid_0      <= m_axis_public_tvalid_0_s;

    m_axis_prng_tready_s        <= m_axis_prng_tready;
    m_axis_secret_tready_s      <= m_axis_secret_tready;
    m_axis_public_tready_0_s    <= m_axis_public_tready_0;

    ----------------------------------------------------
    -- Control Unit
    ----------------------------------------------------
    i_ctrl_unit : entity work.ctrl_unit
    generic map(
        SECRET_EN_G             => SECRET_EN_G,
        CTRL_WIDTH_G            => CTRL_DATA_WIDTH_G,
        DATA_WIDTH_G            => INTF_DATA_WIDTH_G
    )
    port map(
        axis_aclk               => axis_aclk,
        axis_rst                => axis_rst,

        ctrl_vec                => ctrl_vec,
        ctrl_vec_clear          => ctrl_vec_clear,

        s_axis_tdata            => s_axis_intf_tdata,
        s_axis_tvalid           => s_axis_intf_tvalid,
        s_axis_tready           => s_axis_intf_tready,

        m_axis_prng_tdata       => m_axis_ctrl_prng_tdata_s,
        m_axis_prng_tkeep       => m_axis_ctrl_prng_tkeep_s,
        m_axis_prng_tvalid      => m_axis_ctrl_prng_tvalid_s,
        m_axis_prng_tready      => m_axis_ctrl_prng_tready_s,
        m_axis_prng_tlast       => m_axis_ctrl_prng_tlast_s,

        m_axis_secret_tdata     => m_axis_ctrl_secret_tdata_s,
        m_axis_secret_tkeep     => m_axis_ctrl_secret_tkeep_s,
        m_axis_secret_tvalid    => m_axis_ctrl_secret_tvalid_s,
        m_axis_secret_tready    => m_axis_ctrl_secret_tready_s,
        m_axis_secret_tlast     => m_axis_ctrl_secret_tlast_s,

        m_axis_public_tdata     => m_axis_ctrl_public_tdata_s,
        m_axis_public_tkeep     => m_axis_ctrl_public_tkeep_s,
        m_axis_public_tvalid    => m_axis_ctrl_public_tvalid_s,
        m_axis_public_tready    => m_axis_ctrl_public_tready_s,
        m_axis_public_tlast     => m_axis_ctrl_public_tlast_s
    );


    ----------------------------------------------------
    -- PRNG Wrapper
    ----------------------------------------------------
    i_rnd_memory : entity work.conv_to_mem
    generic map(
        CONVERTER_IN_WIDTH_G    => INTF_DATA_WIDTH_G,
        CONVERTER_OUT_WIDTH_G   => RND_DATA_WIDTH_G,
        MEMORY_DEPTH_G          => RND_MEMORY_DEPTH_G
    )
    port map(
        axis_aclk           => axis_aclk,
        axis_rst            => axis_rst,

        s_axis_tdata        => m_axis_ctrl_prng_tdata_s,
        s_axis_tkeep        => m_axis_ctrl_prng_tkeep_s,
        s_axis_tvalid       => m_axis_ctrl_prng_tvalid_s,
        s_axis_tready       => m_axis_ctrl_prng_tready_s,
        s_axis_tlast        => m_axis_ctrl_prng_tlast_s,

        m_axis_tdata        => m_axis_prng_tdata,
        m_axis_tkeep        => m_axis_prng_tkeep,
        m_axis_tvalid       => m_axis_prng_tvalid_s,
        m_axis_tready       => m_axis_prng_tready_s,
        m_axis_tlast        => m_axis_prng_tlast
    );

    ----------------------------------------------------
    -- Secret Memory
    ----------------------------------------------------
    gen_secret_memory : if SECRET_EN_C generate
        i_secret_memory : entity work.conv_to_mem
        generic map(
            CONVERTER_IN_WIDTH_G    => INTF_DATA_WIDTH_G,
            CONVERTER_OUT_WIDTH_G   => SECRET_DATA_WIDTH_G,
            MEMORY_DEPTH_G          => SECRET_MEMORY_DEPTH_G
        )
        port map(
            axis_aclk           => axis_aclk,
            axis_rst            => axis_rst,

            s_axis_tdata        => m_axis_ctrl_secret_tdata_s,
            s_axis_tkeep        => m_axis_ctrl_secret_tkeep_s,
            s_axis_tvalid       => m_axis_ctrl_secret_tvalid_s,
            s_axis_tready       => m_axis_ctrl_secret_tready_s,
            s_axis_tlast        => m_axis_ctrl_secret_tlast_s,

            m_axis_tdata        => m_axis_secret_tdata,
            m_axis_tkeep        => m_axis_secret_tkeep,
            m_axis_tvalid       => m_axis_secret_tvalid_s,
            m_axis_tready       => m_axis_secret_tready_s,
            m_axis_tlast        => m_axis_secret_tlast
        );
    end generate gen_secret_memory;


    ----------------------------------------------------
    -- Public Memory to DUT
    ----------------------------------------------------
    i_public_memory_0 : entity work.conv_to_mem
    generic map(
        CONVERTER_IN_WIDTH_G    => INTF_DATA_WIDTH_G,
        CONVERTER_OUT_WIDTH_G   => PUBLIC_DATA_WIDTH_G,
        MEMORY_DEPTH_G          => PUBLIC_MEMORY_DEPTH_0_G
    )
    port map(
        axis_aclk           => axis_aclk,
        axis_rst            => axis_rst,

        s_axis_tdata        => m_axis_ctrl_public_tdata_s,
        s_axis_tkeep        => m_axis_ctrl_public_tkeep_s,
        s_axis_tvalid       => m_axis_ctrl_public_tvalid_s,
        s_axis_tready       => m_axis_ctrl_public_tready_s,
        s_axis_tlast        => m_axis_ctrl_public_tlast_s,

        m_axis_tdata        => m_axis_public_tdata_0,
        m_axis_tkeep        => m_axis_public_tkeep_0,
        m_axis_tvalid       => m_axis_public_tvalid_0_s,
        m_axis_tready       => m_axis_public_tready_0_s,
        m_axis_tlast        => m_axis_public_tlast_0
    );


    ----------------------------------------------------
    -- Public Memory from DUT
    ----------------------------------------------------
    i_public_memory_1 : entity work.mem_to_conv
    generic map(
        CONVERTER_IN_WIDTH_G    => PUBLIC_DATA_WIDTH_G,
        CONVERTER_OUT_WIDTH_G   => INTF_DATA_WIDTH_G,
        MEMORY_DEPTH_G          => PUBLIC_MEMORY_DEPTH_1_G
    )
    port map(
        axis_aclk           => axis_aclk,
        axis_rst            => axis_rst,

        m_axis_tdata        => m_axis_intf_tdata,
        m_axis_tkeep        => m_axis_intf_tkeep,
        m_axis_tvalid       => m_axis_intf_tvalid_s,
        m_axis_tready       => m_axis_intf_tready,
        m_axis_tlast        => m_axis_intf_tlast,

        s_axis_tdata        => s_axis_public_tdata_1,
        s_axis_tkeep        => s_axis_public_tkeep_1,
        s_axis_tvalid       => s_axis_public_tvalid_1,
        s_axis_tready       => s_axis_public_tready_1,
        s_axis_tlast        => s_axis_public_tlast_1
    );

end architecture structural;
