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
`include "stream_w.sv"
`include "stream_r.sv"

module sample_unit
    import sample_unit_pkg::*;
    import common_pkg::max;
#(
    parameter int unsigned KECCAK_UNROLL_FACTOR = 2,
    parameter int unsigned PAR_FZ               = cross_pkg::SAMPLE_PAR_FZ,
    parameter int unsigned PAR_FP               = cross_pkg::SAMPLE_PAR_FP,
    localparam int unsigned MAX_TRANSFERS       = cross_pkg::MAX_DIGESTS
)
(
    input logic clk,
    input logic rst_n,

    input sample_op_t                       mode,
    input digest_t                          digest_type,
    input logic [$clog2(MAX_TRANSFERS):0]   n_digests,
    input logic                             mode_valid,
    output logic                            mode_ready,
    output logic                            busy,

    // Interface for prng seed or hash input
    AXIS.slave s_axis,

    // Interface for vectors of F_p
	AXIS.master m_axis_0,

    // Interface for vectors of F_z and shake squeeze
	AXIS.master m_axis_1,

    // Dedicated interface for challenge b
	AXIS.master m_axis_b,

    // Dedicated interfaces for V^T and W
	AXIS.master m_axis_w,
	AXIS.master m_axis_v_beta
);
    if (s_axis.DATA_WIDTH != m_axis_0.DATA_WIDTH)
        $error("s_axis and m_axis must have the same DATA_WIDTH!");

    localparam int unsigned DATA_WIDTH = s_axis.DATA_WIDTH;
    localparam int unsigned KEEP_WIDTH = DATA_WIDTH/8;

    /* Fz sampler connections */
    localparam int unsigned FZ_PER_SLICE = DATA_WIDTH / cross_pkg::BITS_Z;
    localparam int unsigned FZ_PAD_BITS = DATA_WIDTH % cross_pkg::BITS_Z;

    localparam int unsigned FZ_BYTES_LAST_SLICE = ((cross_pkg::DIM_FZ % FZ_PER_SLICE) * cross_pkg::BITS_Z + 7) / 8;
    localparam logic [KEEP_WIDTH-1:0] FZ_KEEP_LAST = {{(KEEP_WIDTH-FZ_BYTES_LAST_SLICE){1'b0}}, {FZ_BYTES_LAST_SLICE{1'b1}}};

    /* Constants for muxing sha3 output between Fz and Fp sampler */
    /* For transition Fz->Fp */
    localparam int unsigned BYTES_ZZ_RNG_KEEP_LAST = cross_pkg::BYTES_ZZ_CT_RNG % KEEP_WIDTH;
    localparam logic [KEEP_WIDTH-1:0] FZ_LAST_SHA3_SLICE = (BYTES_ZZ_RNG_KEEP_LAST > 0)
                                    ? {{(KEEP_WIDTH-BYTES_ZZ_RNG_KEEP_LAST){1'b0}}, {BYTES_ZZ_RNG_KEEP_LAST{1'b1}}} : '1;

 `ifdef CATEGORY_1
     localparam int unsigned SHAKE_RATE_BYTES = 168;
 `else
     localparam int unsigned SHAKE_RATE_BYTES = 136;
 `endif

 `ifdef RSDPG
    /* For transition W -> VT */
    localparam int unsigned BYTES_W_RNG_KEEP_LAST = (cross_pkg::BYTES_W_CT_RNG % SHAKE_RATE_BYTES) % KEEP_WIDTH;
    localparam logic [KEEP_WIDTH-1:0] W_LAST_SHA3_SLICE = (BYTES_W_RNG_KEEP_LAST > 0)
                                    ? {{(KEEP_WIDTH-BYTES_W_RNG_KEEP_LAST){1'b0}}, {BYTES_W_RNG_KEEP_LAST{1'b1}}} : '1;
`endif

    /* Fp sampler connections */
    localparam int unsigned FP_PER_SLICE = DATA_WIDTH / cross_pkg::BITS_P;
    localparam int unsigned FP_PAD_BITS = DATA_WIDTH % cross_pkg::BITS_P;

    localparam int unsigned FP_BYTES_LAST_SLICE = ((cross_pkg::N % FP_PER_SLICE) * cross_pkg::BITS_P + 7) / 8;
    localparam logic [KEEP_WIDTH-1:0] FP_KEEP_LAST = {{(KEEP_WIDTH-FP_BYTES_LAST_SLICE){1'b0}}, {FP_BYTES_LAST_SLICE{1'b1}}};

    /* Counter for generated samples */
`ifdef RSDP
    localparam int unsigned W_SHA3_CNT = $clog2(max(cross_pkg::BYTES_V_CT_RNG,
                                                max(cross_pkg::BYTES_CWSTR_RNG, cross_pkg::BYTES_BETA_RNG)));
`elsif RSDPG
    localparam int unsigned W_SHA3_CNT = $clog2(max(cross_pkg::BYTES_V_CT_RNG + cross_pkg::BYTES_W_CT_RNG,
                                                max(cross_pkg::BYTES_CWSTR_RNG, cross_pkg::BYTES_BETA_RNG)));
`endif
    localparam int unsigned DIGEST_BYTES [2] = {cross_pkg::LAMBDA/8, 2*cross_pkg::LAMBDA/8};
    logic [W_SHA3_CNT-1:0] squeeze_bytes;

    localparam int unsigned W_SQ_CNT = $clog2(MAX_TRANSFERS) + 1;
    logic [W_SQ_CNT-1:0] squeeze_cnt;
    logic [W_SHA3_CNT-1:0] sha3_byte_cnt;
    logic [$clog2(KEEP_WIDTH):0] valid_sha3_bytes;

    localparam int unsigned W_FZ_CNT = $clog2(cross_pkg::DIM_FZ);
    logic [W_FZ_CNT-1:0] fz_sample_cnt;

    localparam int unsigned W_FP_CNT = $clog2(max(cross_pkg::N, cross_pkg::T));
    logic [W_FP_CNT-1:0] fp_sample_cnt;

    localparam int unsigned W_FP_V_CNT = $clog2(cross_pkg::T);
    logic [W_FP_V_CNT-1:0] fp_v_sample_cnt;

    localparam int unsigned W_MATV_CNT = $clog2(cross_pkg::K);
    logic [W_MATV_CNT-1:0] mat_v_cnt;

    logic fz_w_en, fz_w_fifo_en;
`ifdef RSDPG
    localparam int unsigned W_MATW_CNT = $clog2(cross_pkg::M);
    logic [W_MATW_CNT-1:0] mat_w_cnt;

    localparam int unsigned W_FZ_W_CNT = $clog2(cross_pkg::N-cross_pkg::DIM_FZ);
    logic [W_FZ_W_CNT-1:0] fz_w_sample_cnt;
`else
    assign {fz_w_en, fz_w_fifo_en} = '0;
`endif


    /* SHA3 signals */
    logic m_axis_sha3_tlast;

    /* sampler and hash enables */
    logic sha3_en, squeeze_en, fz_en, fp_en, fp_v_en, beta_en, beta_en_q, b_en;
    logic fz_fifo_en, fp_fifo_en, fp_fifo_en_q, fp_v_fifo_en, fp_v_fifo_en_q, beta_fifo_en, b_fifo_en;
    logic fifo_v_beta_clr;

    // Muxes and demuxes
    AXIS #(.DATA_WIDTH(PAR_FP*cross_pkg::BITS_P), .ELEM_WIDTH(cross_pkg::BITS_P)) m_axis_demux_1[2]();
    AXIS #(.DATA_WIDTH(PAR_FZ*cross_pkg::BITS_Z), .ELEM_WIDTH(cross_pkg::BITS_Z)) m_axis_demux_2[2]();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mux_0[2]();
    logic sel_mux_0, sel_demux_1, sel_demux_2;

    /* FSM variables */
    typedef enum logic [2:0] {S_IDLE, S_SQUEEZE, S_SAMPLE_FZ, S_SAMPLE_FZ_FP, S_SAMPLE_VT_W, S_SAMPLE_B, S_SAMPLE_BETA} fsm_t;
    fsm_t n_state_s, state_s;

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_sha3(),
        s_axis_fz_fifo_in(), m_axis_fz_fifo_in(),
        s_axis_fp_fifo_in(),
        m_axis_fz(),
        s_axis_fp_sample(),
        s_axis_fifo_cw(), s_axis_sample_b();

    AXIS #(.DATA_WIDTH(PAR_FZ*cross_pkg::BITS_Z), .ELEM_WIDTH(cross_pkg::BITS_Z)) m_axis_fz_sample();
    AXIS #(.DATA_WIDTH(PAR_FP*cross_pkg::BITS_P), .ELEM_WIDTH(cross_pkg::BITS_P)) m_axis_fp_sample(), s_axis_wc_v_beta();

    AXIS #( .DATA_WIDTH(PAR_FZ*cross_pkg::BITS_Z),
            .ELEM_WIDTH(cross_pkg::BITS_Z)) s_axis_fz_wc();

    AXIS #( .DATA_WIDTH(FZ_PER_SLICE*cross_pkg::BITS_Z),
            .ELEM_WIDTH(cross_pkg::BITS_Z)) m_axis_fz_wc();

    AXIS #( .DATA_WIDTH(PAR_FP*cross_pkg::BITS_P), .ELEM_WIDTH(cross_pkg::BITS_P))  s_axis_fp_wc();
    AXIS #( .DATA_WIDTH(cross_pkg::BITS_P), .ELEM_WIDTH(cross_pkg::BITS_P))  m_axis_wc_v_beta();
    AXIS #( .DATA_WIDTH(cross_pkg::BITS_Z), .ELEM_WIDTH(cross_pkg::BITS_Z))  m_axis_wc_w();

    AXIS #( .DATA_WIDTH(((PAR_FP*cross_pkg::BITS_P+7)/8)*8)) s_axis_fifo_v_beta(), m_axis_fifo_v_beta();

    AXIS #( .DATA_WIDTH(FP_PER_SLICE*cross_pkg::BITS_P), .ELEM_WIDTH(cross_pkg::BITS_P)) m_axis_fp_wc();

    AXIS #( .DATA_WIDTH(DATA_WIDTH) ) m_axis_0_int();

    stream_w #(.WORD_SZ(DATA_WIDTH)) sha3_stream_w();
    stream_r #(.WORD_SZ(DATA_WIDTH)) sha3_stream_r();

    /*
    * CONTROL UNIT
    */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state_s <= S_IDLE;
        else        state_s <= n_state_s;
    end

    // Gate the mode ready signal if there are pending operations but
    // a conflicting operation is requested.
    always_comb begin
        mode_ready = 1'b0;
        if (mode_valid && state_s == S_IDLE) begin
            unique case (mode)
                M_SQUEEZE: mode_ready = ~squeeze_en;
                M_SAMPLE_FZ: mode_ready = ~fz_en & ~fz_w_en & ~squeeze_en;
                M_SAMPLE_FZ_FP: mode_ready = ~fz_en & ~fz_w_en & ~fp_en & ~fp_v_en & ~beta_en;
                M_SAMPLE_VT_W: mode_ready = ~fz_en & ~fz_w_en & ~fp_en & ~fp_v_en & ~beta_en;
                M_SAMPLE_BETA: mode_ready = ~beta_en & ~fp_v_en;
                M_SAMPLE_B: mode_ready = ~b_en;
                default: mode_ready = 1'b0;
            endcase
        end
    end
    assign busy = squeeze_en | fz_en | fz_w_en | fp_en | fp_v_en | beta_en | b_en | sha3_en;

    always_comb begin
        n_state_s = state_s;
        unique case (state_s)
            S_IDLE: begin
                if (mode_valid && mode_ready) begin
                    unique  if (mode == M_SQUEEZE)      n_state_s = S_SQUEEZE;
                    else    if (mode == M_SAMPLE_FZ)    n_state_s = S_SAMPLE_FZ;
                    else    if (mode == M_SAMPLE_FZ_FP) n_state_s = S_SAMPLE_FZ_FP;
                    else    if (mode == M_SAMPLE_VT_W)  n_state_s = S_SAMPLE_VT_W;
                    else    if (mode == M_SAMPLE_BETA)  n_state_s = S_SAMPLE_BETA;
                    else    if (mode == M_SAMPLE_B)     n_state_s = S_SAMPLE_B;
                    else                                n_state_s = S_IDLE;
                end
            end

            S_SAMPLE_FZ_FP: begin
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG + cross_pkg::BYTES_ZP_CT_RNG)
                    - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            end

            S_SAMPLE_VT_W: begin
            `ifdef RSDP
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_V_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            `elsif RSDPG
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_V_CT_RNG + cross_pkg::BYTES_W_CT_RNG)
                                    - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            `endif
            end

            S_SAMPLE_BETA: begin
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_BETA_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            end

            S_SAMPLE_FZ: begin
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            end

            S_SAMPLE_B: begin
                if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_CWSTR_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    n_state_s = S_IDLE;
                end
            end

            S_SQUEEZE: begin
                if ( `AXIS_LAST(m_axis_1) && squeeze_cnt >= W_SQ_CNT'(n_digests) - W_SQ_CNT'(1)) begin
                    n_state_s = S_IDLE;
                end
            end

            default:
                n_state_s = state_s;
        endcase
    end

    always_comb begin: demux_0
        unique case (state_s)
            S_SAMPLE_FZ:    m_axis_sha3.tready = s_axis_fz_fifo_in.tready;
            S_SAMPLE_FZ_FP: m_axis_sha3.tready = fz_fifo_en ? s_axis_fz_fifo_in.tready : s_axis_fp_fifo_in.tready;
            S_SAMPLE_B:     m_axis_sha3.tready = s_axis_fifo_cw.tready;
            S_SAMPLE_BETA:  m_axis_sha3.tready = s_axis_fp_fifo_in.tready;

            S_SAMPLE_VT_W:  `ifdef RSDP m_axis_sha3.tready = s_axis_fp_fifo_in.tready;
                            `elsif RSDPG m_axis_sha3.tready = fz_fifo_en ? s_axis_fz_fifo_in.tready : s_axis_fp_fifo_in.tready;
                            `endif
            // S_SQUEEZE is default
            default: m_axis_sha3.tready = s_axis_mux_0[0].tready;
        endcase
    end: demux_0
    assign sha3_en = (state_s != S_IDLE);


    // Ctrl for fz vector sampling
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            {fz_en, fz_fifo_en} <= '0;
            `ifdef RSDPG {fz_w_en, fz_w_fifo_en} <= '0; `endif
        end else begin
            // Assert
            if ( mode_valid && mode_ready && (mode == M_SAMPLE_FZ || mode == M_SAMPLE_FZ_FP) ) begin
                {fz_en, fz_fifo_en} <= '1;
            end

            // Deassert
            if ( `AXIS_LAST(m_axis_1) ) begin
                fz_en <= 1'b0;
            end
            if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes)) begin
                fz_fifo_en <= 1'b0;
            end

        `ifdef RSDPG
            // Assert
            if ( mode_valid && mode_ready && (mode == M_SAMPLE_VT_W) ) begin
                {fz_w_en, fz_w_fifo_en} <= '1;
            end

            // De-assert
            if ( `AXIS_LAST(m_axis_w) ) begin
                if ( mat_w_cnt >= W_MATW_CNT'(cross_pkg::M - 1) ) begin
                    fz_w_en <= 1'b0;
                end
            end
            if (`AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fz_w_fifo_en <= 1'b0;
            end
        `endif
        end
    end

    // Ctrl for fp vector sampling
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            {fp_en, fp_v_en, fp_fifo_en_q, fp_v_fifo_en_q} <= '0;
        end else begin
            // Assert
            if ( mode_valid && mode_ready && mode == M_SAMPLE_FZ_FP ) begin
                fp_en <= 1'b1;
            end
            if ( fp_en && `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fp_fifo_en_q <= 1'b1;
            end

            // De-assert
            if ( `AXIS_LAST(m_axis_0_int) ) begin
                fp_en <= 1'b0;
            end
            if (`AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG + cross_pkg::BYTES_ZP_CT_RNG)
                                            - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fp_fifo_en_q <= 1'b0;
            end

        `ifdef RSDP
            if ( mode_valid && mode_ready && mode == M_SAMPLE_VT_W ) begin
                {fp_v_en, fp_v_fifo_en_q} <= '1;
            end
            if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_V_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fp_v_fifo_en_q <= 1'b0;
            end
        `elsif RSDPG
            if ( mode_valid && mode_ready && mode == M_SAMPLE_VT_W ) begin
                fp_v_en <= 1'b1;
            end
            if ( fp_v_en && `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fp_v_fifo_en_q <= 1'b1;
            end

            if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG + cross_pkg::BYTES_V_CT_RNG)
                                                            - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                fp_v_fifo_en_q <= 1'b0;
            end
        `endif
            if ( `AXIS_LAST(m_axis_v_beta) && mat_v_cnt >= W_MATV_CNT'(cross_pkg::K - 1) ) begin
                fp_v_en <= 1'b0;
            end
        end
    end
    assign fp_fifo_en = fp_fifo_en_q || ( fp_en && `AXIS_TRANS(m_axis_sha3)
                                        && sha3_byte_cnt > W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) );
`ifdef RSDP
    assign fp_v_fifo_en = fp_v_fifo_en_q;
`elsif RSDPG
    assign fp_v_fifo_en = fp_v_fifo_en_q || ( fp_v_en && `AXIS_TRANS(m_axis_sha3)
                                        && sha3_byte_cnt > W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) );
`endif


    // Ctrl for challenge b sampling
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            {b_en, b_fifo_en} <= '0;
        end else begin
            if (mode_valid && mode_ready && mode == M_SAMPLE_B) begin
                {b_en, b_fifo_en} <= '1;
            end
            if ( `AXIS_LAST(m_axis_b) ) begin
                b_en <= 1'b0;
            end
            if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_CWSTR_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                b_fifo_en <= 1'b0;
            end
        end
    end

    // Ctrl for challenge beta sampling
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            {beta_en, beta_fifo_en, beta_en_q} <= '0;
        end else begin
            if (mode_valid && mode_ready && mode == M_SAMPLE_BETA) begin
                {beta_en, beta_fifo_en, beta_en_q} <= '1;
            end
            if ( `AXIS_TRANS(m_axis_fp_sample) && (fp_sample_cnt >= W_FP_CNT'(cross_pkg::T - PAR_FP)) ) begin
                beta_en <= 1'b0;
            end
            if (beta_en_q && `AXIS_LAST(m_axis_v_beta)) begin
                beta_en_q <= 1'b0;
            end
            if ( `AXIS_TRANS(m_axis_sha3) && sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_BETA_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                beta_fifo_en <= 1'b0;
            end
        end
    end

    // Ctrl for squeezing (hashing, csprng)
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            squeeze_en <= 1'b0;
        end else begin
            if (mode_valid && mode_ready && mode == M_SQUEEZE) begin
                squeeze_en <= 1'b1;
            end
            if ( `AXIS_LAST(m_axis_1) && (squeeze_cnt >= W_SQ_CNT'(n_digests) - W_SQ_CNT'(1)) ) begin
                squeeze_en <= 1'b0;
            end
        end
    end

    /*
    * SHA3 INSTANCE
    */
    /* In shake mode, infinite amount is squeezed until new seed is provided.
    * User needs to make sure not to provide new seed data until all the
    * vectors are received.
    */
    axis2stream_w
    u_axis2stream_w
    (
        .clk    ( clk   ),
        .rst_n  ( rst_n ),

        .s_axis         ( s_axis ),
        .stream_w_prod  ( sha3_stream_w )
    );

    sha3
    #(
`ifdef CATEGORY_1
        .SHA3_ALG( sha3_pkg::SHAKE_128),
`else
        .SHA3_ALG( sha3_pkg::SHAKE_256),
`endif
        .STREAM_WIDTH( DATA_WIDTH ),
        .UNROLL_FACTOR(KECCAK_UNROLL_FACTOR),
        .SEED1_SZ(3*cross_pkg::LAMBDA + 16),
        .SEED2_SZ(4*cross_pkg::LAMBDA + 16)
    )
    u_sha3
    (
        .clk_i          ( clk               ),
        .rst_n          ( rst_n & sha3_en   ),
        .clear_i        ( !sha3_en          ),
        .sha3_r_stream  ( sha3_stream_r     ),
        .sha3_w_stream  ( sha3_stream_w     )
    );

    stream_r2axis
    u_stream_r2axis
    (
        .stream_r_cons  ( sha3_stream_r ),
        .m_axis         ( m_axis_sha3 )
    );


    /* In shake mode, infinite amount is squeezed until new seed is provided,
    * therefore no tlast is available and it's artificially created. This only
    * works because sha3 rate > BYTES_HASH and rate > 2*BYTES_HASH, and the
    * shake rates mod DATA_WIDTH are always 0. Otherwise re-alignment would be required.
    * */
    assign m_axis_sha3_tlast = (squeeze_en && sha3_byte_cnt >= squeeze_bytes - W_SHA3_CNT'(valid_sha3_bytes));
    assign squeeze_bytes = W_SHA3_CNT'( DIGEST_BYTES[digest_type] );

    /*
    * Fz FIFO
    * Needs to be large enough such that we can switch last word when
    * transitioning from Fz->Fp without backpressure.
    */
    fifo_ram
    #(
    `ifdef RSDPG
        .DEPTH ( (cross_pkg::BYTES_W_CT_RNG + KEEP_WIDTH-1)/ KEEP_WIDTH )
    `else
        .DEPTH ( (cross_pkg::BYTES_ZZ_CT_RNG + KEEP_WIDTH-1)/ KEEP_WIDTH )
    `endif
    ) u_fz_fifo
    (
        .clk,
        .rst_n  ( rst_n & (fz_en | fz_w_en) ),
        .s_axis ( s_axis_fz_fifo_in ),
        .m_axis ( m_axis_fz_fifo_in )
    );
    assign s_axis_fz_fifo_in.tvalid = m_axis_sha3.tvalid & (fz_fifo_en | fz_w_fifo_en);
    assign s_axis_fz_fifo_in.tlast = m_axis_sha3.tlast;

    always_comb begin
        s_axis_fz_fifo_in.tdata = m_axis_sha3.tdata;
        s_axis_fz_fifo_in.tkeep = m_axis_sha3.tkeep;
        unique case (state_s)
            S_SAMPLE_FZ_FP: begin
                if ( sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    s_axis_fz_fifo_in.tkeep = FZ_LAST_SHA3_SLICE;
                end
            end
        `ifdef RSDPG
            S_SAMPLE_VT_W: begin
                if ( sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                    s_axis_fz_fifo_in.tkeep = W_LAST_SHA3_SLICE;
                end
            end
        `endif
            default: begin
                s_axis_fz_fifo_in.tdata = m_axis_sha3.tdata;
                s_axis_fz_fifo_in.tkeep = m_axis_sha3.tkeep;
            end
        endcase
    end


    /*
    * Fz REJECTION SAMPLER
    */
    zk_sample
    #(
        .MOD_K      ( cross_pkg::Z  ),
        .PAR_ELEMS  ( PAR_FZ        )
    ) u_fz_sample
    (
        .clk,
        .rst_n  ( rst_n & (fz_en | fz_w_en) ),
        .s_axis ( m_axis_fz_fifo_in ),
        .m_axis ( m_axis_fz_sample  )
    );

    //----------------------------------------------------------
    // DEMUX2
    //----------------------------------------------------------
    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_demux_2
    (
        .sel    ( sel_demux_2       ),
        .s_axis ( m_axis_fz_sample  ),
        .m_axis ( m_axis_demux_2    )
    );
    // 1 -> send to W output, 0 -> send to width-converter
    assign sel_demux_2 = fz_w_en;

`ifdef RSDPG

    /*
    * Fz W WIDTH_CONVERTER
    */
    width_converter
    #(
        .ELEM_WIDTH ( cross_pkg::BITS_Z )
    ) u_fz_wc_w_beta
    (
        .axis_aclk  ( clk   ),
        .axis_rst_n ( rst_n & fz_w_en ),

        .s_axis ( m_axis_demux_2[1] ),
        .m_axis ( m_axis_wc_w       )
    );

    `AXIS_ASSIGN_MIN(m_axis_w, m_axis_wc_w);
    assign m_axis_w.tkeep = 1'b1;
    assign m_axis_w.tlast = (fz_w_sample_cnt >= W_FZ_W_CNT'(cross_pkg::N - cross_pkg::DIM_FZ - 1));

`else
    assign {sel_demux_2, m_axis_w.tvalid} = '0;
`endif

    /*
    * Fz WIDTH_CONVERTER
    */
    width_converter
    #(
        .ELEM_WIDTH ( cross_pkg::BITS_Z )
    ) u_fz_wc
    (
        .axis_aclk  ( clk           ),
        .axis_rst_n ( rst_n & fz_en ),
        .s_axis     ( s_axis_fz_wc  ),
        .m_axis     ( m_axis_fz_wc  )
    );
    `AXIS_ASSIGN_MIN( s_axis_fz_wc, m_axis_demux_2[0] )
    assign s_axis_fz_wc.tkeep = m_axis_demux_2[0].tkeep;
    assign s_axis_fz_wc.tlast = (fz_sample_cnt >= W_FZ_CNT'(cross_pkg::DIM_FZ - PAR_FZ));

    /*
    * Connections to a placeholder interface for easier multiplexing with
    * final m_axis interface above
    */
    assign m_axis_fz.tdata = {{FZ_PAD_BITS{1'b0}}, m_axis_fz_wc.tdata};
    assign m_axis_fz.tkeep = (fz_en && m_axis_fz_wc.tvalid && m_axis_fz_wc.tlast) ? FZ_KEEP_LAST : '1;
    assign m_axis_fz.tvalid = m_axis_fz_wc.tvalid;
    assign m_axis_fz_wc.tready = m_axis_fz.tready;
    assign m_axis_fz.tlast = m_axis_fz_wc.tlast;

    //----------------------------------------------------------------
    // MUX0
    //----------------------------------------------------------------
    axis_mux
    #(
        .N_SLAVES ( 2 )
    )
    u_mux_0
    (
        .sel    ( sel_mux_0     ),
        .s_axis ( s_axis_mux_0  ),
        .m_axis ( m_axis_1      )
    );
    assign sel_mux_0 = fz_en;
    `AXIS_ASSIGN(s_axis_mux_0[1], m_axis_fz)

    // Need to do this manual here as the tready needs special treatment above
    assign s_axis_mux_0[0].tdata = m_axis_sha3.tdata;
    assign s_axis_mux_0[0].tkeep = m_axis_sha3.tkeep;
    assign s_axis_mux_0[0].tvalid = m_axis_sha3.tvalid && (state_s == S_SQUEEZE);
    assign s_axis_mux_0[0].tlast = m_axis_sha3_tlast;

    //------------------------------------------------------------------------
    // Fp FIFO
    //------------------------------------------------------------------------
    fifo_ram
    #(
        .DEPTH ( (cross_pkg::BYTES_V_CT_RNG + KEEP_WIDTH-1)/ KEEP_WIDTH )
    ) u_fp_fifo
    (
        .clk    ( clk ),
        .rst_n  ( rst_n & (fp_en | fp_v_en | beta_en) ),
        .s_axis ( s_axis_fp_fifo_in ),
        .m_axis ( s_axis_fp_sample  )
    );
    assign s_axis_fp_fifo_in.tvalid = m_axis_sha3.tvalid & (fp_fifo_en | fp_v_fifo_en | beta_fifo_en);
    assign s_axis_fp_fifo_in.tlast = m_axis_sha3.tlast;

    // Need to shift here when traversing from sampling fz -> fp as we sample
    // from the same seed. Reason is that the amount of bytes per sampler are
    // not necessarily word aligned with the shake output.
    always_comb begin
        s_axis_fp_fifo_in.tdata = m_axis_sha3.tdata;
        s_axis_fp_fifo_in.tkeep = m_axis_sha3.tkeep;
        unique case (state_s)
            S_SAMPLE_FZ_FP: begin
                if ( sha3_byte_cnt > W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes)
                && sha3_byte_cnt <= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) ) begin
                    s_axis_fp_fifo_in.tdata = m_axis_sha3.tdata >> BYTES_ZZ_RNG_KEEP_LAST*8;
                    s_axis_fp_fifo_in.tkeep = m_axis_sha3.tkeep >> BYTES_ZZ_RNG_KEEP_LAST;
                end
            end
        `ifdef RSDPG
            S_SAMPLE_VT_W: begin
                if ( sha3_byte_cnt > W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes)
                && sha3_byte_cnt <= W_SHA3_CNT'(cross_pkg::BYTES_W_CT_RNG) ) begin
                    s_axis_fp_fifo_in.tdata = m_axis_sha3.tdata >> BYTES_W_RNG_KEEP_LAST*8;
                    s_axis_fp_fifo_in.tkeep = m_axis_sha3.tkeep >> BYTES_W_RNG_KEEP_LAST;
                end
            end
        `endif
            default: begin
                s_axis_fp_fifo_in.tdata = m_axis_sha3.tdata;
                s_axis_fp_fifo_in.tkeep = m_axis_sha3.tkeep;
            end
        endcase
    end

    /*
    * Fp REJECTION SAMPLER
    */
    fp_sample
    #(
        .MOD_P      ( cross_pkg::P  ),
        .PAR_ELEMS  ( PAR_FP        )
    ) u_fp_sample
    (
        .clk,
        .rst_n          ( rst_n & (fp_en | fp_v_en | beta_en) ),
        .en_mul_group   ( beta_en           ),
        .s_axis         ( s_axis_fp_sample  ),
        .m_axis         ( m_axis_fp_sample  )
    );


    //----------------------------------------------------------
    // DEMUX1
    //----------------------------------------------------------
    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_demux_1
    (
        .sel    ( sel_demux_1       ),
        .s_axis ( m_axis_fp_sample  ),
        .m_axis ( m_axis_demux_1    )
    );
    // 1 -> send to V or beta to output, 0 -> send to width-converter
    assign sel_demux_1 = (fp_v_en | beta_en);

    // Need some extension/truncation such that fifo below is
    // still implementable in BRAM
    assign s_axis_fifo_v_beta.tdata = (s_axis_fifo_v_beta.DATA_WIDTH)'(m_axis_demux_1[1].tdata);
    assign s_axis_fifo_v_beta.tkeep = '1; //TODO
    assign s_axis_fifo_v_beta.tvalid = m_axis_demux_1[1].tvalid;
    assign m_axis_demux_1[1].tready = s_axis_fifo_v_beta.tready;
    assign s_axis_fifo_v_beta.tlast = m_axis_demux_1[1].tlast;


    //-------------------------------------------------------
    // FIFO V+BETA
    // For V we actually don't need it, but for beta to not
    // block the sampler after re-generating beta in verify
    //--------------------------------------------------------
    fifo_ram
    #(
        .DEPTH      ( (cross_pkg::T+PAR_FP-1)/PAR_FP    ),
        .REG_OUT    ( 1                                 )
    ) u_fifo_v_beta
    (
        .clk,
        .rst_n  ( rst_n & ~fifo_v_beta_clr ),
        .s_axis ( s_axis_fifo_v_beta ),
        .m_axis ( m_axis_fifo_v_beta )
    );
    assign fifo_v_beta_clr = `AXIS_LAST(m_axis_v_beta) &&
                            (beta_en_q || (fp_v_en && mat_v_cnt >= W_MATV_CNT'(cross_pkg::K-1)));

    //-------------------------------------------------------
    // Fp WIDTH_CONVERTER V BETA
    // Convert it to single elment stream on O_2 because
    // otherwise the sorting for mthe matrices in the alu
    // will be pain
    //-------------------------------------------------------
    width_converter
    #(
        .ELEM_WIDTH ( cross_pkg::BITS_P )
    ) u_fp_wc_v_beta
    (
        .axis_aclk  ( clk   ),
        .axis_rst_n ( rst_n & (fp_v_en | beta_en_q) ),

        .s_axis ( s_axis_wc_v_beta  ),
        .m_axis ( m_axis_wc_v_beta  )
    );

    assign s_axis_wc_v_beta.tdata = m_axis_fifo_v_beta.tdata[0 +: PAR_FP*cross_pkg::BITS_P];
    assign s_axis_wc_v_beta.tkeep = '1; // This is more or less useless but
    assign s_axis_wc_v_beta.tvalid = m_axis_fifo_v_beta.tvalid;
    assign m_axis_fifo_v_beta.tready = s_axis_wc_v_beta.tready;
    assign s_axis_wc_v_beta.tlast = 1'b0;
    assign s_axis_wc_v_beta.tuser = m_axis_fifo_v_beta.tuser;

    `AXIS_ASSIGN_MIN( m_axis_v_beta, m_axis_wc_v_beta);
    assign m_axis_v_beta.tkeep = 1'b1;
    assign m_axis_v_beta.tlast = fp_v_en ? (fp_v_sample_cnt >= W_FP_V_CNT'(cross_pkg::N - cross_pkg::K - 1))
                                        : (fp_v_sample_cnt >= W_FP_V_CNT'(cross_pkg::T - 1));

    /*
    * Fp WIDTH_CONVERTER
    */
    width_converter
    #(
        .ELEM_WIDTH ( cross_pkg::BITS_P )
    ) u_fp_wc
    (
        .axis_aclk  ( clk   ),
        .axis_rst_n ( rst_n & fp_en ),

        .s_axis ( s_axis_fp_wc ),
        .m_axis ( m_axis_fp_wc )
    );

    // Connect with width-converter for standard Fp output
    always_comb begin
        `AXIS_ASSIGN_PROC(s_axis_fp_wc, m_axis_demux_1[0])
        s_axis_fp_wc.tvalid = fp_en & m_axis_demux_1[0].tvalid;
        s_axis_fp_wc.tkeep = '1;
        s_axis_fp_wc.tlast = (fp_sample_cnt >= W_FP_CNT'(cross_pkg::N - PAR_FP));
    end

    assign m_axis_0_int.tdata = {{FP_PAD_BITS{1'b0}}, m_axis_fp_wc.tdata};;
    assign m_axis_0_int.tkeep = (fp_en && m_axis_fp_wc.tvalid && m_axis_fp_wc.tlast) ? FP_KEEP_LAST : '1;
    assign m_axis_0_int.tvalid = m_axis_fp_wc.tvalid;
    assign m_axis_fp_wc.tready = m_axis_0_int.tready;
    assign m_axis_0_int.tlast = m_axis_fp_wc.tlast;

    axis_reg #(.SPILL_REG(1))
    u_m_axis0_reg (
        .clk,
        .rst_n,
        .s_axis( m_axis_0_int   ),
        .m_axis( m_axis_0       )
    );


    //-----------------------------------------------------
    // FIFO CW
    //-----------------------------------------------------
    fifo_ram
    #(
        .DEPTH ( (cross_pkg::BYTES_CWSTR_RNG + KEEP_WIDTH-1)/ KEEP_WIDTH )
    ) u_fifo_cw
    (
        .clk,
        .rst_n  ( rst_n & b_en      ),
        .s_axis ( s_axis_fifo_cw    ),
        .m_axis ( s_axis_sample_b   )
    );
    assign s_axis_fifo_cw.tdata = m_axis_sha3.tdata;
    assign s_axis_fifo_cw.tkeep = m_axis_sha3.tkeep;
    assign s_axis_fifo_cw.tvalid = m_axis_sha3.tvalid & b_fifo_en;
    assign s_axis_fifo_cw.tlast = m_axis_sha3.tlast;

    /*
    * CHALLENGE b SAMPLER
    */
    b_sample
    #(
        .T(cross_pkg::T),
        .W(cross_pkg::W)
    ) u_b_sample
    (
        .clk,
        .rst_n  ( rst_n & b_en ),
        .s_axis ( s_axis_sample_b ),
        .m_axis ( m_axis_b )
    );


    /*
    * SAMPLE COUNTERS
    */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n)
            squeeze_cnt <= '0;
        else begin
            if ( squeeze_en && `AXIS_LAST(m_axis_1) ) begin
                if (squeeze_cnt >= W_SQ_CNT'(n_digests) - W_SQ_CNT'(1)) begin
                    squeeze_cnt <= '0;
                end else begin
                    squeeze_cnt <= squeeze_cnt + W_SQ_CNT'(1);
                end
            end
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            fp_sample_cnt <= '0;
        end else begin
            if ( fp_en && `AXIS_TRANS(m_axis_fp_sample) ) begin
                if (fp_sample_cnt >= W_FP_CNT'(cross_pkg::N - PAR_FP)) begin
                    fp_sample_cnt <= '0;
                end else begin
                    fp_sample_cnt <= fp_sample_cnt + W_FP_CNT'(PAR_FP);
                end
            end

            if ( beta_en && `AXIS_TRANS(m_axis_fp_sample) ) begin
                if (fp_sample_cnt >= W_FP_CNT'(cross_pkg::T - PAR_FP)) begin
                    fp_sample_cnt <= '0;
                end else begin
                    fp_sample_cnt <= fp_sample_cnt + W_FP_CNT'(PAR_FP);
                end
            end
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            fp_v_sample_cnt <= '0;
        end else begin

            if ( fp_v_en && `AXIS_TRANS(m_axis_v_beta) ) begin
                if (fp_v_sample_cnt >= W_FP_V_CNT'(cross_pkg::N - cross_pkg::K - 1)) begin
                    fp_v_sample_cnt <= '0;
                end else begin
                    fp_v_sample_cnt <= fp_v_sample_cnt + W_FP_V_CNT'(1);
                end
            end

            if ( beta_en_q && `AXIS_TRANS(m_axis_v_beta) ) begin
                if (fp_v_sample_cnt >= W_FP_V_CNT'(cross_pkg::T - 1)) begin
                    fp_v_sample_cnt <= '0;
                end else begin
                    fp_v_sample_cnt <= fp_v_sample_cnt + W_FP_V_CNT'(1);
                end
            end
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n)
            fz_sample_cnt <= '0;
        else begin
            if ( fz_en && `AXIS_TRANS(m_axis_fz_sample) ) begin
                if (fz_sample_cnt >= W_FZ_CNT'(cross_pkg::DIM_FZ - PAR_FZ)) begin
                    fz_sample_cnt <= '0;
                end else begin
                    fz_sample_cnt <= fz_sample_cnt + W_FZ_CNT'(PAR_FZ);
                end
            end
        end
    end

`ifdef RSDPG
    // Counter for row length of matrix W
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n)
            fz_w_sample_cnt <= '0;
        else begin
            if ( fz_w_en && `AXIS_TRANS(m_axis_w) ) begin
                if (fz_w_sample_cnt >= W_FZ_CNT'(cross_pkg::N - cross_pkg::DIM_FZ - 1)) begin
                    fz_w_sample_cnt <= '0;
                end else begin
                    fz_w_sample_cnt <= fz_w_sample_cnt + W_FZ_CNT'(1);
                end
            end
        end
    end

    // Counts rows for matrix W
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            mat_w_cnt <= '0;
        end else begin
            if ( fz_w_en && `AXIS_LAST(m_axis_w) ) begin
                if ( mat_w_cnt >= W_MATW_CNT'(cross_pkg::M - 1) ) begin
                    mat_w_cnt <= '0;
                end else begin
                    mat_w_cnt <= mat_w_cnt + W_MATW_CNT'(1);
                end
            end
        end
    end
`endif

    // Counts rows for matrix VT
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (! rst_n) begin
            mat_v_cnt <= '0;
        end else begin
            if ( fp_v_en && `AXIS_LAST(m_axis_v_beta) ) begin
                if (mat_v_cnt >= W_MATV_CNT'(cross_pkg::K - 1)) begin
                    mat_v_cnt <= '0;
                end else begin
                    mat_v_cnt <= mat_v_cnt + W_MATV_CNT'(1);
                end
            end

        end
    end

    /*
    * SHA3 BYTE COUNTER
    * Keeps track of output that must be squeezed when sampling Fz first and then Fp
    */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            sha3_byte_cnt <= '0;
        end else begin
            unique case (state_s)
                S_SAMPLE_FZ: begin
                    if (fz_fifo_en && `AXIS_TRANS(m_axis_sha3) ) begin
                        if (sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes)) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end
                S_SAMPLE_FZ_FP: begin
                    if ((fz_fifo_en | fp_fifo_en) && `AXIS_TRANS(m_axis_sha3) ) begin
                        if (sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_ZZ_CT_RNG + cross_pkg::BYTES_ZP_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes)) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end

            `ifdef RSDP
                S_SAMPLE_VT_W: begin
                    if (fp_v_fifo_en && `AXIS_TRANS(m_axis_sha3) ) begin
                        if ( sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_V_CT_RNG) - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end
            `elsif RSDPG
                S_SAMPLE_VT_W: begin
                    if ((fz_w_fifo_en | fp_v_fifo_en) && `AXIS_TRANS(m_axis_sha3) ) begin
                        if ( sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_V_CT_RNG + cross_pkg::BYTES_W_CT_RNG)
                                                - W_SHA3_CNT'(valid_sha3_bytes) ) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end
            `endif

                S_SQUEEZE: begin
                    if ( `AXIS_TRANS(m_axis_sha3) ) begin
                        if (sha3_byte_cnt >= squeeze_bytes - W_SHA3_CNT'(valid_sha3_bytes)) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end

                S_SAMPLE_BETA: begin
                    if ( beta_fifo_en && `AXIS_TRANS(m_axis_sha3) ) begin
                        if (sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_BETA_RNG) - W_SHA3_CNT'(valid_sha3_bytes)) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end

                S_SAMPLE_B: begin
                    if ( b_fifo_en && `AXIS_TRANS(m_axis_sha3) ) begin
                        if (sha3_byte_cnt >= W_SHA3_CNT'(cross_pkg::BYTES_CWSTR_RNG) - W_SHA3_CNT'(valid_sha3_bytes)) begin
                            sha3_byte_cnt <= '0;
                        end else begin
                            sha3_byte_cnt <= sha3_byte_cnt + W_SHA3_CNT'(valid_sha3_bytes);
                        end
                    end
                end

                default: begin
                    sha3_byte_cnt <= '0;
                end
            endcase
        end
    end

    /* Count ones in m_axis_sha3.tkeep */
    /* Actually not required for the sha3 core we use, as in shake mode, */
    /* output of tkeep is always '1 (only supports IO widths where below is the case */
    if (SHAKE_RATE_BYTES % KEEP_WIDTH == 0) begin
        assign valid_sha3_bytes = $bits(valid_sha3_bytes)'(KEEP_WIDTH);
    end else begin
        always_comb begin
            valid_sha3_bytes = '0;
            foreach(m_axis_sha3.tkeep[i]) begin
                valid_sha3_bytes += m_axis_sha3.tkeep[i];
            end
        end
    end

endmodule
