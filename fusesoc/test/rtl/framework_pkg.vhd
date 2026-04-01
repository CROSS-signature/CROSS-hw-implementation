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


package framework_pkg is

    -----------------------------------------------------------------------------------
    -- Config
    -----------------------------------------------------------------------------------
    constant GLOBAL_CLK_PERIODE_NS_C        : natural                       := 20;
    constant GLOBAL_CLK_FREQUENCY_MHZ_C     : natural                       := 50000000;

    -- Reset configuration
    constant RST_ACTIVE_LOW                 : std_logic                     := '1';

    -- Interface configuration
    constant INTF_DATA_WIDTH_C              : integer                       := 8;
    constant INTF_RX_FIFO_EN_C              : boolean                       := true;
    constant INTF_RX_FIFO_DEPTH_C           : integer                       := 4;
    constant INTF_TX_FIFO_EN_C              : boolean                       := true;
    constant INTF_TX_FIFO_DEPTH_C           : integer                       := 4;

    constant USE_UART_C                     : boolean                       := true;

    constant UART_BAUD_RATE_C               : integer                       := 2000000;
    constant UART_EN_PARITY_C               : boolean                       := false;
    constant UART_EVEN_PARITY_C             : boolean                       := true;
    constant UART_N_PAYLOAD_BITS_C          : integer                       := 8;
    constant UART_N_STOP_BITS_C             : integer                       := 1;

    -- Framework subsystem configuration
    constant RND_DATA_WIDTH_C               : integer                       := 64;
    constant RND_MEMORY_DEPTH_C             : integer                       := 128;

    -- We use this for msg/keys
    constant SECRET_EN_C                    : boolean                       := true;
    constant SECRET_DATA_WIDTH_C            : integer                       := 64;
    constant SECRET_MEMORY_DEPTH_C          : integer                       := 512;

    -- And this for the signature
    constant PUBLIC_DATA_WIDTH_C            : integer                       := 64;
    constant PUBLIC_MEMORY_DEPTH_0_C        : integer                       := 9325;
    constant PUBLIC_MEMORY_DEPTH_1_C        : integer                       := 9325;

    constant CTRL_VEC_DATA_WIDTH_C          : integer                       := 8;


    -----------------------------------------------------------------------------------
    -- Type/CMD Encodings
    -----------------------------------------------------------------------------------
    constant PRNG_TYPE_C                : std_logic_vector(7 downto 0)  := x"00";
    constant SECRET_TYPE_C              : std_logic_vector(7 downto 0)  := x"01";
    constant PUBLIC_TYPE_C              : std_logic_vector(7 downto 0)  := x"02";
    constant CTRL_TYPE_C                : std_logic_vector(7 downto 0)  := x"03";

    constant LEN_SIZE_BITS_C            : integer                       := 32;

    -----------------------------------------------------------------------------------
    -- Helper Functions
    -----------------------------------------------------------------------------------
    --! Log of base 2
    function log2_ceil (N: natural) return natural;

    --! Immediate if
    function iif (a : boolean; b, c : integer) return integer;

end package framework_pkg;


package body framework_pkg is

    --! Log of base 2
    function log2_ceil (N: natural) return natural is
    begin
         if ( N = 0 ) then
             return 0;
         elsif N <= 2 then
             return 1;
         else
            if (N mod 2 = 0) then
                return 1 + log2_ceil(N/2);
            else
                return 1 + log2_ceil((N+1)/2);
            end if;
         end if;
    end function log2_ceil;

    --! Immediate if
    function iif (a : boolean; b, c : integer) return integer is
    begin
        if (a) then
            return b;
        else
            return c;
        end if;
    end function iif;

end package body framework_pkg;
