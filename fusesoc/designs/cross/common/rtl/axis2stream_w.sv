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
`include "stream_w.sv"

/* The stream_w interface has the requirement that its 'bytes' signal
* must not be zero if is_last is high and thus we must compensate for that if last
* axis slice is fully filled.
* */
module axis2stream_w
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    stream_w.prod stream_w_prod
);

    AXIS #(.DATA_WIDTH(s_axis.DATA_WIDTH), .TUSER_WIDTH(s_axis.TUSER_WIDTH)) s_axis_int();

    /* In this interface having tkeep all ones is encoded as 0, so we actually don't need
    * the extra bit when counting and can ignore the carry out */
    logic [$clog2(s_axis_int.DATA_WIDTH/8)-1:0] popcnt_s_axis_tkeep;
    logic tlast_reg;

    if (s_axis_int.DATA_WIDTH != stream_w_prod.WORD_SZ)
        $error("s_axis_int.DATA_WIDTH and stream_w_prod.WORD_SZ must be equal!");

    // Used to generate 'initial ready'
    axis_reg #( .SPILL_REG(1) )
    u_axis_reg
    (
        .clk,
        .rst_n,
        .s_axis (s_axis     ),
        .m_axis (s_axis_int )
    );

    always_comb begin
        popcnt_s_axis_tkeep = '0;
        foreach(s_axis_int.tkeep[i])
            popcnt_s_axis_tkeep += $bits(popcnt_s_axis_tkeep)'(s_axis_int.tkeep[i]);
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            tlast_reg <= 1'b0;
        end else begin
            /* Set if last slice is full */
            if (s_axis_int.tvalid && s_axis_int.tready && s_axis_int.tlast && &s_axis_int.tkeep)
                tlast_reg <= s_axis_int.tlast;
            /* Reset if the word has been taken */
            if (tlast_reg && stream_w_prod.grant)
                tlast_reg <= 1'b0;
        end
    end

    assign stream_w_prod.data = s_axis_int.tdata;
    assign stream_w_prod.request = s_axis_int.tvalid | tlast_reg;
    assign s_axis_int.tready = stream_w_prod.grant & ~tlast_reg;
    assign stream_w_prod.bytes = popcnt_s_axis_tkeep;

    /* If last slice is fully filled, dont set is_last but tlast_reg in next cycle */
    assign stream_w_prod.is_last = (~&s_axis_int.tkeep && s_axis_int.tlast) | tlast_reg;

endmodule
