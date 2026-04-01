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

module tb_decompress
    import packing_unit_pkg::*;
#(
    parameter int unsigned DATA_WIDTH = 64
)
(
    input logic clk,
    input logic rst_n,

    input decomp_mode_t mode,
    input logic mode_valid,
    output logic mode_ready,

    output logic fz_error,
    output logic pad_rsp0_error,
    input logic error_clear,

    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
    input logic s_axis_tvalid,
    output logic s_axis_tready,
    input logic s_axis_tlast,
    input logic [2:0] s_axis_tuser,

    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic m_axis_tvalid,
    input logic m_axis_tready,
    output logic m_axis_tlast,
    output logic [2:0] m_axis_tuser
);

    AXIS #(.DATA_WIDTH(DATA_WIDTH), .TUSER_WIDTH(3)) s_axis(), m_axis();

    unpacking_unit
    u_dut
    (
        .clk,
        .rst_n,

        .mode,
        .mode_valid,
        .mode_ready,

        .fz_error,
        .pad_rsp0_error,
        .error_clear,

        .s_axis ( s_axis ),
        .m_axis ( m_axis )
    );

    `AXIS_EXPORT_SLAVE(s_axis)
    assign s_axis.tuser = s_axis_tuser;

    `AXIS_EXPORT_MASTER(m_axis)
    assign m_axis_tuser = m_axis.tuser;

endmodule
