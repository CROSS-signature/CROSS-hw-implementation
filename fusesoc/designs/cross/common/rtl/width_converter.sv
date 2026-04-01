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

module width_converter
#(
    parameter int ELEM_WIDTH = 8
)
(
    input logic axis_aclk,
    input logic axis_rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);

    localparam WIDTH_IN = s_axis.DATA_WIDTH;
    localparam WIDTH_OUT = m_axis.DATA_WIDTH;

    if (WIDTH_IN == WIDTH_OUT) begin : gen_bypass

        `AXIS_ASSIGN(m_axis, s_axis)

    end else if (WIDTH_IN > WIDTH_OUT) begin : gen_downscale

        downscale
        #(
            .ELEM_WIDTH (ELEM_WIDTH)
        ) u_downscale
        (
            .axis_aclk  ( axis_aclk     ),
            .axis_rst_n ( axis_rst_n    ),
            .s_axis     ( s_axis        ),
            .m_axis     ( m_axis        )
        );

    end else if (WIDTH_IN < WIDTH_OUT) begin : gen_upscale

        upscale
        #(
            .ELEM_WIDTH (ELEM_WIDTH)
        ) u_upscale
        (
            .axis_aclk  ( axis_aclk     ),
            .axis_rst_n ( axis_rst_n    ),
            .s_axis     ( s_axis        ),
            .m_axis     ( m_axis        )
        );

    end


endmodule
