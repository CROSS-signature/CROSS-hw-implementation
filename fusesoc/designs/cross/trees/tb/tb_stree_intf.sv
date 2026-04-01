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

module tb_stree_intf
    import stree_pkg::*;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned WORDS_PER_SEED = cross_pkg::BYTES_SEED / (DATA_WIDTH/8),
    localparam int unsigned AW_INT = $clog2(2*cross_pkg::T-1),
    localparam int unsigned ADDR_WIDTH = $clog2((2*cross_pkg::T-1)*WORDS_PER_SEED)
)
(
    input logic clk,
    input logic rst_n,

    input stree_opcode_t            op,
    input logic                     op_valid,
    output logic                    op_ready,

    input logic                     sign_done,

    output logic [AW_INT-1:0]       path_addr,
    output logic                    path_addr_valid,
    output logic                    path_last,
    output logic                    flag_last,

    input logic [DATA_WIDTH-1:0]    s_axis_sig_tdata,
    input logic [DATA_WIDTH/8-1:0]  s_axis_sig_tkeep,
    input logic                     s_axis_sig_tvalid,
    output logic                    s_axis_sig_tready,
    input logic                     s_axis_sig_tlast,

    output logic [DATA_WIDTH-1:0]   m_axis_sig_tdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_sig_tkeep,
    output logic                    m_axis_sig_tvalid,
    input logic                     m_axis_sig_tready,
    output logic                    m_axis_sig_tlast,

    input logic [DATA_WIDTH-1:0]    s_axis_tdata,
    input logic [DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input logic                     s_axis_tvalid,
    output logic                    s_axis_tready,
    input logic                     s_axis_tlast,

    output logic [DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                    m_axis_tvalid,
    input logic                     m_axis_tready,
    output logic                    m_axis_tlast,

    // 8-bit for test
    input logic [7:0]               s_axis_ch_tdata,
    input logic                     s_axis_ch_tvalid,
    output logic                    s_axis_ch_tready,
    input logic                     s_axis_ch_tlast,

    output logic                    regen_done,
    output logic                    regen_is_leaf
);

    logic flag_bit_wr, flag_bit_rd, flag_we;
    logic [7:0] flag_bit_wr_tmp, flag_bit_rd_tmp;

    logic [AW_INT-1:0] flag_addr;

    logic [ADDR_WIDTH-1:0]  ctrl_addr;
    logic                   ctrl_addr_we;
    logic                   ctrl_addr_valid;
    logic                   ctrl_addr_ready;

    logic [ADDR_WIDTH-1:0]  sig_addr;
    logic                   sig_addr_we;
    logic                   sig_addr_valid;
    logic                   sig_addr_ready;

    localparam int unsigned W_FCNT = $clog2(2 + 1);
    logic [W_FCNT-1:0] ctrl_addr_frame_cnt, sig_addr_frame_cnt;

    logic                               stree_mem_en;
    logic [ADDR_WIDTH-1:0]              stree_mem_addr;
    logic [DATA_WIDTH/8-1:0]            stree_mem_we;
    logic [DATA_WIDTH+DATA_WIDTH/8-1:0] stree_mem_wdata, stree_mem_rdata;

    logic stree_done, addr_is_path, vrfy_copy_leaf;

    AXIS #( .DATA_WIDTH(1) ) s_axis_ch();
    AXIS #( .DATA_WIDTH(DATA_WIDTH) ) s_axis(), m_axis(), s_axis_sig(), m_axis_sig();

    logic unused;
    assign unused = |sig_addr_ready;

    assign sig_addr = '0;
    assign sig_addr_we = '0;
    assign sig_addr_valid = '0;
    assign sig_addr_frame_cnt = '0;

    assign flag_bit_wr_tmp = 8'(flag_bit_wr);
    assign flag_bit_rd = flag_bit_rd_tmp[0];

    stree_addr
    #(
        .DATA_WIDTH ( DATA_WIDTH    )
    )
    u_stree_addr
    (
        .clk,
        .rst_n,
        .sig_ctrl_path_cnt          (                       ),
        .sig_ctrl_path_cnt_valid    (                       ),
        .sig_ctrl_stree_done        ( stree_done            ),
        .sig_ctrl_sign_done         ( sign_done             ),
        .sig_ctrl_stree_vrfy_done   (                       ),
        .stree_leaves_done          (                       ),
        .regen_done,
        .regen_is_leaf,
        .regen_fetch_path           ( vrfy_copy_leaf        ),
        .op,
        .op_valid,
        .op_ready,
        .flag_addr,
        .flag_bit_wr,
        .flag_we,
        .flag_bit_rd,
        .flag_last,
        .path_addr,
        .path_addr_valid,
        .path_last,
        .addr                       ( ctrl_addr             ),
        .addr_is_path               ( addr_is_path          ),
        .addr_we                    ( ctrl_addr_we          ),
        .addr_valid                 ( ctrl_addr_valid       ),
        .addr_ready                 ( ctrl_addr_ready       ),
        .addr_last_seed             (                       ),
        .addr_frame_cnt             ( ctrl_addr_frame_cnt   ),

        .s_axis_ch ( s_axis_ch )
    );

    stree_su_intf
    #(
        .DATA_WIDTH ( DATA_WIDTH ),
        .ADDR_WIDTH ( ADDR_WIDTH )
    )
    u_stree_su_intf
    (
        .clk,
        .rst_n,
        .stree_sign_done            ( stree_done            ),
        .stree_vrfy_addr_is_path    ( addr_is_path          ), // verify only, node is moved from signature to sample unit
        .stree_vrfy_copy_leaf       ( vrfy_copy_leaf        ), // verify only, node is moved from signature to seed tree
        .mem_en                     ( stree_mem_en          ),
        .mem_addr                   ( stree_mem_addr        ),
        .mem_we                     ( stree_mem_we          ),
        .mem_wdata                  ( stree_mem_wdata       ),
        .mem_rdata                  ( stree_mem_rdata       ),
        .ctrl_addr                  ( ctrl_addr             ),
        .ctrl_addr_we               ( ctrl_addr_we          ),
        .ctrl_addr_valid            ( ctrl_addr_valid       ),
        .ctrl_addr_ready            ( ctrl_addr_ready       ),
        .ctrl_addr_frame_cnt        ( ctrl_addr_frame_cnt   ),
        .sig_addr                   ( sig_addr              ),
        .sig_addr_we                ( sig_addr_we           ),
        .sig_addr_valid             ( sig_addr_valid        ),
        .sig_addr_ready             ( sig_addr_ready        ),
        .sig_addr_frame_cnt         ( sig_addr_frame_cnt    ),
        .s_axis_sig_ctrl            ( s_axis_sig            ),
        .m_axis_sig_ctrl            ( m_axis_sig            ),
        .s_axis                     ( s_axis                ),
        .m_axis                     ( m_axis                )
    );

    sp_ram_parity
    #(
        .PARITY_WIDTH(DATA_WIDTH/8),
        .DATA_WIDTH(DATA_WIDTH+DATA_WIDTH/8),
        .DEPTH( (2*cross_pkg::T-1)*WORDS_PER_SEED)
    )
    u_test_ram_stree
    (
        .clk,
        .en_i       ( stree_mem_en      ),
        .we_i       ( stree_mem_we      ),
        .addr_i     ( stree_mem_addr    ),
        .wdata_i    ( stree_mem_wdata   ),
        .rdata_o    ( stree_mem_rdata   )
    );

    sp_ram
    #(
        .DATA_WIDTH(8),
        .DEPTH( (2*cross_pkg::T-1) )
    )
    u_test_ram_flags
    (
        .clk,
        .en_i       ( 1'b1              ),
        .we_i       ( flag_we           ),
        .addr_i     ( flag_addr         ),
        .wdata_i    ( flag_bit_wr_tmp   ),
        .rdata_o    ( flag_bit_rd_tmp   )
    );

    `AXIS_EXPORT_MASTER(m_axis)
    `AXIS_EXPORT_MASTER(m_axis_sig)
    `AXIS_EXPORT_SLAVE(s_axis)
    `AXIS_EXPORT_SLAVE(s_axis_sig)

    assign s_axis_ch.tdata = s_axis_ch_tdata[0];
    assign s_axis_ch.tvalid = s_axis_ch_tvalid;
    assign s_axis_ch_tready = s_axis_ch.tready;
    assign s_axis_ch.tlast = s_axis_ch_tlast;

endmodule
