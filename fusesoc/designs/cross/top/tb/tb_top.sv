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

module tb_top
    import cross_pkg::*;
#(
    parameter int unsigned DATA_WIDTH = 64,
    parameter int unsigned KECCAK_UNROLL_FACTOR = 2,
    parameter int unsigned MAT_DATA_WIDTH = 712,
    parameter bit TEST_EN = 1'b1
)
(
    input logic clk,
    input logic rst_n,

    input cross_opcode_t            cross_op,
    input logic                     cross_op_valid,
    output logic                    cross_op_ready,
    output logic                    cross_op_done,
    output logic                    cross_op_done_val,

    input logic [DATA_WIDTH-1:0]    s_axis_rng_tdata,
    input logic [DATA_WIDTH/8-1:0]  s_axis_rng_tkeep,
    input logic                     s_axis_rng_tvalid,
    output logic                    s_axis_rng_tready,
    input logic                     s_axis_rng_tlast,

    input logic [DATA_WIDTH-1:0]    s_axis_msg_keys_tdata,
    input logic [DATA_WIDTH/8-1:0]  s_axis_msg_keys_tkeep,
    input logic                     s_axis_msg_keys_tvalid,
    output logic                    s_axis_msg_keys_tready,
    input logic                     s_axis_msg_keys_tlast,

    input logic [DATA_WIDTH-1:0]    s_axis_sig_tdata,
    input logic [DATA_WIDTH/8-1:0]  s_axis_sig_tkeep,
    input logic                     s_axis_sig_tvalid,
    output logic                    s_axis_sig_tready,
    input logic                     s_axis_sig_tlast,

    output logic [DATA_WIDTH-1:0]   m_axis_sig_keys_tdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_sig_keys_tkeep,
    output logic                    m_axis_sig_keys_tvalid,
    input logic                     m_axis_sig_keys_tready,
    output logic                    m_axis_sig_keys_tlast
);
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_rng();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_msg_keys();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_sig();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_sig_keys();

    cross_top
    #(
        .DW(DATA_WIDTH),
        .KECCAK_UNROLL_FACTOR(KECCAK_UNROLL_FACTOR),
        .MAT_DATA_WIDTH(MAT_DATA_WIDTH),
        .TEST_EN(TEST_EN)
    )
    u_top
    (
        .clk,
        .rst_n,
        .cross_op,
        .cross_op_valid,
        .cross_op_ready,
        .cross_op_done,
        .cross_op_done_val,
        .s_axis_rng         ( s_axis_rng        ),
        .s_axis_msg_keys    ( s_axis_msg_keys   ),
        .s_axis_sig         ( s_axis_sig        ),
        .m_axis_sig_keys    ( m_axis_sig_keys   )
    );

    `AXIS_EXPORT_SLAVE(s_axis_rng);
    `AXIS_EXPORT_SLAVE(s_axis_msg_keys);
    `AXIS_EXPORT_SLAVE(s_axis_sig);
    `AXIS_EXPORT_MASTER(m_axis_sig_keys);

endmodule
