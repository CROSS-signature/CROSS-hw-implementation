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

module cross_tree_wrapper
    import tree_unit_pkg::tree_unit_opcode_t;
    import sample_unit_pkg::digest_t;
    import cross_pkg::MAX_DIGESTS;
#(
    parameter int unsigned DW = 64,
    localparam int unsigned W_TRANS = $clog2(MAX_DIGESTS) + 1,
	localparam int unsigned AW_INT_STREE = $clog2(2*cross_pkg::T - 1)
)
(
    input logic clk,
    input logic rst_n,

    input tree_unit_opcode_t        op,
    input logic                     op_valid,
    output logic                    op_ready,

    output digest_t                 digest_size,
    output logic [W_TRANS-1:0]      n_digests,
    output logic [AW_INT_STREE-1:0] stree_parent_idx,
    output logic                    stree_tree_computed,

    output logic                    sign_done,
    output logic                    vrfy_done,
    output logic                    vrfy_stree_done,
    output logic                    vrfy_mtree_done,
    output logic                    vrfy_pad_err,
    input logic                     vrfy_pad_err_clear,

    input logic                     sel_mux_i0,
    AXIS.slave                      s_axis_i0[2],
    AXIS.master                     m_axis,

    AXIS.slave                      s_axis_b,
    AXIS.slave                      s_axis_sig,
    AXIS.master                     m_axis_sig
);

    AXIS #(.DATA_WIDTH(DW)) m_axis_mux(), s_axis_tree(), m_axis_tree();

	// -----------------------------------------------
	// TREE UNIT instance
	// -----------------------------------------------
`ifdef FAST
    no_tree_unit
`else
    tree_unit
`endif
    #(
        .DATA_WIDTH ( DW )
    )
    u_tree_unit
    (
        .clk,
        .rst_n,
        .op,
        .op_valid,
        .op_ready,
        .stree_parent_idx,
        .stree_tree_computed,
        .sign_done,
        .vrfy_done,
        .vrfy_stree_done,
        .vrfy_mtree_done,
        .vrfy_pad_err,
        .vrfy_pad_err_clear,
        .digest_size,
        .n_digests,
        .s_axis             ( s_axis_tree   ),
        .m_axis             ( m_axis_tree   ),
        .s_axis_sig         ( s_axis_sig    ),
        .m_axis_sig         ( m_axis_sig    ),
        .s_axis_ch          ( s_axis_b      )
    );

	// -----------------------------------------------
	// INPUT MUX
	// -----------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_mux
    (
        .sel    ( sel_mux_i0    ),
        .s_axis ( s_axis_i0     ),
        .m_axis ( m_axis_mux    )
    );

	// -----------------------------------------------
	// IO registers only for RSDP(G) small
	// -----------------------------------------------
`ifdef RSDPG
    `ifdef SMALL
        axis_reg #( .SPILL_REG(1) )
        u_axis_reg_in
        (
            .clk,
            .rst_n,
            .s_axis( m_axis_mux     ),
            .m_axis( s_axis_tree    )
        );

        axis_reg #( .SPILL_REG(1) )
        u_axis_reg_out
        (
            .clk,
            .rst_n,
            .s_axis( m_axis_tree    ),
            .m_axis( m_axis         )
        );
    `else
        `AXIS_ASSIGN(s_axis_tree, m_axis_mux);
        assign s_axis_tree.tuser = m_axis_mux.tuser;

        `AXIS_ASSIGN(m_axis, m_axis_tree);
        assign m_axis.tuser = m_axis_tree.tuser;
    `endif
`else
    `ifdef CATEGORY_3
        axis_reg #( .SPILL_REG(1) )
        u_axis_reg_in
        (
            .clk,
            .rst_n,
            .s_axis( m_axis_mux     ),
            .m_axis( s_axis_tree    )
        );

        axis_reg #( .SPILL_REG(1) )
        u_axis_reg_out
        (
            .clk,
            .rst_n,
            .s_axis( m_axis_tree    ),
            .m_axis( m_axis         )
        );
    `else
        `AXIS_ASSIGN(s_axis_tree, m_axis_mux);
        assign s_axis_tree.tuser = m_axis_mux.tuser;

        `AXIS_ASSIGN(m_axis, m_axis_tree);
        assign m_axis.tuser = m_axis_tree.tuser;
    `endif
`endif

endmodule
