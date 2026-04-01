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

module axis_mux #(
    parameter int unsigned N_SLAVES  = 2,
    parameter int unsigned BITS_ELEM = 8
) (
    input logic [$clog2(N_SLAVES)-1:0] sel,

    AXIS.slave  s_axis[N_SLAVES],
    AXIS.master m_axis
);
    localparam DW = m_axis.DATA_WIDTH;
    localparam UW = m_axis.TUSER_WIDTH;

    logic [          N_SLAVES*DW-1:0] tdata_int;
    logic [N_SLAVES*(DW/BITS_ELEM)-1:0] tkeep_int;
    logic [             N_SLAVES-1:0] tvalid_int;
    logic [             N_SLAVES-1:0] tlast_int;
    logic [          N_SLAVES*UW-1:0] tuser_int;

    assign m_axis.tdata  = tdata_int[sel*DW+:DW];
    assign m_axis.tkeep  = tkeep_int[sel*(DW/BITS_ELEM)+:DW/BITS_ELEM];
    assign m_axis.tvalid = tvalid_int[sel];
    assign m_axis.tlast  = tlast_int[sel];
    assign m_axis.tuser  = tuser_int[sel*UW+:UW];

    generate
        for (genvar s = 0; s < N_SLAVES; s++) begin : gen_mux
            assign tdata_int[s*DW+:DW]                     = s_axis[s].tdata;
            assign tkeep_int[s*DW/BITS_ELEM+:DW/BITS_ELEM] = s_axis[s].tkeep;
            assign tvalid_int[s]                           = s_axis[s].tvalid;
            assign tlast_int[s]                            = s_axis[s].tlast;
            assign tuser_int[s*UW+:UW]                     = s_axis[s].tuser;

            always_comb begin
                s_axis[s].tready = 1'b0;
                if (sel == $clog2(N_SLAVES)'(s)) begin
                    s_axis[s].tready = m_axis.tready;
                end
            end

        end
    endgenerate

endmodule
