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

module axis_compare
#(
    parameter int unsigned DW = 64
)
(
    input logic clk,
    input logic rst_n,

    output logic flag_is_unequal,
    input logic flag_clear,

    AXIS.slave s_axis[2]
);

    logic [DW-1:0] mask0, mask1;
    logic is_unequal, is_unequal_q, data_is_unequal, mask_is_unequal;

    assign flag_is_unequal = is_unequal | is_unequal_q;

    // synchronize both streams
    assign s_axis[0].tready = s_axis[1].tvalid;
    assign s_axis[1].tready = s_axis[0].tvalid;

    for (genvar i=0; i<DW/8; i++) begin
        assign mask0[8*i +: 8] = {8{s_axis[0].tkeep[i]}};
        assign mask1[8*i +: 8] = {8{s_axis[1].tkeep[i]}};
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            is_unequal_q <= 1'b0;
        end else begin
            if (flag_clear) begin
                is_unequal_q <= 1'b0;
            end else begin
                if ( `AXIS_TRANS(s_axis[0]) && `AXIS_TRANS(s_axis[1]) ) begin
                    is_unequal_q <= is_unequal_q | is_unequal;
                end
            end
        end
    end

    assign is_unequal = (`AXIS_TRANS(s_axis[0]) && `AXIS_TRANS(s_axis[1])) && ( data_is_unequal | mask_is_unequal);
    assign data_is_unequal = |((s_axis[0].tdata & mask0) ^ (s_axis[1].tdata & mask1));
    assign mask_is_unequal = |(mask0 ^ mask1);

endmodule
