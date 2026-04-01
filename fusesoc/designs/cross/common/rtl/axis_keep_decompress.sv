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

/*
 *  Transform a standard AXI-Stream (slave) where each tkeep bit signals the validity
 *  of a byte to an AXI-Stream (master) where each tkeep bit signals the validity of
 *  an element of size `ELEM_WIDTH`.
 */
module axis_keep_decompress
    import cross_pkg::*;
#(
    parameter int            ELEM_WIDTH = 8,
    parameter element_type_t ELEM_TYPE  = ELEM_TYPE_FZ_NM
) (
    AXIS.slave  s_axis,
    AXIS.master m_axis
);
    localparam int DW = m_axis.DATA_WIDTH;
    localparam int TCOEFFS = DW / ELEM_WIDTH;
    localparam int LAST_COEFFS = ELEM_COEFFS[ELEM_TYPE] <= TCOEFFS ? TCOEFFS : ELEM_COEFFS[ELEM_TYPE] % TCOEFFS;
    localparam logic [TCOEFFS-1:0] LAST_TKEEP = {
        {(TCOEFFS - LAST_COEFFS) {1'b0}}, {LAST_COEFFS{1'b1}}
    };

    assign m_axis.tdata  = DW'(s_axis.tdata);
    assign m_axis.tvalid = s_axis.tvalid;
    assign s_axis.tready = m_axis.tready;
    assign m_axis.tlast  = s_axis.tlast;

    always_comb begin
        m_axis.tkeep = '1;
        if (s_axis.tlast) begin
            m_axis.tkeep = LAST_TKEEP;
        end
    end

endmodule
