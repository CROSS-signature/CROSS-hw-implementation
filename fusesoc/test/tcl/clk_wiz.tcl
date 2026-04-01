# Copyright 2026, Technical University of Munich
# Copyright 2026, Politecnico di Milano.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0. You may obtain a
# copy of the License at
#
# https://solderpad.org/licenses/SHL-2.1/
#
# Unless required by applicable law or agreed to in writing, any work
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------
#
# CROSS - Codes and Restricted Objects Signature Scheme
#
# @version 1.0 (April 2026)
#
# @author: Patrick Karl <patrick.karl@tum.de>

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0

set_property -dict [list \
                    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50} \
                    CONFIG.USE_LOCKED {true} \
                    CONFIG.USE_RESET {false} \
                    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
                    CONFIG.MMCM_CLKFBOUT_MULT_F {10.000} \
                    CONFIG.MMCM_CLKOUT0_DIVIDE_F {20.000} \
                    CONFIG.CLKOUT1_JITTER {151.636} \
                    CONFIG.CLKOUT1_PHASE_ERROR {98.575}] [get_ips clk_wiz_0]

set_property generate_synth_checkpoint false [get_files clk_wiz_0.xci]
