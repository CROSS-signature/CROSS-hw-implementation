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

module tb_sample_unit
    import sample_unit_pkg::*;
#(
    parameter int unsigned DATA_WIDTH = 64,
    parameter int unsigned KECCAK_UNROLL_FACTOR = 2,
`ifdef FAST
    localparam int unsigned MAX_TRANSFERS = cross_pkg::T/4 + 1
`else
    localparam int unsigned MAX_TRANSFERS = 2
`endif
)
(
    input logic                             clk,
    input logic                             rst_n,


    input sample_op_t                       mode,
    input digest_t                          digest_type,
    input logic [$clog2(MAX_TRANSFERS):0]   n_digests,
    input logic                             mode_valid,
    output logic                            mode_ready,

    /* Interface for prng seed or hash input */
    input logic [DATA_WIDTH-1:0]        s_axis_sha3_tdata,
    input logic [DATA_WIDTH/8-1:0]      s_axis_sha3_tkeep,
    input logic                         s_axis_sha3_tvalid,
    output logic                        s_axis_sha3_tready,
    input logic                         s_axis_sha3_tlast,

    output logic [DATA_WIDTH-1:0]       m_axis_0_tdata,
    output logic [DATA_WIDTH/8-1:0]     m_axis_0_tkeep,
    output logic                        m_axis_0_tvalid,
    input logic                         m_axis_0_tready,
    output logic                        m_axis_0_tlast,

    output logic [DATA_WIDTH-1:0]       m_axis_1_tdata,
    output logic [DATA_WIDTH/8-1:0]     m_axis_1_tkeep,
    output logic                        m_axis_1_tvalid,
    input logic                         m_axis_1_tready,
    output logic                        m_axis_1_tlast,

    /* Dedicated interface for matrix v and beta */
    output logic [cross_pkg::BITS_P-1:0]    m_axis_v_beta_tdata,
    output logic                            m_axis_v_beta_tkeep,
    output logic                            m_axis_v_beta_tvalid,
    input logic                             m_axis_v_beta_tready,
    output logic                            m_axis_v_beta_tlast,

    /* Dedicated interface for matrix w */
    output logic [cross_pkg::BITS_Z-1:0]    m_axis_w_tdata,
    output logic                            m_axis_w_tkeep,
    output logic                            m_axis_w_tvalid,
    input logic                             m_axis_w_tready,
    output logic                            m_axis_w_tlast,

    /* Dedicated interface for challenge b */
    output logic                            m_axis_b_tdata,
    output logic                            m_axis_b_tvalid,
    input logic                             m_axis_b_tready,
    output logic                            m_axis_b_tlast
);

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_0(), m_axis_1();
    AXIS #(.DATA_WIDTH(1)) m_axis_b();

    AXIS #(.DATA_WIDTH(cross_pkg::BITS_Z)) m_axis_w();
    AXIS #(.DATA_WIDTH(cross_pkg::BITS_P)) m_axis_v_beta();

	sample_unit #(
        .KECCAK_UNROLL_FACTOR(KECCAK_UNROLL_FACTOR)
    )
	u_sample_unit
	(
		.clk,
		.rst_n,
        .digest_type,
        .n_digests,
		.mode,
		.mode_valid,
		.mode_ready,
        .s_axis(s_axis),
		.m_axis_0(m_axis_0),
		.m_axis_1(m_axis_1),
		.m_axis_v_beta(m_axis_v_beta),
		.m_axis_w(m_axis_w),
		.m_axis_b(m_axis_b)
	);

    assign s_axis.tdata = s_axis_sha3_tdata;
    assign s_axis.tkeep = s_axis_sha3_tkeep;
    assign s_axis.tvalid = s_axis_sha3_tvalid;
    assign s_axis_sha3_tready = s_axis.tready;
    assign s_axis.tlast = s_axis_sha3_tlast;

	assign m_axis_0_tdata = m_axis_0.tdata;
	assign m_axis_0_tkeep = m_axis_0.tkeep;
	assign m_axis_0_tvalid = m_axis_0.tvalid;
	assign m_axis_0.tready = m_axis_0_tready;
	assign m_axis_0_tlast = m_axis_0.tlast;

	assign m_axis_1_tdata = m_axis_1.tdata;
	assign m_axis_1_tkeep = m_axis_1.tkeep;
	assign m_axis_1_tvalid = m_axis_1.tvalid;
	assign m_axis_1.tready = m_axis_1_tready;
	assign m_axis_1_tlast = m_axis_1.tlast;

	assign m_axis_v_beta_tdata = m_axis_v_beta.tdata;
	assign m_axis_v_beta_tkeep = m_axis_v_beta.tkeep;
	assign m_axis_v_beta_tvalid = m_axis_v_beta.tvalid;
	assign m_axis_v_beta.tready = m_axis_v_beta_tready;
	assign m_axis_v_beta_tlast = m_axis_v_beta.tlast;

	assign m_axis_w_tdata = m_axis_w.tdata;
	assign m_axis_w_tkeep = m_axis_w.tkeep;
	assign m_axis_w_tvalid = m_axis_w.tvalid;
	assign m_axis_w.tready = m_axis_w_tready;
	assign m_axis_w_tlast = m_axis_w.tlast;

	assign m_axis_b_tdata = m_axis_b.tdata;
	assign m_axis_b_tvalid = m_axis_b.tvalid;
	assign m_axis_b.tready = m_axis_b_tready;
	assign m_axis_b_tlast = m_axis_b.tlast;

endmodule
