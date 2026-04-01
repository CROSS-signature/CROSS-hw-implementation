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

// This module is basically a 1-2 demux that clones and synchronizes both
// outputs if both of them are selected
module axis_clone
#(
    parameter logic INPUT_REG = 1'b0
)
(
    input logic clk,
    input logic rst_n,
    input logic [1:0] sel,

    AXIS.slave s_axis,
    AXIS.master m_axis[2]
);

    logic sync_outputs;
    AXIS #(.DATA_WIDTH(s_axis.DATA_WIDTH), .ELEM_WIDTH(s_axis.ELEM_WIDTH) ) s_axis_tmp();

    //----------------------------------------------------
    // INPUT REGISTER (optional)
    //----------------------------------------------------
    generate
        if (INPUT_REG) begin
            axis_reg
            u_input_reg
            (
                .clk,
                .rst_n,
                .s_axis( s_axis     ),
                .m_axis( s_axis_tmp )
            );
        end else begin
            `AXIS_ASSIGN(s_axis_tmp, s_axis);
            assign s_axis_tmp.tuser = s_axis.tuser;
        end
    endgenerate

    // If both outputs are selected, sync them
    assign sync_outputs = &sel;

    assign m_axis[0].tdata = s_axis_tmp.tdata;
    assign m_axis[0].tkeep = s_axis_tmp.tkeep;
    assign m_axis[0].tvalid = s_axis_tmp.tvalid & sel[0] & (m_axis[1].tready | ~sync_outputs);
    assign m_axis[0].tlast = s_axis_tmp.tlast;
    assign m_axis[0].tuser = s_axis_tmp.tuser;

    assign m_axis[1].tdata = s_axis_tmp.tdata;
    assign m_axis[1].tkeep = s_axis_tmp.tkeep;
    assign m_axis[1].tvalid = s_axis_tmp.tvalid & sel[1] & (m_axis[0].tready | ~sync_outputs);
    assign m_axis[1].tlast = s_axis_tmp.tlast;
    assign m_axis[1].tuser = s_axis_tmp.tuser;

    assign s_axis_tmp.tready = sync_outputs ? (m_axis[0].tready & m_axis[1].tready) : (m_axis[0].tready & sel[0]) | (m_axis[1].tready & sel[1]);

endmodule
