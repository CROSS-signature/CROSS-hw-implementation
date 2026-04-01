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

module tb_zk_sample
    import cross_pkg::*;
#(
    parameter int unsigned PAR_ELEMS    = 1,
    parameter int unsigned DATA_WIDTH   = 64
)
(
    input logic clk,
    input logic rst_n,

    input logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input logic [DATA_WIDTH/8-1:0]      s_axis_tkeep,
    input logic                         s_axis_tvalid,
    output logic                        s_axis_tready,
    input logic                         s_axis_tlast,

    output logic [BITS_Z*PAR_ELEMS-1:0] m_axis_tdata,
    output logic [PAR_ELEMS-1:0]        m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input logic                         m_axis_tready,
    output logic                        m_axis_tlast
);

    AXIS #(.DATA_WIDTH(BITS_Z*PAR_ELEMS), .ELEM_WIDTH(BITS_Z)) m_axis();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis();

    zk_sample
    #(
        .MOD_K      ( Z         ),
        .PAR_ELEMS  ( PAR_ELEMS )
    )
    u_dut
    (
        .clk,
        .rst_n,
        .s_axis ( s_axis ),
        .m_axis ( m_axis )
    );

    `AXIS_EXPORT_MASTER(m_axis);
    `AXIS_EXPORT_SLAVE(s_axis);

endmodule
