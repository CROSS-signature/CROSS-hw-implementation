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

# Ensure the design meets timing
set slack_ns [get_property SLACK [get_timing_paths -delay_type min_max]]
send_msg "Slack check 1-1" INFO "Slack is ${slack_ns} ns."

# Print message in logs
send_msg "Report generation 1-1" INFO "Start generating reports"

# Generate utilization report
report_utilization -file report_global_utilization.txt
report_utilization -hierarchical -file report_hierarchical_utilization.txt

# Generate time report
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets -file report_timing.txt

# Generate high fan out list
report_high_fanout_nets -timing -max_nets 1000 -fanout_greater_than 100 -file report_fanout.txt

# Generate design analysis report
report_design_analysis -timing -setup -hierarchical_depth 10 -complexity -congestion -file report_design_analysis.txt

# Generate suggestion report
report_qor_suggestions -file report_qor_suggestions.txt

if {[info exists env(XLX_SYNTH_OOC)]} {
  # disable relative error on bitstream generation
  send_msg "Bitstream generation 1-1" INFO "Out-of-context synthesis detected, skipping bitstream generation"
  set_property IS_ENABLED 0 [get_drc_checks {HDOOC-3}]
}

if [expr {$slack_ns < 0}] {
  send_msg "Slack check 1-2" "ERROR" "Timing failed. Slack is ${slack_ns} ns."
}
