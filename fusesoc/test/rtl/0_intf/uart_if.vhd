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
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

entity uart_if is
    generic(
        BAUD_RATE_G         : integer;
        CLK_FREQ_G          : integer;
        EN_PARITY_G         : boolean;
        EVEN_PARITY_G       : boolean;
        N_PAYLOAD_BITS_G    : integer range 5 to 8;
        N_STOP_BITS_G       : integer range 1 to 2
    );
    port(
        --! Control Port
        axis_aclk               : in    std_ulogic;
        axis_rst                : in    std_ulogic;
        parity_error            : out   std_ulogic;
        frame_error             : out   std_ulogic;

        --! UART Serial Port
        txd                     : out   std_ulogic;
        rxd                     : in    std_ulogic;

        --! User Port
        s_axis_tdata            : in    std_ulogic_vector(7 downto 0);
        s_axis_tvalid           : in    std_ulogic;
        s_axis_tready           : out   std_ulogic;
        m_axis_tdata            : out   std_ulogic_vector(7 downto 0);
        m_axis_tvalid           : out   std_ulogic
    );
end entity uart_if;

architecture behavioral of uart_if is

    --! Max counter value for clock divider
    constant CLK_DIVIDER_C      : integer               := (CLK_FREQ_G / BAUD_RATE_G);
    constant IDLE_STOP_BIT_C    : std_ulogic            := '1';
    constant START_BIT_C        : std_ulogic            := '0';

    --! Number of synchronization stages to sync rxd to clk.
    -- If more than 3, just increase max range
    constant N_SYNC_STAGES_C    : integer range 2 to 3  := 2;

    signal n_m_axis_tdata_s     : std_ulogic_vector(7 downto 0);
    signal m_axis_tdata_s       : std_ulogic_vector(7 downto 0);
    signal n_m_axis_tvalid_s    : std_logic;
    signal m_axis_tvalid_s      : std_logic := '0';

    signal n_parity_error_s     : std_ulogic;
    signal parity_error_s       : std_ulogic;
    signal n_frame_error_s      : std_ulogic;
    signal frame_error_s        : std_ulogic;

    signal tx_clk_cnt_s         : integer range 0 to CLK_DIVIDER_C - 1;
    signal n_tx_bit_cnt_s       : integer range 0 to N_PAYLOAD_BITS_G - 1;
    signal tx_bit_cnt_s         : integer range 0 to N_PAYLOAD_BITS_G - 1;

    signal rx_clk_cnt_s         : integer range 0 to CLK_DIVIDER_C - 1;
    signal n_rx_bit_cnt_s       : integer range 0 to N_PAYLOAD_BITS_G - 1;
    signal rx_bit_cnt_s         : integer range 0 to N_PAYLOAD_BITS_G - 1;

    signal tx_reg_s             : std_logic_vector(7 downto 0);
    signal n_tx_reg_s           : std_logic_vector(7 downto 0);

    --! State definition for transmission.
    type tx_state_t is (TX_IDLE, TX_START, TX_TRANSMIT, TX_PARITY, TX_STOP);
    signal n_tx_state_s : tx_state_t;
    signal tx_state_s   : tx_state_t := TX_IDLE;

    --! State definition for reception.
    type rx_state_t is (RX_IDLE, RX_START ,RX_RECEIVE, RX_PARITY, RX_STOP);
    signal n_rx_state_s : rx_state_t;
    signal rx_state_s   : rx_state_t := RX_IDLE;

    --! Vector synchronizing
    signal rxd_sync_s   : std_ulogic_vector(N_SYNC_STAGES_C - 1 downto 0);
    signal rxd_reg_s    : std_ulogic;

begin

    --------------------------------------------------------------------
    -- Mapping internal signals to ouput
    --------------------------------------------------------------------
    m_axis_tdata    <= m_axis_tdata_s;
    m_axis_tvalid   <= m_axis_tvalid_s;
    parity_error    <= parity_error_s;
    frame_error     <= frame_error_s;

    --------------------------------------------------------------------
    --! Process synchronizing rxd.
    --------------------------------------------------------------------
    -- Two signal assignments would be less verbose, however this coding style
    -- allows to use more sync stages by just increasing N_SYNC_STAGES_C.
    p_sync_rxd : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                rxd_sync_s <= (others => '1');
            else
                rxd_sync_s(0) <= rxd;
                for i in 1 to (N_SYNC_STAGES_C - 1) loop
                    rxd_sync_s(i) <= rxd_sync_s(i-1);
                end loop;
            end if;
        end if;
    end process p_sync_rxd;
    rxd_reg_s <= rxd_sync_s(N_SYNC_STAGES_C - 1);

    --------------------------------------------------------------------
    --! Clock divider process for transmission and reception
    --------------------------------------------------------------------
    p_clk_divider : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                tx_clk_cnt_s <= 0;
                rx_clk_cnt_s <= 0;
            else
                -- TX clock divider
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1 or tx_state_s = TX_IDLE) then
                    tx_clk_cnt_s <= 0;
                else
                    tx_clk_cnt_s <= tx_clk_cnt_s + 1;
                end if;

                -- RX clock divider
                if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1 or rx_state_s = RX_IDLE) then
                    rx_clk_cnt_s <= 0;
                else
                    rx_clk_cnt_s <= rx_clk_cnt_s + 1;
                end if;
            end if;
        end if;
    end process p_clk_divider;

    --------------------------------------------------------------------
    -- --! Control and Data Registers
    --------------------------------------------------------------------
    p_reg : process(axis_aclk)
    begin
        if rising_edge(axis_aclk) then
            if (axis_rst = '1') then
                tx_state_s              <= TX_IDLE;
                rx_state_s              <= RX_IDLE;
                m_axis_tvalid_s         <= '0';
                parity_error_s          <= '0';
                frame_error_s           <= '0';
            else
                tx_state_s              <= n_tx_state_s;
                tx_bit_cnt_s            <= n_tx_bit_cnt_s;
                rx_state_s              <= n_rx_state_s;
                rx_bit_cnt_s            <= n_rx_bit_cnt_s;
                m_axis_tdata_s          <= n_m_axis_tdata_s;
                m_axis_tvalid_s         <= n_m_axis_tvalid_s;
                parity_error_s          <= n_parity_error_s;
                frame_error_s           <= n_frame_error_s;
                tx_reg_s                <= n_tx_reg_s;
            end if;
        end if;
    end process p_reg;

    --------------------------------------------------------------------
    -- TX FSM
    --------------------------------------------------------------------
    --! Next state process.
    -- Wait for valid byte to transmit, then start with start bit.
    -- Afterwards, transmit 8 payload bytes.
    -- Finish with stop bit.
    p_tx_next_state : process(all)
    begin
        case tx_state_s is
            when TX_IDLE =>
                if (s_axis_tvalid = '1') then
                    n_tx_state_s <= TX_START;
                else
                    n_tx_state_s <= TX_IDLE;
                end if;

            when TX_START =>
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    n_tx_state_s <= TX_TRANSMIT;
                else
                    n_tx_state_s <= TX_START;
                end if;

            when TX_TRANSMIT =>
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1 and tx_bit_cnt_s >= N_PAYLOAD_BITS_G - 1) then
                    if (EN_PARITY_G) then
                        n_tx_state_s <= TX_PARITY;
                    else
                        n_tx_state_s <= TX_STOP;
                    end if;
                else
                    n_tx_state_s <= TX_TRANSMIT;
                end if;

            when TX_PARITY =>
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    n_tx_state_s <= TX_STOP;
                else
                    n_tx_state_s <= TX_PARITY;
                end if;

            when TX_STOP =>
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1 and tx_bit_cnt_s >= N_STOP_BITS_G - 1) then
                    n_tx_state_s <= TX_IDLE;
                else
                    n_tx_state_s <= TX_STOP;
                end if;

            when others =>
                n_tx_state_s <= TX_IDLE;

        end case;
    end process p_tx_next_state;

    --! Tx output decoding process
    -- busy is asserted while transmission is ongoing.
    -- txd is either idle/start/stop marker or LSB/MSB depending on config.
    p_tx_output_decode : process(all)
    begin
        -- Defaults preventing latches
        s_axis_tready   <= '0';
        n_tx_bit_cnt_s  <= tx_bit_cnt_s;
        n_tx_reg_s      <= tx_reg_s;

        case tx_state_s is
            when TX_IDLE =>
                s_axis_tready   <= '1';
                n_tx_bit_cnt_s  <= 0;
                n_tx_reg_s      <= s_axis_tdata;
                txd             <= IDLE_STOP_BIT_C;

            when TX_START =>
                txd <= START_BIT_C;

            when TX_TRANSMIT =>
                txd <= tx_reg_s(tx_bit_cnt_s);
                -- Count the number of transmitted bytes
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    if (tx_bit_cnt_s >= N_PAYLOAD_BITS_G - 1) then
                        n_tx_bit_cnt_s <= 0;
                    else
                        n_tx_bit_cnt_s <= tx_bit_cnt_s + 1;
                    end if;
                end if;

            -- xor1 generates xor of the argument vector.
            when TX_PARITY =>
                if (EVEN_PARITY_G and xor_reduce(tx_reg_s) = '0')
                or (not EVEN_PARITY_G and xor_reduce(tx_reg_s) = '1') then
                    txd <= '0';
                else
                    txd <= '1';
                end if;

            when TX_STOP =>
                txd <= IDLE_STOP_BIT_C;
                -- Count the number of stop bits.
                if (tx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    if (tx_bit_cnt_s >= N_STOP_BITS_G - 1) then
                        n_tx_bit_cnt_s <= 0;
                    else
                        n_tx_bit_cnt_s <= tx_bit_cnt_s + 1;
                    end if;
                end if;

            when others =>
                txd <= IDLE_STOP_BIT_C;

        end case;
    end process p_tx_output_decode;

    --------------------------------------------------------------------
    -- RX FSM
    --------------------------------------------------------------------
    --! Next state process.
    -- Wait for detection of start bit.
    -- Then sample the following byte and afterwards wait one bit (stop bit)
    -- before going back to initial state.
    p_rx_next_state : process(all)
    begin
        case rx_state_s is
            when RX_IDLE =>
                if (rxd_reg_s = START_BIT_C) then
                    n_rx_state_s <= RX_START;
                else
                    n_rx_state_s <= RX_IDLE;
                end if;

            when RX_START =>
                 if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    n_rx_state_s <= RX_RECEIVE;
                else
                    n_rx_state_s <= RX_START;
                end if;

            when RX_RECEIVE =>
                if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1 and rx_bit_cnt_s >= N_PAYLOAD_BITS_G - 1) then
                    if (EN_PARITY_G) then
                        n_rx_state_s <= RX_PARITY;
                    else
                        n_rx_state_s <= RX_STOP;
                    end if;
                else
                    n_rx_state_s <= RX_RECEIVE;
                end if;

            when RX_PARITY =>
                if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    n_rx_state_s <= RX_STOP;
                else
                    n_rx_state_s <= RX_PARITY;
                end if;

            -- Don't wait for rx_clk_cnt_s >= CLK_DIVIDER_C - 1 in this state.
            -- This would lead to a shift in the sampling point, because we start
            -- with one cycle delay. If the start bit follows without 'pause cycles',
            -- the one cycle delay accumulates and we'll get an error after some time.
            -- Going back to RX_IDLE directly after latching makes sure that the delay
            -- stays at 1 cycle.
            when RX_STOP =>
                if (rx_clk_cnt_s >= CLK_DIVIDER_C/2 - 1 and rx_bit_cnt_s >= N_STOP_BITS_G - 1) then
                    n_rx_state_s <= RX_IDLE;
                else
                    n_rx_state_s <= RX_STOP;
                end if;

            when others =>
                n_rx_state_s <= RX_IDLE;

        end case;
    end process p_rx_next_state;

    p_rx_output_decode : process(all)
    begin
        -- Defaults preventing latches
        n_m_axis_tdata_s    <= m_axis_tdata_s;
        n_m_axis_tvalid_s   <= '0';
        n_parity_error_s    <= parity_error_s;
        n_frame_error_s     <= frame_error_s;
        n_rx_bit_cnt_s      <= rx_bit_cnt_s;

        case rx_state_s is
            when RX_IDLE =>
                n_parity_error_s    <= '0';
                n_frame_error_s     <= '0';
                n_rx_bit_cnt_s      <= 0;

            when RX_START =>
                if (rx_clk_cnt_s = CLK_DIVIDER_C/2 - 1 and rxd_reg_s /= START_BIT_C) then
                    n_frame_error_s <= '1';
                end if;

            when RX_RECEIVE =>
                if (rx_clk_cnt_s = CLK_DIVIDER_C/2 - 1) then
                    n_m_axis_tdata_s(rx_bit_cnt_s) <= rxd_reg_s;
                end if;
                -- Count bits with clk_cnt to not skip the last bits
                if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    if (rx_bit_cnt_s >= N_PAYLOAD_BITS_G - 1) then
                        n_rx_bit_cnt_s  <= 0;
                    else
                        n_rx_bit_cnt_s  <= rx_bit_cnt_s + 1;
                    end if;
                end if;


            -- Upon reception of the parity bit, check error case:
            -- In even partiy mode, payload bits plus parity bit must be even.
            -- In odd parity mode, payload bits plus parity bit must be odd
            when RX_PARITY =>
                if (rx_clk_cnt_s = CLK_DIVIDER_C/2 - 1) then
                    if (EVEN_PARITY_G and (xor_reduce(m_axis_tdata_s) xor rxd_reg_s) = '1')
                    or (not EVEN_PARITY_G and (xor_reduce(m_axis_tdata_s) xor rxd_reg_s) = '0') then
                        n_parity_error_s <= '1';
                    end if;
                end if;

            -- Count number of stop bits.
            -- Sample stop bits in the middle of the symbol, check for correct frame ending.
            -- After configured number of stop bits, asser valid signal
            -- Check for correct frame ending and assert data_from_uart_valid_s.
            when RX_STOP =>
                if (rx_clk_cnt_s >= CLK_DIVIDER_C - 1) then
                    if (rx_bit_cnt_s >= N_STOP_BITS_G - 1) then
                        n_rx_bit_cnt_s  <= 0;
                    else
                        n_rx_bit_cnt_s  <= rx_bit_cnt_s + 1;
                    end if;
                end if;
                if (rx_clk_cnt_s >= CLK_DIVIDER_C/2 - 1) then
                    if (rxd_reg_s /= IDLE_STOP_BIT_C) then
                        n_frame_error_s <= '1';
                    end if;
                    if (rx_bit_cnt_s >= N_STOP_BITS_G - 1) then
                      n_m_axis_tvalid_s <= '1';
                    end if;
                end if;

            when others =>
                null;

        end case;
    end process p_rx_output_decode;

end architecture behavioral;
