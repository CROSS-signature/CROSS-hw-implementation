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

module tb_mtree_addr
    import mtree_pkg::*;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned WORDS_PER_HASH = cross_pkg::BYTES_HASH / (DATA_WIDTH/8),
    localparam int unsigned ADDR_WIDTH = $clog2((2*cross_pkg::T-1)*WORDS_PER_HASH),
    localparam int unsigned AW_INT = $clog2(2*cross_pkg::T-1)
)
(
    input logic clk,
    input logic rst_n,

    input mtree_opcode_t    op,
    input logic             op_valid,
    output logic            op_ready,

    output logic sig_ctrl_mtree_done,
    output logic sig_ctrl_mtree_vrfy_done,
    output logic sig_ctrl_proof_cnt_valid,
    input logic sig_ctrl_sign_done,
    output logic [$clog2(cross_pkg::TREE_NODES_TO_STORE)-1:0] sig_ctrl_proof_cnt,

    output logic [ADDR_WIDTH-1:0]   addr,
    output logic                    addr_is_proof,
    output logic                    addr_we,
    output logic                    addr_valid,
    input logic                     addr_ready,
    output logic [$clog2(2+1)-1:0]  addr_frame_cnt,
    output logic                    flag_last,

    output logic [AW_INT-1:0]       proof_addr,
    output logic                    proof_addr_valid,

    input logic [7:0]               s_axis_ch_tdata,
    input logic                     s_axis_ch_tvalid,
    output logic                    s_axis_ch_tready,
    input logic                     s_axis_ch_tlast
);

    logic flag_bit_wr, flag_bit_rd, flag_we;
    logic [7:0] flag_bit_wr_tmp, flag_bit_rd_tmp;

    logic [AW_INT-1:0] flag_addr;

    assign flag_bit_wr_tmp = 8'(flag_bit_wr);
    assign flag_bit_rd = flag_bit_rd_tmp[0];

    sp_ram
    #(
        .DATA_WIDTH(8),
        .DEPTH(2*cross_pkg::T - 1)
    )
    u_test_ram
    (
        .clk,
        .en_i       ( 1'b1          ),
        .we_i       ( flag_we       ),
        .addr_i     ( flag_addr     ),
        .wdata_i    ( flag_bit_wr_tmp   ),
        .rdata_o    ( flag_bit_rd_tmp   )
    );

    AXIS #( .DATA_WIDTH(1) ) s_axis_ch();

    mtree_addr
    #(
        .DATA_WIDTH( DATA_WIDTH )
    )
    u_mtree_addr
    (
        .clk,
        .rst_n,
        .op,
        .op_valid,
        .op_ready,
        .sig_ctrl_mtree_done,
        .sig_ctrl_mtree_vrfy_done,
        .sig_ctrl_proof_cnt_valid,
        .sig_ctrl_proof_cnt,
        .sig_ctrl_sign_done,
        .proof_addr,
        .proof_addr_valid,
        .flag_addr,
        .flag_we,
        .flag_bit_wr,
        .flag_bit_rd,
        .flag_last,
        .addr,
        .addr_is_proof,
        .addr_we,
        .addr_valid,
        .addr_ready,
        .addr_frame_cnt,

        .s_axis_ch (s_axis_ch)
    );

    assign s_axis_ch.tdata = s_axis_ch_tdata[0];
    assign s_axis_ch.tvalid = s_axis_ch_tvalid;
    assign s_axis_ch_tready = s_axis_ch.tready;
    assign s_axis_ch.tlast = s_axis_ch_tlast;

endmodule
