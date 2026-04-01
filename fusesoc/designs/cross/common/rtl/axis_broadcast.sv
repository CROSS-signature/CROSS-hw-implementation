// Copyright 2026, Technical University of Munich
// Copyright 2026, Politecnico di Milano.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License");
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0. You may obtain a
// copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ----------
//
// CROSS - Codes and Restricted Objects Signature Scheme
//
// @version 1.0 (April 2026)
//
// @author: Francesco Antognazza <francesco.antognazza@polimi.it>

`timescale 1ps / 1ps
`include "axis_intf.svh"

module axis_broadcast
    import common_pkg::*;
#(
    parameter int unsigned N_CLONES   = 1,
    parameter bit          TUSER_USED = 1'b0
) (
    input logic                axis_aclk,
    input logic                axis_rst_n,
    input logic [N_CLONES-1:0] en_clone,

    AXIS.slave  s_axis,
    AXIS.master m_axis[N_CLONES+1]
);

    generate
        `AXIS_ASSIGN(m_axis[0], s_axis);
        for (genvar i = 0; i < N_CLONES; i++) begin : gen_clone
            // cannot use AXIS_ASSIGN_GATED as we cannot drive the m_axis tready
            assign m_axis[i+1].tdata = s_axis.tdata;
            assign m_axis[i+1].tkeep = s_axis.tkeep;
            assign m_axis[i+1].tvalid = en_clone[i] & s_axis.tvalid & s_axis.tready;  // filter valid signal
            if (TUSER_USED) begin : gen_tuser
                assign m_axis[i+1].tuser = s_axis.tuser;
            end
            assign m_axis[i+1].tlast = s_axis.tlast;

            // check for tready of slaves
            `ASSERT(missed_transaction, en_clone[i] ? `AXIS_TRANS(s_axis) ==
                    `AXIS_TRANS(m_axis[i+1])
                    : 1'b1, axis_aclk, axis_rst_n)
        end
    endgenerate

endmodule
