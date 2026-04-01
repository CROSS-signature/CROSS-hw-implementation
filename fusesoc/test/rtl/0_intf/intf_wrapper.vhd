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
-- @author   Patrick Karl <patrick.karl@tum.de>
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity intf_wrapper is
    generic(
        GLOBAL_CLK_PERIODE_NS_G         : natural;
        GLOBAL_CLK_FREQUENCY_MHZ_G      : natural;
        INTF_DATA_WIDTH_G               : integer;
        RX_FIFO_EN_G                    : boolean;
        RX_FIFO_DEPTH_G                 : integer;
        TX_FIFO_EN_G                    : boolean;
        TX_FIFO_DEPTH_G                 : integer;

        USE_UART_G                      : boolean;

        UART_BAUD_RATE_G                : integer;
        UART_EN_PARITY_G                : boolean;
        UART_EVEN_PARITY_G              : boolean;
        UART_N_PAYLOAD_BITS_G           : integer;
        UART_N_STOP_BITS_G              : integer
    );
    port(
        -- EXTERNAL SIDE
        -- uart
        uart_txd                    : out   std_logic;
        uart_rxd                    : in    std_logic;
        uart_parity_error           : out   std_logic;
        uart_frame_error            : out   std_logic;

        -- USER SIDE
        axis_aclk                   : in    std_logic;
        axis_rst                    : in    std_logic;

        m_axis_tdata                : out   std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
        m_axis_tvalid               : out   std_logic;
        m_axis_tready               : in    std_logic;

        s_axis_tdata                : in    std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
        s_axis_tvalid               : in    std_logic;
        s_axis_tready               : out   std_logic
    );
end entity intf_wrapper;


architecture structural of intf_wrapper is

    signal m_axis_uart_tdata_s          : std_logic_vector(7 downto 0);
    signal m_axis_uart_tvalid_s         : std_logic := '0';

    signal s_axis_uart_tdata_s          : std_logic_vector(7 downto 0);
    signal s_axis_uart_tvalid_s         : std_logic := '0';
    signal s_axis_uart_tready_s         : std_logic := '0';

    signal m_axis_tx_fifo_tdata_s       : std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
    signal m_axis_tx_fifo_tvalid_s      : std_logic := '0';
    signal m_axis_tx_fifo_tready_s      : std_logic := '0';

    signal s_axis_rx_fifo_tdata_s       : std_logic_vector(INTF_DATA_WIDTH_G - 1 downto 0);
    signal s_axis_rx_fifo_tvalid_s      : std_logic := '0';
    signal s_axis_rx_fifo_tready_s      : std_logic := '0';

begin


    --------------------------------------------------------------------------
    -- UART
    --------------------------------------------------------------------------
    gen_UART : if USE_UART_G generate
        i_uart : entity work.uart_if
        generic map(
            CLK_FREQ_G          => GLOBAL_CLK_FREQUENCY_MHZ_G,
            BAUD_RATE_G         => UART_BAUD_RATE_G,
            EN_PARITY_G         => UART_EN_PARITY_G,
            EVEN_PARITY_G       => UART_EVEN_PARITY_G,
            N_PAYLOAD_BITS_G    => UART_N_PAYLOAD_BITS_G,
            N_STOP_BITS_G       => UART_N_STOP_BITS_G
        )
        port map(
            --! Control Port
            axis_aclk           => axis_aclk,
            axis_rst            => axis_rst,
            parity_error        => uart_parity_error,
            frame_error         => uart_frame_error,

            --! UART Serial Port
            txd                 => uart_txd,
            rxd                 => uart_rxd,

            --! User Port
            s_axis_tdata        => s_axis_uart_tdata_s,
            s_axis_tvalid       => s_axis_uart_tvalid_s,
            s_axis_tready       => s_axis_uart_tready_s,
            m_axis_tdata        => m_axis_uart_tdata_s,
            m_axis_tvalid       => m_axis_uart_tvalid_s
        );
    end generate gen_UART;


    --------------------------------------------------------------------------
    -- RX FIFO
    --------------------------------------------------------------------------
    gen_rx_fifo : if RX_FIFO_EN_G generate
        i_rx_fifo : entity work.fifo
        generic map(
            WIDTH_G         => INTF_DATA_WIDTH_G,
            DEPTH_G         => RX_FIFO_DEPTH_G
        )
        port map(
            axis_aclk       => axis_aclk,
            axis_rst        => axis_rst,

            s_axis_tdata    => s_axis_rx_fifo_tdata_s,
            s_axis_tkeep    => (others => '1'),
            s_axis_tvalid   => s_axis_rx_fifo_tvalid_s,
            s_axis_tready   => s_axis_rx_fifo_tready_s,
            s_axis_tlast    => '0',

            m_axis_tdata    => m_axis_tdata,
            m_axis_tkeep    => open,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => open
        );

        -- Connect with UART
        gen_uart_con : if USE_UART_G generate
            s_axis_rx_fifo_tdata_s  <= m_axis_uart_tdata_s;
            s_axis_rx_fifo_tvalid_s <= m_axis_uart_tvalid_s;
        end generate gen_uart_con;

    else generate

        -- Connect with UART
        gen_uart_con : if USE_UART_G generate
            m_axis_tdata  <= m_axis_uart_tdata_s;
            m_axis_tvalid <= m_axis_uart_tvalid_s;
        end generate gen_uart_con;

    end generate gen_rx_fifo;


    --------------------------------------------------------------------------
    -- TX FIFO
    --------------------------------------------------------------------------
    gen_tx_fifo : if TX_FIFO_EN_G generate
        i_tx_fifo : entity work.fifo
        generic map(
            WIDTH_G         => INTF_DATA_WIDTH_G,
            DEPTH_G         => TX_FIFO_DEPTH_G
        )
        port map(
            axis_aclk       => axis_aclk,
            axis_rst        => axis_rst,

            s_axis_tdata    => s_axis_tdata,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tkeep    => (others => '1'),
            s_axis_tlast    => '0',
            s_axis_tready   => s_axis_tready,

            m_axis_tdata    => m_axis_tx_fifo_tdata_s,
            m_axis_tkeep    => open,
            m_axis_tvalid   => m_axis_tx_fifo_tvalid_s,
            m_axis_tready   => m_axis_tx_fifo_tready_s,
            m_axis_tlast    => open
        );

        -- Connect with UART
        gen_uart_con : if USE_UART_G generate
            s_axis_uart_tdata_s     <= m_axis_tx_fifo_tdata_s;
            s_axis_uart_tvalid_s    <= m_axis_tx_fifo_tvalid_s;
            m_axis_tx_fifo_tready_s <= s_axis_uart_tready_s;
        end generate gen_uart_con;

    else generate

        -- Connect with UART
        gen_uart_con : if USE_UART_G generate
            s_axis_uart_tdata_s     <= s_axis_tdata;
            s_axis_uart_tvalid_s    <= s_axis_tvalid;
            s_axis_tready           <= s_axis_uart_tready_s;
        end generate gen_uart_con;

    end generate gen_tx_fifo;

end architecture structural;
