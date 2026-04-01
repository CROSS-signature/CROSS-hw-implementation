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
// @author: Francesco Antognazza <francesco.antognazza@polimi.it>

`timescale 1ps / 1ps

module arithmetic_unit
    import common_pkg::*;
    import arithmetic_unit_pkg::*;
    import cross_pkg::*;
#(
    parameter int unsigned STREAM_WIDTH = 64,
    parameter int unsigned MAT_DATA_WIDTH = 192,
    localparam int unsigned MAT_WORD_WIDTH = min(
        MAT_DATA_WIDTH, iceilfrac(max((N - K) * BITS_P, (N - M) * BITS_Z), 8) * 8
    ),
    localparam int unsigned K1 = STREAM_WIDTH / BITS_Z,
    localparam int unsigned K2 = STREAM_WIDTH / BITS_P,
`ifdef RSDPG
    localparam int unsigned K3 = MAT_WORD_WIDTH / BITS_Z,
`endif
    localparam int unsigned K4 = MAT_WORD_WIDTH / BITS_P
) (
    input  logic           clk_i,
    input  logic           rst_n,
    input  arithmetic_op_t op_i,
    input  logic           start_i,
    output logic           done_o,
    //
           AXIS.slave      in_0,
           AXIS.slave      in_1,
           AXIS.slave      in_2,
           AXIS.slave      in_3,
`ifdef RSDPG
           AXIS.slave      in_4,
`endif
           AXIS.slave      in_5,
           AXIS.master     out_0,
           AXIS.master     out_1,
           AXIS.master     out_2
);

    // -----------------------------------------------
    // Localparam definitions
    // -----------------------------------------------

    localparam int MAT_WORD_BYTES = MAT_WORD_WIDTH / 8;
    localparam int ETA_WORD_BYTES = STREAM_WIDTH / 8;

`ifdef RSDPG
    localparam int MUX1_INPUTS = 2;
    localparam int BITS_MUX1_INPUTS = $clog2(MUX1_INPUTS);
    localparam int MUX7_INPUTS = 2;
    localparam int BITS_MUX7_INPUTS = $clog2(MUX7_INPUTS);
`endif
    localparam int MUX2_INPUTS = 3;
    localparam int MUX3_INPUTS = 2;
    localparam int MUX4_INPUTS = 2;
    localparam int MUX6_INPUTS = 2;
    localparam int BITS_MUX2_INPUTS = $clog2(MUX2_INPUTS);
    localparam int BITS_MUX3_INPUTS = $clog2(MUX3_INPUTS);
    localparam int BITS_MUX4_INPUTS = $clog2(MUX4_INPUTS);
    localparam int BITS_MUX6_INPUTS = $clog2(MUX6_INPUTS);

`ifdef RSDPG
    localparam int DEMUX3_OUTPUTS = 2;  // I_1 sinks
    localparam int BITS_DEMUX3_OUTPUTS = $clog2(DEMUX3_OUTPUTS);
    localparam int DEMUX9_OUTPUTS = 2;  // I_5 sinks
    localparam int BITS_DEMUX9_OUTPUTS = $clog2(DEMUX9_OUTPUTS);
    localparam int DEMUX10_OUTPUTS = 2;
    localparam int BITS_DEMUX10_OUTPUTS = $clog2(DEMUX10_OUTPUTS);
`endif
    localparam int DEMUX1_OUTPUTS = 2;  // I_0 sinks
    localparam int DEMUX2_OUTPUTS = 2;  // I_2 sinks
    localparam int DEMUX4_OUTPUTS = 2;  // mux1 sinks
    localparam int DEMUX5_OUTPUTS = 2;  // exp_res sinks
    localparam int DEMUX6_OUTPUTS = 2;  // mul1_res sinks
    localparam int DEMUX7_OUTPUTS = 2;  // vmmulfp_res sinks
    localparam int DEMUX8_OUTPUTS = 2;  // beta sinks
    localparam int BITS_DEMUX1_OUTPUTS = $clog2(DEMUX1_OUTPUTS);
    localparam int BITS_DEMUX2_OUTPUTS = $clog2(DEMUX2_OUTPUTS);
    localparam int BITS_DEMUX4_OUTPUTS = $clog2(DEMUX4_OUTPUTS);
    localparam int BITS_DEMUX5_OUTPUTS = $clog2(DEMUX5_OUTPUTS);
    localparam int BITS_DEMUX6_OUTPUTS = $clog2(DEMUX6_OUTPUTS);
    localparam int BITS_DEMUX7_OUTPUTS = $clog2(DEMUX7_OUTPUTS);
    localparam int BITS_DEMUX8_OUTPUTS = $clog2(DEMUX8_OUTPUTS);

    localparam int V_MAT_ROWS = K;
`ifdef RSDPG
    localparam int W_MAT_ROWS = M;
    localparam int W_ROW_WORDS = iceilfrac(BITS_Z * (N - M), BITS_Z * K3);
`else
    localparam int W_MAT_ROWS = 0;
    localparam int W_ROW_WORDS = 0;
`endif
    localparam int V_ROW_WORDS = iceilfrac(BITS_P * (N - K), BITS_P * K4);
    localparam int ETA_VEC_WORDS = iceilfrac(BITS_Z * N, BITS_Z * K1);
    localparam int V_MAT_WORDS = V_MAT_ROWS * V_ROW_WORDS;
    localparam int W_MAT_WORDS = W_MAT_ROWS * W_ROW_WORDS;
    localparam int ETA_MAT_WORDS = T * ETA_VEC_WORDS;
    localparam int BITS_MEMV_FRAME_CTR = $clog2(V_MAT_ROWS);
    localparam int BITS_MEMETA_FRAME_CTR = $clog2(T);
    localparam int MEMVW_ADDR_WIDTH = $clog2(V_MAT_WORDS + W_MAT_WORDS);
    localparam int MEMETA_ADDR_WIDTH = $clog2(ETA_MAT_WORDS);
    localparam int BASE_ADDR_V = 0 + W_MAT_WORDS;
    localparam int BASE_ADDR_ETA = 0;
`ifdef RSDPG
    localparam int BITS_MEMW_FRAME_CTR = $clog2(W_MAT_ROWS);
    localparam int BASE_ADDR_W = 0;
    localparam int BITS_W_MAT_ROWS = $clog2(W_MAT_ROWS);
`endif
    localparam int BITS_V_MAT_ROWS = $clog2(V_MAT_ROWS);

    typedef enum logic [3:0] {
        IDLE,
        INIT_V_W,
        KEYGEN,
        SIGN_EXPAND_ETA,
        SIGN_COMMITMENTS_PREPARATION,
        SIGN_FIRST_ROUND_RESPONSES,
        VERIFY_CASE_B0,
        VERIFY_CASE_B1
    } fsm_state_t;
    fsm_state_t state_d, state_q;

    typedef enum logic {
        MEM_READ  = 0,
        MEM_WRITE
    } mem_op_t;

    // -----------------------------------------------
    // Definition of streams
    // -----------------------------------------------

    // streams for the memory adapters
    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    )
        m_axis_memv (), s_axis_memv ();
`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    )
        m_axis_memw (), s_axis_memw ();
`endif
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    )
        m_axis_memeta (), s_axis_memeta ();

`ifdef RSDPG
    // VMMULFZ
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    )
        vmmulfz_vec (), vmmulfz_res ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K3),
        .ELEM_WIDTH(BITS_Z)
    ) vmmulfz_mat ();
`endif

    // SUBFZ1
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    )
        sub1_op1 (), sub1_op2 (), sub1_res ();

`ifdef RSDPG
    // SUBFZ2
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    )
        sub2_op1 (), sub2_op2 (), sub2_res ();
`endif

    // EXP
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) exp_op ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) exp_res ();

    // MUL1
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    )
        mul1_op1 (), mul1_op2 (), mul1_res ();

    // ADD
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    )
        add_op1 (), add_op2 (), add_res ();

    // VMMULFP
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) vmmulfp_vec ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) vmmulfp_res ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K4),
        .ELEM_WIDTH(BITS_P)
    ) vmmulfp_mat ();

    // MUL2
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    )
        mul2_op1 (), mul2_op2 (), mul2_res ();

    // SUB3
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    )
        sub3_op1 (), sub3_op2 (), sub3_res ();

    // STREAM downconverter
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) downconv1_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) downconv1_out ();

    // STREAM upconverter

`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(BITS_Z),
        .ELEM_WIDTH(BITS_Z)
    ) upconv1_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K3),
        .ELEM_WIDTH(BITS_Z)
    ) upconv1_out ();
`endif

    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) upconv2_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K4),
        .ELEM_WIDTH(BITS_P)
    ) upconv2_out ();

    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) upconv3_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) upconv3_out ();

    // STREAM replicate
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) repl1_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) repl1_out ();

    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) repl2_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) repl2_out ();

    // STREAM broadcast
`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast1_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast1_out[2] ();
    logic en_broadcast1;
`endif

    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast2_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast2_out[2] ();
    logic en_broadcast2;

`ifdef RSDP
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast3_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) broadcast3_out[2] ();
    logic en_broadcast3;
`endif

    // STREAM keep decompress
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp2_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kdecomp2_out ();

    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp3_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) kdecomp3_out ();

    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp4_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) kdecomp4_out ();
`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp5_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K3),
        .ELEM_WIDTH(BITS_Z)
    ) kdecomp5_out ();
`endif
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp6_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kdecomp6_out ();

    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp7_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kdecomp7_out ();

    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp8_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K4),
        .ELEM_WIDTH(BITS_P)
    ) kdecomp8_out ();

    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp9_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kdecomp9_out ();

    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp10_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) kdecomp10_out ();

    // STREAM keep compress

    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) kcomp1_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp1_out ();

    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) kcomp2_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp2_out ();

    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kcomp3_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp3_out ();

    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kcomp4_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp4_out ();

    AXIS #(
        .DATA_WIDTH(BITS_P * K4),
        .ELEM_WIDTH(BITS_P)
    ) kcomp5_in ();
    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp5_out ();

`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(BITS_Z * K3),
        .ELEM_WIDTH(BITS_Z)
    ) kcomp6_in ();
    AXIS #(
        .DATA_WIDTH(MAT_WORD_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp6_out ();

    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) kcomp7_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp7_out ();

    // MUX1
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) mux1_out ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) mux1_in[MUX1_INPUTS] ();
`endif

    // MUX2
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) mux2_out ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) mux2_in[MUX2_INPUTS] ();

    // MUX3
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) mux3_out ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) mux3_in[MUX3_INPUTS] ();

    // MUX4
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) mux4_out ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) mux4_in[MUX4_INPUTS] ();

    // MUX6
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) mux6_out ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) mux6_in[MUX6_INPUTS] ();

`ifdef RSDPG
    // MUX7
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) mux7_out ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) mux7_in[MUX7_INPUTS] ();
`endif

    // DEMUX1
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux1_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux1_out[DEMUX1_OUTPUTS] ();

    // DEMUX2
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) demux2_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) demux2_out[DEMUX2_OUTPUTS] ();

`ifdef RSDPG
    // DEMUX3
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux3_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux3_out[DEMUX3_OUTPUTS] ();
`endif

    // DEMUX4
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux4_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux4_out[DEMUX4_OUTPUTS] ();

    // DEMUX5
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) demux5_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) demux5_out[DEMUX5_OUTPUTS] ();

    // DEMUX6
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) demux6_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P * K2),
        .ELEM_WIDTH(BITS_P)
    ) demux6_out[DEMUX6_OUTPUTS] ();

    // DEMUX7
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux7_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux7_out[DEMUX7_OUTPUTS] ();

    // DEMUX8
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux8_in ();
    AXIS #(
        .DATA_WIDTH(BITS_P),
        .ELEM_WIDTH(BITS_P)
    ) demux8_out[DEMUX8_OUTPUTS] ();

`ifdef RSDPG
    // DEMUX9
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) demux9_in ();
    AXIS #(
        .DATA_WIDTH(STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) demux9_out[DEMUX9_OUTPUTS] ();

    // DEMUX10
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux10_in ();
    AXIS #(
        .DATA_WIDTH(BITS_Z * K1),
        .ELEM_WIDTH(BITS_Z)
    ) demux10_out[DEMUX10_OUTPUTS] ();
`endif

    // -----------------------------------------------
    // Definition of signals
    // -----------------------------------------------

    logic done_d, done_q;
    logic [BITS_V_MAT_ROWS-1:0] v_ctr_d, v_ctr_q;
`ifdef RSDPG
    logic [BITS_W_MAT_ROWS-1:0] w_ctr_d, w_ctr_q;

    logic [BITS_MUX1_INPUTS-1:0] mux1_sel;
    logic [BITS_MUX7_INPUTS-1:0] mux7_sel;
    logic [BITS_DEMUX3_OUTPUTS-1:0] demux3_sel;
    logic [BITS_DEMUX9_OUTPUTS-1:0] demux9_sel;
    logic [BITS_DEMUX10_OUTPUTS-1:0] demux10_sel;
`endif
    logic [BITS_MUX2_INPUTS-1:0] mux2_sel;
    logic [BITS_MUX3_INPUTS-1:0] mux3_sel;
    logic [BITS_MUX4_INPUTS-1:0] mux4_sel;
    logic [BITS_MUX6_INPUTS-1:0] mux6_sel;
    logic [BITS_DEMUX1_OUTPUTS-1:0] demux1_sel;
    logic [BITS_DEMUX2_OUTPUTS-1:0] demux2_sel;
    logic [BITS_DEMUX4_OUTPUTS-1:0] demux4_sel;
    logic [BITS_DEMUX5_OUTPUTS-1:0] demux5_sel;
    logic [BITS_DEMUX6_OUTPUTS-1:0] demux6_sel;
    logic [BITS_DEMUX7_OUTPUTS-1:0] demux7_sel;
    logic [BITS_DEMUX8_OUTPUTS-1:0] demux8_sel;

    // Memory interface (for now SP RAM)
    logic memv_en;
    logic [MAT_WORD_BYTES-1:0] memv_we;
    logic [MEMVW_ADDR_WIDTH-1:0] memv_addr;
    logic [MAT_WORD_WIDTH + MAT_WORD_WIDTH/8-1:0] memv_wdata, memv_rdata;
    //
`ifdef RSDPG
    logic memw_en;
    logic [MAT_WORD_BYTES-1:0] memw_we;
    logic [MEMVW_ADDR_WIDTH-1:0] memw_addr;
    logic [MAT_WORD_WIDTH + MAT_WORD_WIDTH/8-1:0] memw_wdata, memw_rdata;
`else
    /* verilator lint_off UNUSED */
    logic [MAT_WORD_WIDTH + MAT_WORD_WIDTH/8-1:0] memw_empty;
`endif
    //
    logic memeta_en;
    logic [ETA_WORD_BYTES-1:0] memeta_we;
    logic [MEMETA_ADDR_WIDTH-1:0] memeta_addr;
    logic [MEMETA_ADDR_WIDTH-1:0] memeta_idx_w_d, memeta_idx_w_q;
    logic [MEMETA_ADDR_WIDTH-1:0] memeta_idx_r_d, memeta_idx_r_q;
    logic [STREAM_WIDTH + STREAM_WIDTH/8-1:0] memeta_wdata, memeta_rdata;
    /* verilator lint_off UNUSED */
    logic [STREAM_WIDTH + STREAM_WIDTH/8-1:0] memeta_empty;

    // Memory adapters
    logic [BITS_MEMV_FRAME_CTR-1:0] ctrl_memv_frame_cnt;
    logic [MEMVW_ADDR_WIDTH-1:0] ctrl_memv_addr;
    logic ctrl_memv_addr_valid, ctrl_memv_wr_rd;
    //
`ifdef RSDPG
    logic [BITS_MEMW_FRAME_CTR-1:0] ctrl_memw_frame_cnt;
    logic [MEMVW_ADDR_WIDTH-1:0] ctrl_memw_addr;
    logic ctrl_memw_addr_valid, ctrl_memw_wr_rd;
`endif
    //
    logic [BITS_MEMETA_FRAME_CTR-1:0] ctrl_memeta_frame_cnt;
    logic [MEMETA_ADDR_WIDTH-1:0] ctrl_memeta_addr;
    logic ctrl_memeta_addr_valid, ctrl_memeta_wr_rd;


    // Unit start/stop signals
    /* verilator lint_off UNUSED */
    logic vmmulfp_start, vmmulfp_done;
    /* verilator lint_off UNUSED */
    logic add_done;
    /* verilator lint_off UNUSED */
    logic sub1_done;
`ifdef RSDPG
    /* verilator lint_off UNUSED */
    logic vmmulfz_start, vmmulfz_done;
    /* verilator lint_off UNUSED */
    logic sub2_done;
    logic sub2_done_d, sub2_done_q;
`endif
    /* verilator lint_off UNUSED */
    logic sub3_done;
    /* verilator lint_off UNUSED */
    logic mul1_done;
    /* verilator lint_off UNUSED */
    logic mul2_done;
    /* verilator lint_off UNUSED */
    logic exp_start, exp_done;

    // -----------------------------------------------
    // Register update
    // -----------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin
            state_q <= IDLE;
            v_ctr_q <= 'b0;
`ifdef RSDPG
            w_ctr_q     <= 'b0;
            sub2_done_q <= 1'b0;
`endif
            memeta_idx_w_q <= MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA);
            memeta_idx_r_q <= MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA);
            done_q         <= 1'b0;
        end else begin
            state_q <= state_d;
            v_ctr_q <= v_ctr_d;
`ifdef RSDPG
            w_ctr_q     <= w_ctr_d;
            sub2_done_q <= sub2_done_d;
`endif
            memeta_idx_w_q <= memeta_idx_w_d;
            memeta_idx_r_q <= memeta_idx_r_d;
            done_q         <= done_d;
        end
    end

    // -----------------------------------------------
    // Finite State Machines
    // -----------------------------------------------
    always_comb begin : compute_FSM
        state_d = state_q;
        //
        ctrl_memv_addr = MEMVW_ADDR_WIDTH'(0);
        ctrl_memv_addr_valid = 1'b0;
        ctrl_memv_wr_rd = MEM_READ;
        ctrl_memv_frame_cnt = 'b0;
        //
        ctrl_memeta_addr = MEMETA_ADDR_WIDTH'(0);
        ctrl_memeta_addr_valid = 1'b0;
        ctrl_memeta_wr_rd = MEM_READ;
        ctrl_memeta_frame_cnt = 'b0;
        //
`ifdef RSDPG
        ctrl_memw_addr = MEMVW_ADDR_WIDTH'(0);
        ctrl_memw_addr_valid = 1'b0;
        ctrl_memw_wr_rd = MEM_READ;
        ctrl_memw_frame_cnt = 'b0;
        //
        mux1_sel = 'b0;
        mux7_sel = 'b0;
        demux3_sel = 'b0;
        demux9_sel = 'b0;
        demux10_sel = 'b0;
`endif
        mux2_sel = 'b0;
        mux3_sel = 'b0;
        mux4_sel = 'b0;
        mux6_sel = 'b0;
        demux1_sel = 'b1;
        demux2_sel = 'b0;
        demux4_sel = 'b0;
        demux5_sel = 'b0;
        demux6_sel = 'b0;
        demux7_sel = 'b0;
        demux8_sel = 'b0;
        //
        vmmulfp_start = 1'b0;
`ifdef RSDPG
        vmmulfz_start = 1'b0;
`endif
        exp_start = 1'b0;
        //
        v_ctr_d   = v_ctr_q;
`ifdef RSDPG
        w_ctr_d = w_ctr_q;
        sub2_done_d = sub2_done_q;
        en_broadcast1 = 1'b0;
`endif
        en_broadcast2 = 1'b0;
`ifdef RSDP
        en_broadcast3 = 1'b0;
`endif
        memeta_idx_w_d = memeta_idx_w_q;
        memeta_idx_r_d = memeta_idx_r_q;
        done_d = 1'b0;

        unique case (state_q)
            IDLE: begin
                if (start_i) begin
                    unique case (op_i)

                        arithmetic_unit_pkg::ARITH_OP_INIT: begin
                            state_d = INIT_V_W;

`ifdef RSDPG
                            // write W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_WRITE;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);
`endif
                            // write V
                            v_ctr_d = 'b0;
                            ctrl_memv_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_V);
                            ctrl_memv_addr_valid = 1'b1;
                            ctrl_memv_wr_rd = MEM_WRITE;
                            ctrl_memv_frame_cnt = BITS_MEMV_FRAME_CTR'(V_MAT_ROWS);
                        end

                        arithmetic_unit_pkg::ARITH_OP_KEYGEN: begin
                            state_d = KEYGEN;

`ifdef RSDPG
                            // read W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_READ;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);
`endif
                            // read V
                            v_ctr_d = 'b0;
                            ctrl_memv_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_V);
                            ctrl_memv_addr_valid = 1'b1;
                            ctrl_memv_wr_rd = MEM_READ;
                            ctrl_memv_frame_cnt = BITS_MEMV_FRAME_CTR'(V_MAT_ROWS);

`ifdef RSDPG
                            vmmulfz_start = 1'b1;
`endif
                            exp_start = 1'b1;
                            vmmulfp_start = 1'b1;
                        end

                        arithmetic_unit_pkg::ARITH_OP_SIGN_EXPAND_ETA: begin
`ifdef RSDPG
                            state_d = SIGN_EXPAND_ETA;

                            // read W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_READ;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);

                            vmmulfz_start = 1'b1;
`endif
                        end

                        arithmetic_unit_pkg::ARITH_OP_SIGN_COMMITMENTS_PREPARATION: begin
                            state_d = SIGN_COMMITMENTS_PREPARATION;

`ifdef RSDPG
                            // read W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_READ;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);
`endif
                            // read V
                            v_ctr_d = 'b0;
                            ctrl_memv_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_V);
                            ctrl_memv_addr_valid = 1'b1;
                            ctrl_memv_wr_rd = MEM_READ;
                            ctrl_memv_frame_cnt = BITS_MEMV_FRAME_CTR'(V_MAT_ROWS);
                            // write ETA
                            ctrl_memeta_addr = memeta_idx_w_q;
                            ctrl_memeta_addr_valid = 1'b1;
                            ctrl_memeta_wr_rd = MEM_WRITE;
                            ctrl_memeta_frame_cnt = BITS_MEMETA_FRAME_CTR'(1);

`ifdef RSDPG
                            vmmulfz_start = 1'b1;
`endif
                            exp_start = 1'b1;
                            vmmulfp_start = 1'b1;
                        end

                        arithmetic_unit_pkg::ARITH_OP_SIGN_FIRST_ROUND_RESPONSES: begin
                            state_d = SIGN_FIRST_ROUND_RESPONSES;

                            // read ETA through MEMETA port A
                            ctrl_memeta_addr = memeta_idx_r_q;
                            ctrl_memeta_addr_valid = 1'b1;
                            ctrl_memeta_frame_cnt = BITS_MEMETA_FRAME_CTR'(1);

                            exp_start = 1'b1;
                        end

                        arithmetic_unit_pkg::ARITH_OP_VERIFY_CASE_B0: begin
                            state_d = VERIFY_CASE_B0;

`ifdef RSDPG
                            // read W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_READ;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);
`endif
                            // read V
                            v_ctr_d = 'b0;
                            ctrl_memv_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_V);
                            ctrl_memv_addr_valid = 1'b1;
                            ctrl_memv_wr_rd = MEM_READ;
                            ctrl_memv_frame_cnt = BITS_MEMV_FRAME_CTR'(V_MAT_ROWS);

`ifdef RSDPG
                            vmmulfz_start = 1'b1;
`endif
                            exp_start = 1'b1;
                            vmmulfp_start = 1'b1;
                        end

                        arithmetic_unit_pkg::ARITH_OP_VERIFY_CASE_B1: begin
                            state_d = VERIFY_CASE_B1;

`ifdef RSDPG
                            // read W
                            w_ctr_d = 'b0;
                            ctrl_memw_addr = MEMVW_ADDR_WIDTH'(BASE_ADDR_W);
                            ctrl_memw_addr_valid = 1'b1;
                            ctrl_memw_wr_rd = MEM_READ;
                            ctrl_memw_frame_cnt = BITS_MEMW_FRAME_CTR'(W_MAT_ROWS);
`endif

`ifdef RSDPG
                            vmmulfz_start = 1'b1;
`endif
                            exp_start = 1'b1;
                        end

                        default: begin
                            state_d = IDLE;
                        end

                    endcase
                end
            end

            INIT_V_W: begin
                demux1_sel = BITS_DEMUX1_OUTPUTS'(0);

`ifdef RSDPG
                if (`AXIS_LAST(in_4)) begin
                    w_ctr_d = w_ctr_q + 1;
                    if (w_ctr_q == BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        if (v_ctr_q == BITS_MEMV_FRAME_CTR'(V_MAT_ROWS) || (
                            `AXIS_LAST(in_0)
                            && v_ctr_q >= BITS_MEMV_FRAME_CTR'(V_MAT_ROWS - 1))) begin
                            state_d = IDLE;
                            done_d  = 1'b1;
                        end
                    end
                end
`endif

                if (`AXIS_LAST(in_0)) begin
                    v_ctr_d = v_ctr_q + 1;
                    if (v_ctr_q == BITS_MEMV_FRAME_CTR'(V_MAT_ROWS - 1)) begin
`ifdef RSDPG
                        if (w_ctr_q == BITS_MEMW_FRAME_CTR'(W_MAT_ROWS) || (
                            `AXIS_LAST(in_4)
                            && w_ctr_q >= BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1))) begin
                            state_d = IDLE;
                            done_d  = 1'b1;
                        end
`else
                        state_d = IDLE;
                        done_d  = 1'b1;
`endif
                    end
                end
            end

            KEYGEN: begin
`ifdef RSDPG
                demux3_sel = BITS_DEMUX3_OUTPUTS'(1);
                mux1_sel = BITS_MUX1_INPUTS'(1);
                demux10_sel = BITS_DEMUX10_OUTPUTS'(0);
`endif
                demux4_sel = BITS_DEMUX4_OUTPUTS'(0);
                mux2_sel   = BITS_MUX2_INPUTS'(1);
                demux5_sel = BITS_DEMUX5_OUTPUTS'(1);
                mux3_sel   = BITS_MUX3_INPUTS'(1);
                demux7_sel = BITS_DEMUX7_OUTPUTS'(0);
                mux4_sel   = BITS_MUX4_INPUTS'(0);

`ifdef RSDPG
                if (`AXIS_LAST(m_axis_memw)) begin
                    if (w_ctr_q != BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        w_ctr_d = w_ctr_q + 1;
                    end
                end
`endif
                if (`AXIS_LAST(m_axis_memv)) begin
                    if (v_ctr_q != BITS_MEMV_FRAME_CTR'(V_MAT_ROWS - 1)) begin
                        v_ctr_d = v_ctr_q + 1;
                    end
                end

                if (`AXIS_LAST(vmmulfp_res)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                end
            end

            SIGN_EXPAND_ETA: begin
`ifdef RSDPG
                demux3_sel  = BITS_DEMUX3_OUTPUTS'(1);
                mux1_sel    = BITS_MUX1_INPUTS'(1);
                demux4_sel  = BITS_DEMUX4_OUTPUTS'(0);
                mux2_sel    = BITS_MUX2_INPUTS'(1);
                demux10_sel = BITS_DEMUX10_OUTPUTS'(1);
                mux7_sel    = BITS_MUX7_INPUTS'(0);
                if (`AXIS_LAST(m_axis_memw)) begin
                    if (w_ctr_q != BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        w_ctr_d = w_ctr_q + 1;
                    end
                end
                if (`AXIS_LAST(out_2)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                end
`endif
            end

            SIGN_COMMITMENTS_PREPARATION: begin
`ifdef RSDPG
                demux3_sel = BITS_DEMUX3_OUTPUTS'(1);
                mux1_sel   = BITS_MUX1_INPUTS'(1);
                if (sub2_done_q) begin
                    demux9_sel = BITS_DEMUX9_OUTPUTS'(1);
                end else begin
                    demux9_sel = BITS_DEMUX9_OUTPUTS'(0);
                end
                mux7_sel    = BITS_MUX7_INPUTS'(1);
                demux10_sel = BITS_DEMUX10_OUTPUTS'(0);
`endif
                demux4_sel = BITS_DEMUX4_OUTPUTS'(1);
                mux2_sel   = BITS_MUX2_INPUTS'(2);
                demux5_sel = BITS_DEMUX5_OUTPUTS'(0);
                mux6_sel   = BITS_MUX6_INPUTS'(0);
                demux6_sel = BITS_DEMUX6_OUTPUTS'(1);
                mux3_sel   = BITS_MUX3_INPUTS'(0);
                demux7_sel = BITS_DEMUX7_OUTPUTS'(0);
                mux4_sel   = BITS_MUX4_INPUTS'(0);
`ifdef RSDPG
                en_broadcast1 = 1'b1;
`endif
                en_broadcast2 = 1'b1;
`ifdef RSDP
                en_broadcast3 = 1'b1;
`endif

`ifdef RSDPG
                if (sub2_done) begin
                    sub2_done_d = 1'b1;
                end

                if (`AXIS_LAST(m_axis_memw)) begin
                    if (w_ctr_q != BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        w_ctr_d = w_ctr_q + 1;
                    end
                end
`endif
                if (`AXIS_LAST(m_axis_memv)) begin
                    if (v_ctr_q != BITS_MEMV_FRAME_CTR'(V_MAT_ROWS - 1)) begin
                        v_ctr_d = v_ctr_q + 1;
                    end
                end

                if (`AXIS_LAST(vmmulfp_res)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                    if (memeta_idx_w_q == MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA + ETA_VEC_WORDS * (T-1))) begin
                        memeta_idx_w_d = MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA);
                    end else begin
                        memeta_idx_w_d = memeta_idx_w_q + MEMETA_ADDR_WIDTH'(ETA_VEC_WORDS);
                    end
`ifdef RSDPG
                    sub2_done_d = 1'b0;
`endif
                end
            end

            SIGN_FIRST_ROUND_RESPONSES: begin
                mux2_sel   = BITS_MUX2_INPUTS'(0);
                demux1_sel = BITS_DEMUX1_OUTPUTS'(1);
                demux8_sel = BITS_DEMUX8_OUTPUTS'(0);
                mux6_sel   = BITS_MUX6_INPUTS'(1);
                demux5_sel = BITS_DEMUX5_OUTPUTS'(0);
                demux6_sel = BITS_DEMUX6_OUTPUTS'(0);
                demux2_sel = BITS_DEMUX2_OUTPUTS'(1);
`ifdef RSDPG
                demux10_sel = BITS_DEMUX10_OUTPUTS'(0);
`endif

                if (`AXIS_LAST(add_res)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                    if (memeta_idx_r_q == MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA + ETA_VEC_WORDS * (T-1))) begin
                        memeta_idx_r_d = MEMETA_ADDR_WIDTH'(BASE_ADDR_ETA);
                    end else begin
                        memeta_idx_r_d = memeta_idx_r_q + MEMETA_ADDR_WIDTH'(ETA_VEC_WORDS);
                    end
                end
            end

            VERIFY_CASE_B0: begin
`ifdef RSDPG
                demux3_sel = BITS_DEMUX3_OUTPUTS'(1);
                mux1_sel = BITS_MUX1_INPUTS'(1);
                demux10_sel = BITS_DEMUX10_OUTPUTS'(0);
`endif
                demux4_sel = BITS_DEMUX4_OUTPUTS'(0);
                mux2_sel   = BITS_MUX2_INPUTS'(1);
                demux5_sel = BITS_DEMUX5_OUTPUTS'(0);
                mux6_sel   = BITS_MUX6_INPUTS'(0);
                demux1_sel = BITS_DEMUX1_OUTPUTS'(1);
                demux8_sel = BITS_DEMUX8_OUTPUTS'(1);
                demux6_sel = BITS_DEMUX6_OUTPUTS'(1);
                mux3_sel   = BITS_MUX3_INPUTS'(0);
                demux2_sel = BITS_DEMUX2_OUTPUTS'(0);
                demux7_sel = BITS_DEMUX7_OUTPUTS'(1);
                mux4_sel   = BITS_MUX4_INPUTS'(1);

`ifdef RSDPG
                if (`AXIS_LAST(m_axis_memw)) begin
                    if (w_ctr_q != BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        w_ctr_d = w_ctr_q + 1;
                    end
                end
`endif
                if (`AXIS_LAST(m_axis_memv)) begin
                    if (v_ctr_q != BITS_MEMV_FRAME_CTR'(V_MAT_ROWS - 1)) begin
                        v_ctr_d = v_ctr_q + 1;
                    end
                end

                if (`AXIS_LAST(sub3_res)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                end
            end

            VERIFY_CASE_B1: begin
`ifdef RSDPG
                demux3_sel = BITS_DEMUX3_OUTPUTS'(1);
                mux1_sel = BITS_MUX1_INPUTS'(1);
                demux10_sel = BITS_DEMUX10_OUTPUTS'(0);
`endif
                demux4_sel = BITS_DEMUX4_OUTPUTS'(0);
                mux2_sel   = BITS_MUX2_INPUTS'(1);
                demux5_sel = BITS_DEMUX5_OUTPUTS'(0);
                mux6_sel   = BITS_MUX6_INPUTS'(1);
                demux1_sel = BITS_DEMUX1_OUTPUTS'(1);
                demux8_sel = BITS_DEMUX8_OUTPUTS'(0);
                demux2_sel = BITS_DEMUX2_OUTPUTS'(1);
                demux6_sel = BITS_DEMUX6_OUTPUTS'(0);

`ifdef RSDPG
                if (`AXIS_LAST(m_axis_memw)) begin
                    if (w_ctr_q != BITS_MEMW_FRAME_CTR'(W_MAT_ROWS - 1)) begin
                        w_ctr_d = w_ctr_q + 1;
                    end
                end
`endif
                if (`AXIS_LAST(add_res)) begin
                    state_d = IDLE;
                    done_d  = 1'b1;
                end
            end
        endcase
    end

    assign done_o = done_q;

    // -----------------------------------------------
    // Piping stuff
    // -----------------------------------------------

    // MUX IN-OUT
`ifdef RSDPG
    `AXIS_ASSIGN(mux1_in[0], demux3_out[0]);
    `AXIS_ASSIGN(mux1_in[1], vmmulfz_res);
`endif
    `AXIS_ASSIGN(demux4_in, broadcast2_out[0]);

    `AXIS_ASSIGN(mux2_in[0], kdecomp7_out);
    `AXIS_ASSIGN(mux2_in[1], demux4_out[0]);
    `AXIS_ASSIGN(mux2_in[2], sub1_res);

    `AXIS_ASSIGN(mux3_in[0], demux6_out[1]);
    `AXIS_ASSIGN(mux3_in[1], demux5_out[1]);
    `AXIS_ASSIGN(vmmulfp_vec, mux3_out);

    `AXIS_ASSIGN(mux4_in[0], demux7_out[0]);
    `AXIS_ASSIGN(mux4_in[1], sub3_res);
    `AXIS_ASSIGN(upconv3_in, mux4_out);
    `AXIS_ASSIGN(kcomp1_in, upconv3_out)

    `AXIS_ASSIGN(mux6_in[0], kdecomp4_out);
    `AXIS_ASSIGN(mux6_in[1], repl1_out);
    `AXIS_ASSIGN(mul1_op1, mux6_out);

`ifdef RSDPG
    `AXIS_ASSIGN(kcomp3_in, sub2_res);
`else
    `AXIS_ASSIGN(kcomp3_in, broadcast3_out[1]);
`endif

    `AXIS_ASSIGN(sub1_op1, kdecomp9_out);

    // DEMUX IN-OUT
    `AXIS_ASSIGN(demux1_in, in_0);
    `AXIS_ASSIGN(upconv2_in, demux1_out[0]);
    `AXIS_ASSIGN(kcomp5_in, upconv2_out)
    `AXIS_ASSIGN(s_axis_memv, kcomp5_out);
    `AXIS_ASSIGN(repl1_in, demux8_out[0]);

    `AXIS_ASSIGN(demux2_in, in_2);
    `AXIS_ASSIGN(downconv1_in, kdecomp3_out);
    `AXIS_ASSIGN(add_op1, kdecomp10_out);

    `AXIS_ASSIGN(sub1_op2, demux4_out[1]);

    `AXIS_ASSIGN(demux5_in, exp_res);
    `AXIS_ASSIGN(mul1_op2, demux5_out[0]);

    `AXIS_ASSIGN(demux6_in, mul1_res);
    `AXIS_ASSIGN(add_op2, demux6_out[0]);

    `AXIS_ASSIGN(demux7_in, vmmulfp_res);
    `AXIS_ASSIGN(sub3_op1, demux7_out[1]);

    `AXIS_ASSIGN(demux8_in, demux1_out[1]);
    `AXIS_ASSIGN(mul2_op1, repl2_out);

`ifdef RSDPG
    `AXIS_ASSIGN(demux9_in, in_5);
    `AXIS_ASSIGN(kdecomp9_in, demux9_out[1]);
    `AXIS_ASSIGN(kdecomp6_in, demux9_out[0]);
`else
    `AXIS_ASSIGN(kdecomp9_in, in_5);
`endif

    `AXIS_ASSIGN(vmmulfp_mat, kdecomp8_out);

`ifdef RSDPG
    `AXIS_ASSIGN(demux10_in, mux2_out);
    `AXIS_ASSIGN(exp_op, demux10_out[0]);
    `AXIS_ASSIGN(kcomp7_in, demux10_out[1]);
    `AXIS_ASSIGN(mux7_in[0], kcomp7_out);
    `AXIS_ASSIGN(mux7_in[1], kcomp3_out);
`else
    `AXIS_ASSIGN(exp_op, broadcast3_out[0]);
    `AXIS_ASSIGN(broadcast3_in, mux2_out);
`endif

    `AXIS_ASSIGN(sub3_op2, mul2_res);

    `AXIS_ASSIGN(kcomp2_in, add_res);

    `AXIS_ASSIGN(kdecomp2_in, in_1);
    `AXIS_ASSIGN(kdecomp3_in, demux2_out[0]);
    `AXIS_ASSIGN(kdecomp4_in, in_3);
    `AXIS_ASSIGN(kdecomp7_in, m_axis_memeta);
    `AXIS_ASSIGN(kdecomp8_in, m_axis_memv);
    `AXIS_ASSIGN(kdecomp10_in, demux2_out[1]);
    `AXIS_ASSIGN(out_0, kcomp1_out);
    `AXIS_ASSIGN(out_1, kcomp2_out);
`ifdef RSDPG
    `AXIS_ASSIGN(out_2, mux7_out);
`else
    `AXIS_ASSIGN(out_2, kcomp3_out);
`endif

    `AXIS_ASSIGN(s_axis_memeta, kcomp4_out);

`ifdef RSDPG
    `AXIS_ASSIGN(sub2_op1, kdecomp6_out);
    `AXIS_ASSIGN(broadcast1_in, demux3_out[1]);
    `AXIS_ASSIGN(broadcast2_in, mux1_out);
    `AXIS_ASSIGN(sub2_op2, broadcast1_out[1]);
`else
    `AXIS_ASSIGN(broadcast2_in, kdecomp2_out);
`endif

    `AXIS_ASSIGN(kcomp4_in, broadcast2_out[1]);

`ifdef RSDPG
    `AXIS_ASSIGN(demux3_in, kdecomp2_out);
    `AXIS_ASSIGN(vmmulfz_vec, broadcast1_out[0]);
    `AXIS_ASSIGN(vmmulfz_mat, kdecomp5_out);
    `AXIS_ASSIGN(kdecomp5_in, m_axis_memw);
    `AXIS_ASSIGN(upconv1_in, in_4);
    `AXIS_ASSIGN(kcomp6_in, upconv1_out);
    `AXIS_ASSIGN(s_axis_memw, kcomp6_out);
`endif

    `AXIS_ASSIGN(mul2_op2, downconv1_out);
    `AXIS_ASSIGN(repl2_in, demux8_out[1]);

    // -----------------------------------------------
    // Stream converters
    // -----------------------------------------------
    width_converter #(
        .ELEM_WIDTH(BITS_P)
    ) u_conv_mul2_op2 (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(downconv1_in),
        .m_axis(downconv1_out)
    );
`ifdef RSDPG
    width_converter #(
        .ELEM_WIDTH(BITS_Z)
    ) u_conv_memw (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(upconv1_in),
        .m_axis(upconv1_out)
    );
`endif
    width_converter #(
        .ELEM_WIDTH(BITS_P)
    ) u_conv_memv (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(upconv2_in),
        .m_axis(upconv2_out)
    );
    width_converter #(
        .ELEM_WIDTH(BITS_P)
    ) u_conv_out0 (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(upconv3_in),
        .m_axis(upconv3_out)
    );
    axis_replicate #(
        .ELEM_WIDTH(BITS_P),
        .COUNT(N)
    ) u_conv_beta_replicate_mul1 (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(repl1_in),
        .m_axis(repl1_out)
    );
    axis_replicate #(
        .ELEM_WIDTH(BITS_P),
        .COUNT(N - K)
    ) u_conv_beta_replicate_mul2 (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(repl2_in),
        .m_axis(repl2_out)
    );
`ifdef RSDPG
    axis_clone u_broadcast_in_1 (
        .clk   (clk_i),
        .rst_n (rst_n),
        .sel   ({en_broadcast1, 1'b1}),
        .s_axis(broadcast1_in),
        .m_axis(broadcast1_out)
    );
`endif
    axis_clone u_broadcast_mux1_out (
        .clk   (clk_i),
        .rst_n (rst_n),
        .sel   ({en_broadcast2, 1'b1}),
        .s_axis(broadcast2_in),
        .m_axis(broadcast2_out)
    );
`ifdef RSDP
    axis_clone u_broadcast_mux2_out (
        .clk   (clk_i),
        .rst_n (rst_n),
        .sel   ({en_broadcast3, 1'b1}),
        .s_axis(broadcast3_in),
        .m_axis(broadcast3_out)
    );
`endif

`ifdef RSDP
    localparam element_type_t ELEM_TYPE_IN1 = ELEM_TYPE_FZ_N;  // eta, eta', sigma
`elsif RSDPG
    localparam element_type_t ELEM_TYPE_IN1 = ELEM_TYPE_FZ_M;  // zeta, zeta', delta
`endif
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_IN1)
    ) u_kdecomp_in1 (
        .s_axis(kdecomp2_in),
        .m_axis(kdecomp2_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_NK)
    ) u_kdecomp_mul2 (
        .s_axis(kdecomp3_in),
        .m_axis(kdecomp3_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_N)
    ) u_kdecomp_in3 (
        .s_axis(kdecomp4_in),
        .m_axis(kdecomp4_out)
    );
`ifdef RSDPG
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_NM)
    ) u_kdecomp_memw (
        .s_axis(kdecomp5_in),
        .m_axis(kdecomp5_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_M)
    ) u_kdecomp_sub2 (
        .s_axis(kdecomp6_in),
        .m_axis(kdecomp6_out)
    );
`endif
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_N)
    ) u_kdecomp_memeta (
        .s_axis(kdecomp7_in),
        .m_axis(kdecomp7_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_NK)
    ) u_kdecomp_memv (
        .s_axis(kdecomp8_in),
        .m_axis(kdecomp8_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_N)
    ) u_kdecomp_sub1 (
        .s_axis(kdecomp9_in),
        .m_axis(kdecomp9_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_N)
    ) u_kdecomp_add (
        .s_axis(kdecomp10_in),
        .m_axis(kdecomp10_out)
    );

    axis_keep_compress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_NK)
    ) u_kcomp_out0 (
        .s_axis(kcomp1_in),
        .m_axis(kcomp1_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_N)
    ) u_kcomp_out1 (
        .s_axis(kcomp2_in),
        .m_axis(kcomp2_out)
    );
`ifdef RSDP
    localparam element_type_t ELEM_TYPE_OUT2 = ELEM_TYPE_FZ_N;  // sigma
`elsif RSDPG
    localparam element_type_t ELEM_TYPE_OUT2 = ELEM_TYPE_FZ_M;  // delta
`endif
    axis_keep_compress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_OUT2)
    ) u_kcomp_out2_sigma (
        .s_axis(kcomp3_in),
        .m_axis(kcomp3_out)
    );

    axis_keep_compress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FP_N)
    ) u_kcomp_memeta (
        .s_axis(kcomp4_in),
        .m_axis(kcomp4_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(BITS_P),
        .ELEM_TYPE (ELEM_TYPE_FP_NK)
    ) u_kcomp_memv (
        .s_axis(kcomp5_in),
        .m_axis(kcomp5_out)
    );
`ifdef RSDPG
    axis_keep_compress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_NM)
    ) u_kcomp_memw (
        .s_axis(kcomp6_in),
        .m_axis(kcomp6_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(BITS_Z),
        .ELEM_TYPE (ELEM_TYPE_FZ_N)
    ) u_kcomp_eta (
        .s_axis(kcomp7_in),
        .m_axis(kcomp7_out)
    );
`endif

    // -----------------------------------------------
    // AXIS_MEM adapter
    // -----------------------------------------------
`ifdef RSDPG
    axis_ram_adapter #(
        .MEM_DW         (MAT_WORD_WIDTH + MAT_WORD_WIDTH / 8),
        .MEM_AW         (MEMVW_ADDR_WIDTH),
        .FRAME_CNT_WIDTH(BITS_MEMW_FRAME_CTR),
        .AXIS_DW        (MAT_WORD_WIDTH)
    ) u_memw_adapter (
        .clk                (clk_i),
        .rst_n              (rst_n),
        .base_addr          (ctrl_memw_addr),
        .base_addr_valid    (ctrl_memw_addr_valid),
        .base_addr_wr_rd    (ctrl_memw_wr_rd),
        .base_addr_frame_cnt(ctrl_memw_frame_cnt),
        .mem_en             (memw_en),
        .mem_we             (memw_we),
        .mem_addr           (memw_addr),
        .mem_wdata          (memw_wdata),
        .mem_rdata          (memw_rdata),
        .s_axis             (s_axis_memw),
        .m_axis             (m_axis_memw)
    );
`endif

    axis_ram_adapter #(
        .MEM_DW         (MAT_WORD_WIDTH + MAT_WORD_WIDTH / 8),
        .MEM_AW         (MEMVW_ADDR_WIDTH),
        .FRAME_CNT_WIDTH(BITS_MEMV_FRAME_CTR),
        .AXIS_DW        (MAT_WORD_WIDTH)
    ) u_memv_adapter (
        .clk                (clk_i),
        .rst_n              (rst_n),
        .base_addr          (ctrl_memv_addr),
        .base_addr_valid    (ctrl_memv_addr_valid),
        .base_addr_wr_rd    (ctrl_memv_wr_rd),
        .base_addr_frame_cnt(ctrl_memv_frame_cnt),
        .mem_en             (memv_en),
        .mem_we             (memv_we),
        .mem_addr           (memv_addr),
        .mem_wdata          (memv_wdata),
        .mem_rdata          (memv_rdata),
        .s_axis             (s_axis_memv),
        .m_axis             (m_axis_memv)
    );

    axis_ram_adapter #(
        .MEM_DW         (STREAM_WIDTH + STREAM_WIDTH / 8),
        .MEM_AW         (MEMETA_ADDR_WIDTH),
        .FRAME_CNT_WIDTH(BITS_MEMETA_FRAME_CTR),
        .AXIS_DW        (STREAM_WIDTH)
    ) u_memeta_adapter (
        .clk                (clk_i),
        .rst_n              (rst_n),
        .base_addr          (ctrl_memeta_addr),
        .base_addr_valid    (ctrl_memeta_addr_valid),
        .base_addr_wr_rd    (ctrl_memeta_wr_rd),
        .base_addr_frame_cnt(ctrl_memeta_frame_cnt),
        .mem_en             (memeta_en),
        .mem_we             (memeta_we),
        .mem_addr           (memeta_addr),
        .mem_wdata          (memeta_wdata),
        .mem_rdata          (memeta_rdata),
        .s_axis             (s_axis_memeta),
        .m_axis             (m_axis_memeta)
    );

    // -----------------------------------------------
    // SRAM
    // -----------------------------------------------
    dp_ram_parity #(
        .DATA_WIDTH  (MAT_WORD_WIDTH + MAT_WORD_WIDTH / 8),
        .PARITY_WIDTH(MAT_WORD_WIDTH / 8),
        .DEPTH       (W_MAT_WORDS + V_MAT_WORDS)
    ) u_memvw (
        .clk_a    (clk_i),
        .en_a_i   (memv_en),
        .we_a_i   (memv_we),
        .addr_a_i (memv_addr),
        .wdata_a_i(memv_wdata),
        .rdata_a_o(memv_rdata),

`ifdef RSDPG
        .clk_b    (clk_i),
        .en_b_i   (memw_en),
        .we_b_i   (memw_we),
        .addr_b_i (memw_addr),
        .wdata_b_i(memw_wdata),
        .rdata_b_o(memw_rdata)
`else
        .clk_b    (clk_i),
        .en_b_i   (1'b0),
        .we_b_i   ('b0),
        .addr_b_i ('b0),
        .wdata_b_i('b0),
        .rdata_b_o(memw_empty)
`endif
    );

    dp_ram_parity #(
        .DATA_WIDTH  (STREAM_WIDTH + STREAM_WIDTH / 8),
        .PARITY_WIDTH(STREAM_WIDTH / 8),
        .DEPTH       (ETA_MAT_WORDS)
    ) u_memeta (
        .clk_a    (clk_i),
        .en_a_i   (memeta_en),
        .we_a_i   (memeta_we),
        .addr_a_i (memeta_addr),
        .wdata_a_i(memeta_wdata),
        .rdata_a_o(memeta_rdata),

        .clk_b    (clk_i),
        .en_b_i   (1'b0),
        .we_b_i   ('b0),
        .addr_b_i ('b0),
        .wdata_b_i('b0),
        .rdata_b_o(memeta_empty)
    );

    //-----------------------------------------------
    // Instantiation of multiplexers and demultiplexers
    //-----------------------------------------------
`ifdef RSDPG
    axis_mux #(
        .N_SLAVES (MUX1_INPUTS),
        .BITS_ELEM(BITS_Z)
    ) u_axis_mux1 (
        .sel   (mux1_sel),
        .s_axis(mux1_in),
        .m_axis(mux1_out)
    );
`endif
    axis_mux #(
        .N_SLAVES (MUX2_INPUTS),
        .BITS_ELEM(BITS_Z)
    ) u_axis_mux2 (
        .sel   (mux2_sel),
        .s_axis(mux2_in),
        .m_axis(mux2_out)
    );
    axis_mux #(
        .N_SLAVES (MUX3_INPUTS),
        .BITS_ELEM(BITS_P)
    ) u_axis_mux3 (
        .sel   (mux3_sel),
        .s_axis(mux3_in),
        .m_axis(mux3_out)
    );
    axis_mux #(
        .N_SLAVES (MUX4_INPUTS),
        .BITS_ELEM(BITS_P)
    ) u_axis_mux4 (
        .sel   (mux4_sel),
        .s_axis(mux4_in),
        .m_axis(mux4_out)
    );
    axis_mux #(
        .N_SLAVES (MUX6_INPUTS),
        .BITS_ELEM(BITS_P)
    ) u_axis_mux6 (
        .sel   (mux6_sel),
        .s_axis(mux6_in),
        .m_axis(mux6_out)
    );
`ifdef RSDPG
    axis_mux #(
        .N_SLAVES (MUX7_INPUTS),
        .BITS_ELEM(8)
    ) u_axis_mux7 (
        .sel   (mux7_sel),
        .s_axis(mux7_in),
        .m_axis(mux7_out)
    );
`endif

    axis_demux #(
        .N_MASTERS(DEMUX1_OUTPUTS)
    ) u_axis_demux1 (
        .sel   (demux1_sel),
        .s_axis(demux1_in),
        .m_axis(demux1_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX2_OUTPUTS)
    ) u_axis_demux2 (
        .sel   (demux2_sel),
        .s_axis(demux2_in),
        .m_axis(demux2_out)
    );
`ifdef RSDPG
    axis_demux #(
        .N_MASTERS(DEMUX3_OUTPUTS)
    ) u_axis_demux3 (
        .sel   (demux3_sel),
        .s_axis(demux3_in),
        .m_axis(demux3_out)
    );
`endif
    axis_demux #(
        .N_MASTERS(DEMUX4_OUTPUTS)
    ) u_axis_demux4 (
        .sel   (demux4_sel),
        .s_axis(demux4_in),
        .m_axis(demux4_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX5_OUTPUTS)
    ) u_axis_demux5 (
        .sel   (demux5_sel),
        .s_axis(demux5_in),
        .m_axis(demux5_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX6_OUTPUTS)
    ) u_axis_demux6 (
        .sel   (demux6_sel),
        .s_axis(demux6_in),
        .m_axis(demux6_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX7_OUTPUTS)
    ) u_axis_demux7 (
        .sel   (demux7_sel),
        .s_axis(demux7_in),
        .m_axis(demux7_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX8_OUTPUTS)
    ) u_axis_demux8 (
        .sel   (demux8_sel),
        .s_axis(demux8_in),
        .m_axis(demux8_out)
    );
`ifdef RSDPG
    axis_demux #(
        .N_MASTERS(DEMUX9_OUTPUTS)
    ) u_axis_demux9 (
        .sel   (demux9_sel),
        .s_axis(demux9_in),
        .m_axis(demux9_out)
    );
    axis_demux #(
        .N_MASTERS(DEMUX10_OUTPUTS)
    ) u_axis_demux10 (
        .sel   (demux10_sel),
        .s_axis(demux10_in),
        .m_axis(demux10_out)
    );
`endif


    //-----------------------------------------------
    // Instantiation of computing units
    //-----------------------------------------------
`ifdef RSDPG
    mul_vector_matrix_m #(
        .MAT_TDATA_WIDTH(BITS_Z * K3)
    ) u_mul_vector_matrix_m (
        .clk_i  (clk_i),
        .rst_n  (rst_n),
        .start_i(vmmulfz_start),
        .done_o (vmmulfz_done),
        .vector (vmmulfz_vec),
        .matrix (vmmulfz_mat),
        .result (vmmulfz_res)
    );
`endif

    add_sub_vector #(
        .TDATA_WIDTH(BITS_Z * K1),
        .MODULO(Z)
    ) u_sub_vector_1 (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .op_i(arithmetic_unit_pkg::ARITH_OP_SUB),
        .done_o(sub1_done),
        .op1(sub1_op1),
        .op2(sub1_op2),
        .res(sub1_res)
    );
`ifdef RSDPG
    add_sub_vector #(
        .TDATA_WIDTH(BITS_Z * K1),
        .MODULO(Z)
    ) u_sub_vector_2 (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .op_i(arithmetic_unit_pkg::ARITH_OP_SUB),
        .done_o(sub2_done),
        .op1(sub2_op1),
        .op2(sub2_op2),
        .res(sub2_res)
    );
`endif
    exp_vector #(
        .IN_TDATA_WIDTH (BITS_Z * K1),
        .OUT_TDATA_WIDTH(BITS_P * K2)
    ) u_exp_vector (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .start_i(exp_start),
        .done_o(exp_done),
        .op(exp_op),
        .res(exp_res)
    );

    mul_vector #(
        .TDATA_WIDTH(BITS_P * K2)
    ) u_mul_vector_1 (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .done_o(mul1_done),
        .op1(mul1_op1),
        .op2(mul1_op2),
        .res(mul1_res)
    );

    add_sub_vector #(
        .TDATA_WIDTH(BITS_P * K2),
        .MODULO(P)
    ) u_add_vector (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .op_i(arithmetic_unit_pkg::ARITH_OP_ADD),
        .done_o(add_done),
        .op1(add_op1),
        .op2(add_op2),
        .res(add_res)
    );

    mul_vector_matrix_h_tr #(
        .MAT_TDATA_WIDTH(BITS_P * K4)
    ) u_mul_vector_matrix_h_tr (
        .clk_i  (clk_i),
        .rst_n  (rst_n),
        .start_i(vmmulfp_start),
        .done_o (vmmulfp_done),
        .vector (vmmulfp_vec),
        .matrix (vmmulfp_mat),
        .result (vmmulfp_res)
    );

    mul_vector #(
        .TDATA_WIDTH(BITS_P)
    ) u_mul_vector_2 (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .done_o(mul2_done),
        .op1(mul2_op1),
        .op2(mul2_op2),
        .res(mul2_res)
    );

    add_sub_vector #(
        .TDATA_WIDTH(BITS_P),
        .MODULO(P)
    ) u_sub_vector_3 (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .op_i(arithmetic_unit_pkg::ARITH_OP_SUB),
        .done_o(sub3_done),
        .op1(sub3_op1),
        .op2(sub3_op2),
        .res(sub3_res)
    );

endmodule
