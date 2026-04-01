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

entity prng is
    generic (
        SEED_WIDTH_G    : integer;
        RND_WIDTH_G     : integer
    );
    port (
        axis_aclk           : in    std_logic;
        axis_rst            : in    std_logic;

        s_axis_seed_tdata   : in    std_logic_vector(SEED_WIDTH_G - 1 downto 0);
        s_axis_seed_tvalid  : in    std_logic;
        s_axis_seed_tready  : out   std_logic;

        m_axis_rnd_tdata    : out   std_logic_vector(RND_WIDTH_G - 1 downto 0);
        m_axis_rnd_tvalid   : out   std_logic;
        m_axis_rnd_tready   : in    std_logic
    );
end entity prng;


architecture behavioral of prng is

    -- Signal declarations

begin

    ----------------------------------------------------------------------------
    -- Instantiate a PRNG here
    ----------------------------------------------------------------------------

end architecture behavioral;
