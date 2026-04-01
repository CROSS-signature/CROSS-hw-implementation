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
// @author: Patrick Karl <patrick.karl@tum.de>

`timescale 1ps / 1ps
`include "axis_intf.svh"

module axis_demux
#(
    parameter int unsigned N_MASTERS = 1
)
(
    input logic [$clog2(N_MASTERS)-1:0] sel,

    AXIS.slave s_axis,
    AXIS.master m_axis [N_MASTERS]
);

    logic tready_int[N_MASTERS];
    assign s_axis.tready = tready_int[sel];

    generate
        for (genvar m=0; m<N_MASTERS; m++) begin
            assign m_axis[m].tdata = s_axis.tdata;
            assign m_axis[m].tkeep = s_axis.tkeep;
            assign m_axis[m].tlast = s_axis.tlast;
            assign m_axis[m].tuser = s_axis.tuser;

            assign tready_int[m] = m_axis[m].tready;

            always_comb begin
                m_axis[m].tvalid = 1'b0;
                if ( sel == $clog2(N_MASTERS)'(m) ) begin
                    m_axis[m].tvalid = s_axis.tvalid;
                end
            end

        end
    endgenerate

endmodule
