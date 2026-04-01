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

module packing_unit
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    localparam int unsigned DATA_WIDTH = s_axis.DATA_WIDTH;
    AXIS #(.DATA_WIDTH(DATA_WIDTH), .TUSER_WIDTH(1)) m_axis_pack_int();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_int();

    //--------------------------------
    // PACKING module
    //--------------------------------
    cross_pack
    u_pack
    (
        .clk,
        .rst_n,
        .s_axis ( s_axis            ),
        .m_axis ( m_axis_pack_int   )
    );

    //--------------------------------
    // AXIS combiner
    //--------------------------------
    axis_combiner
    u_axis_combiner
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_pack_int   ),
        .m_axis ( m_axis            )
    );

endmodule
