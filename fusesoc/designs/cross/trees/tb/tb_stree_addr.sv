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

module tb_stree_addr
    import stree_pkg::*;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned WORDS_PER_SEED = cross_pkg::BYTES_SEED / (DATA_WIDTH/8),
    localparam int unsigned AW_INT = $clog2(2*cross_pkg::T - 1),
    localparam int unsigned ADDR_WIDTH = $clog2( (2*cross_pkg::T-1)*WORDS_PER_SEED ),
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    output logic regen_done,
    output logic regen_is_leaf,
    output logic regen_fetch_path,

    output logic [$clog2(cross_pkg::TREE_NODES_TO_STORE)-1:0] sig_ctrl_path_cnt,
    output logic sig_ctrl_path_cnt_valid,
    output logic sig_ctrl_stree_done,
    input logic sig_ctrl_sign_done,
    output logic sig_ctrl_stree_vrfy_done,
    output logic stree_leaves_done,
    output logic [AW_INT-1:0] parent_idx,

    input stree_opcode_t    op,
    input logic             op_valid,
    output logic            op_ready,

    output logic [ADDR_WIDTH-1:0]   addr,
    output logic                    addr_is_path,
    output logic                    addr_we,
    output logic                    addr_valid,
    input logic                     addr_ready,
    output logic                    addr_last_seed,
    output logic [W_FCNT-1:0]       addr_frame_cnt,
    output logic                    flag_last,

    output logic [AW_INT-1:0]       path_addr,
    output logic                    path_addr_valid,
    output logic                    path_last,

    input logic  [8-1:0]            s_axis_ch_tdata,
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
        .DEPTH( 2*cross_pkg::T - 1 )
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

    stree_addr
    #(
        .DATA_WIDTH( DATA_WIDTH )
    )
    u_stree_addr
    (
        .clk,
        .rst_n,
        .op,
        .op_valid,
        .op_ready,
        .sig_ctrl_stree_done,
        .sig_ctrl_sign_done,
        .sig_ctrl_stree_vrfy_done,
        .sig_ctrl_path_cnt,
        .sig_ctrl_path_cnt_valid,
        .stree_leaves_done,
        .parent_idx,
        .regen_done,
        .regen_is_leaf,
        .regen_fetch_path,
        .path_addr,
        .path_addr_valid,
        .path_last,
        .flag_addr,
        .flag_we,
        .flag_bit_wr,
        .flag_bit_rd,
        .flag_last,
        .addr,
        .addr_is_path,
        .addr_we,
        .addr_valid,
        .addr_ready,
        .addr_last_seed,
        .addr_frame_cnt,

        .s_axis_ch (s_axis_ch)
    );

    assign s_axis_ch.tdata = s_axis_ch_tdata[0];
    assign s_axis_ch.tvalid = s_axis_ch_tvalid;
    assign s_axis_ch_tready = s_axis_ch.tready;
    assign s_axis_ch.tlast = s_axis_ch_tlast;

endmodule
