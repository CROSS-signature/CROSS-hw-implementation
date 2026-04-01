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
# @author: Francesco Antognazza <francesco.antognazza@polimi.it>

# Xilinx UG 894 "Using Tcl Scripting"

set workroot [pwd]

if {[info exists env(XLX_SYNTH_STRAT)]} {
  set_property strategy $env(XLX_SYNTH_STRAT) [get_runs synth_1]
}

if {[info exists env(XLX_IMPL_STRAT)]} {
  set_property strategy $env(XLX_IMPL_STRAT) [get_runs impl_1]
}

set_property STEPS.WRITE_BITSTREAM.TCL.PRE "${workroot}/pre_bitstream.tcl" [get_runs impl_1]

if {[info exists env(XLX_SYNTH_OOC)]} {
  set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
}

if {[info exists env(XLX_FLAT_HIER)]} {
  set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
}
