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
use work.framework_pkg.all;


entity tdp_wrapper is
    generic(
        DATA_WIDTH_G    : integer;
        DEPTH_G         : integer;
        N_PACKETS_G     : integer;
        INTF_A_TYPE_G   : string;   -- "STREAM", "MEMORY_MAPPED"
        INTF_B_TYPE_G   : string    -- "STREAM", "MEMORY_MAPPED"
    );
    port(
        axis_aclk       : in    std_logic;
        axis_rst        : in    std_logic;

        -- Port A interface, either stream or memory mapped
        -- STREAM
        s_axis_tdata    : in    std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        s_axis_tkeep    : in    std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        s_axis_tvalid   : in    std_logic;
        s_axis_tready   : out   std_logic;
        s_axis_tlast    : in    std_logic;

        -- MEMORY MAPPED
        port_en_a       : in    std_logic;
        addr_a          : in    std_logic_vector(log2_ceil(DEPTH_G) - 1 downto 0);
        wr_en_a         : in    std_logic;
        wr_data_a       : in    std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        wr_data_par_a   : in    std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        rd_data_a       : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        rd_data_par_a   : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        done_a          : in    std_logic;

        -- Port B interface, either stream or memory mapped
        -- STREAM
        m_axis_tdata    : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        m_axis_tkeep    : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        m_axis_tvalid   : out   std_logic;
        m_axis_tready   : in    std_logic;
        m_axis_tlast    : out   std_logic;

        -- MEMORY MAPPED
        port_en_b       : in    std_logic;
        addr_b          : in    std_logic_vector(log2_ceil(DEPTH_G) - 1 downto 0);
        wr_en_b         : in    std_logic;
        wr_data_b       : in    std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        wr_data_par_b   : in    std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
        rd_data_b       : out   std_logic_vector(DATA_WIDTH_G - 1 downto 0);
        rd_data_par_b   : out   std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0)
    );
end entity tdp_wrapper;


architecture behavioral of tdp_wrapper is

    -- Signal declarations
    signal port_en_a_s      : std_logic := '0';
    signal addr_a_s         : std_logic_vector(log2_ceil(DEPTH_G) - 1 downto 0);
    signal wr_en_a_s        : std_logic;
    signal wr_data_a_s      : std_logic_vector(DATA_WIDTH_G - 1 downto 0);
    signal wr_data_par_a_s  : std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
    signal rd_data_a_s      : std_logic_vector(DATA_WIDTH_G - 1 downto 0);
    signal rd_data_par_a_s  : std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);

    signal port_en_b_s      : std_logic := '0';
    signal addr_b_s         : std_logic_vector(log2_ceil(DEPTH_G) - 1 downto 0);
    signal wr_en_b_s        : std_logic;
    signal wr_data_b_s      : std_logic_vector(DATA_WIDTH_G - 1 downto 0);
    signal wr_data_par_b_s  : std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);
    signal rd_data_b_s      : std_logic_vector(DATA_WIDTH_G - 1 downto 0);
    signal rd_data_par_b_s  : std_logic_vector(DATA_WIDTH_G/8 - 1 downto 0);


    signal s_axis_tready_s  : std_logic := '0';

    signal m_axis_tvalid_s  : std_logic := '0';
    signal m_axis_tlast_s   : std_logic;

    signal packet_fill_s    : integer range 0 to N_PACKETS_G := 0;

begin


    -- Assertions --
    assert DATA_WIDTH_G mod 8 = 0
        report "DATA_WIDTH_G must be multiple of 8!"
        severity failure;

    assert INTF_A_TYPE_G = "MEMORY_MAPPED" or INTF_A_TYPE_G = "STREAM"
        report "Allowed types are MEMORY_MAPPED or STREAM"
        severity failure;

    assert INTF_B_TYPE_G = "MEMORY_MAPPED" or INTF_B_TYPE_G = "STREAM"
        report "Allowed types are MEMORY_MAPPED or STREAM"
        severity failure;


    -- Some output connections
    s_axis_tready   <= s_axis_tready_s;
    m_axis_tvalid   <= m_axis_tvalid_s;
    m_axis_tlast    <= m_axis_tlast_s;

    ------------------------------------------------------------
    -- MEMORY INSTANCE
    ------------------------------------------------------------
    i_tdp_bram : entity work.tdp_bram
    generic map(
        DATA_WIDTH_G  => DATA_WIDTH_G,
        ADDR_WIDTH_G  => log2_ceil(DEPTH_G)
    )
    port map(
        clk_a           => axis_aclk,
        port_en_a       => port_en_a_s,
        addr_a          => addr_a_s,
        wr_en_a         => wr_en_a_s,
        wr_data_a       => wr_data_a_s,
        wr_data_par_a   => wr_data_par_a_s,
        rd_data_a       => rd_data_a_s,
        rd_data_par_a   => rd_data_par_a_s,

        clk_b           => axis_aclk,
        port_en_b       => port_en_b_s,
        addr_b          => addr_b_s,
        wr_en_b         => wr_en_b_s,
        wr_data_b       => wr_data_b_s,
        wr_data_par_b   => wr_data_par_b_s,
        rd_data_b       => rd_data_b_s,
        rd_data_par_b   => rd_data_par_b_s
    );


    ------------------------------------------------------------
    -- PORT A LOGIC
    ------------------------------------------------------------
    -- MEMORY_MAPPED
    gen_port_a : if INTF_A_TYPE_G = "MEMORY_MAPPED" generate

        -- Directly assign Port for memory mapped interface
        port_en_a_s     <= port_en_a;
        addr_a_s        <= addr_a;
        wr_en_a_s       <= wr_en_a;
        wr_data_a_s     <= wr_data_a;
        wr_data_par_a_s <= wr_data_par_a;
        rd_data_a       <= rd_data_a_s;
        rd_data_par_a   <= rd_data_par_a_s;


    -- STREAM
    else generate

        signal addr_a_int_s     : integer range 0 to DEPTH_G - 1        := 0;
        signal packet_cnt_s     : integer range 0 to N_PACKETS_G - 1    := 0;

    begin

        port_en_a_s     <= s_axis_tvalid;
        addr_a_s        <= std_logic_vector(to_unsigned(addr_a_int_s, addr_a_s'length));
        wr_data_a_s     <= s_axis_tdata;
        wr_data_par_a_s <= s_axis_tkeep(DATA_WIDTH_G/8 - 1 downto 1) & s_axis_tlast;
        wr_en_a_s       <= s_axis_tvalid and s_axis_tready_s;
        s_axis_tready_s <= '1' when (packet_fill_s < N_PACKETS_G) else '0';


        -- Address counter
        p_addr_a : process(axis_aclk)
        begin
            if rising_edge(axis_aclk) then
                if (axis_rst = '1') then
                    addr_a_int_s <= 0;
                else
                    if (s_axis_tvalid = '1' and s_axis_tready_s = '1') then
                        if (addr_a_int_s >= DEPTH_G - 1 or (s_axis_tlast = '1' and packet_cnt_s >= N_PACKETS_G - 1)) then
                            addr_a_int_s <= 0;
                        else
                            addr_a_int_s <= addr_a_int_s + 1;
                        end if;
                    end if;
                end if;
            end if;
        end process p_addr_a;

        -- Packet counter
        p_packet_cnt : process(axis_aclk)
        begin
            if rising_edge(axis_aclk) then
                if (axis_rst = '1') then
                    packet_cnt_s <= 0;
                else
                    if (s_axis_tvalid = '1' and s_axis_tready_s = '1' and s_axis_tlast = '1') then
                        if (packet_cnt_s >= N_PACKETS_G - 1) then
                            packet_cnt_s <= 0;
                        else
                            packet_cnt_s <= packet_cnt_s + 1;
                        end if;
                    end if;
                end if;
            end if;
        end process p_packet_cnt;

    end generate gen_port_a;

    ------------------------------------------------------------
    -- PORT B LOGIC
    ------------------------------------------------------------
    -- MEMORY_MAPPED
    gen_port_b : if INTF_B_TYPE_G = "MEMORY_MAPPED" generate

        -- Directly assign Port for memory mapped interface
        port_en_b_s     <= port_en_b;
        addr_b_s        <= addr_b;
        wr_en_b_s       <= wr_en_b;
        wr_data_b_s     <= wr_data_b;
        wr_data_par_b_s <= wr_data_par_b;
        rd_data_b       <= rd_data_b_s;
        rd_data_par_b   <= rd_data_par_b_s;

    -- STREAM
    else generate

        type state_t is (IDLE, READOUT);
        signal state_s          : state_t   := IDLE;
        signal n_state_s        : state_t;

        signal addr_b_int_s     : integer range 0 to DEPTH_G - 1 := 0;
        signal n_addr_b_int_s   : integer range 0 to DEPTH_G - 1;

        signal packet_cnt_s     : integer range 0 to N_PACKETS_G - 1;

    begin


        -- FSM required for look-ahead readout
        --! Register
        p_reg : process(axis_aclk)
        begin
            if rising_edge(axis_aclk) then
                if (axis_rst = '1') then
                    state_s         <= IDLE;
                else
                    state_s         <= n_state_s;
                    addr_b_int_s    <= n_addr_b_int_s;
                end if;
            end if;
        end process p_reg;


        -- Next state logic
        p_next_state : process(all)
        begin
            -- Default preventing latch
            n_state_s <= state_s;

            case state_s is
                when IDLE =>
                    if (packet_fill_s >= N_PACKETS_G or (INTF_A_TYPE_G = "MEMORY_MAPPED" and done_a = '1')) then
                        n_state_s <= READOUT;
                    end if;

                when READOUT =>
                    if (m_axis_tvalid_s = '1' and m_axis_tready = '1' and m_axis_tlast_s = '1' and packet_cnt_s >= N_PACKETS_G - 1) then
                        n_state_s <= IDLE;
                    end if;

                when others =>
                    n_state_s <= IDLE;

            end case;
        end process p_next_state;


        -- Output logic
        p_output : process(all)
        begin
            -- Default values
            n_addr_b_int_s  <= addr_b_int_s;

            case state_s is
                when IDLE =>
                    n_addr_b_int_s <= 0;

                when READOUT =>
                    if (m_axis_tvalid_s = '1' and m_axis_tready = '1') then
                        if (addr_b_int_s >= DEPTH_G - 1) then
                            n_addr_b_int_s <= 0;
                        else
                            n_addr_b_int_s <= addr_b_int_s + 1;
                        end if;
                    end if;

                when others =>
                    null;
            end case;
        end process p_output;


        -- Packet counter
        p_packet_cnt : process(axis_aclk)
        begin
            if rising_edge(axis_aclk) then
                if (axis_rst = '1') then
                    packet_cnt_s <= 0;
                else
                    if (m_axis_tvalid_s = '1' and m_axis_tready = '1' and m_axis_tlast_s = '1') then
                        if (packet_cnt_s >= N_PACKETS_G - 1) then
                            packet_cnt_s <= 0;
                        else
                            packet_cnt_s <= packet_cnt_s + 1;
                        end if;
                    end if;
                end if;
            end if;
        end process p_packet_cnt;

        -- Perform lookahead such that the correct data is always present in the next cycle
        port_en_b_s     <= '1' when (packet_fill_s >= N_PACKETS_G or state_s = READOUT) else '0';
        addr_b_s        <= std_logic_vector(to_unsigned(n_addr_b_int_s, addr_b_s'length));
        wr_en_b_s       <= '0';

        m_axis_tdata    <= rd_data_b_s;
        m_axis_tkeep    <= rd_data_par_b_s(DATA_WIDTH_G/8 - 1 downto 1) & '1';
        m_axis_tvalid_s <= '1' when (state_s = READOUT) else '0';
        m_axis_tlast_s  <= rd_data_par_b_s(0);

    end generate gen_port_b;


    ------------------------------------------------------------
    -- If both STREAM, generate packet fill count
    ------------------------------------------------------------
    gen_fill_cnt : if (INTF_A_TYPE_G = "STREAM" and INTF_B_TYPE_G = "STREAM") generate

        p_fill_cnt : process(axis_aclk)
        begin
            if rising_edge(axis_aclk) then
                if (axis_rst = '1') then
                    packet_fill_s <= 0;
                else
                    -- Fill memory
                    if (s_axis_tvalid = '1' and s_axis_tready_s = '1' and s_axis_tlast = '1') then
                        packet_fill_s <= packet_fill_s + 1;
                    end if;

                    -- Read  memory
                    if (m_axis_tvalid_s = '1' and m_axis_tready = '1' and m_axis_tlast_s = '1') then
                        packet_fill_s <= packet_fill_s - 1;
                    end if;

                end if;
            end if;
        end process p_fill_cnt;

    end generate gen_fill_cnt;

end architecture behavioral;
