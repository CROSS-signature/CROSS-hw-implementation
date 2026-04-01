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

module sig_ctrl
#(
    parameter DATA_WIDTH = 64,
    parameter MTREE_ADDR_WIDTH = 16,
    parameter STREE_ADDR_WIDTH = 16,
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    input logic sign_start,
    output logic sign_done,

    input logic vrfy_start,
    output logic vrfy_done,
    input logic vrfy_stree_done,
    input logic vrfy_mtree_done,
    output logic vrfy_pad_err,
    input logic vrfy_pad_err_clear,

    input logic [W_NCNT-1:0] path_cnt,
    input logic path_cnt_valid,
    input logic [W_NCNT-1:0] proof_cnt,
    input logic proof_cnt_valid,

    // Connection to proof / path fifo
    AXIS.slave s_axis_proof_path,

    // Connections to mtree memory controller
    output logic [MTREE_ADDR_WIDTH-1:0] mtree_addr,
    output logic mtree_addr_we,
    output logic mtree_addr_valid,
    input logic mtree_addr_ready,
    output logic [W_FCNT-1:0] mtree_addr_frame_cnt,

    // Connections to stree memory controller
    output logic [STREE_ADDR_WIDTH-1:0] stree_addr,
    output logic stree_addr_we,
    output logic stree_addr_valid,
    input logic stree_addr_ready,
    output logic [W_FCNT-1:0] stree_addr_frame_cnt,

    // Connection to mtree memory
    AXIS.slave s_axis_mtree_su,
    AXIS.master m_axis_mtree_su,

    // Conections to stree memory
    AXIS.slave s_axis_stree_su,
    AXIS.master m_axis_stree_su,

    // Connections to signature memory
    AXIS.slave s_axis_sig,
    AXIS.master m_axis_sig
);

    typedef enum logic [3:0] {S_IDLE, S_SIGN_PROOF, S_SIGN_PAD_PROOF, S_SIGN_PATH, S_SIGN_PAD_PATH,
                            S_VRFY_PATH, S_VRFY_FLUSH_PATH, S_VRFY_PROOF, S_VRFY_FLUSH_PROOF} state_t;
    state_t state, n_state;

    localparam int unsigned WORDS_PER_HASH = cross_pkg::BYTES_HASH / (DATA_WIDTH/8);
    localparam int unsigned WORDS_PER_SEED = cross_pkg::BYTES_SEED / (DATA_WIDTH/8);

    localparam int unsigned W_NCNT = $clog2( cross_pkg::TREE_NODES_TO_STORE );
    logic [W_NCNT-1:0] node_cnt;
    logic node_cnt_en;

    localparam int unsigned W_WCNT = $clog2( WORDS_PER_HASH );
    logic [W_WCNT-1:0] word_cnt, word_cnt_max;
    logic word_cnt_en;

    logic mode_sign;
    logic pad_err_d, pad_err_q;

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_demux(), m_axis_demux[2]();

    //------------------------------------------------------
    // Controls to the adapter in the mtree_su/stree_su
    // adapter are more or less fix wired.
    //------------------------------------------------------
    assign mtree_addr           = MTREE_ADDR_WIDTH'(s_axis_proof_path.tdata) * MTREE_ADDR_WIDTH'(WORDS_PER_HASH);
    assign mtree_addr_we        = !( state == S_SIGN_PROOF );
    assign mtree_addr_valid     = ( state == S_SIGN_PROOF && s_axis_proof_path.tvalid );
    assign mtree_addr_frame_cnt = W_FCNT'(1);

    assign stree_addr           = STREE_ADDR_WIDTH'(s_axis_proof_path.tdata) * STREE_ADDR_WIDTH'(WORDS_PER_SEED);
    assign stree_addr_we        = !( state == S_SIGN_PATH );
    assign stree_addr_valid     = ( state == S_SIGN_PATH && s_axis_proof_path.tvalid );
    assign stree_addr_frame_cnt = W_FCNT'(1);

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            mode_sign <= 1'b0;
        end else begin
            if (state == S_IDLE) begin
                mode_sign <= sign_start;
            end
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            pad_err_q <= 1'b0;
        end else begin
            if ( vrfy_pad_err_clear ) begin
                pad_err_q <= 1'b0;
            end else begin
                if ( `AXIS_TRANS(s_axis_sig) && (state == S_VRFY_FLUSH_PATH || state == S_VRFY_FLUSH_PROOF) ) begin
                    pad_err_q <= pad_err_q | pad_err_d;
                end
            end
        end
    end
    // If seeds and hashes are not a multiple of full words, we need to mask here
    // to make sure we don't consider potentially dirty bits as padding errors.
    // Gate the data signal such that the flag is only set in flushing states,
    // allows to easily connect to output without the extra register delay.
    assign pad_err_d = (|s_axis_sig.tdata) && s_axis_sig.tvalid && (state == S_VRFY_FLUSH_PATH || state == S_VRFY_FLUSH_PROOF);
    assign vrfy_pad_err = pad_err_d | pad_err_q;

    //------------------------------------------------------
    // DEMUX to send s_axis_sig to stree or mtree
    //------------------------------------------------------
    axis_demux #(.N_MASTERS(2))
    u_axis_demux
    (
        .sel    ( state == S_VRFY_PATH  ),
        .s_axis ( s_axis_demux          ),
        .m_axis ( m_axis_demux          )
    );
    `AXIS_ASSIGN( m_axis_stree_su, m_axis_demux[1] );
    `AXIS_ASSIGN( m_axis_mtree_su, m_axis_demux[0] );

    // if we are in flush state, don't connect signature input
    // but flush the padded part from the signature.
    always_comb begin
        `AXIS_ASSIGN_PROC(s_axis_demux, s_axis_sig);
        if (state == S_VRFY_FLUSH_PATH || state == S_VRFY_FLUSH_PROOF) begin
            s_axis_sig.tready = 1'b1;
            s_axis_demux.tvalid = 1'b0;
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb
    begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                unique  if (sign_start) n_state = S_SIGN_PROOF;
                else    if (vrfy_start) n_state = S_VRFY_PATH;
                else                    n_state = S_IDLE;
            end
            S_SIGN_PROOF: begin
                if ( (`AXIS_LAST(m_axis_sig) || !s_axis_proof_path.tvalid)
                && proof_cnt_valid && node_cnt >= proof_cnt - W_NCNT'(1) ) begin
                    if ( node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                        n_state = S_SIGN_PATH;
                    end else begin
                        n_state = S_SIGN_PAD_PROOF;
                    end
                end
            end
            S_SIGN_PAD_PROOF: begin
                if ( `AXIS_LAST(m_axis_sig) && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                    n_state = S_SIGN_PATH;
                end
            end
            S_SIGN_PATH: begin
                if ( (`AXIS_LAST(m_axis_sig) || !s_axis_proof_path.tvalid)
                && path_cnt_valid && node_cnt >= path_cnt - W_NCNT'(1) ) begin
                    if ( node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                        n_state = S_IDLE;
                    end else begin
                        n_state = S_SIGN_PAD_PATH;
                    end
                end
            end
            S_SIGN_PAD_PATH: begin
                if ( `AXIS_LAST(m_axis_sig) && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                    n_state = S_IDLE;
                end
            end
            S_VRFY_PATH: begin
                if ( vrfy_stree_done ) begin
                    if ( node_cnt > W_NCNT'(0) ) begin
                        n_state = S_VRFY_FLUSH_PATH;
                    end else begin
                        n_state = S_VRFY_PROOF;
                    end
                end
            end
            S_VRFY_FLUSH_PATH: begin
                if ( `AXIS_LAST(s_axis_sig) && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                    n_state = S_VRFY_PROOF;
                end
            end
            S_VRFY_PROOF: begin
                if ( vrfy_mtree_done ) begin
                    if ( node_cnt > W_NCNT'(0) ) begin
                        n_state = S_VRFY_FLUSH_PROOF;
                    end else begin
                        n_state = S_IDLE;
                    end
                end
            end
            S_VRFY_FLUSH_PROOF: begin
                if ( `AXIS_LAST(s_axis_sig) && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) ) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) axis_inft_const_zero();
    assign axis_inft_const_zero.tdata   = '0;
    assign axis_inft_const_zero.tkeep   = '1;
    assign axis_inft_const_zero.tvalid  = ( state == S_SIGN_PAD_PROOF || state == S_SIGN_PAD_PATH );
    assign axis_inft_const_zero.tlast   = ( state == S_SIGN_PAD_PROOF) ? (word_cnt >= W_WCNT'(WORDS_PER_HASH - 1)) : (word_cnt >= W_WCNT'(WORDS_PER_SEED - 1) );

    always_comb
    begin
        `AXIS_ASSIGN_PROC(m_axis_sig, s_axis_mtree_su);
        {s_axis_mtree_su.tready, s_axis_stree_su.tready, m_axis_sig.tuser, s_axis_proof_path.tready} = '0;
        unique case(state)
            S_SIGN_PROOF: begin
                `AXIS_ASSIGN_PROC(m_axis_sig, s_axis_mtree_su);
                s_axis_proof_path.tready = mtree_addr_ready;
            end
            S_SIGN_PAD_PROOF: begin
                `AXIS_ASSIGN_PROC(m_axis_sig, axis_inft_const_zero);
                s_axis_proof_path.tready = 1'b0;
            end
            S_SIGN_PATH: begin
                `AXIS_ASSIGN_PROC(m_axis_sig, s_axis_stree_su);
                m_axis_sig.tuser[0] = ( node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) );
                s_axis_proof_path.tready = stree_addr_ready;
            end
            S_SIGN_PAD_PATH: begin
                `AXIS_ASSIGN_PROC(m_axis_sig, axis_inft_const_zero);
                m_axis_sig.tuser[0] = ( node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) );
                s_axis_proof_path.tready = 1'b0;
            end
            default: begin
                `AXIS_ASSIGN_PROC(m_axis_sig, s_axis_mtree_su);
                {s_axis_mtree_su.tready, s_axis_stree_su.tready, m_axis_sig.tuser, s_axis_proof_path.tready} = '0;
            end
        endcase
    end

    assign sign_done = ( state == S_SIGN_PATH && path_cnt_valid && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) )
                    || ( state == S_SIGN_PAD_PATH && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) && `AXIS_LAST(m_axis_sig) );
    assign vrfy_done = ( state == S_VRFY_PROOF && vrfy_mtree_done && (node_cnt == W_NCNT'(0)) )
                    || ( state == S_VRFY_FLUSH_PROOF && node_cnt >= W_NCNT'(cross_pkg::TREE_NODES_TO_STORE - 1) && `AXIS_LAST(s_axis_sig) );


    //------------------------------------------------------
    // NODE_COUNTER for the nodes to pack into the response
    //------------------------------------------------------
    counter
    #(
        .CNT_WIDTH ( W_NCNT )
    )
    u_node_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( W_NCNT'(cross_pkg::TREE_NODES_TO_STORE)   ),
        .inc        ( W_NCNT'(1)                                ),
        .trigger    ( node_cnt_en                               ),
        .cnt        ( node_cnt                                  )
    );

    assign node_cnt_en = (mode_sign) ? `AXIS_LAST(m_axis_sig) : `AXIS_LAST(s_axis_sig);

    //-----------------------------------------------
    // WORD_COUNTER for the words per node to
    // generate tlast of padded frame
    //-----------------------------------------------
    counter
    #(
        .CNT_WIDTH ( W_WCNT )
    )
    u_word_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( word_cnt_max  ),
        .inc        ( W_WCNT'(1)    ),
        .trigger    ( word_cnt_en   ),
        .cnt        ( word_cnt      )
    );
    assign word_cnt_en  = (state == S_SIGN_PAD_PROOF || state == S_SIGN_PAD_PATH) && `AXIS_TRANS(m_axis_sig);
    assign word_cnt_max = (state == S_SIGN_PAD_PROOF) ? W_WCNT'(WORDS_PER_HASH) : W_WCNT'(WORDS_PER_SEED);

endmodule
