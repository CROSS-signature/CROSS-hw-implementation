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

module tb_no_tree
    import tree_unit_pkg::*;
#(
    parameter DATA_WIDTH = 64,
	localparam int unsigned AW_INT_STREE = $clog2(2*cross_pkg::T - 1),
`ifdef FAST
    localparam int unsigned MAX_NUM_DIGESTS = cross_pkg::T/4 + 1
`else
    localparam int unsigned MAX_NUM_DIGESTS = 2
`endif
)
(
	input logic clk,
	input logic rst_n,

    input tree_unit_opcode_t                    op,
    input logic                                 op_valid,
    output logic                                op_ready,

    output logic [AW_INT_STREE-1:0]             stree_parent_idx,
    output logic                                stree_tree_computed,
    output logic                                sign_done,
    output logic                                vrfy_done,
    output logic                                vrfy_stree_done,
    output logic                                vrfy_mtree_done,
    output logic                                vrfy_pad_err,
    input logic                                 vrfy_pad_err_clear,

    output sample_unit_pkg::digest_t            digest_size,
    output logic [$clog2(MAX_NUM_DIGESTS):0]    n_digests,

    input logic [DATA_WIDTH-1:0]                s_axis_tdata,
    input logic [DATA_WIDTH/8-1:0]              s_axis_tkeep,
    input logic                                 s_axis_tvalid,
    output logic                                s_axis_tready,
    input logic                                 s_axis_tlast,

    output logic [DATA_WIDTH-1:0]               m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0]             m_axis_tkeep,
    output logic                                m_axis_tvalid,
    input logic                                 m_axis_tready,
    output logic                                m_axis_tlast,

    input logic [DATA_WIDTH-1:0]                s_axis_sig_tdata,
    input logic [DATA_WIDTH/8-1:0]              s_axis_sig_tkeep,
    input logic                                 s_axis_sig_tvalid,
    output logic                                s_axis_sig_tready,
    input logic                                 s_axis_sig_tlast,

    output logic [DATA_WIDTH-1:0]               m_axis_sig_tdata,
    output logic [DATA_WIDTH/8-1:0]             m_axis_sig_tkeep,
    output logic                                m_axis_sig_tvalid,
    input logic                                 m_axis_sig_tready,
    output logic                                m_axis_sig_tlast,

    // 8-bit for test
    input logic [7:0]                           s_axis_ch_tdata,
    input logic                                 s_axis_ch_tvalid,
    output logic                                s_axis_ch_tready,
    input logic                                 s_axis_ch_tlast
);

    AXIS #( .DATA_WIDTH(1) ) s_axis_ch();
    AXIS #( .DATA_WIDTH(DATA_WIDTH) ) s_axis(), m_axis(), s_axis_sig(), m_axis_sig();

    no_tree_unit
    u_no_tree_unit
    (
        .clk,
        .rst_n,
        .op,
        .op_valid,
        .op_ready,
        .sign_done,
        .vrfy_done,
        .vrfy_stree_done,
        .vrfy_mtree_done,
        .vrfy_pad_err,
        .vrfy_pad_err_clear,
        .stree_tree_computed,
        .stree_parent_idx,
        .digest_size,
        .n_digests,
        .s_axis         ( s_axis        ),
        .m_axis         ( m_axis        ),
        .s_axis_sig     ( s_axis_sig    ),
        .m_axis_sig     ( m_axis_sig    ),
        .s_axis_ch      ( s_axis_ch     )
    );

    assign s_axis_ch.tdata = s_axis_ch_tdata[0];
    assign s_axis_ch.tvalid = s_axis_ch_tvalid;
    assign s_axis_ch_tready = s_axis_ch.tready;
    assign s_axis_ch.tlast = s_axis_ch_tlast;

    `AXIS_EXPORT_SLAVE(s_axis_sig)
    `AXIS_EXPORT_MASTER(m_axis_sig)

    `AXIS_EXPORT_SLAVE(s_axis)
    `AXIS_EXPORT_MASTER(m_axis)

endmodule
