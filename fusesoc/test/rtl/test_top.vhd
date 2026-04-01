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
use ieee.std_logic_misc.or_reduce;
use work.framework_pkg;

library unisim;
use unisim.vcomponents.all;

entity test_top is
    port(
        -- Uncomment chosen interface

        -- UART
        uart_txd            : out   std_logic;
        uart_rxd            : in    std_logic;

        -- General Ports
        global_clk          : in    std_logic;
        global_rst          : in    std_logic
    );
end entity test_top;


architecture structural of test_top is

    -- Clock wizard component
    component clk_wiz_0
        port (
            clk_in1     : in std_logic;
            clk_out1    : out std_logic;
            locked      : out std_logic
        );
    end component clk_wiz_0;

    -- Signal declarations
    signal sys_rst_s                    : std_logic;
    signal ctrl_vec_s                   : std_logic_vector(framework_pkg.CTRL_VEC_DATA_WIDTH_C - 1 downto 0) := (others => '0');
    signal ctrl_vec_clear_s             : std_logic_vector(framework_pkg.CTRL_VEC_DATA_WIDTH_C - 1 downto 0) := (others => '0');
    signal cross_op_ready_s             : std_logic;

    -- Signals from interface to framework
    signal m_axis_intf_tdata_s          : std_logic_vector(framework_pkg.INTF_DATA_WIDTH_C - 1 downto 0);
    signal m_axis_intf_tvalid_s         : std_logic := '0';
    signal m_axis_intf_tready_s         : std_logic := '0';

    -- Signals from framework to dut
    signal s_axis_intf_tdata_s          : std_logic_vector(framework_pkg.INTF_DATA_WIDTH_C - 1 downto 0);
    signal s_axis_intf_tvalid_s         : std_logic := '0';
    signal s_axis_intf_tready_s         : std_logic := '0';

    -- PRNG framework data to dut
    signal m_axis_prng_dut_tdata_s      : std_logic_vector(framework_pkg.RND_DATA_WIDTH_C - 1 downto 0);
    signal m_axis_prng_dut_tkeep_s      : std_logic_vector(framework_pkg.RND_DATA_WIDTH_C/8 - 1 downto 0);
    signal m_axis_prng_dut_tvalid_s     : std_logic := '0';
    signal m_axis_prng_dut_tready_s     : std_logic := '0';
    signal m_axis_prng_dut_tlast_s      : std_logic := '0';

    -- Secret framework data to dut
    signal m_axis_secret_dut_tdata_s    : std_logic_vector(framework_pkg.SECRET_DATA_WIDTH_C - 1 downto 0);
    signal m_axis_secret_dut_tkeep_s    : std_logic_vector(framework_pkg.SECRET_DATA_WIDTH_C/8 - 1 downto 0);
    signal m_axis_secret_dut_tvalid_s   : std_logic := '0';
    signal m_axis_secret_dut_tready_s   : std_logic := '0';
    signal m_axis_secret_dut_tlast_s    : std_logic := '0';

    -- Public framework data to dut
    signal m_axis_public_dut_tdata_s    : std_logic_vector(framework_pkg.PUBLIC_DATA_WIDTH_C - 1 downto 0);
    signal m_axis_public_dut_tkeep_s    : std_logic_vector(framework_pkg.PUBLIC_DATA_WIDTH_C/8 - 1 downto 0);
    signal m_axis_public_dut_tvalid_s   : std_logic := '0';
    signal m_axis_public_dut_tready_s   : std_logic := '0';
    signal m_axis_public_dut_tlast_s    : std_logic := '0';

    -- Output data from DUT
    signal m_axis_dut_tdata_s           : std_logic_vector(framework_pkg.PUBLIC_DATA_WIDTH_C - 1 downto 0);
    signal m_axis_dut_tkeep_s           : std_logic_vector(framework_pkg.PUBLIC_DATA_WIDTH_C/8 - 1 downto 0);
    signal m_axis_dut_tvalid_s          : std_logic := '0';
    signal m_axis_dut_tready_s          : std_logic := '0';
    signal m_axis_dut_tlast_s           : std_logic := '0';

    -- External interface signals
    signal uart_txd_s                   : std_logic := '1';
    signal uart_rxd_s                   : std_logic;
    signal uart_parity_error_s          : std_logic;
    signal uart_frame_error_s           : std_logic;

    component tb_top
        generic ( DATA_WIDTH : natural; TEST_EN : std_logic );
        port (
            clk                         : in std_logic;
            rst_n                       : in std_logic;

            cross_op                    : in std_logic_vector(1 downto 0);
            cross_op_valid              : in std_logic;
            cross_op_ready              : out std_logic;
            cross_op_done               : out std_logic;
            cross_op_done_val           : out std_logic;

            s_axis_rng_tdata            : in std_logic_vector(DATA_WIDTH-1 downto 0);
            s_axis_rng_tkeep            : in std_logic_vector(DATA_WIDTH/8-1 downto 0);
            s_axis_rng_tvalid           : in std_logic;
            s_axis_rng_tready           : out std_logic;
            s_axis_rng_tlast            : in std_logic;

            s_axis_msg_keys_tdata       : in std_logic_vector(DATA_WIDTH-1 downto 0);
            s_axis_msg_keys_tkeep       : in std_logic_vector(DATA_WIDTH/8-1 downto 0);
            s_axis_msg_keys_tvalid      : in std_logic;
            s_axis_msg_keys_tready      : out std_logic;
            s_axis_msg_keys_tlast       : in std_logic;

            s_axis_sig_tdata            : in std_logic_vector(DATA_WIDTH-1 downto 0);
            s_axis_sig_tkeep            : in std_logic_vector(DATA_WIDTH/8-1 downto 0);
            s_axis_sig_tvalid           : in std_logic;
            s_axis_sig_tready           : out std_logic;
            s_axis_sig_tlast            : in std_logic;

            m_axis_sig_keys_tdata       : out std_logic_vector(DATA_WIDTH-1 downto 0);
            m_axis_sig_keys_tkeep       : out std_logic_vector(DATA_WIDTH/8-1 downto 0);
            m_axis_sig_keys_tvalid      : out std_logic;
            m_axis_sig_keys_tready      : in std_logic;
            m_axis_sig_keys_tlast       : out std_logic
        );
    end component tb_top;

    signal sys_clk      : std_logic;
    signal clk_locked   : std_logic;
    signal init_cnt_s   : integer range 0 to 10 := 0;

begin


    -------------------------------------------------------------------------------
    -- Clock wizard
    -------------------------------------------------------------------------------
    i_clk_wiz : clk_wiz_0
    port map(
        clk_in1     => global_clk,
        clk_out1    => sys_clk,
        locked      => clk_locked
    );
    -------------------------------------------------------------------------------
    -- EXTERNAL CONNECTIONS
    -------------------------------------------------------------------------------
    uart_txd    <= uart_txd_s;
    uart_rxd_s  <= uart_rxd;


    -------------------------------------------------------------------------------
    -- RESET
    -------------------------------------------------------------------------------
    -- Register reset for fanout reasons
    p_rst : process(sys_clk)
    begin
        if rising_edge(sys_clk) then
            if (init_cnt_s < 10) then
                sys_rst_s <= '1';
            else
                sys_rst_s <= (global_rst xor framework_pkg.RST_ACTIVE_LOW) or not clk_locked;
            end if;
        end if;
    end process p_rst;

    p_init_rst : process(sys_clk)
    begin
        if rising_edge(sys_clk) then
            if (global_rst = '0') then
                init_cnt_s <= 0;
            else
                if (init_cnt_s < 10) then
                    init_cnt_s <= init_cnt_s + 1;
                end if;
            end if;
        end if;
    end process p_init_rst;


    -------------------------------------------------------------------------------
    -- INTERFACE WRAPPER
    -------------------------------------------------------------------------------
    i_intf_wrapper : entity work.intf_wrapper
    generic map(
        GLOBAL_CLK_PERIODE_NS_G         => framework_pkg.GLOBAL_CLK_PERIODE_NS_C,
        GLOBAL_CLK_FREQUENCY_MHZ_G      => framework_pkg.GLOBAL_CLK_FREQUENCY_MHZ_C,
        INTF_DATA_WIDTH_G               => framework_pkg.INTF_DATA_WIDTH_C,
        RX_FIFO_EN_G                    => framework_pkg.INTF_RX_FIFO_EN_C,
        RX_FIFO_DEPTH_G                 => framework_pkg.INTF_RX_FIFO_DEPTH_C,
        TX_FIFO_EN_G                    => framework_pkg.INTF_TX_FIFO_EN_C,
        TX_FIFO_DEPTH_G                 => framework_pkg.INTF_TX_FIFO_DEPTH_C,

        USE_UART_G                      => framework_pkg.USE_UART_C,

        UART_BAUD_RATE_G                => framework_pkg.UART_BAUD_RATE_C,
        UART_EN_PARITY_G                => framework_pkg.UART_EN_PARITY_C,
        UART_EVEN_PARITY_G              => framework_pkg.UART_EVEN_PARITY_C,
        UART_N_PAYLOAD_BITS_G           => framework_pkg.UART_N_PAYLOAD_BITS_C,
        UART_N_STOP_BITS_G              => framework_pkg.UART_N_STOP_BITS_C
    )
    port map(
        -- EXTERNAL SIDE
        -- uart
        uart_txd                    => uart_txd_s,
        uart_rxd                    => uart_rxd_s,
        uart_parity_error           => uart_parity_error_s,
        uart_frame_error            => uart_frame_error_s,

        -- USER SIDE
        axis_aclk                   => sys_clk,
        axis_rst                    => sys_rst_s,

        m_axis_tdata                => m_axis_intf_tdata_s,
        m_axis_tvalid               => m_axis_intf_tvalid_s,
        m_axis_tready               => m_axis_intf_tready_s,

        s_axis_tdata                => s_axis_intf_tdata_s,
        s_axis_tvalid               => s_axis_intf_tvalid_s,
        s_axis_tready               => s_axis_intf_tready_s
    );


    -------------------------------------------------------------------------------
    -- FRAMEWORK SUBSYSTEM
    -------------------------------------------------------------------------------
    i_framework : entity work.framework_subsystem
    generic map(
        INTF_DATA_WIDTH_G           => framework_pkg.INTF_DATA_WIDTH_C,
        RND_DATA_WIDTH_G            => framework_pkg.RND_DATA_WIDTH_C,
        RND_MEMORY_DEPTH_G          => framework_pkg.RND_MEMORY_DEPTH_C,
        SECRET_EN_G                 => framework_pkg.SECRET_EN_C,
        SECRET_DATA_WIDTH_G         => framework_pkg.SECRET_DATA_WIDTH_C,
        SECRET_MEMORY_DEPTH_G       => framework_pkg.SECRET_MEMORY_DEPTH_C,
        PUBLIC_DATA_WIDTH_G         => framework_pkg.PUBLIC_DATA_WIDTH_C,
        PUBLIC_MEMORY_DEPTH_0_G     => framework_pkg.PUBLIC_MEMORY_DEPTH_0_C,
        PUBLIC_MEMORY_DEPTH_1_G     => framework_pkg.PUBLIC_MEMORY_DEPTH_1_C,
        CTRL_DATA_WIDTH_G           => framework_pkg.CTRL_VEC_DATA_WIDTH_C
    )
    port map(
        axis_aclk               => sys_clk,
        axis_rst                => sys_rst_s,

        -- Ports to Interface
        s_axis_intf_tdata       => m_axis_intf_tdata_s,
        s_axis_intf_tvalid      => m_axis_intf_tvalid_s,
        s_axis_intf_tready      => m_axis_intf_tready_s,

        m_axis_intf_tdata       => s_axis_intf_tdata_s,
        m_axis_intf_tkeep       => open,
        m_axis_intf_tvalid      => s_axis_intf_tvalid_s,
        m_axis_intf_tready      => s_axis_intf_tready_s,
        m_axis_intf_tlast       => open,

        -- Ports to DUT
        -- CTRL
        ctrl_vec                => ctrl_vec_s,
        ctrl_vec_clear          => ctrl_vec_clear_s,

        -- PRNG
        m_axis_prng_tdata       => m_axis_prng_dut_tdata_s,
        m_axis_prng_tkeep       => m_axis_prng_dut_tkeep_s,
        m_axis_prng_tvalid      => m_axis_prng_dut_tvalid_s,
        m_axis_prng_tready      => m_axis_prng_dut_tready_s,
        m_axis_prng_tlast       => m_axis_prng_dut_tlast_s,

        -- SECRET
        m_axis_secret_tdata     => m_axis_secret_dut_tdata_s,
        m_axis_secret_tkeep     => m_axis_secret_dut_tkeep_s,
        m_axis_secret_tvalid    => m_axis_secret_dut_tvalid_s,
        m_axis_secret_tready    => m_axis_secret_dut_tready_s,
        m_axis_secret_tlast     => m_axis_secret_dut_tlast_s,

        -- PUBLIC 0
        m_axis_public_tdata_0   => m_axis_public_dut_tdata_s,
        m_axis_public_tkeep_0   => m_axis_public_dut_tkeep_s,
        m_axis_public_tvalid_0  => m_axis_public_dut_tvalid_s,
        m_axis_public_tready_0  => m_axis_public_dut_tready_s,
        m_axis_public_tlast_0   => m_axis_public_dut_tlast_s,

        -- PUBLIC 1
        s_axis_public_tdata_1   => m_axis_dut_tdata_s,
        s_axis_public_tkeep_1   => m_axis_dut_tkeep_s,
        s_axis_public_tvalid_1  => m_axis_dut_tvalid_s,
        s_axis_public_tready_1  => m_axis_dut_tready_s,
        s_axis_public_tlast_1   => m_axis_dut_tlast_s
    );



    -------------------------------------------------------------------------------
    -- DUT - LWC API compatible cipher
    -------------------------------------------------------------------------------
    u_cross_dut : tb_top
    generic map(
        DATA_WIDTH  => 64,
        TEST_EN     => '1'
    )
    port map(
        clk                         => sys_clk,
        rst_n                       => not sys_rst_s,

        cross_op                    => ctrl_vec_s(1 downto 0),
        cross_op_valid              => ctrl_vec_s(2),
        cross_op_ready              => cross_op_ready_s,
        cross_op_done               => open,
        cross_op_done_val           => open,

        s_axis_rng_tdata            => m_axis_prng_dut_tdata_s,
        s_axis_rng_tkeep            => m_axis_prng_dut_tkeep_s,
        s_axis_rng_tvalid           => m_axis_prng_dut_tvalid_s,
        s_axis_rng_tready           => m_axis_prng_dut_tready_s,
        s_axis_rng_tlast            => m_axis_prng_dut_tlast_s,

        s_axis_msg_keys_tdata       => m_axis_secret_dut_tdata_s,
        s_axis_msg_keys_tkeep       => m_axis_secret_dut_tkeep_s,
        s_axis_msg_keys_tvalid      => m_axis_secret_dut_tvalid_s,
        s_axis_msg_keys_tready      => m_axis_secret_dut_tready_s,
        s_axis_msg_keys_tlast       => m_axis_secret_dut_tlast_s,

        s_axis_sig_tdata            => m_axis_public_dut_tdata_s,
        s_axis_sig_tkeep            => m_axis_public_dut_tkeep_s,
        s_axis_sig_tvalid           => m_axis_public_dut_tvalid_s,
        s_axis_sig_tready           => m_axis_public_dut_tready_s,
        s_axis_sig_tlast            => m_axis_public_dut_tlast_s,

        m_axis_sig_keys_tdata       => m_axis_dut_tdata_s,
        m_axis_sig_keys_tkeep       => m_axis_dut_tkeep_s,
        m_axis_sig_keys_tvalid      => m_axis_dut_tvalid_s,
        m_axis_sig_keys_tready      => m_axis_dut_tready_s,
        m_axis_sig_keys_tlast       => m_axis_dut_tlast_s
    );

    -- clear is valid and ready
    ctrl_vec_clear_s(2) <= ctrl_vec_s(2) and cross_op_ready_s;

end architecture structural;
