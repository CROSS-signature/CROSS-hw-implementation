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

module downscale
#(
    parameter ELEM_WIDTH = 8
)
(
    input logic axis_aclk,
    input logic axis_rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);


    localparam WIDTH_IN = s_axis.DATA_WIDTH;
    localparam WIDTH_OUT = m_axis.DATA_WIDTH;
    localparam MAX_CYCLES = WIDTH_IN / WIDTH_OUT;

    if ( (s_axis.DATA_WIDTH % ELEM_WIDTH) != 0 )
        $error ("s_axis.DATA_WIDTH (%d) must be multiple of ELEM_WIDTH (%d)!", s_axis.DATA_WIDTH, ELEM_WIDTH);

    if ( (m_axis.DATA_WIDTH % ELEM_WIDTH) != 0 )
        $error ("m_axis.DATA_WIDTH (%d) must be multiple of ELEM_WIDTH (%d)!", m_axis.DATA_WIDTH, ELEM_WIDTH);

    if ( (WIDTH_IN % WIDTH_OUT) != 0 )
        $error ("WIDTH_IN (%d) must be multiple of WIDTH_OUT (%d) for now!", WIDTH_IN, WIDTH_OUT);

    localparam W_CNT = $clog2(MAX_CYCLES);
    logic [W_CNT-1:0] cnt_s;

    logic [WIDTH_OUT/ELEM_WIDTH-1:0]  cur_keep_slice;
    logic [WIDTH_OUT/ELEM_WIDTH-1:0]  next_keep_slice;

    assign m_axis.tdata = s_axis.tdata[WIDTH_OUT*cnt_s +: WIDTH_OUT];
    assign m_axis.tkeep = cur_keep_slice;
    assign m_axis.tvalid = s_axis.tvalid;
    assign m_axis.tuser = s_axis.tuser;

    /* Define current and next output slice in valid input data to correctly assert tlast */
    assign cur_keep_slice   = s_axis.tkeep[WIDTH_OUT/ELEM_WIDTH*cnt_s +: WIDTH_OUT/ELEM_WIDTH];
    assign next_keep_slice  = (cnt_s < W_CNT'(MAX_CYCLES - 1)) ? s_axis.tkeep[WIDTH_OUT/ELEM_WIDTH*(cnt_s+1) +: WIDTH_OUT/ELEM_WIDTH] : '1;

    /* Either cnt is at limit, current slice has at least one zero (signals last slice), or the next slice is completely empty */
    assign m_axis.tlast = ( (cnt_s >= W_CNT'(MAX_CYCLES - 1)) || (&cur_keep_slice == 1'b0) || (|next_keep_slice == 1'b0) ) ? s_axis.tlast : 1'b0;

    /* Either cnt is at limit or we output the last slice */
    assign s_axis.tready = ( (cnt_s >= W_CNT'(MAX_CYCLES - 1)) || (m_axis.tvalid && m_axis.tlast) ) ? m_axis.tready : 1'b0;

    /* counter  */
    always_ff @(posedge axis_aclk)
    begin
        if (!axis_rst_n)
            cnt_s <= '0;
        else begin
            if (m_axis.tvalid && m_axis.tready) begin
                if (cnt_s >= W_CNT'(MAX_CYCLES - 1) || m_axis.tlast)
                    cnt_s <= '0;
                else
                    cnt_s <= cnt_s + W_CNT'(1);
            end
        end
    end

endmodule
