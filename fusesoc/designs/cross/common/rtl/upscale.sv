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

module upscale
#(
    parameter int unsigned ELEM_WIDTH = 8
)
(
    input logic axis_aclk,
    input logic axis_rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);

    if ( (s_axis.DATA_WIDTH % ELEM_WIDTH) != 0 )
        $error ("s_axis.DATA_WIDTH (%d) must be multiple of ELEM_WIDTH (%d)!", s_axis.DATA_WIDTH, ELEM_WIDTH);

    if ( (m_axis.DATA_WIDTH % ELEM_WIDTH) != 0 )
        $error ("m_axis.DATA_WIDTH (%d) must be multiple of ELEM_WIDTH (%d)!", m_axis.DATA_WIDTH, ELEM_WIDTH);

    if ( (m_axis.DATA_WIDTH % s_axis.DATA_WIDTH) != 0 )
        $error ("m_axis.DATA_WIDTH (%d) must be multiple of s_axis.DATA_WIDTH (%d) for now!", m_axis.DATA_WIDTH, s_axis.DATA_WIDTH);

    localparam int unsigned WIDTH_IN = s_axis.DATA_WIDTH;
    localparam int unsigned WIDTH_OUT = m_axis.DATA_WIDTH;
    localparam int unsigned MAX_CYCLES = WIDTH_OUT / WIDTH_IN;

    logic [$clog2(MAX_CYCLES)-1:0] cnt_s;

    logic [WIDTH_OUT-WIDTH_IN-1:0]              data_reg_s;
    logic [(WIDTH_OUT-WIDTH_IN)/ELEM_WIDTH-1:0] keep_reg_s;


    /* Mux with counter */
    assign m_axis.tvalid = !axis_rst_n ? 1'b0 : (cnt_s >= $bits(cnt_s)'(MAX_CYCLES - 1) || (s_axis.tlast && s_axis.tvalid)) ? s_axis.tvalid : 1'b0;
    assign s_axis.tready = !axis_rst_n ? 1'b0 : (cnt_s >= $bits(cnt_s)'(MAX_CYCLES - 1) || (s_axis.tlast && s_axis.tvalid)) ? m_axis.tready : 1'b1;
    assign m_axis.tlast = s_axis.tlast;

    /* Since there is no notion of how large tuser is per byte, it's defined
    * in this implementation that tuser is the same for all words of an axis
    * frame */
    assign m_axis.tuser = s_axis.tuser;

    /* data mux */
    always_comb begin
        m_axis.tdata = 'b0;
        m_axis.tdata[WIDTH_OUT-WIDTH_IN-1:0] = data_reg_s;
        m_axis.tdata[WIDTH_IN*cnt_s +: WIDTH_IN] = s_axis.tdata;
    end

    /* keep mux */
    always_comb begin
        m_axis.tkeep = {{(WIDTH_IN/ELEM_WIDTH){'0}}, keep_reg_s};
        m_axis.tkeep[(WIDTH_IN/ELEM_WIDTH)*cnt_s +: WIDTH_IN/ELEM_WIDTH] = s_axis.tkeep;
    end

    /* build register keep */
    always_ff @(posedge axis_aclk)
    begin
        if (!axis_rst_n)
            keep_reg_s <= '0;
        else begin
            if (s_axis.tvalid && s_axis.tready) begin
                if (cnt_s < $bits(cnt_s)'(MAX_CYCLES - 1))
                    keep_reg_s[(WIDTH_IN/ELEM_WIDTH)*cnt_s +: WIDTH_IN/ELEM_WIDTH] <= s_axis.tkeep;
                else
                    keep_reg_s <= '0;
            end
        end
    end

    /* build register data */
    always_ff @(posedge axis_aclk)
    begin
        if (s_axis.tvalid && s_axis.tready) begin
            if (cnt_s < $bits(cnt_s)'(MAX_CYCLES - 1))
                data_reg_s[WIDTH_IN*cnt_s +: WIDTH_IN] <= s_axis.tdata;
        end
    end

    /* counter to switch mux */
    always_ff @(posedge axis_aclk)
    begin
        if (!axis_rst_n)
            cnt_s <= '0;
        else begin
            if (s_axis.tvalid && s_axis.tready) begin
                if (cnt_s >= $bits(cnt_s)'(MAX_CYCLES - 1) || s_axis.tlast)
                    cnt_s <= '0;
                else
                    cnt_s <= cnt_s + 1;
            end
        end
    end

endmodule
