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
`include "memctrl_intf.svh"

module cross_top
    import cross_pkg::*;
    import cross_memory_map_pkg::*;
    import arithmetic_unit_pkg::*;
    import sample_unit_pkg::*;
    import tree_unit_pkg::*;
    import packing_unit_pkg::*;
    import common_pkg::max;
#(
    parameter int unsigned DW = 64,
    parameter int unsigned KECCAK_UNROLL_FACTOR = 2,
    parameter int unsigned MAT_DATA_WIDTH = 712,
    parameter bit TEST_EN = 0
)
(
    input logic clk,
    input logic rst_n,

    input cross_opcode_t    cross_op,
    input logic             cross_op_valid,
    output logic            cross_op_ready,

    output logic            cross_op_done_val,
    output logic            cross_op_done,

    AXIS.slave s_axis_rng,
    AXIS.slave s_axis_msg_keys,
    AXIS.slave s_axis_sig,

    AXIS.master m_axis_sig_keys
);

    // MEMORY
    logic [1:0] sel_demux0_mem0, sel_demux1_mem0, sel_mux0_mem0, sel_mux1_mem0, sel_demux0_mem1, sel_mux0_mem1;
    logic sel_demux1_sigmem, sel_mux0_sigmem, sel_mux1_sigmem;

    AXIS #(.DATA_WIDTH(DW)) m_axis_demux0_mem0[3](), m_axis_demux1_mem0[3](), s_axis_mux0_mem0[3](), s_axis_mux1_mem0[3](),
                            m_axis_demux0_mem1[3](), s_axis_mux0_mem1[3](), m_axis_demux0_sigmem(), m_axis_demux1_sigmem[2](),
                            s_axis_mux0_sigmem[2](), s_axis_mux1_sigmem[2]();

    localparam int unsigned W_FCNT_MEM0 = max(BITS_T + 1, $clog2(5+2*TREE_NODES_TO_STORE));
    localparam int unsigned W_FCNT_MEM1 = BITS_T + 1;
    localparam int unsigned W_FCNT_SIGMEM = max(BITS_T + 1, $clog2(3+2*TREE_NODES_TO_STORE+(T-W)+1));
    MEMCTRL #( .MEM_AW(MEM0_AW), .W_FCNT(W_FCNT_MEM0) ) ctrl_mem0[2]();
    MEMCTRL #( .MEM_AW(MEM1_AW), .W_FCNT(W_FCNT_MEM1) ) ctrl_mem1[2]();
    MEMCTRL #( .MEM_AW(SIGMEM_AW), .W_FCNT(W_FCNT_SIGMEM) ) ctrl_sigmem[2]();

    localparam int unsigned FZ_PER_WORD = DW / cross_pkg::BITS_Z;
    localparam int unsigned WORDS_FZ_VEC = (cross_pkg::DIM_FZ + FZ_PER_WORD - 1) / FZ_PER_WORD;

    localparam int unsigned FP_PER_WORD = DW / cross_pkg::BITS_P;
    localparam int unsigned WORDS_FP_VEC = (cross_pkg::N + FP_PER_WORD - 1) / FP_PER_WORD;

    logic [MEM0_AW-1:0] sigma_delta_addr_q, cmt1_addr_q;
    logic [MEM1_AW-1:0] uy_addr_q;

    // ALU
    arithmetic_op_t alu_op;
    logic alu_start, alu_done, alu_busy;

    logic sel_mux_alu_i1, sel_mux_alu_i3, sel_demux_alu_o0;
    logic [1:0] sel_mux_alu_i2;

    AXIS #(.DATA_WIDTH(DW)) s_axis_mux_alu_i1[2](), s_axis_mux_alu_i2[3](), s_axis_mux_alu_i3[2](), m_axis_demux_alu_o0[2](), m_axis_alu_o1();
    AXIS #(.DATA_WIDTH(BITS_P)) s_axis_alu_i0();
    AXIS #(.DATA_WIDTH(BITS_Z)) s_axis_alu_i4();


    // SAMPLER
    localparam int unsigned W_DIGESTS   = $clog2(MAX_DIGESTS) + 1;

    sample_op_t sample_op;
    logic sample_op_valid, sample_op_ready, sample_busy;

    digest_t sample_digest_type;
    logic [W_DIGESTS-1:0] sample_n_digests;

    logic sel_demux_sample_i0, sel_demux_sample_o0;
    logic [1:0] sel_demux_sample_o1;
    logic [2:0] sel_mux_sample_i0;

    AXIS #(.DATA_WIDTH(DW)) s_axis_dsc(), m_axis_sample_o0[2](), m_axis_sample_o1[4](), s_axis_sample_i0[7]();


    // TREES
    tree_unit_opcode_t tree_op;
    logic tree_op_valid, tree_op_ready;
    logic tree_err, tree_err_clear, tree_stree_computed;

    localparam int unsigned AW_INT_STREE = $clog2(2*T-1);
    digest_t tree_digest_type;
    logic [W_DIGESTS-1:0] tree_n_digests;
    logic [AW_INT_STREE-1:0] tree_parent_idx;

    logic sel_mux_tree_i0;
    logic tree_sign_done, tree_sign_done_q, tree_vrfy_done, tree_vrfy_stree_done, tree_vrfy_mtree_done;

    AXIS #(.DATA_WIDTH(DW)) s_axis_tree_i0[2](), m_axis_tree_o0();

    // DEMUXES
    logic sel_demux_rng;
    logic [1:0] sel_demux_msg_keys;
    AXIS #(.DATA_WIDTH(DW)) m_axis_demux_rng[2](), m_axis_demux_msg_keys[3]();

    logic [1:0] sel_clone_b, sel_clone_uprime;
    logic clear_fifo_ch_b;
    AXIS #(.DATA_WIDTH(1)) s_axis_clone_b(), m_axis_clone_b[2](), m_axis_ch_b_fifo();
    AXIS #(.DATA_WIDTH(DW)) m_axis_clone_uprime[2](), m_axis_clone_y[2]();

    // COMPARISON
    logic compare_flag, compare_flag_clear;
    AXIS #(.DATA_WIDTH(DW)) s_axis_compare[2]();

	// DECOMPRESSION
	decomp_mode_t decomp_op;
	logic decomp_op_valid, decomp_op_ready, decomp_fz_err, decomp_pad_rsp0_err, decomp_err_clear;
    logic sel_mux_decomp, sel_demux_decomp;
    AXIS #(.DATA_WIDTH(DW)) s_axis_mux_decomp[2](), m_axis_mux_decomp(), m_axis_decomp_int(), m_axis_decomp[2]();

    AXIS #(.DATA_WIDTH(DW)) s_axis_rng_int(), s_axis_msg_keys_int();

    // FSM
`ifdef RSDPG
    typedef enum logic [4:0] {S_IDLE, S_STORE_SK, S_EXPAND_SK, S_SAMPLE_VT_W, S_SAMPLE_ETA_ZETA, S_EXPAND_ZETA, S_PACK_KEYS,
                                S_STORE_SK_MSEED_SALT, S_GEN_STREE, S_ID_LOOP_CMT, S_GEN_MTREE,
                                S_GEN_D1, S_GEN_D01, S_GEN_DBETA, S_FIRST_RSP, S_GEN_DB, S_CH_B, S_PACK_RSP1, S_PACK_RSP0,
                                S_STREAM_SIG, S_LOAD_SIG, S_PARSE_DIGESTS, S_LOAD_PK, S_LOAD_RSP1, S_LOAD_RSP0, S_VRFY_BETA,
                                S_VRFY_LOOP, S_TEST_CNT} fsm_t;
`else
    typedef enum logic [4:0] {S_IDLE, S_STORE_SK, S_EXPAND_SK, S_SAMPLE_VT_W, S_SAMPLE_ETA_ZETA, S_PACK_KEYS,
                                S_STORE_SK_MSEED_SALT, S_GEN_STREE, S_ID_LOOP_CMT, S_GEN_MTREE,
                                S_GEN_D1, S_GEN_D01, S_GEN_DBETA, S_FIRST_RSP, S_GEN_DB, S_CH_B, S_PACK_RSP1, S_PACK_RSP0,
                                S_STREAM_SIG, S_LOAD_SIG, S_PARSE_DIGESTS, S_LOAD_PK, S_LOAD_RSP1, S_LOAD_RSP0, S_VRFY_BETA,
                                S_VRFY_LOOP, S_TEST_CNT} fsm_t;
`endif

    fsm_t n_state, state;
    logic keygen_en, sign_en, vrfy_en;
    logic keygen_done, sign_done, vrfy_done;

`ifdef FAST
    localparam int unsigned W_CNT1      = $clog2(T+4);
    localparam int unsigned W_CNT_MTREE = $clog2(T+4+5);
`else
    localparam int unsigned W_CNT1      = $clog2(T+2);
    localparam int unsigned W_CNT_MTREE = $clog2(3);
`endif

    localparam int unsigned W_CNT0 = $clog2(8);
    logic [W_CNT0-1:0] cnt0, cnt0_max;
    logic cnt0_en;

    logic [W_CNT_MTREE-1:0] cnt_mtree;
    logic cnt_mtree_en;

    localparam int unsigned W_CNT_STREAM = $clog2(5+2*TREE_NODES_TO_STORE);
    logic [W_CNT_STREAM-1:0] cnt_stream;
    logic cnt_stream_en;

    localparam int unsigned W_CNT_VRFY_LOOP = $clog2(6);
    logic [W_CNT_VRFY_LOOP-1:0] cnt_vrfy_loop, cnt_vrfy_loop_max;
    logic cnt_vrfy_loop_en;

    logic [W_CNT1-1:0] cnt1, cnt1_max;
    logic cnt1_en;

    localparam int unsigned W_CNT2 = $clog2(T-W);
    logic [W_CNT2-1:0] cnt2, cnt2_max;
    logic cnt2_en;

    localparam int unsigned W_CNTL0 = $clog2(10);
    logic [W_CNTL0-1:0] cnt_lcmt0;
    logic cnt_lcmt0_en;

    localparam int unsigned W_CNTL1 = $clog2(4);
    logic [W_CNTL1-1:0] cnt_lcmt1;
    logic cnt_lcmt1_en;

`ifdef RSDPG
    logic rsdpg_gate;
`endif
    logic vrfy_syn_loaded;
    logic tree_computation_gated;
    logic keygen_requested;
    logic rsp0_packed;

    typedef enum logic [1:0] {CMT1_IDLE, CMT1_ACTIVE, CMT1_WAIT} cmt1_gate_t;
    cmt1_gate_t cmt1_gate_en;

    // ---------------------------------------------
    // MEMORY WRAPPER
    // ---------------------------------------------
    cross_mem_wrapper #( .DW(DW) )
    u_mem_wrapper
    (
        .clk,
        .rst_n,

        // MEM0
        .ctrl_mem0              ( ctrl_mem0             ),
        .sel_demux0_mem0        ( sel_demux0_mem0       ),
        .m_axis_demux0_mem0     ( m_axis_demux0_mem0    ),
        .sel_demux1_mem0        ( sel_demux1_mem0       ),
        .m_axis_demux1_mem0     ( m_axis_demux1_mem0    ),
        .sel_mux0_mem0          ( sel_mux0_mem0         ),
        .s_axis_mux0_mem0       ( s_axis_mux0_mem0      ),
        .sel_mux1_mem0          ( sel_mux1_mem0         ),
        .s_axis_mux1_mem0       ( s_axis_mux1_mem0      ),

        // MEM1
        .ctrl_mem1              ( ctrl_mem1             ),
        .sel_demux0_mem1        ( sel_demux0_mem1       ),
        .m_axis_demux0_mem1     ( m_axis_demux0_mem1    ),
        .sel_mux0_mem1          ( sel_mux0_mem1         ),
        .s_axis_mux0_mem1       ( s_axis_mux0_mem1      ),

        // SIGMEM
        .ctrl_sigmem            ( ctrl_sigmem           ),
        .m_axis_demux0_sigmem   ( m_axis_demux0_sigmem  ),
        .sel_demux1_sigmem      ( sel_demux1_sigmem     ),
        .m_axis_demux1_sigmem   ( m_axis_demux1_sigmem  ),
        .sel_mux0_sigmem        ( sel_mux0_sigmem       ),
        .s_axis_mux0_sigmem     ( s_axis_mux0_sigmem    ),
        .sel_mux1_sigmem        ( sel_mux1_sigmem       ),
        .s_axis_mux1_sigmem     ( s_axis_mux1_sigmem    )
    );

    // ---------------------------------------------
    // ALU WRAPPER
    // ---------------------------------------------
    cross_alu_wrapper #(
        .MAT_DATA_WIDTH(MAT_DATA_WIDTH),
        .DW(DW)
    )
    u_alu_wrapper
    (
        .clk,
        .rst_n,
        .op             ( alu_op                ),
        .op_start       ( alu_start             ),
        .op_done        ( alu_done              ),
        .sel_mux_i1     ( sel_mux_alu_i1        ),
        .sel_mux_i2     ( sel_mux_alu_i2        ),
        .sel_mux_i3     ( sel_mux_alu_i3        ),
        .sel_demux_o0   ( sel_demux_alu_o0      ),
        .s_axis_i0      ( s_axis_alu_i0         ),
        .s_axis_mux_i1  ( s_axis_mux_alu_i1     ),
        .s_axis_mux_i2  ( s_axis_mux_alu_i2     ),
        .s_axis_mux_i3  ( s_axis_mux_alu_i3     ),
        .s_axis_i4      ( s_axis_alu_i4         ),
        .s_axis_i5      ( m_axis_demux1_mem0[1] ),
        .m_axis_o0      ( m_axis_demux_alu_o0   ),
        .m_axis_o1      ( m_axis_alu_o1         ),
        .m_axis_o2      ( s_axis_mux1_mem0[1]   )
    );

    // ---------------------------------------------
    // ALU WRAPPER
    // ---------------------------------------------
    cross_sample_wrapper
    #(
        .DW(DW),
        .KECCAK_UNROLL_FACTOR(KECCAK_UNROLL_FACTOR)
    )
    u_sample_wrapper
    (
        .clk,
        .rst_n,
        .op             ( sample_op             ),
        .op_valid       ( sample_op_valid       ),
        .op_ready       ( sample_op_ready       ),
        .busy           ( sample_busy           ),
        .digest_type    ( sample_digest_type    ),
        .n_digests      ( sample_n_digests      ),
        .sel_mux        ( sel_mux_sample_i0     ),
        .s_axis_mux     ( s_axis_sample_i0      ),
        .sel_demux_i0   ( sel_demux_sample_i0   ),
        .m_axis_pack    ( s_axis_mux0_sigmem[1] ),
        .sel_demux_o0   ( sel_demux_sample_o0   ),
        .m_axis_o0      ( m_axis_sample_o0      ),
        .sel_demux_o1   ( sel_demux_sample_o1   ),
        .m_axis_o1      ( m_axis_sample_o1      ),
        .m_axis_b       ( s_axis_clone_b        ),
        .m_axis_w       ( s_axis_alu_i4         ),
        .m_axis_v_beta  ( s_axis_alu_i0         )
    );

    // ---------------------------------------------
    // TREE WRAPPER
    // ---------------------------------------------
    cross_tree_wrapper #( .DW(DW) )
    u_tree_wrapper
    (
        .clk,
        .rst_n,
        .op                 ( tree_op                   ),
        .op_valid           ( tree_op_valid             ),
        .op_ready           ( tree_op_ready             ),
        .digest_size        ( tree_digest_type          ),
        .n_digests          ( tree_n_digests            ),
        .stree_parent_idx   ( tree_parent_idx           ),
        .stree_tree_computed( tree_stree_computed       ),
        .sign_done          ( tree_sign_done            ),
        .vrfy_done          ( tree_vrfy_done            ),
        .vrfy_stree_done    ( tree_vrfy_stree_done      ),
        .vrfy_mtree_done    ( tree_vrfy_mtree_done      ),
        .vrfy_pad_err       ( tree_err                  ),
        .vrfy_pad_err_clear ( tree_err_clear            ),
        .sel_mux_i0         ( sel_mux_tree_i0           ),
        .s_axis_i0          ( s_axis_tree_i0            ),
        .m_axis             ( m_axis_tree_o0            ),
        .s_axis_b           ( m_axis_clone_b[1]         ),
        .s_axis_sig         ( m_axis_demux1_sigmem[1]   ),
        .m_axis_sig         ( s_axis_mux1_sigmem[1]     )
    );

    //--------------------------------------------------
    // LUT-FIFOs to store challenge b for path
    //--------------------------------------------------
    circ_buffer #( .DEPTH(T), .REG_OUT(1) )
    u_fifo_ch
    (
        .clk,
        .rst_n,
        .clear  ( clear_fifo_ch_b   ),
        .s_axis ( m_axis_clone_b[0] ),
        .m_axis ( m_axis_ch_b_fifo  )
    );
    assign clear_fifo_ch_b = (state == S_IDLE);

    //--------------------------------------------------
    // Parser for rng and msg input streams
    //--------------------------------------------------
    rng_parser
    u_rng_parser
    (
        .clk,
        .rst_n,
        .is_keygen  ( keygen_en         ),
        .is_sign    ( sign_en           ),
        .s_axis     ( s_axis_rng        ),
        .m_axis     ( s_axis_rng_int    )
    );

    msg_parser
    u_msg_parser
    (
        .clk,
        .rst_n,
        .is_sign    ( sign_en               ),
        .is_vrfy    ( vrfy_en               ),
        .s_axis     ( s_axis_msg_keys       ),
        .m_axis     ( s_axis_msg_keys_int   )
    );

    // ---------------------------------------------
    // DEMUXES, AXIS_CLONE
    // ---------------------------------------------
    axis_demux #( .N_MASTERS(2) )
    u_demux_rng
    (
        .sel    ( sel_demux_rng     ),
        .s_axis ( s_axis_rng_int    ),
        .m_axis ( m_axis_demux_rng  )
    );

    axis_demux #( .N_MASTERS(3) )
    u_demux_msg_keys
    (
        .sel    ( sel_demux_msg_keys    ),
        .s_axis ( s_axis_msg_keys_int   ),
        .m_axis ( m_axis_demux_msg_keys )
    );

    axis_clone #( .INPUT_REG(1'b0) )
    u_axis_clone_uprime
    (
        .clk,
        .rst_n,
        .sel    ( sel_clone_uprime      ),
        .s_axis ( m_axis_sample_o0[1]   ),
        .m_axis ( m_axis_clone_uprime   )
    );

    axis_clone #( .INPUT_REG(1'b0) )
    u_axis_clone_b0
    (
        .clk,
        .rst_n,
        .sel    ( sel_clone_b       ),
        .s_axis ( s_axis_clone_b    ),
        .m_axis ( m_axis_clone_b    )
    );

    axis_clone #( .INPUT_REG(1'b0) )
    u_axis_clone_y
    (
        .clk,
        .rst_n,
        .sel    ( {sign_en, 1'b1}   ),
        .s_axis ( m_axis_alu_o1     ),
        .m_axis ( m_axis_clone_y    )
    );

    // ---------------------------------------------
    // COMPARISON MODULE
    // ---------------------------------------------
    axis_compare #( .DW(DW) )
    u_compare_module
    (
        .clk,
        .rst_n,
        .flag_is_unequal( compare_flag          ),
        .flag_clear     ( compare_flag_clear    ),
        .s_axis         ( s_axis_compare        )
    );

    // ---------------------------------------------
    // DECOMPRESSION UNIT
    // ---------------------------------------------
    unpacking_unit #( .OUT_REG(1) )
    u_unpacking_unit
    (
        .clk,
        .rst_n,
        .mode           ( decomp_op             ),
        .mode_valid     ( decomp_op_valid       ),
        .mode_ready     ( decomp_op_ready       ),
        .fz_error       ( decomp_fz_err         ),
        .pad_rsp0_error ( decomp_pad_rsp0_err   ),
        .error_clear    ( decomp_err_clear      ),
        .s_axis         ( m_axis_mux_decomp     ),
        .m_axis         ( m_axis_decomp_int     )
    );

    axis_mux #( .N_SLAVES(2) )
    u_mux_decomp
    (
        .sel    ( sel_mux_decomp    ),
        .s_axis ( s_axis_mux_decomp ),
        .m_axis ( m_axis_mux_decomp )
    );
    `AXIS_ASSIGN( s_axis_mux_decomp[0], m_axis_demux0_sigmem    );
    `AXIS_ASSIGN( s_axis_mux_decomp[1], m_axis_demux_msg_keys[2]);
    always_comb begin
        s_axis_mux_decomp[0].tuser = {M_UNPACK_BP, 1'b1};
        s_axis_mux_decomp[1].tuser = {M_UNPACK_S, 1'b1};
        unique case (state)
            S_PARSE_DIGESTS: begin
                s_axis_mux_decomp[0].tuser = {M_UNPACK_BP, 1'b1};
            end
            S_LOAD_PK: begin
                s_axis_mux_decomp[1].tuser = (cnt0 >= W_CNT0'(2-1)) ? {M_UNPACK_S, 1'b1} : {M_UNPACK_BP, 1'b1};
            end
            default: begin
                s_axis_mux_decomp[0].tuser = {M_UNPACK_BP, 1'b1};
                s_axis_mux_decomp[1].tuser = {M_UNPACK_S, 1'b1};
            end
        endcase
    end


    axis_demux #( .N_MASTERS(2) )
    u_demux_decomp
    (
        .sel    ( sel_demux_decomp  ),
        .s_axis ( m_axis_decomp_int ),
        .m_axis ( m_axis_decomp     )
    );

    // ---------------------------------------------
    // SIGNATURE PARSER
    // ---------------------------------------------
    sig_parser
    u_sig_parser
    (
        .clk,
        .rst_n,
        .s_axis ( s_axis_sig            ),
        .m_axis ( s_axis_mux1_sigmem[0] )
    );

    // ---------------------------------------------
    // CONNECTIONS
    // ---------------------------------------------
    `AXIS_ASSIGN(s_axis_mux0_mem0[0], m_axis_demux_msg_keys[0] );
    `AXIS_ASSIGN(s_axis_mux0_mem0[1], m_axis_demux_rng[0] );
    `AXIS_ASSIGN(s_axis_mux0_mem0[2], m_axis_sample_o1[1] );

    `AXIS_ASSIGN(s_axis_mux1_mem0[0], m_axis_demux_alu_o0[0] );
    `AXIS_ASSIGN(s_axis_mux1_mem0[2], m_axis_decomp[1] );

    `AXIS_ASSIGN(s_axis_mux0_mem1[1], m_axis_clone_uprime[1] );
    `AXIS_ASSIGN(s_axis_mux0_mem1[2], m_axis_decomp[0] );

    `AXIS_ASSIGN(s_axis_mux0_sigmem[0], m_axis_demux0_mem0[1] );

    `AXIS_ASSIGN(s_axis_tree_i0[0], m_axis_sample_o1[2] );
    `AXIS_ASSIGN(s_axis_tree_i0[1], m_axis_demux_rng[1] );

    `AXIS_ASSIGN(s_axis_mux_alu_i1[0], m_axis_demux0_mem0[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i1[1], m_axis_sample_o1[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i2[0], m_axis_sample_o0[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i2[1], m_axis_demux1_mem0[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i2[2], m_axis_demux0_mem1[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i3[0], m_axis_clone_uprime[0] );
    `AXIS_ASSIGN(s_axis_mux_alu_i3[1], m_axis_demux0_mem1[1] );

    `AXIS_ASSIGN(s_axis_sample_i0[0], m_axis_demux_msg_keys[1] );
    `AXIS_ASSIGN(s_axis_sample_i0[1], m_axis_demux0_mem1[2] );
    `AXIS_ASSIGN(s_axis_sample_i0[2], m_axis_demux_alu_o0[1] );
    `AXIS_ASSIGN(s_axis_sample_i0[3], m_axis_tree_o0 );
    `AXIS_ASSIGN(s_axis_sample_i0[4], m_axis_demux1_mem0[2] );
    `AXIS_ASSIGN(s_axis_sample_i0[5], s_axis_dsc );
    `AXIS_ASSIGN(s_axis_sample_i0[6], m_axis_clone_y[1] );


    `AXIS_ASSIGN(s_axis_compare[0], m_axis_demux0_mem0[2]);
    `AXIS_ASSIGN(s_axis_compare[1], m_axis_sample_o1[3]);
    `AXIS_ASSIGN(s_axis_mux0_mem1[0], m_axis_clone_y[0]);

    // ---------------------------------------------
    // TOP-LEVEL FSM
    // ---------------------------------------------
    assign cross_op_ready = (state == S_IDLE);
    assign cross_op_done = keygen_done | sign_done | vrfy_done;
    assign cross_op_done_val = vrfy_en ? (tree_err | decomp_fz_err | decomp_pad_rsp0_err | compare_flag) : 1'b0;

    assign keygen_done = ( state == S_PACK_KEYS && cnt0 >= W_CNT0'(6 - 1) && `AXIS_LAST(m_axis_sig_keys) );
    assign sign_done = (state == S_STREAM_SIG && `AXIS_LAST(m_axis_sig_keys) && cnt_stream >= W_CNT_STREAM'(5+2*TREE_NODES_TO_STORE - 1));
    assign vrfy_done = (state == S_GEN_DB && `AXIS_LAST(s_axis_compare[1]) && vrfy_en);

    assign compare_flag_clear = vrfy_done;
    assign decomp_err_clear = vrfy_done;
    assign tree_err_clear = vrfy_done;

    logic unused;
    assign unused = |sample_op_ready & |tree_op_ready & |decomp_op_ready & |tree_vrfy_done;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            {keygen_en, sign_en, vrfy_en} <= '0;
        end else begin
            if (cross_op_valid && cross_op_ready) begin
                keygen_en   <= (cross_op == OP_KEYGEN);
                sign_en     <= (cross_op == OP_SIGN);
                vrfy_en     <= (cross_op == OP_VERIFY);
            end
            if (keygen_done) keygen_en <= 1'b0;
            if (sign_done) sign_en <= 1'b0;
            if (vrfy_done) vrfy_en <= 1'b0;
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            tree_sign_done_q <= 1'b0;
        end else begin
            if (tree_sign_done_q) begin
                if ( `AXIS_LAST(m_axis_sig_keys) && cnt_stream >= W_CNT_STREAM'(5+2*TREE_NODES_TO_STORE-1) ) begin
                    tree_sign_done_q <= 1'b0;
                end
            end else begin
                tree_sign_done_q <= tree_sign_done;
            end
        end
    end

    always_comb begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if (cross_op_valid && cross_op_ready) begin
                    unique  if (cross_op == OP_KEYGEN)  n_state = S_STORE_SK;
                    else    if (cross_op == OP_SIGN)    n_state = S_STORE_SK_MSEED_SALT;
                    else    if (cross_op == OP_VERIFY)  n_state = S_LOAD_SIG;
                    else                                n_state = S_IDLE;
                end
            end
            S_STORE_SK: begin
                if ( `AXIS_LAST(s_axis_mux0_mem0[1]) ) begin
                    n_state = S_EXPAND_SK;
                end
            end
            S_EXPAND_SK: begin
                if ( `AXIS_LAST(s_axis_mux0_mem0[2]) && cnt0 >= W_CNT0'(4 - 1) ) begin
                    n_state = S_SAMPLE_VT_W;
                end
            end
            S_SAMPLE_VT_W: begin
                if ( `AXIS_LAST(s_axis_sample_i0[5]) ) begin
                    if (vrfy_en) begin
                        n_state = S_GEN_DBETA;
                    end else begin
                        n_state = S_SAMPLE_ETA_ZETA;
                    end
                end
            end
            S_SAMPLE_ETA_ZETA: begin
                if (keygen_en) begin
                    if ( `AXIS_LAST(s_axis_sample_i0[5]) ) begin
                        n_state = S_PACK_KEYS;
                    end
                end else begin
                    if ( `AXIS_LAST(s_axis_mux0_mem0[2]) ) begin
                    `ifdef RSDPG
                        n_state = S_EXPAND_ZETA;
                    `else
                        n_state = S_GEN_STREE;
                    `endif
                    end
                end
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                if ( `AXIS_LAST(s_axis_mux1_mem0[1]) ) begin
                    n_state = S_GEN_STREE;
                end
            end
        `endif
            S_PACK_KEYS: begin
                if ( `AXIS_LAST(m_axis_sig_keys) && cnt0 >= W_CNT0'(6 - 1) ) begin
                    if (TEST_EN) begin
                        n_state = S_TEST_CNT;
                    end else begin
                        n_state = S_IDLE;
                    end
                end
            end
            S_STORE_SK_MSEED_SALT: begin
                if ( `AXIS_LAST(s_axis_mux0_mem0[1]) && cnt0 >= W_CNT0'(3 - 1) ) begin
                    n_state = S_EXPAND_SK;
                end
            end
            S_GEN_STREE: begin
                if (sign_en) begin
                    if (tree_stree_computed) begin
                        n_state = S_ID_LOOP_CMT;
                    end
                end else begin
                    if (tree_vrfy_stree_done) begin
                        n_state = S_VRFY_BETA;
                    end
                end
            end
            S_ID_LOOP_CMT: begin
                if ( `AXIS_LAST(s_axis_tree_i0[0]) && cnt1 >= W_CNT1'(T - 1) ) begin
                    n_state = S_GEN_MTREE;
                end
            end
            S_GEN_MTREE: begin
                if ( (sign_en && `AXIS_LAST(s_axis_tree_i0[0]) && cnt1 >= cnt1_max - W_CNT1'(1))
                || (vrfy_en && tree_vrfy_mtree_done) ) begin
                    n_state = S_GEN_D1;
                end
            end
            S_GEN_D1: begin
                if ( `AXIS_LAST(s_axis_mux0_mem0[2]) ) begin
                    n_state = S_GEN_D01;
                end
            end
            S_GEN_D01: begin
                if (sign_en) begin
                    if ( `AXIS_LAST(s_axis_mux0_mem0[2]) ) begin
                        n_state = S_GEN_DBETA;
                    end
                end else begin
                    if ( `AXIS_LAST(s_axis_compare[1]) ) begin
                        n_state = S_GEN_DB;
                    end
                end
            end
            S_GEN_DBETA: begin
                if ( `AXIS_LAST(s_axis_mux0_mem0[2]) && cnt0 >= W_CNT0'(6 - 1) ) begin
                    if (sign_en) begin
                        n_state = S_FIRST_RSP;
                    end else begin
                        n_state = S_LOAD_RSP1;
                    end
                end
            end
            S_FIRST_RSP: begin
                if ( `AXIS_LAST(s_axis_mux0_mem1[0]) && cnt1 >= W_CNT1'(T - 1) ) begin
                    n_state = S_GEN_DB;
                end
            end
            S_GEN_DB: begin
                if (sign_en) begin
                    if ( `AXIS_LAST(s_axis_mux0_mem0[2]) ) begin
                        n_state = S_CH_B;
                    end
                end else begin
                    if ( `AXIS_LAST(s_axis_compare[1]) ) begin
                        if (TEST_EN) begin
                            n_state = S_TEST_CNT;
                        end else begin
                            n_state = S_IDLE;
                        end
                    end
                end
            end
            S_CH_B: begin
                if (sign_en) begin // sign
                    if ( `AXIS_LAST(s_axis_mux0_sigmem[0]) && cnt0 >= W_CNT0'(5 - 1) ) begin
                        n_state = S_PACK_RSP1;
                    end
                end else begin // verify
                    if ( `AXIS_LAST(s_axis_sample_i0[5]) ) begin
                        n_state = S_LOAD_PK;
                    end
                end
            end
            S_PACK_RSP1: begin
                if ( `AXIS_LAST(m_axis_ch_b_fifo) ) begin
                    n_state = S_PACK_RSP0;
                end
            end
            // Continue if trees are done and either last rsp0 word was packed or rsp0 finished before the trees did
            S_PACK_RSP0: begin
                if ( (tree_sign_done | tree_sign_done_q) && ((`AXIS_LAST(m_axis_ch_b_fifo)) | rsp0_packed) ) begin
                    n_state = S_STREAM_SIG;
                end
            end
            S_STREAM_SIG: begin
                if ( `AXIS_LAST(m_axis_sig_keys) && cnt_stream >= W_CNT_STREAM'(5+2*TREE_NODES_TO_STORE - 1) ) begin
                    if (TEST_EN) begin
                        n_state = S_TEST_CNT;
                    end else begin
                        n_state = S_IDLE;
                    end
                end
            end
            S_LOAD_SIG: begin
                if ( `AXIS_LAST(s_axis_mux1_sigmem[0]) && s_axis_mux1_sigmem[0].tuser[0] ) begin
                    n_state = S_PARSE_DIGESTS;
                end
            end
            S_PARSE_DIGESTS: begin
                if ( `AXIS_LAST(s_axis_mux1_mem0[2]) && cnt0 >= W_CNT0'(3 - 1) ) begin
                    n_state = S_CH_B;
                end
            end
            S_LOAD_PK: begin
                if ( `AXIS_LAST(s_axis_mux1_mem0[2]) && cnt0 >= W_CNT0'(2 - 1) ) begin
                    n_state = S_SAMPLE_VT_W;
                end
            end
            S_LOAD_RSP1: begin
                if ( `AXIS_LAST(m_axis_ch_b_fifo) ) begin
                    n_state = S_LOAD_RSP0;
                end
            end
            // For fast version, there's no seed_tree to generate in verify
            S_LOAD_RSP0: begin
                if ( `AXIS_LAST(m_axis_ch_b_fifo) ) begin
                    `ifdef FAST
                        n_state = S_VRFY_BETA;
                    `else
                        n_state = S_GEN_STREE;
                    `endif
                end
            end
            S_VRFY_BETA: begin
                if ( s_axis_alu_i0.tvalid && !sample_busy ) begin
                    n_state = S_VRFY_LOOP;
                end
            end
            S_VRFY_LOOP: begin
                if ( `AXIS_LAST(m_axis_ch_b_fifo) ) begin
                    n_state = S_GEN_MTREE;
                end
            end
            S_TEST_CNT: begin
                if (`AXIS_LAST(m_axis_sig_keys)) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    // API/CLONE (DE-) MUXES
    assign sel_clone_b = '1;
    assign sel_clone_uprime = '1;
    always_comb begin
        {sel_demux_rng, sel_demux_msg_keys} = '0;
        unique case(state)
            // Store in mem0
            S_STORE_SK: begin
                sel_demux_rng = 1'b0;
            end
            // Store sk in mem0, mseed in tree and salt in mem0
            S_STORE_SK_MSEED_SALT: begin
                sel_demux_rng = (cnt0 == W_CNT0'(1));
                sel_demux_msg_keys = 2'd0;
            end
            S_GEN_DBETA: begin
                sel_demux_msg_keys = 2'd1;
            end
            S_LOAD_PK: begin
                sel_demux_msg_keys = 2'd2;
            end
            default: begin
                {sel_demux_rng, sel_demux_msg_keys} = '0;
            end
        endcase
    end

    // MEMORY CONTROLLER
    always_comb begin
        ctrl_mem0[0].addr = '0;
        ctrl_mem0[0].addr_valid = 1'b0;
        ctrl_mem0[0].we = 1'b0;
        ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
        unique case(state)
            // Store sk_seed in mem0
            S_STORE_SK: begin
                ctrl_mem0[0].addr = MEM0_ADDR_SK_SEED;
                ctrl_mem0[0].addr_valid = 1'b1;
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // Store seed_pk and seed_e
            // Seed_e is temporarily at etas position
            S_EXPAND_SK: begin
                if (cnt0 >= W_CNT0'(4 - 1)) begin
                    ctrl_mem0[0].addr = MEM0_ADDR_PK_SEED;
                end else begin
                    ctrl_mem0[0].addr = MEM0_ADDR_SEEDE_ETA;
                end
                ctrl_mem0[0].addr_valid = (cnt0 > W_CNT0'(1));
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // Read out sk_seed and pk_seed (consecutive locations)
            S_PACK_KEYS: begin
                ctrl_mem0[0].addr = MEM0_ADDR_SK_SEED;
                ctrl_mem0[0].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[0].we = 1'b0;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(2);
            end
            // Store sk and salt
            S_STORE_SK_MSEED_SALT: begin
                if (cnt0 >= W_CNT0'(2 - 1)) begin
                    ctrl_mem0[0].addr = MEM0_ADDR_SALT;
                end else begin
                    ctrl_mem0[0].addr = MEM0_ADDR_SK_SEED;
                end
                ctrl_mem0[0].addr_valid = 1'b1;
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // Store eta/zeta
            S_SAMPLE_ETA_ZETA: begin
            `ifdef RSDPG
                ctrl_mem0[0].addr = MEM0_ADDR_ZETA;
            `else
                ctrl_mem0[0].addr = MEM0_ADDR_SEEDE_ETA;
            `endif
                ctrl_mem0[0].addr_valid = sign_en;
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                ctrl_mem0[0].addr = MEM0_ADDR_ZETA;
                ctrl_mem0[0].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[0].we = 1'b0;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
        `endif
            S_ID_LOOP_CMT: begin
                ctrl_mem0[0].addr = cmt1_addr_q;
                ctrl_mem0[0].addr_valid = (cmt1_gate_en == CMT1_ACTIVE);
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // For verify, abuse unused memory location of salt that is not
            // used anymore
            S_GEN_D1: begin
                ctrl_mem0[0].addr = sign_en ? MEM0_ADDR_D1_D01 : MEM0_ADDR_SALT;
                ctrl_mem0[0].addr_valid = 1'b1;
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // If sign_en, write the resulting digest.
            // If vrfy_en, read d01 and send to comparison module
            S_GEN_D01: begin
                ctrl_mem0[0].addr = MEM0_ADDR_D1_D01;
                ctrl_mem0[0].addr_valid = (cnt0 > W_CNT0'(0));
                ctrl_mem0[0].we = sign_en;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // Abuse another address part here for verify that is sign only and
            // re-generated there anyway
            S_GEN_DBETA: begin
                ctrl_mem0[0].addr = sign_en ? MEM0_ADDR_DM_DBETA_DB : MEM0_ADDR_SEEDE_ETA;
                ctrl_mem0[0].addr_valid = 1'b1;
                ctrl_mem0[0].we = 1'b1;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // For signing, we write DB into memory.
            // For verification we read DB that has been parsed from the
            // signature and send it to the comparison module
            S_GEN_DB: begin
                ctrl_mem0[0].addr = MEM0_ADDR_DM_DBETA_DB;
                ctrl_mem0[0].addr_valid = 1'b1;
                ctrl_mem0[0].we = sign_en;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
            end
            // Load salt, d01, db to store in sigmem
            S_CH_B: begin
                ctrl_mem0[0].addr = MEM0_ADDR_SALT;
                ctrl_mem0[0].addr_valid = sign_en ? (cnt0 == W_CNT0'(2)) : 1'b0;
                ctrl_mem0[0].we = 1'b0;
                ctrl_mem0[0].fcnt = W_FCNT_MEM0'(3);
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    ctrl_mem0[0].addr = cmt1_addr_q;
                    ctrl_mem0[0].addr_valid = m_axis_ch_b_fifo.tvalid;
                    ctrl_mem0[0].we = 1'b1;
                    ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
                end else begin
                    ctrl_mem0[0].addr = sigma_delta_addr_q;
                    ctrl_mem0[0].addr_valid = m_axis_ch_b_fifo.tvalid && (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0));
                    ctrl_mem0[0].we = 1'b0;
                    ctrl_mem0[0].fcnt = W_FCNT_MEM0'(1);
                end
            end
            default: begin
                ctrl_mem0[0].addr = '0;
                ctrl_mem0[0].addr_valid = 1'b0;
                ctrl_mem0[0].we = 1'b0;
                ctrl_mem0[0].fcnt = '0;
            end
        endcase
    end

    always_comb begin
        ctrl_mem0[1].addr = '0;
        ctrl_mem0[1].addr_valid = 1'b0;
        ctrl_mem0[1].we = 1'b0;
        ctrl_mem0[1].fcnt = '0;
        unique case(state)
            // Load sk_seed
            S_EXPAND_SK: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SK_SEED;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            // Load pk_seed
            S_SAMPLE_VT_W: begin
                ctrl_mem0[1].addr = MEM0_ADDR_PK_SEED;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0)) && !alu_busy;
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            // Load seed_e
            S_SAMPLE_ETA_ZETA: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SEEDE_ETA;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SEEDE_ETA;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b1;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
        `endif
            // Load the salt for seed tree generation
            S_GEN_STREE: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            `ifdef FAST
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(1))
                                            && (cnt1 == W_CNT1'(0) // For quad seeds and first T/4 round seeds
                                            ||  cnt1 == W_CNT1'(4) // For second T/4 round seeds
                                            ||  cnt1 == W_CNT1'(4+T/4+REM_0) // For third T/4 round seeds
                                            ||  cnt1 == W_CNT1'(4+T/4+REM_0+T/4+REM_1) // For last T/4 round seeds
                                            ||  cnt1 == W_CNT1'(4+T/4+REM_0+T/4+REM_1+T/4+REM_2)); // For last T/4 round seeds
            `else
                ctrl_mem0[1].addr_valid = m_axis_tree_o0.tvalid & ((sign_en & ~tree_stree_computed) | (vrfy_en & ~tree_vrfy_stree_done));
            `endif
            end
        `ifdef RSDPG
            S_ID_LOOP_CMT: begin
                if (cmt1_gate_en == CMT1_ACTIVE) begin
                    ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    ctrl_mem0[1].addr_valid = (cnt_lcmt1 == W_CNTL1'(0));
                    ctrl_mem0[1].we = 1'b0;;
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end else begin
                    unique if (cnt_lcmt0 == W_CNTL0'(2)) begin
                        ctrl_mem0[1].addr = MEM0_ADDR_ZETA;
                    end else if (cnt_lcmt0 == W_CNTL0'(3) || cnt_lcmt0 == W_CNTL0'(4) || cnt_lcmt0 == W_CNTL0'(6)) begin
                        ctrl_mem0[1].addr = sigma_delta_addr_q;
                    end else if (cnt_lcmt0 == W_CNTL0'(5)) begin
                        ctrl_mem0[1].addr = MEM0_ADDR_SEEDE_ETA;
                    end else begin
                        ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    end
                    ctrl_mem0[1].addr_valid = (cnt_lcmt0 <= W_CNTL0'(7)) & ~rsdpg_gate;
                    ctrl_mem0[1].we = (cnt_lcmt0 == W_CNTL0'(3) || cnt_lcmt0 == W_CNTL0'(4));
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end
            end
        `else
            S_ID_LOOP_CMT: begin
                if (cmt1_gate_en == CMT1_ACTIVE) begin
                    ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    ctrl_mem0[1].addr_valid = (cnt_lcmt1 == W_CNTL1'(0));
                    ctrl_mem0[1].we = 1'b0;;
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end else begin
                    unique if (cnt_lcmt0 == W_CNTL0'(2)) begin
                        ctrl_mem0[1].addr = MEM0_ADDR_SEEDE_ETA;
                    end else if (cnt_lcmt0 >= W_CNTL0'(3) && cnt_lcmt0 <= W_CNTL0'(6)) begin
                        ctrl_mem0[1].addr = sigma_delta_addr_q;
                    end else begin
                        ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    end
                    ctrl_mem0[1].addr_valid = (cnt_lcmt0 <= W_CNTL0'(7));
                    ctrl_mem0[1].we = (cnt_lcmt0 == W_CNTL0'(3) || cnt_lcmt0 == W_CNTL0'(4));
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end
            end
        `endif
            S_GEN_D1: begin
                ctrl_mem0[1].addr = MEM0_ADDR_CMT_1;
                ctrl_mem0[1].addr_valid = (cnt1 <= W_CNT1'(T-1));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(T);
            end
            S_GEN_D01: begin
                ctrl_mem0[1].addr = sign_en ? MEM0_ADDR_D1_D01 : MEM0_ADDR_SALT;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            // Abuse another address part here for verify that is sign only and
            // re-generated there anyway
            S_GEN_DBETA: begin
                unique if (cnt0 == W_CNT0'(3)) begin
                    ctrl_mem0[1].addr = sign_en ? MEM0_ADDR_DM_DBETA_DB : MEM0_ADDR_SEEDE_ETA;
                end else if (cnt0 == W_CNT0'(4)) begin
                    ctrl_mem0[1].addr = MEM0_ADDR_D1_D01;
                end else begin
                    ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                end
                ctrl_mem0[1].addr_valid = (cnt0 >= W_CNT0'(3) && cnt0 <= W_CNT0'(5));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_FIRST_RSP: begin
                ctrl_mem0[1].addr = MEM0_ADDR_DM_DBETA_DB;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            // Abuse another address part here for verify that is sign only and
            // re-generated there anyway
            S_GEN_DB: begin
                ctrl_mem0[1].addr = sign_en ? MEM0_ADDR_DM_DBETA_DB : MEM0_ADDR_SEEDE_ETA;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0)) && (cnt1 == W_CNT1'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_CH_B: begin
                ctrl_mem0[1].addr = MEM0_ADDR_DM_DBETA_DB;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_PACK_RSP1: begin
                ctrl_mem0[1].addr = cmt1_addr_q;
                ctrl_mem0[1].addr_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata);
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_PACK_RSP0: begin
                ctrl_mem0[1].addr = sigma_delta_addr_q;
                ctrl_mem0[1].addr_valid = ~rsp0_packed && (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata) && (cnt0 == W_CNT0'(1));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_PARSE_DIGESTS: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                ctrl_mem0[1].addr_valid = 1'b1;
                ctrl_mem0[1].we = 1'b1;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(3);
            end
            // read pk_seed and pk_syn, decompress the later and store it in
            // mem
            S_LOAD_PK: begin
                ctrl_mem0[1].addr = MEM0_ADDR_PK_SEED;
                ctrl_mem0[1].addr_valid = 1'b1;
                ctrl_mem0[1].we = 1'b1;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(2);
            end
            S_LOAD_RSP1: begin
                ctrl_mem0[1].addr = cmt1_addr_q;
                ctrl_mem0[1].addr_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata);
                ctrl_mem0[1].we = 1'b1;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_LOAD_RSP0: begin
                ctrl_mem0[1].addr = sigma_delta_addr_q;
                ctrl_mem0[1].addr_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata) && (cnt0 == W_CNT0'(1));
                ctrl_mem0[1].we = 1'b1;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_VRFY_BETA: begin
                ctrl_mem0[1].addr = MEM0_ADDR_SEEDE_ETA;
                ctrl_mem0[1].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    ctrl_mem0[1].addr_valid = m_axis_ch_b_fifo.tvalid && (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0));
                    ctrl_mem0[1].we = 1'b0;
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end else begin
                    unique if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(2)) begin
                        ctrl_mem0[1].addr = sigma_delta_addr_q;
                    end else if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0)) begin
                        ctrl_mem0[1].addr = MEM0_ADDR_PK_S;
                    end else begin
                        ctrl_mem0[1].addr = MEM0_ADDR_SALT;
                    end
                    ctrl_mem0[1].addr_valid = m_axis_ch_b_fifo.tvalid &&
                                            (   (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0) && !vrfy_syn_loaded)
                                                || cnt_vrfy_loop == W_CNT_VRFY_LOOP'(2)
                                                || cnt_vrfy_loop == W_CNT_VRFY_LOOP'(3) );
                    ctrl_mem0[1].we = 1'b0;
                    ctrl_mem0[1].fcnt = W_FCNT_MEM0'(1);
                end
            end
            default: begin
                ctrl_mem0[1].addr = '0;
                ctrl_mem0[1].addr_valid = 1'b0;
                ctrl_mem0[1].we = 1'b0;
                ctrl_mem0[1].fcnt = '0;
            end
        endcase
    end
    always_comb begin
        ctrl_sigmem[0].addr = SIGMEM_ADDR_SALT;
        ctrl_sigmem[0].addr_valid = 1'b0;
        ctrl_sigmem[0].we = 1'b0;
        ctrl_sigmem[0].fcnt = '0;
        unique case(state)
            // Store sk_seed, pk_seed and pk_syn
            S_PACK_KEYS: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_SALT;
                ctrl_sigmem[0].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_sigmem[0].we = 1'b1;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(3);
            end
            // Store salt, d01, db
            S_CH_B: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_SALT;
                ctrl_sigmem[0].addr_valid = sign_en;
                ctrl_sigmem[0].we = 1'b1;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(3);
            end
            // We do not need a separate activation for RSP0, as it
            // lies directly behind RSP1 and thus, setting fcnt = 2
            // makes sure both response vectors are written properly
            S_PACK_RSP1: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_RSP1;
                ctrl_sigmem[0].addr_valid = (cnt1 == W_CNT1'(0));
                ctrl_sigmem[0].we = 1'b1;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(2);
            end
            // Load salt, d01, db
            S_PARSE_DIGESTS: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_SALT;
                ctrl_sigmem[0].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_sigmem[0].we = 1'b0;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(3);
            end
            S_LOAD_RSP1: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_RSP1;
                ctrl_sigmem[0].addr_valid = (cnt1 == W_CNT1'(0));
                ctrl_sigmem[0].we = 1'b0;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(T-W);
            end
            S_LOAD_RSP0: begin
                ctrl_sigmem[0].addr = SIGMEM_ADDR_RSP0;
                ctrl_sigmem[0].addr_valid = (cnt1 == W_CNT1'(0));
                ctrl_sigmem[0].we = 1'b0;
                ctrl_sigmem[0].fcnt = W_FCNT_SIGMEM'(1);
            end
            default: begin
                ctrl_sigmem[0].addr = '0;
                ctrl_sigmem[0].addr_valid = 1'b0;
                ctrl_sigmem[0].we = 1'b0;
                ctrl_sigmem[0].fcnt = '0;
            end
        endcase
    end

    always_comb begin
        ctrl_sigmem[1].addr = SIGMEM_ADDR_SALT;
        ctrl_sigmem[1].addr_valid = 1'b0;
        ctrl_sigmem[1].we = 1'b0;
        ctrl_sigmem[1].fcnt = '0;
        unique case(state)
            // Load sk_seed, pk_seed and pk_syn
            S_PACK_KEYS: begin
                ctrl_sigmem[1].addr = SIGMEM_ADDR_SALT;
                ctrl_sigmem[1].addr_valid = (cnt0 == W_CNT0'(3));
                ctrl_sigmem[1].we = 1'b0;
                ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(3);
            end
            // Activate storing the Merkle proofs here
            // Seed path is at different adress and will be set
            // in next states as long as the seed path is not yet stored
            S_CH_B: begin
                ctrl_sigmem[1].addr = SIGMEM_ADDR_MERKLE_PROOFS;
                ctrl_sigmem[1].addr_valid = sign_en;
                ctrl_sigmem[1].we = 1'b1;
                ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(TREE_NODES_TO_STORE);
            end
            S_PACK_RSP0,
            S_PACK_RSP1: begin
                ctrl_sigmem[1].addr = SIGMEM_ADDR_SEED_PATHS;
                ctrl_sigmem[1].addr_valid = ~(tree_sign_done | tree_sign_done_q);
                ctrl_sigmem[1].we = 1'b1;
                ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(TREE_NODES_TO_STORE);
            end
            S_STREAM_SIG: begin
                if (!tree_sign_done && !tree_sign_done_q) begin
                    ctrl_sigmem[1].addr = SIGMEM_ADDR_SEED_PATHS;
                    ctrl_sigmem[1].addr_valid = 1'b1;
                    ctrl_sigmem[1].we = 1'b1;
                    ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(TREE_NODES_TO_STORE);
                end else begin
                    ctrl_sigmem[1].addr = SIGMEM_ADDR_SALT;
                    ctrl_sigmem[1].addr_valid = (tree_sign_done | tree_sign_done_q);
                    ctrl_sigmem[1].we = 1'b0;
                    ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(5+2*TREE_NODES_TO_STORE);
                end
            end
            S_LOAD_SIG: begin
                ctrl_sigmem[1].addr = SIGMEM_ADDR_SALT;
                ctrl_sigmem[1].addr_valid = 1'b1;
                ctrl_sigmem[1].we = 1'b1;
                ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(3+2*TREE_NODES_TO_STORE+(T-W)+1);
            end
            S_PARSE_DIGESTS: begin
                ctrl_sigmem[1].addr = SIGMEM_ADDR_SEED_PATHS;
                ctrl_sigmem[1].addr_valid = 1'b1;
                ctrl_sigmem[1].we = 1'b0;
                ctrl_sigmem[1].fcnt = W_FCNT_SIGMEM'(2*TREE_NODES_TO_STORE);
            end
            default: begin
                ctrl_sigmem[1].addr = '0;
                ctrl_sigmem[1].addr_valid = 1'b0;
                ctrl_sigmem[1].we = 1'b0;
                ctrl_sigmem[1].fcnt = '0;
            end
        endcase
    end

    // Port 0 is read only
    assign ctrl_mem1[0].we = 1'b0;
    always_comb begin
        ctrl_mem1[0].addr = MEM1_ADDR_U_Y;
        ctrl_mem1[0].addr_valid = 1'b0;
        ctrl_mem1[0].fcnt = W_FCNT_MEM1'(1);
        unique case(state)
            S_FIRST_RSP: begin
                ctrl_mem1[0].addr = MEM1_ADDR_U_Y;
                ctrl_mem1[0].addr_valid = (cnt0 == W_CNT0'(0));
                ctrl_mem1[0].fcnt = W_FCNT_MEM1'(T);
            end
            S_GEN_DB: begin
                ctrl_mem1[0].addr = MEM1_ADDR_U_Y;
                ctrl_mem1[0].addr_valid = (cnt0 == W_CNT0'(0)) && (cnt1 == W_CNT1'(0)) && vrfy_en;
                ctrl_mem1[0].fcnt = W_FCNT_MEM1'(T);
            end
            S_PACK_RSP0: begin
                ctrl_mem1[0].addr = uy_addr_q;
                ctrl_mem1[0].addr_valid = ~rsp0_packed && (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata) && (cnt0 == W_CNT0'(0));
                ctrl_mem1[0].fcnt = W_FCNT_MEM1'(1);
            end
            S_VRFY_LOOP: begin
                ctrl_mem1[0].addr = uy_addr_q;
                ctrl_mem1[0].fcnt = W_FCNT_MEM1'(1);
                ctrl_mem1[0].addr_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata) && (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0));
            end
            default: begin
                ctrl_mem1[0].addr = '0;
                ctrl_mem1[0].addr_valid = 1'b0;
                ctrl_mem1[0].fcnt = W_FCNT_MEM1'(1);
            end
        endcase
    end

    // Port 1 is write only
    assign ctrl_mem1[1].we = 1'b1;
    always_comb begin
        ctrl_mem1[1].addr = MEM1_ADDR_U_Y;
        ctrl_mem1[1].addr_valid = 1'b0;
        ctrl_mem1[1].fcnt = W_FCNT_MEM1'(1);
        unique case(state)
            S_ID_LOOP_CMT: begin
                ctrl_mem1[1].addr = MEM1_ADDR_U_Y;
                ctrl_mem1[1].addr_valid = (cnt1 == W_CNT1'(0));
                ctrl_mem1[1].fcnt = W_FCNT_MEM1'(T);
            end
            S_FIRST_RSP: begin
                ctrl_mem1[1].addr = MEM1_ADDR_U_Y;
                ctrl_mem1[1].addr_valid = (cnt1 == W_CNT1'(0));
                ctrl_mem1[1].fcnt = W_FCNT_MEM1'(T);
            end
            S_LOAD_RSP0: begin
                ctrl_mem1[1].addr = uy_addr_q;
                ctrl_mem1[1].addr_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata) && (cnt0 == W_CNT0'(0));
                ctrl_mem1[1].fcnt = W_FCNT_MEM1'(1);
            end
            S_VRFY_LOOP: begin
                ctrl_mem1[1].addr = uy_addr_q;
                ctrl_mem1[1].fcnt = W_FCNT_MEM1'(1);
                ctrl_mem1[1].addr_valid = (m_axis_ch_b_fifo.tvalid & m_axis_ch_b_fifo.tdata) & s_axis_mux0_mem1[0].tvalid;
            end
            default: begin
                ctrl_mem1[1].addr = '0;
                ctrl_mem1[1].addr_valid = 1'b0;
                ctrl_mem1[1].fcnt = W_FCNT_MEM1'(1);
            end
        endcase
    end

    // MEMORY (DE-) MUX SELECTS
    always_comb begin
        {sel_demux0_mem0, sel_demux1_mem0, sel_mux0_mem0, sel_mux1_mem0, sel_demux0_mem1, sel_mux0_mem1} = '0;
        {sel_mux0_sigmem} = '0;
        unique case(state)
            // Store in mem0
            S_STORE_SK: begin
                sel_mux0_mem0 = 2'd1;
            end
            // Load and store in mem0
            S_EXPAND_SK: begin
                sel_demux1_mem0 = 2'd2;
                sel_mux0_mem0 = 2'd2;
            end
            // Load from mem0
            // In sign/verify, eta/zeta is stored in mem0 coming from sampler
            S_SAMPLE_VT_W,
            S_SAMPLE_ETA_ZETA: begin
                sel_mux0_mem0 = 2'd2;
                sel_demux1_mem0 = 2'd2;
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                sel_mux1_mem0 = 2'd1;
                sel_demux0_mem0 = 2'd0;
            end
        `endif
            // Load from mem0 and alu directly
            // Store in sigmem
            S_PACK_KEYS: begin
                sel_demux0_mem0 = 2'd1;
                sel_mux0_sigmem = (cnt0 >= W_CNT0'(3 - 1));
            end
            // Store sk and salt - mseed goes to tree unit
            S_STORE_SK_MSEED_SALT: begin
                sel_mux0_mem0 = (cnt0 >= W_CNT0'(1)) ? 2'd1 : 2'd0;
            end
            // Read the salt for each iteration of the tree expansion
            S_GEN_STREE: begin
                sel_demux1_mem0 = 2'd2;
            end
            S_ID_LOOP_CMT: begin
                if (cmt1_gate_en == CMT1_ACTIVE) begin
                    sel_demux1_mem0 = 2'd2;
                end else begin
                    sel_demux0_mem0 = 2'd0;
                    `ifdef RSDPG
                        sel_demux1_mem0 = (cnt_lcmt0 >= W_CNTL0'(3) && cnt_lcmt0 <= W_CNTL0'(5)) ? 2'd1 : 2'd2;
                    `else
                        sel_demux1_mem0 = (cnt_lcmt0 == W_CNTL0'(3) || cnt_lcmt0 == W_CNTL0'(4)) ? 2'd1 : 2'd2;
                    `endif
                end
                sel_mux0_mem0 = 2'd2;
                sel_mux0_mem1 = 2'd1;
                sel_mux1_mem0 = 2'd1;
            end
            S_GEN_D1,
            S_GEN_D01,
            S_GEN_DBETA,
            S_GEN_DB: begin
                sel_mux1_mem0 = 2'd1;
                sel_demux0_mem0 = 2'd2;
                sel_mux0_mem0 = 2'd2;
                sel_demux1_mem0 = 2'd2;
                sel_demux0_mem1 = 2'd2;
            end
            S_FIRST_RSP: begin
                sel_demux1_mem0 = 2'd2;
                sel_demux0_mem1 = 2'd0;
                sel_mux0_mem1 = 2'd0;
            end
            S_CH_B: begin
                sel_demux0_mem0 = 2'd1;
                sel_demux1_mem0 = 2'd2;
                sel_mux0_sigmem = 1'b0;
            end
            S_PACK_RSP1: begin
                sel_demux1_mem0 = 2'd2;
                sel_mux0_sigmem = 1'b1;
            end
            S_PACK_RSP0: begin
                sel_demux1_mem0 = 2'd2;
                sel_demux0_mem1 = 2'd2;
                sel_mux0_sigmem = 1'b1;
            end
            // Keep sel_mux0_sigmem = 1'b since combining the two packed
            // rsp0 tuples might lead to a tail that is to be stored in
            // the states first cycle.
            S_STREAM_SIG: begin
                sel_mux0_sigmem = 1'b1;
            end
            S_PARSE_DIGESTS: begin
                sel_mux1_mem0 = 2'd2;
            end
            S_LOAD_PK: begin
                sel_mux1_mem0 = 2'd2;
            end
            S_LOAD_RSP1: begin
                sel_mux1_mem0 = 2'd2;
            end
            S_LOAD_RSP0: begin
                sel_mux1_mem0 = 2'd2;
                sel_mux0_mem1 = 2'd2;
            end
            S_VRFY_BETA: begin
                sel_demux1_mem0 = 2'd2;
            end
            S_VRFY_LOOP: begin
                sel_demux0_mem0 = 2'd0;
                sel_demux0_mem1 = 2'd1;
                sel_mux0_mem0 = 2'd2;
                sel_mux0_mem1 = 2'd0;
                if (m_axis_ch_b_fifo.tdata) begin
                    sel_demux1_mem0 = 2'd2;
                end else begin
                    sel_demux1_mem0 = (cnt_vrfy_loop >= W_CNT_VRFY_LOOP'(2)) ? 2'd2 : 2'd0;
                end
            end
            default: begin
                {sel_demux0_mem0, sel_demux1_mem0, sel_mux0_mem0, sel_mux1_mem0, sel_demux0_mem1, sel_mux0_mem1} = '0;
                {sel_mux0_sigmem} = '0;
            end
        endcase
    end
    assign sel_mux1_sigmem = sign_en;
    assign sel_demux1_sigmem = vrfy_en;

    // ALU CONTROLLER
    always_comb begin
        alu_op = ARITH_OP_INIT;
        alu_start = 1'b0;
        sel_mux_alu_i2 = '0;
        {sel_mux_alu_i1, sel_mux_alu_i3, sel_demux_alu_o0} = '0;
        unique case (state)
            // Initialize storing V and optionally W
            S_SAMPLE_VT_W: begin
                alu_op = ARITH_OP_INIT;
                alu_start = 1'b1;
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                alu_op = ARITH_OP_SIGN_EXPAND_ETA;
                alu_start = (cnt0 == W_CNT0'(0));
            end
        `endif
            // Call keygen and write syndrome to packing unit
            S_PACK_KEYS: begin
                alu_op = ARITH_OP_KEYGEN;
                alu_start = keygen_en && !alu_busy && !keygen_requested;
                sel_mux_alu_i1 = 1'b1;
                sel_demux_alu_o0 = 1'b1;
            end
            S_ID_LOOP_CMT: begin
                alu_op = ARITH_OP_SIGN_COMMITMENTS_PREPARATION;
                alu_start = (cnt_lcmt0 <= W_CNTL0'(2));
                sel_demux_alu_o0 = 1'b1;
                sel_mux_alu_i1 = 1'b1;
                sel_mux_alu_i3 = 1'b0;
            end
            S_FIRST_RSP: begin
                alu_op = ARITH_OP_SIGN_FIRST_ROUND_RESPONSES;
                alu_start = ~alu_busy;
                sel_mux_alu_i2 = 2'd2;
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    alu_op = ARITH_OP_VERIFY_CASE_B1;
                    alu_start = (m_axis_ch_b_fifo.tvalid & ~alu_busy) && (cnt2 == W_CNT2'(0));
                    sel_mux_alu_i1 = 1'b1;
                    sel_mux_alu_i2 = 2'd0;
                end else begin
                    alu_op = ARITH_OP_VERIFY_CASE_B0;
                    alu_start = (m_axis_ch_b_fifo.tvalid & ~alu_busy) && (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0));
                    sel_mux_alu_i1 = 1'b0;
                    sel_mux_alu_i2 = 2'd1;
                    sel_mux_alu_i3 = 1'b1;
                    sel_demux_alu_o0 = 1'b1;
                end
            end
            default: begin
                alu_op = ARITH_OP_INIT;
                alu_start = 1'b0;
                sel_mux_alu_i2 = '0;
                {sel_mux_alu_i1, sel_mux_alu_i3, sel_demux_alu_o0} = '0;
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            alu_busy <= 1'b0;
        end else begin
            if (alu_busy) begin
                if (alu_done) begin
                    alu_busy <= 1'b0;
                end
            end else begin
                if (alu_start) begin
                    alu_busy <= 1'b1;
                end
            end
        end
    end

    // SAMPLE_CONTROLLER
    always_comb begin
        sample_op = M_SQUEEZE;
        sample_op_valid = 1'b0;
        sample_digest_type = sample_unit_pkg::LAMBDA;
        sample_n_digests = W_DIGESTS'(2);
        {sel_demux_sample_i0, sel_demux_sample_o0} = '0;
        sel_demux_sample_o1 = 2'd0;
        sel_mux_sample_i0 = 3'd0;
        unique case (state)
            // Expand sk_seed into seed_e and seed_pk
            S_EXPAND_SK: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = (cnt0 == W_CNT0'(0));
                sample_digest_type =sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(2);
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(1)) ? 3'd5 : 3'd4;
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = 2'd1;
            end
            // Expand seed_pk into V, W
            S_SAMPLE_VT_W: begin
                sample_op = M_SAMPLE_VT_W;
                sample_op_valid = vrfy_en ? 1'b1 : !alu_busy;
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(1)) ? 3'd5 : 3'd4;
                sel_demux_sample_i0 = 1'b1;
            end
            // Expand seed_e into eta/zeta
            // In case of keygen, forward eta/zeta immediately to ALU,
            // otherwise store eta/zeta in mem0
            S_SAMPLE_ETA_ZETA: begin
                sample_op = M_SAMPLE_FZ;
                sample_op_valid = (cnt0 <= W_CNT0'(1));
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(1)) ? 3'd5 : 3'd4;
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = keygen_en ? 2'd0 : 2'd1;
            end
            // Load syndrome from alu and pack
            // We might need 1-2 cycles for the dsc to be absorbed here due
            // to register stages, so switch that demux when cnt0 > 0
            S_PACK_KEYS: begin
                sel_mux_sample_i0 = 3'd2;
                sel_demux_sample_i0 = (cnt0 == W_CNT0'(0));
                sel_demux_sample_o1 = 2'd0;
            end
            // Generate the seed tree
            S_GEN_STREE: begin
                sample_op = M_SQUEEZE;
            `ifdef FAST
                sample_op_valid = (cnt1 <= W_CNT1'(4+T/4+REM_0+T/4+REM_1+T/4+REM_2)) & ~tree_stree_computed & ~tree_computation_gated;
            `else
                sample_op_valid = m_axis_tree_o0.tvalid & ((sign_en & ~tree_stree_computed ) | (vrfy_en & ~tree_vrfy_stree_done));
            `endif
                sample_digest_type = tree_digest_type;
                sample_n_digests = tree_n_digests;
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = 2'd2;
                if (cnt0 >= 3 - 1) begin // dsc
                    sel_mux_sample_i0 = 3'd5;
                end else if (cnt0 >= 2 - 1) begin // salt
                    sel_mux_sample_i0 = 3'd4;
                end else begin // seed
                    sel_mux_sample_i0 = 3'd3;
                end
            end
            // Sample \eta_p or \zeta_p and u_p
            S_ID_LOOP_CMT: begin
                sample_op           = (cmt1_gate_en == CMT1_IDLE) ? M_SAMPLE_FZ_FP : M_SQUEEZE;
                sample_digest_type  = sample_unit_pkg::LAMBDA_2;
                sample_n_digests    = W_DIGESTS'(1);

                // CSPRNG expansion to sample e' and u'
                unique if (cmt1_gate_en == CMT1_IDLE) begin
                    sample_op_valid = ( cnt_lcmt0 <= W_CNTL0'(2) );
                    sel_demux_sample_o1 = 2'd0;
                    unique if (cnt_lcmt0 == W_CNTL0'(0)) begin
                        sel_mux_sample_i0 = 3'd3;
                    end else if (cnt_lcmt0 == W_CNTL0'(1) ) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd5;
                    end
                // Hashing to compute cmt1
                end else if (cmt1_gate_en == CMT1_ACTIVE) begin
                    sample_op_valid = ( cnt_lcmt1 == W_CNTL1'(0) );
                    sel_demux_sample_o1 = 2'd1;
                    unique if (cnt_lcmt1 == W_CNTL1'(0)) begin
                        sel_mux_sample_i0 = 3'd3;
                    end else if (cnt_lcmt1 == W_CNTL1'(1)) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd5;
                    end
                // Now hash s_tilde computing cmt0
                end else begin
                    sample_op_valid = ( cnt_lcmt0 == W_CNTL0'(5) );
                    sel_demux_sample_o1 = 2'd2;
                    unique if (cnt_lcmt0 == W_CNTL0'(4) || cnt_lcmt0 == W_CNTL0'(5)) begin // check if 4 needed
                        sel_mux_sample_i0 = 3'd2;
                    end else if ( cnt_lcmt0 == W_CNTL0'(6) || cnt_lcmt0 == W_CNTL0'(7)) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd5;
                    end
                end
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o0 = 1'b1;
            end
            S_GEN_MTREE: begin
                sample_op = M_SQUEEZE;
                sample_digest_type = tree_digest_type;
                sample_n_digests = tree_n_digests;
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = 2'd2;
            `ifdef FAST
                sample_op_valid = (cnt1 <= W_CNT1'(4)) && ~tree_computation_gated;
                if (cnt_mtree == W_CNT_MTREE'(T/4+REM_0)
                    || cnt_mtree == W_CNT_MTREE'(T/4+REM_0+T/4+REM_1+1)
                    || cnt_mtree == W_CNT_MTREE'(T/4+REM_0+T/4+REM_1+T/4+REM_2+2)
                    || cnt_mtree == W_CNT_MTREE'(T+3)
                    || cnt_mtree == W_CNT_MTREE'(T+4+4)) begin
                    sel_mux_sample_i0 = 3'd5;
                end else begin
                    sel_mux_sample_i0 = 3'd3;
                end
            `else
                sample_op_valid = sign_en | (vrfy_en & ~tree_vrfy_mtree_done);
                sel_mux_sample_i0 = (cnt_mtree >= W_CNT_MTREE'(3-1)) ? 3'd5 : 3'd3;
            `endif
            end
            S_GEN_D1: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = (cnt1 == W_CNT1'(0));
                sample_digest_type = sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(1);
                sel_demux_sample_i0 = 1'b1;
                sel_mux_sample_i0 = (cnt1 == W_CNT1'(T)) ? 3'd5 : 3'd4;
                sel_demux_sample_o1 = 2'd1;
            end
            S_GEN_D01: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = (cnt0 == W_CNT0'(0));
                sample_digest_type = sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(1);
                sel_demux_sample_i0 = 1'b1;

                sel_demux_sample_o1 = sign_en ? 2'd1 : 2'd3;
                unique if (cnt0 == W_CNT0'(0)) begin
                    sel_mux_sample_i0 = 3'd3;
                end else if (cnt0 == W_CNT0'(1)) begin
                    sel_mux_sample_i0 = 3'd4;
                end else begin
                    sel_mux_sample_i0 = 3'd5;
                end
            end
            S_GEN_DBETA: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = (cnt0 <= W_CNT0'(5));
                sample_digest_type = sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(1);
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = 2'd1;
                unique if (cnt0 == W_CNT0'(0)) begin
                    sel_mux_sample_i0 = 3'd0;
                end else if (cnt0 == W_CNT0'(1) || cnt0 == W_CNT0'(6)) begin
                    sel_mux_sample_i0 = 3'd5;
                end else begin
                    sel_mux_sample_i0 = 3'd4;
                end
            end
            S_FIRST_RSP: begin
                sample_op = (cnt0 == W_CNT0'(0)) ? M_SAMPLE_BETA : M_SQUEEZE;
                sample_op_valid = 1'b1;
                sample_digest_type = sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(1);
                sel_demux_sample_i0 = 1'b1;
                unique if (cnt0 == W_CNT0'(0)) begin
                    sel_mux_sample_i0 = 3'd4;
                end else if (cnt0 == W_CNT0'(1)) begin
                    sel_mux_sample_i0 = 3'd5;
                end else begin
                    sel_mux_sample_i0 = 3'd6;
                end
            end
            S_VRFY_BETA: begin
                sample_op = M_SAMPLE_BETA;
                sample_op_valid = (cnt0 == W_CNT0'(0));
                sel_demux_sample_i0 = 1'b1;
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(1)) ? 3'd5 : 3'd4;
            end
            S_GEN_DB: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = (cnt0 == W_CNT0'(0)) && (cnt1 == W_CNT1'(0)) && vrfy_en;
                sample_digest_type = sample_unit_pkg::LAMBDA_2;
                sample_n_digests = W_DIGESTS'(1);
                sel_demux_sample_i0 = 1'b1;
                sel_demux_sample_o1 = sign_en ? 2'd1 : 2'd3;
                if (sign_en) begin
                    if (cnt1 >= W_CNT1'(1)) begin
                        sel_mux_sample_i0 = 3'd5;
                    end else begin
                        sel_mux_sample_i0 = 3'd4;
                    end
                end else begin
                    unique if (cnt1 >= W_CNT1'(T+1)) begin
                        sel_mux_sample_i0 = 3'd5;
                    end else if (cnt1 == W_CNT1'(T)) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd1;
                    end
                end
            end
            S_CH_B: begin
                sample_op = M_SAMPLE_B;
                sample_op_valid = 1'b1;
                sel_demux_sample_i0 = 1'b1;
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(1)) ? 3'd5 : 3'd4;
            end
            S_LOAD_PK: begin
                sel_demux_sample_i0 = 1'b1;
            end
            S_PACK_RSP1: begin
                sel_demux_sample_i0 = 1'b0;
                sel_mux_sample_i0 = 3'd4;
            end
            S_PACK_RSP0: begin
                sel_demux_sample_i0 = 1'b0;
                sel_mux_sample_i0 = (cnt0 == W_CNT0'(0)) ? 3'd1 : 3'd4;
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    sample_op           = (cnt2 >= W_CNT2'(2-1)) ? M_SQUEEZE : M_SAMPLE_FZ_FP;
                    sample_op_valid     = (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0)) && m_axis_ch_b_fifo.tvalid;
                    sample_digest_type  = sample_unit_pkg::LAMBDA_2;
                    sample_n_digests    = W_DIGESTS'(1);
                    sel_demux_sample_i0 = 1'b1;
                    sel_demux_sample_o0 = 1'b0;
                    sel_demux_sample_o1 = (cnt2 >= W_CNT2'(2-1)) ? 2'd1 : 2'd0;
                    unique if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0)) begin
                        sel_mux_sample_i0 = 3'd3;
                    end else if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(1)) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd5;
                    end
                end else begin
                    sample_op           = M_SQUEEZE;
                    sample_op_valid     = m_axis_ch_b_fifo.tvalid && (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0));
                    sample_digest_type  = sample_unit_pkg::LAMBDA_2;
                    sample_n_digests    = W_DIGESTS'(1);
                    unique if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(1)) begin
                        sel_mux_sample_i0 = 3'd2;
                    end else if (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(2) || cnt_vrfy_loop == W_CNT_VRFY_LOOP'(3)) begin
                        sel_mux_sample_i0 = 3'd4;
                    end else begin
                        sel_mux_sample_i0 = 3'd5;
                    end
                    sel_demux_sample_i0 = 1'b1;
                    sel_demux_sample_o1 = 2'd2;
                end
            end
            default: begin
                sample_op = M_SQUEEZE;
                sample_op_valid = 1'b0;
                sample_digest_type = sample_unit_pkg::LAMBDA;
                sample_n_digests = W_DIGESTS'(2);
                {sel_demux_sample_i0, sel_demux_sample_o0} = '0;
                sel_demux_sample_o1 = 2'b00;
                sel_mux_sample_i0 = 3'b000;
            end
        endcase
    end

    // TREE CONTROLLER
    always_comb begin
        tree_op = M_SIGN;
        tree_op_valid = 1'b0;
        sel_mux_tree_i0 = 1'b0;
        unique case(state)
            S_STORE_SK_MSEED_SALT: begin
                tree_op = M_SIGN;
                tree_op_valid = 1'b1;
                sel_mux_tree_i0 = 1'b1;
            end
            S_GEN_STREE,
            S_ID_LOOP_CMT,
            S_GEN_MTREE: begin
                sel_mux_tree_i0 = 1'b0;
            end
            S_PARSE_DIGESTS: begin
                tree_op = M_VERIFY;
                tree_op_valid = 1'b1;
            end
            S_VRFY_LOOP: begin
                sel_mux_tree_i0 = 1'b0;
            end
            default: begin
                tree_op = M_SIGN;
                tree_op_valid = 1'b0;
                sel_mux_tree_i0 = 1'b0;
            end
        endcase
    end

    // DECOMPRESSION CONTROLLER
    always_comb begin
        decomp_op = BP;
        decomp_op_valid = 1'b0;
        sel_demux_decomp = 1'b0;
        sel_mux_decomp = 1'b0;
        unique case(state)
            S_PARSE_DIGESTS: begin
                decomp_op = BP;
                decomp_op_valid = 1'b1;
                sel_demux_decomp = 1'b1;
                sel_mux_decomp = 1'b0;
            end
            S_LOAD_PK: begin
                decomp_op = (cnt0 == W_CNT0'(0)) ? BP : SYN;
                decomp_op_valid = 1'b1;
                sel_demux_decomp = 1'b1;
                sel_mux_decomp = 1'b1;
            end
            S_LOAD_RSP1: begin
                decomp_op = BP;
                decomp_op_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata);
                sel_demux_decomp = 1'b1;
                sel_mux_decomp = 1'b0;
            end
            S_LOAD_RSP0: begin
                decomp_op = RSP;
                decomp_op_valid = (m_axis_ch_b_fifo.tvalid & ~m_axis_ch_b_fifo.tdata);
                sel_demux_decomp = cnt0[0];
                sel_mux_decomp = 1'b0;
            end
            default: begin
                decomp_op = BP;
                decomp_op_valid = 1'b0;
                sel_demux_decomp = 1'b0;
                sel_mux_decomp = 1'b0;
            end
        endcase
    end

    always_comb begin
        s_axis_dsc.tdata = '0;
        s_axis_dsc.tvalid = 1'b0;
        unique case (state)
            S_EXPAND_SK: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(3*T+1);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1));
            end
            S_SAMPLE_VT_W: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(3*T+2);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1));
            end
            S_SAMPLE_ETA_ZETA: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(3*T+3);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1));
            end
            S_CH_B: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(3*T);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1));
            end
            S_FIRST_RSP,
            S_VRFY_BETA: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(3*T-1);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1));
            end
            S_GEN_STREE: begin
                s_axis_dsc.tdata[0 +: 16] = 16'(tree_parent_idx);
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(2));
            end
            S_ID_LOOP_CMT: begin
                if (cmt1_gate_en == CMT1_ACTIVE) begin
                    s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) ) | 16'h8000;
                    s_axis_dsc.tvalid = (cnt_lcmt1 == W_CNTL1'(2));
                end else begin
                    if ( cnt_lcmt0 >= W_CNTL0'(8) ) begin
                        s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) ) | 16'h8000;
                    end else begin
                        s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) );
                    end
                    s_axis_dsc.tvalid = (cnt_lcmt0 == W_CNTL0'(2) || cnt_lcmt0 == W_CNTL0'(8));
                end
            end
            S_GEN_D1: begin
                s_axis_dsc.tdata[0 +: 16] = 16'h8000;
                s_axis_dsc.tvalid = (cnt1 == W_CNT1'(T));
            end
            S_GEN_D01: begin
                s_axis_dsc.tdata[0 +: 16] = 16'h8000;
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(2));
            end
            S_GEN_DBETA: begin
                s_axis_dsc.tdata[0 +: 16] = 16'h8000;
                s_axis_dsc.tvalid = (cnt0 == W_CNT0'(1) || cnt0 == W_CNT0'(6));
            end
            S_GEN_DB: begin
                s_axis_dsc.tdata[0 +: 16] = 16'h8000;
                s_axis_dsc.tvalid = sign_en ? (cnt1 == W_CNT1'(1)) : (cnt1 == W_CNT1'(T+1));
            end
            S_GEN_MTREE: begin
                s_axis_dsc.tdata[0 +: 16] = 16'h8000;
            `ifdef FAST
                if (cnt_mtree == W_CNT_MTREE'(T/4+REM_0)
                    || cnt_mtree == W_CNT_MTREE'(T/4+REM_0+1+T/4+REM_1)
                    || cnt_mtree == W_CNT_MTREE'(T/4+REM_0+1+T/4+REM_1+1+T/4+REM_2)
                    || cnt_mtree == W_CNT_MTREE'(T+3)
                    || cnt_mtree == W_CNT_MTREE'(T+4+4)) begin
                    s_axis_dsc.tvalid = 1'b1;
                end else begin
                    s_axis_dsc.tvalid = 1'b0;
                end
            `else
                s_axis_dsc.tvalid = (cnt_mtree == W_CNT_MTREE'(2));
            `endif
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    if (cnt2 >= W_CNT2'(2-1)) begin
                        s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) ) | 16'h8000;
                    end else begin
                        s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) );
                    end
                    s_axis_dsc.tvalid = (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(2));
                end else begin
                    s_axis_dsc.tdata[0 +: 16] = ( 16'(2*T-1) + 16'(cnt1) ) | 16'h8000;
                    s_axis_dsc.tvalid = (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(4));
                end
            end
            default: begin
                s_axis_dsc.tdata = '0;
                s_axis_dsc.tvalid = 1'b0;
            end
        endcase
    end
    // domain separation has always two bytes
    assign s_axis_dsc.tkeep = (DW/8)'(3);
    assign s_axis_dsc.tlast = 1'b1;

    always_comb begin
        s_axis_sample_i0[0].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[1].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[2].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b0};
        s_axis_sample_i0[6].tuser = {M_PASSTHROUGH, 1'b0};
        unique case (state)
            S_EXPAND_SK,
            S_SAMPLE_VT_W,
            S_SAMPLE_ETA_ZETA,
            S_GEN_D01,
            S_FIRST_RSP,
            S_CH_B: begin
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
                s_axis_sample_i0[6].tuser = {M_PACK_FP, 1'b0};
            end
            S_VRFY_BETA: begin
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            // Pack the syndrome
            S_PACK_KEYS: begin
                s_axis_sample_i0[2].tuser = {M_PACK_S, 1'b1};
            end
            // DSC is always the last input frame
            S_GEN_STREE: begin
                s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            S_ID_LOOP_CMT: begin
                // s tilde, \sigma_i or \delta_i, salt, dsc
                if (cmt1_gate_en == CMT1_ACTIVE) begin
                    s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
                end else begin
                    s_axis_sample_i0[2].tuser = {M_PACK_S, 1'b0};
                    s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[4].tuser = (cnt_lcmt0 == W_CNTL0'(6)) ? {M_PACK_FZ, 1'b0} : {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
                end
            end
            S_GEN_MTREE: begin
                s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            S_GEN_D1: begin
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            S_GEN_DBETA: begin
                s_axis_sample_i0[0].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            S_GEN_DB: begin
                s_axis_sample_i0[1].tuser = {M_PACK_FP, 1'b0};
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
            end
            S_PACK_RSP1: begin
                s_axis_sample_i0[4].tuser = (cnt2 >= W_CNT2'(T-W-1)) ? {M_PASSTHROUGH, 1'b1} : {M_PASSTHROUGH, 1'b0};
            end
            S_PACK_RSP0: begin
                s_axis_sample_i0[1].tuser = {M_PACK_FP, 1'b0};
                if (cnt2 >= W_CNT2'(T - W - 1)) begin
                    s_axis_sample_i0[4].tuser = {M_PACK_FZ, 1'b1};
                end else begin
                    s_axis_sample_i0[4].tuser = {M_PACK_FZ, 1'b0};
                end
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    // seed, salt, dsc
                    s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
                end else begin
                    // s tilde, \sigma_i or \delta_i, salt, dsc
                    s_axis_sample_i0[2].tuser = {M_PACK_S, 1'b0};
                    s_axis_sample_i0[4].tuser = (cnt_vrfy_loop == W_CNT_VRFY_LOOP'(2)) ? {M_PACK_FZ, 1'b0} : {M_PASSTHROUGH, 1'b0};
                    s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b1};
                end
            end
            default: begin
                s_axis_sample_i0[0].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[1].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[2].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[3].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[4].tuser = {M_PASSTHROUGH, 1'b0};
                s_axis_sample_i0[5].tuser = {M_PASSTHROUGH, 1'b0};
            end
        endcase
    end

    always_comb begin
        unique case(state)
            // Acknowledge challenge bit if b[i] = 1 (no cmt1[i] is packed)
            // or if b[i] = 0 and cmt1[i] has been loaded from memory
            // Same is true for tuple (y[i], \sigma[i] or \delta[i]) where
            // delta always on s_axis_sample_i0[4]
            S_PACK_RSP1: begin
                m_axis_ch_b_fifo.tready = ( (m_axis_ch_b_fifo.tvalid & m_axis_ch_b_fifo.tdata) | (`AXIS_LAST(s_axis_sample_i0[4])) );
            end
            S_PACK_RSP0: begin
                m_axis_ch_b_fifo.tready = ~rsp0_packed & ( (m_axis_ch_b_fifo.tvalid & m_axis_ch_b_fifo.tdata) | (`AXIS_LAST(s_axis_sample_i0[4])) );
            end
            // \delta or \sigma is the second element in our rsp0 tuple, so
            // it's fine to only acknowledge with `AXIS_LAST(s_axis_mux1_mem0[2])
            S_LOAD_RSP1,
            S_LOAD_RSP0: begin
                m_axis_ch_b_fifo.tready = ( (m_axis_ch_b_fifo.tvalid & m_axis_ch_b_fifo.tdata) | (`AXIS_LAST(s_axis_mux1_mem0[2])) );
            end
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tdata) begin
                    m_axis_ch_b_fifo.tready = `AXIS_LAST(s_axis_mux0_mem0[2]);
                end else begin
                    m_axis_ch_b_fifo.tready = `AXIS_LAST(s_axis_tree_i0[0]);
                end
            end
            default: begin
                m_axis_ch_b_fifo.tready = 1'b0;
            end
        endcase
    end

    //-----------------------------------------------------
    // Utility counter 0
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT0 )
    )
    u_cnt0
    (
        .clk,
        .rst_n,
        .max_val    ( cnt0_max      ),
        .inc        ( W_CNT0'(1)    ),
        .trigger    ( cnt0_en       ),
        .cnt        ( cnt0          )
    );
    always_comb begin
        cnt0_en  = 1'b0;
        cnt0_max = W_CNT0'(3);
        unique case(state)
            // Count seed_sk and dsc as input, seed_e and seed_pk as outputs
            S_EXPAND_SK: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[4])) || `AXIS_LAST(s_axis_sample_i0[5]) || (`AXIS_LAST(m_axis_sample_o1[1]));
                cnt0_max = W_CNT0'(4);
            end
            S_SAMPLE_VT_W: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]));
                cnt0_max = W_CNT0'(2);
            end
            // Count seed_e and dsc as input and generated eta/zeta as output
            S_SAMPLE_ETA_ZETA: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[4])) || (`AXIS_LAST(s_axis_sample_i0[5])) || (`AXIS_LAST(s_axis_mux0_mem0[2]));
                cnt0_max = sign_en ? W_CNT0'(3) : W_CNT0'(2);
            end
        `ifdef RSDPG
            S_EXPAND_ZETA: begin
                cnt0_en = (`AXIS_LAST(s_axis_mux1_mem0[1])) || (`AXIS_LAST(m_axis_demux0_mem0[0]));
                cnt0_max = W_CNT0'(2);
            end
        `endif
            // Count storing of sk_seed, pk_seed and syndrome as well
            // as streaming them to external world
            S_PACK_KEYS: begin
                cnt0_en = (`AXIS_LAST(s_axis_mux0_sigmem[0]) || `AXIS_LAST(s_axis_mux0_sigmem[1]) || `AXIS_LAST(m_axis_sig_keys));
                cnt0_max = W_CNT0'(6);
            end
            S_STORE_SK_MSEED_SALT: begin
                cnt0_en = (`AXIS_LAST(m_axis_demux_rng[0]) || `AXIS_LAST(m_axis_demux_rng[1]) || `AXIS_LAST(m_axis_demux_msg_keys[0]));
                cnt0_max = W_CNT0'(3);
            end
        `ifdef FAST
            // seed, salt, dsc
            S_GEN_STREE: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]));
                cnt0_max = W_CNT0'(3);
            end
        `else
            // seed, salt, dsc, two output seeds
            S_GEN_STREE: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]) || `AXIS_LAST(m_axis_sample_o1[2]));
                cnt0_max = W_CNT0'(5);
            end
        `endif
            S_GEN_D01: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]) ||`AXIS_LAST(s_axis_mux0_mem0[2]) || `AXIS_LAST(s_axis_compare[1]));
                cnt0_max = W_CNT0'(4);
            end
            S_GEN_DBETA: begin
                cnt0_en = (`AXIS_LAST(s_axis_sample_i0[0]) || `AXIS_LAST(s_axis_sample_i0[5]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_mux0_mem0[2]));
                cnt0_max = W_CNT0'(8);
            end
            S_FIRST_RSP: begin
                cnt0_en = ( `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]) || (`AXIS_LAST(s_axis_mux0_mem1[0]) && cnt1 >= W_CNT1'(T - 1)) );
                cnt0_max = W_CNT0'(3);
            end
            S_GEN_DB: begin
                cnt0_en = ( (`AXIS_LAST(m_axis_demux1_mem0[2])) || (`AXIS_LAST(s_axis_mux0_mem0[2]) || `AXIS_LAST(s_axis_compare[1])) );
                cnt0_max = W_CNT0'(2);
            end
            S_CH_B: begin
                cnt0_en = ( (`AXIS_LAST(m_axis_demux1_mem0[2]) || `AXIS_LAST(s_axis_sample_i0[5])) || (`AXIS_LAST(m_axis_demux0_mem0[1])) );
                cnt0_max = sign_en ? W_CNT0'(5) : W_CNT0'(2);
            end
            S_PACK_RSP0: begin
                cnt0_en = ( `AXIS_LAST(s_axis_sample_i0[1]) || `AXIS_LAST(s_axis_sample_i0[4]) );
                cnt0_max = W_CNT0'(2);
            end
            S_PARSE_DIGESTS: begin
                cnt0_en = `AXIS_LAST(s_axis_mux1_mem0[2]);
                cnt0_max = W_CNT0'(3);
            end
            S_LOAD_PK: begin
                cnt0_en = `AXIS_LAST(s_axis_mux1_mem0[2]);
                cnt0_max = W_CNT0'(2);
            end
            S_LOAD_RSP0: begin
                cnt0_en = `AXIS_LAST(s_axis_mux0_mem1[2]) || `AXIS_LAST(s_axis_mux1_mem0[2]);
                cnt0_max = W_CNT0'(2);
            end
            S_VRFY_BETA: begin
                cnt0_en = `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]) || (cnt0 >= W_CNT0'(1) && !sample_busy);
                cnt0_max = W_CNT0'(3);
            end
            default: begin
                cnt0_en  = 1'b0;
                cnt0_max = W_CNT0'(3);
            end
        endcase
    end

    //-----------------------------------------------------
    // Utility counter 1
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT1 )
    )
    u_cnt1
    (
        .clk,
        .rst_n,
        .max_val    ( cnt1_max      ),
        .inc        ( W_CNT1'(1)    ),
        .trigger    ( cnt1_en       ),
        .cnt        ( cnt1          )
    );
    always_comb begin
        cnt1_en  = 1'b0;
        cnt1_max = W_CNT1'(T);
        unique case(state)
            S_ID_LOOP_CMT: begin
                cnt1_en  = `AXIS_LAST(s_axis_tree_i0[0]);
                cnt1_max = W_CNT1'(T);
            end
        `ifdef FAST
            S_GEN_STREE: begin
                cnt1_en  = `AXIS_LAST(s_axis_tree_i0[0]);
                cnt1_max = W_CNT1'(T+4);
            end
            S_GEN_MTREE: begin
                cnt1_en  = `AXIS_LAST(s_axis_tree_i0[0]);
                cnt1_max = W_CNT1'(5);
            end
        `else
            S_GEN_MTREE: begin
                cnt1_en  = sign_en && `AXIS_LAST(s_axis_tree_i0[0]);
                cnt1_max = W_CNT1'(T-1);
            end
        `endif
            S_GEN_D1: begin
                cnt1_en  = ( `AXIS_LAST(m_axis_demux1_mem0[2]) || `AXIS_LAST(s_axis_sample_i0[5]) || `AXIS_LAST(s_axis_mux0_mem0[2]) );
                cnt1_max = W_CNT1'(T+2);
            end
            S_FIRST_RSP: begin
                cnt1_en  = `AXIS_LAST(s_axis_mux0_mem1[0]);
                cnt1_max = W_CNT1'(T);
            end
            S_GEN_DB: begin
                cnt1_en  = ( `AXIS_LAST(m_axis_demux0_mem1[2]) || `AXIS_LAST(m_axis_demux1_mem0[2]) || `AXIS_LAST(s_axis_sample_i0[5]) );
                cnt1_max = sign_en ? W_CNT1'(2) : W_CNT1'(T+2);
            end
            S_PACK_RSP1,
            S_PACK_RSP0,
            S_LOAD_RSP1,
            S_LOAD_RSP0,
            S_VRFY_LOOP: begin
                cnt1_en  = `AXIS_TRANS(m_axis_ch_b_fifo);
                cnt1_max = W_CNT1'(T);
            end
            default: begin
                cnt1_en  = 1'b0;
                cnt1_max = W_CNT1'(T);
            end
        endcase
    end

    //-----------------------------------------------------
    // Utility counter 2
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT2 )
    )
    u_cnt2
    (
        .clk,
        .rst_n,
        .max_val    ( cnt2_max      ),
        .inc        ( W_CNT2'(1)    ),
        .trigger    ( cnt2_en       ),
        .cnt        ( cnt2          )
    );
    always_comb begin
        cnt2_en = 1'b0;
        cnt2_max = W_CNT2'(T-W);
        unique case(state)
            S_PACK_RSP1,
            S_PACK_RSP0: begin
                cnt2_en = `AXIS_LAST(s_axis_sample_i0[4]);
                cnt2_max = W_CNT2'(T-W);
            end
            S_VRFY_LOOP: begin
                cnt2_en = (m_axis_ch_b_fifo.tvalid & m_axis_ch_b_fifo.tdata)
                        && (`AXIS_LAST(s_axis_mux0_mem1[0]) || `AXIS_LAST(s_axis_mux0_mem0[2]));
                cnt2_max = W_CNT2'(2);
            end
            default: begin
                cnt2_en = 1'b0;
            end
        endcase
    end

    //-----------------------------------------------------
    // Counter specifically Merkle tree
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT_MTREE )
    )
    u_cnt_mtree
    (
        .clk,
        .rst_n,
    `ifdef FAST
        .max_val    ( W_CNT_MTREE'(T+4+5)   ),
    `else
        .max_val    ( W_CNT_MTREE'(3)       ),
    `endif
        .inc        ( W_CNT_MTREE'(1)       ),
        .trigger    ( cnt_mtree_en          ),
        .cnt        ( cnt_mtree             )
    );
    assign cnt_mtree_en = (state == S_GEN_MTREE) && (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[5]));

    //-----------------------------------------------------
    // Counter specifically for computation of cmt0
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNTL0 )
    )
    u_cnt_loop_cmt0
    (
        .clk,
        .rst_n,
        .max_val    ( W_CNTL0'(10)  ),
        .inc        ( W_CNTL0'(1)   ),
        .trigger    ( cnt_lcmt0_en  ),
        .cnt        ( cnt_lcmt0     )
    );
    assign cnt_lcmt0_en = ( state == S_ID_LOOP_CMT &&
                            (((`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5])) && cmt1_gate_en != CMT1_ACTIVE)
                            || `AXIS_LAST(s_axis_mux_alu_i1[1]) || `AXIS_LAST(s_axis_mux1_mem0[1])
                            || `AXIS_LAST(s_axis_sample_i0[2]) || `AXIS_LAST(s_axis_tree_i0[0])) );

    //-----------------------------------------------------
    // Counter specifically for computation of cmt1
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNTL1 )
    )
    u_cnt_loop_cmt1
    (
        .clk,
        .rst_n,
        .max_val    ( W_CNTL1'(4)  ),
        .inc        ( W_CNTL1'(1)   ),
        .trigger    ( cnt_lcmt1_en  ),
        .cnt        ( cnt_lcmt1     )
    );
    assign cnt_lcmt1_en = ( cmt1_gate_en == CMT1_ACTIVE &&
                            (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5])
                            || `AXIS_LAST(s_axis_mux0_mem0[2])) );


    //-----------------------------------------------------
    // Counter specifically for the verification loop
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT_VRFY_LOOP )
    )
    u_cnt_vrfy_loop
    (
        .clk,
        .rst_n,
        .max_val    ( cnt_vrfy_loop_max     ),
        .inc        ( W_CNT_VRFY_LOOP'(1)   ),
        .trigger    ( cnt_vrfy_loop_en      ),
        .cnt        ( cnt_vrfy_loop         )
    );
    always_comb begin
        cnt_vrfy_loop_en    = 1'b0;
        cnt_vrfy_loop_max   = W_CNT_VRFY_LOOP'(4);
        unique case(state)
            S_VRFY_LOOP: begin
                if (m_axis_ch_b_fifo.tvalid) begin
                    if (m_axis_ch_b_fifo.tdata) begin
                        cnt_vrfy_loop_en = (`AXIS_LAST(s_axis_sample_i0[3]) || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5])
                                || `AXIS_LAST(s_axis_mux0_mem1[0]) || `AXIS_LAST(s_axis_mux0_mem0[2]));
                        cnt_vrfy_loop_max = W_CNT_VRFY_LOOP'(4);
                    end else begin
                        cnt_vrfy_loop_en = (`AXIS_LAST(m_axis_demux1_mem0[2]) || `AXIS_LAST(m_axis_demux0_mem0[0]) || `AXIS_LAST(s_axis_sample_i0[2])
                                || `AXIS_LAST(s_axis_sample_i0[4]) || `AXIS_LAST(s_axis_sample_i0[5]) || `AXIS_LAST(s_axis_tree_i0[0]));
                        cnt_vrfy_loop_max = W_CNT_VRFY_LOOP'(6);
                    end
                end
            end
            default: begin
                cnt_vrfy_loop_en    = 1'b0;
                cnt_vrfy_loop_max   = W_CNT_VRFY_LOOP'(4);
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            vrfy_syn_loaded <= 1'b0;
        end else begin
            if (state == S_VRFY_LOOP && m_axis_ch_b_fifo.tvalid && !m_axis_ch_b_fifo.tdata) begin
                if ( cnt_vrfy_loop == W_CNT_VRFY_LOOP'(0) ) begin
                    if (`AXIS_LAST(m_axis_demux1_mem0[0]) ) begin
                        vrfy_syn_loaded <= 1'b1;
                    end
                end else begin
                    vrfy_syn_loaded <= 1'b0;
                end
            end
        end
    end

    //-----------------------------------------------------
    // Counter specifically for signature streaming
    //-----------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_CNT_STREAM )
    )
    u_cnt_stream
    (
        .clk,
        .rst_n,
        .max_val    ( W_CNT_STREAM'(5+2*TREE_NODES_TO_STORE)),
        .inc        ( W_CNT_STREAM'(1)  ),
        .trigger    ( cnt_stream_en     ),
        .cnt        ( cnt_stream        )
    );
    assign cnt_stream_en = (state == S_STREAM_SIG) && `AXIS_LAST(m_axis_sig_keys);

    //-----------------------------------------------------
    // Registering addresses instead of multiplying them
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            cmt1_addr_q  <= MEM0_ADDR_CMT_1;
        end else begin
            unique case (state)
                S_ID_LOOP_CMT: begin
                    if ( `AXIS_LAST(s_axis_tree_i0[0]) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            cmt1_addr_q <= MEM0_ADDR_CMT_1;
                        end else begin
                            cmt1_addr_q <= cmt1_addr_q + MEM0_AW'(WORDS_PER_HASH);
                        end
                    end
                end
                S_VRFY_LOOP,
                S_LOAD_RSP1,
                S_PACK_RSP1: begin
                    if ( `AXIS_TRANS(m_axis_ch_b_fifo) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            cmt1_addr_q <= MEM0_ADDR_CMT_1;
                        end else begin
                            cmt1_addr_q <= cmt1_addr_q + MEM0_AW'(WORDS_PER_HASH);
                        end
                    end
                end
                default: begin
                    cmt1_addr_q  <= MEM0_ADDR_CMT_1;
                end
            endcase
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            uy_addr_q  <= MEM1_ADDR_U_Y;
        end else begin
            unique case (state)
                S_VRFY_LOOP,
                S_LOAD_RSP0,
                S_PACK_RSP0: begin
                    if ( `AXIS_TRANS(m_axis_ch_b_fifo) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            uy_addr_q <= MEM1_ADDR_U_Y;
                        end else begin
                            uy_addr_q <= uy_addr_q + MEM1_AW'(WORDS_FP_VEC);
                        end
                    end
                end
                default: begin
                    uy_addr_q <= MEM1_ADDR_U_Y;
                end
            endcase
        end
    end

`ifdef RSDP
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            sigma_delta_addr_q  <= MEM0_ADDR_SIGMA_I;
        end else begin
            unique case (state)
                S_ID_LOOP_CMT: begin
                    if ( `AXIS_LAST(s_axis_tree_i0[0]) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            sigma_delta_addr_q <= MEM0_ADDR_SIGMA_I;
                        end else begin
                            sigma_delta_addr_q <= sigma_delta_addr_q + MEM0_AW'(WORDS_FZ_VEC);
                        end
                    end
                end
                S_VRFY_LOOP,
                S_PACK_RSP0,
                S_LOAD_RSP0: begin
                    if ( `AXIS_TRANS(m_axis_ch_b_fifo) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            sigma_delta_addr_q <= MEM0_ADDR_SIGMA_I;
                        end else begin
                            sigma_delta_addr_q <= sigma_delta_addr_q + MEM0_AW'(WORDS_FZ_VEC);
                        end
                    end
                end
                default: begin
                    sigma_delta_addr_q  <= MEM0_ADDR_SIGMA_I;
                end
            endcase
        end
    end
`else
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            sigma_delta_addr_q <= MEM0_ADDR_DELTA_I;
        end else begin
            unique case (state)
                S_ID_LOOP_CMT: begin
                    if ( `AXIS_LAST(s_axis_tree_i0[0]) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            sigma_delta_addr_q <= MEM0_ADDR_DELTA_I;
                        end else begin
                            sigma_delta_addr_q <= sigma_delta_addr_q + MEM0_AW'(WORDS_FZ_VEC);
                        end
                    end
                end
                S_VRFY_LOOP,
                S_PACK_RSP0,
                S_LOAD_RSP0: begin
                    if ( `AXIS_TRANS(m_axis_ch_b_fifo) ) begin
                        if (cnt1 >= W_CNT1'(T-1)) begin
                            sigma_delta_addr_q <= MEM0_ADDR_DELTA_I;
                        end else begin
                            sigma_delta_addr_q <= sigma_delta_addr_q + MEM0_AW'(WORDS_FZ_VEC);
                        end
                    end
                end
                default: begin
                    sigma_delta_addr_q <= MEM0_ADDR_DELTA_I;
                end
            endcase
        end
    end

    //-----------------------------------------------------
    // Gating signal to prevent undesired triggering of
    // memory operation
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            rsdpg_gate <= 1'b0;
        end else begin
            if (state == S_ID_LOOP_CMT) begin
                if (rsdpg_gate) begin
                    // Reset after s_tilde is generated
                    if ( `AXIS_LAST(s_axis_sample_i0[2]) ) begin
                        rsdpg_gate <= 1'b0;
                    end
                end else begin
                    // Set after \delta_i is read from memory
                    if ( (cnt_lcmt0 == W_CNTL0'(5)) && `AXIS_LAST(m_axis_demux1_mem0[1]) ) begin
                        rsdpg_gate <= 1'b1;
                    end
                end
            end
        end
    end
`endif

    //-----------------------------------------------------
    // Gating computation of cmt1 in ID loop iteration
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            cmt1_gate_en <= CMT1_IDLE;
        end else begin
            if (state == S_ID_LOOP_CMT) begin
                unique case( cmt1_gate_en )
                    CMT1_IDLE: begin
                        // Wait until sigma is stored
                        if ( `AXIS_LAST(s_axis_mux1_mem0[1]) ) begin
                            cmt1_gate_en <= CMT1_ACTIVE;
                        end
                    end
                    CMT1_ACTIVE: begin
                        if ( `AXIS_LAST(s_axis_mux0_mem0[2]) ) begin
                            cmt1_gate_en <= CMT1_WAIT;
                        end
                    end
                    CMT1_WAIT: begin
                        if ( `AXIS_LAST(s_axis_tree_i0[0]) ) begin
                            cmt1_gate_en <= CMT1_IDLE;
                        end
                    end
                    default: begin
                        cmt1_gate_en <= CMT1_IDLE;
                    end
                endcase
            end
        end
    end

    //-----------------------------------------------------
    // Gating sample on last tree computation to prevent
    // wrong command issued due to register stage delay
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            tree_computation_gated <= 1'b0;
        end else begin
            unique case (state)
                S_GEN_STREE: begin
                    if ( `AXIS_LAST(s_axis_tree_i0[0]) && cnt1 >= W_CNT1'(T+4-1) ) begin
                        tree_computation_gated <= 1'b1;
                    end
                    if ( tree_stree_computed ) begin
                        tree_computation_gated <= 1'b0;
                    end
                end
                S_GEN_MTREE: begin
                    if ( `AXIS_LAST(s_axis_tree_i0[0]) && cnt1 >= W_CNT1'(5 - 2) ) begin
                        tree_computation_gated <= 1'b1;
                    end
                end
                default: begin
                    tree_computation_gated <= 1'b0;
                end
            endcase
        end
    end

    //-----------------------------------------------------
    // Check if ALU was started to do keygen already
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            keygen_requested <= 1'b0;
        end else begin
            if (state == S_PACK_KEYS) begin
                if ( !alu_busy && alu_start ) begin
                    keygen_requested <= 1'b1;
                end
            end else begin
                keygen_requested <= 1'b0;
            end
        end
    end

    //-----------------------------------------------------
    // Check if rsp0 was packed already before tree
    // finished
    //-----------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            rsp0_packed <= 1'b0;
        end else begin
            if (state == S_PACK_RSP0) begin
                if ( `AXIS_LAST(m_axis_ch_b_fifo) ) begin
                    rsp0_packed <= 1'b1;
                end
            end else begin
                rsp0_packed <= 1'b0;
            end
        end
    end


//-----------------------------------------------------
// Test signals, performance counters etc.
//-----------------------------------------------------
if (TEST_EN) begin

    logic [23:0] test_cnt, test_cnt_online;
    logic test_done_val;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            test_cnt <= '0;
        end else begin
            if (keygen_en | sign_en | vrfy_en) begin
                if (state != S_TEST_CNT) begin
                    test_cnt <= test_cnt + 24'd1;
                end
            end else begin
                test_cnt <= '0;
            end
        end
    end

    logic keygen_en_online, sign_en_online, vrfy_en_online;

    assign keygen_en_online = keygen_en;
    assign sign_en_online = sign_en && (state == S_GEN_DBETA
                                        || state == S_FIRST_RSP
                                        || state == S_GEN_DB
                                        || state == S_CH_B
                                        || state == S_PACK_RSP1
                                        || state == S_PACK_RSP0
                                        || state == S_STREAM_SIG);
    assign vrfy_en_online = vrfy_en;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            test_cnt_online <= '0;
        end else begin
            if (keygen_en_online | sign_en_online | vrfy_en_online) begin
                if (state != S_TEST_CNT) begin
                    test_cnt_online <= test_cnt_online + 24'd1;
                end
            end else begin
                test_cnt_online <= '0;
            end
        end
    end


    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            test_done_val <= '0;
        end else begin
            if (keygen_done | sign_done | vrfy_done) begin
                test_done_val <= cross_op_done_val;
            end
        end
    end

    logic sel_test_mux;
    assign sel_test_mux = (state == S_TEST_CNT);

    AXIS #(.DATA_WIDTH(DW)) s_axis_test_mux[2]();

    axis_mux #( .N_SLAVES(2) )
    u_mux_test
    (
        .sel    ( sel_test_mux      ),
        .s_axis ( s_axis_test_mux   ),
        .m_axis ( m_axis_sig_keys   )
    );
    `AXIS_ASSIGN(s_axis_test_mux[0], m_axis_demux1_sigmem[0]);

    assign s_axis_test_mux[1].tdata = (DW'(test_cnt_online) << 32) | (DW'(test_done_val) << 24) | DW'(test_cnt);
    assign s_axis_test_mux[1].tkeep = (DW/8)'(127);
    assign s_axis_test_mux[1].tvalid = (state == S_TEST_CNT);
    assign s_axis_test_mux[1].tlast = 1'b1;

end else begin

    `AXIS_ASSIGN(m_axis_sig_keys, m_axis_demux1_sigmem[0] );
end

endmodule
