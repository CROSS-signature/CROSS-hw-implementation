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

module no_tree_unit
    import tree_unit_pkg::*;
    import cross_pkg::MAX_DIGESTS;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned W_NUM_DIGEST = $clog2(MAX_DIGESTS) + 1,
	localparam int unsigned AW_INT_STREE = $clog2(2*cross_pkg::T - 1)
)
(
	input logic clk,
	input logic rst_n,

    input tree_unit_opcode_t            op,
    input logic                         op_valid,
    output logic                        op_ready,
    output logic [AW_INT_STREE-1:0]     stree_parent_idx,
    output logic                        stree_tree_computed,
    output logic                        sign_done,
    output logic                        vrfy_done,
    output logic                        vrfy_stree_done,
    output logic                        vrfy_mtree_done,
    output logic                        vrfy_pad_err,
    input logic                         vrfy_pad_err_clear,
    output sample_unit_pkg::digest_t    digest_size,
    output logic [W_NUM_DIGEST-1:0]     n_digests,

    // Connection to sample unit
    AXIS.slave s_axis,
    AXIS.master m_axis,

    // Connection to signature
    AXIS.slave s_axis_sig,
    AXIS.master m_axis_sig,

    // Connection to dedicated challenge port (2nd challenge b) of sample unit
	AXIS.slave s_axis_ch
);

    typedef enum logic [3:0] {S_IDLE, S_SIGN_FETCH_MSEED, S_SIGN_EXPAND_MSEED, S_SIGN_EXPAND_QSEED, S_SIGN_PROVIDE_SEEDS,
                            S_HASH_CMT_0, S_PROVIDE_CMT_0_HASH, S_SIGN_WAIT_CH_B,
                            S_VRFY_COPY_SEEDS, S_VRFY_WAIT_CH_B} fsm_t;
    fsm_t n_state, state;
    logic mode_sign, mode_vrfy;
    logic sel_mux_s_axis_mem, sel_mux_m_axis, sel_demux_m_axis_mem, sel_demux_s_axis_sig, wait_result;

    localparam int unsigned WPH = cross_pkg::BYTES_HASH / (DATA_WIDTH/8);
    localparam int unsigned WPS = cross_pkg::BYTES_SEED / (DATA_WIDTH/8);

    // Memory needs to store T seeds as well as the T cmt_0's and the quad
    // hashes (which will be overwritten by root)
    localparam int unsigned MEM_DEPTH   = (cross_pkg::T+4)*WPH + cross_pkg::T*WPS;
    localparam int unsigned MEM_AW      = $clog2(MEM_DEPTH);

    enum logic [MEM_AW-1:0] {   QUAD_SEED_ADDR_0    = MEM_AW'( 0                                                           ),
                                QUAD_SEED_ADDR_1    = MEM_AW'( (cross_pkg::T/4     + OFF_1)*WPS                            ),
                                QUAD_SEED_ADDR_2    = MEM_AW'( (2*(cross_pkg::T/4) + OFF_2)*WPS                            ),
                                QUAD_SEED_ADDR_3    = MEM_AW'( (3*(cross_pkg::T/4) + OFF_3)*WPS                            ),
                                MROOT_ADDR          = MEM_AW'( (cross_pkg::T*WPS)                                          ),
                                CMT_ADDR_0          = MEM_AW'( (cross_pkg::T*WPS) + 4*WPH                                  ),
                                CMT_ADDR_1          = MEM_AW'( (cross_pkg::T*WPS) + (4 + cross_pkg::T/4 + OFF_1)*WPH       ),
                                CMT_ADDR_2          = MEM_AW'( (cross_pkg::T*WPS) + (4 + 2*(cross_pkg::T/4) + OFF_2)*WPH   ),
                                CMT_ADDR_3          = MEM_AW'( (cross_pkg::T*WPS) + (4 + 3*(cross_pkg::T/4) + OFF_3)*WPH   )
                            } mem_addr_t;

    // Frame counter
    localparam int unsigned W_FCNT = $clog2(cross_pkg::T + 4);
    logic [W_FCNT-1:0] fcnt_in, fcnt_in_max;
    logic fcnt_in_en;

    logic [W_FCNT-1:0] fcnt_out, fcnt_out_max;
    logic fcnt_out_en;

    // Utility counter
    localparam int unsigned W_CNT = $clog2(3);
    logic [W_CNT-1:0] cnt, cnt_max;
    logic cnt_en;

    localparam int unsigned W_CNT_SIG = $clog2(cross_pkg::TREE_NODES_TO_STORE);
    logic [W_CNT_SIG-1:0] cnt_sig;
    logic cnt_sig_en;


    //--------------------------------------------------
    // signals for seed/cmt_0 mem and both adapters
    //--------------------------------------------------
    logic seed_cmt_mem_en;
    logic [DATA_WIDTH+DATA_WIDTH/8-1:0] seed_cmt_mem_wdata, seed_cmt_mem_rdata;
    logic [DATA_WIDTH/8-1:0] seed_cmt_mem_we;
    logic [MEM_AW-1:0] seed_cmt_mem_addr;

    logic [MEM_AW-1:0] ctrl_base_addr;
    logic ctrl_base_addr_valid, ctrl_base_addr_wr_rd;
    logic [W_FCNT-1:0] ctrl_base_addr_frame_cnt;

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mem(), m_axis_mem();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mux_s_axis_mem[2](), s_axis_mux_m_axis[2](), m_axis_demux_m_axis_mem[2](), m_axis_demux_s_axis_sig[2]();
    AXIS #(.DATA_WIDTH(s_axis_ch.DATA_WIDTH)) m_axis_ch_fifo();
    logic ch_fifo_clear;

    assign sign_done = (state == S_SIGN_WAIT_CH_B) && `AXIS_LAST(m_axis_sig) && (cnt >= W_CNT'(2-1)) && (cnt_sig >= W_CNT_SIG'(cross_pkg::TREE_NODES_TO_STORE-1));
    assign vrfy_done = (mode_vrfy && state == S_PROVIDE_CMT_0_HASH && `AXIS_LAST(m_axis));
    assign vrfy_stree_done = (mode_vrfy && state != S_VRFY_COPY_SEEDS);
    assign vrfy_mtree_done = (mode_vrfy && state == S_PROVIDE_CMT_0_HASH);
    assign stree_tree_computed = (state == S_SIGN_PROVIDE_SEEDS || state == S_VRFY_WAIT_CH_B);

    // Not applicable for fast version, as the signature is not padded.
    assign vrfy_pad_err = 1'b0;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            stree_parent_idx <= '0;
        end else begin
            unique case (state)
                S_SIGN_EXPAND_QSEED: begin
                    if (`AXIS_LAST(m_axis)) begin
                        stree_parent_idx <= AW_INT_STREE'(fcnt_out) + AW_INT_STREE'(1);
                    end
                end
                // For mseed
                default: begin
                    stree_parent_idx <= AW_INT_STREE'(0);
                end
            endcase
        end
    end

    //--------------------------------------------------
    // MUX for m_axis
    //--------------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_mux_m_axis
    (
        .sel    ( sel_mux_m_axis    ),
        .s_axis ( s_axis_mux_m_axis ),
        .m_axis ( m_axis            )
    );
    `AXIS_ASSIGN( s_axis_mux_m_axis[0], m_axis_demux_s_axis_sig[0]  );
    `AXIS_ASSIGN( s_axis_mux_m_axis[1], m_axis_demux_m_axis_mem[1]  );

    //--------------------------------------------------
    // MUX for s_axis_mem
    //--------------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_mux_s_axis_mem
    (
        .sel    ( sel_mux_s_axis_mem    ),
        .s_axis ( s_axis_mux_s_axis_mem ),
        .m_axis ( s_axis_mem            )
    );
    `AXIS_ASSIGN( s_axis_mux_s_axis_mem[0], m_axis_demux_s_axis_sig[1]  );
    `AXIS_ASSIGN( s_axis_mux_s_axis_mem[1], s_axis                      );

    //--------------------------------------------------
    // DEMUX for m_axis_mem
    //--------------------------------------------------
    axis_demux #( .N_MASTERS(2) )
    u_demux_m_axis_mem
    (
        .sel    ( sel_demux_m_axis_mem      ),
        .s_axis ( m_axis_mem                ),
        .m_axis ( m_axis_demux_m_axis_mem   )
    );
    `AXIS_ASSIGN( m_axis_sig, m_axis_demux_m_axis_mem[0] );

    //--------------------------------------------------
    // DEMUX for s_axis_sig
    //--------------------------------------------------
    axis_demux #( .N_MASTERS(2) )
    u_demux_s_axis_sig
    (
        .sel    ( sel_demux_s_axis_sig  ),
        .s_axis ( s_axis_sig ),
        .m_axis ( m_axis_demux_s_axis_sig  )
    );

    //--------------------------------------------------
    // LUT-FIFO to store challenge b for path
    //--------------------------------------------------
    circ_buffer #( .DEPTH(cross_pkg::T) )
    u_ch_circ_buffer
    (
        .clk,
        .rst_n,
        .clear  ( ch_fifo_clear     ),
        .s_axis ( s_axis_ch         ),
        .m_axis ( m_axis_ch_fifo    )
    );
    // assign ch_fifo_clear = ( (cnt >= W_CNT'(2 - 1)) && `AXIS_LAST(m_axis_ch_fifo) );
    assign ch_fifo_clear = ( state == S_IDLE );

    //--------------------------------------------------
    // MEMORY adapter for seeds and cmt_0
    //--------------------------------------------------
    axis_ram_adapter
    #(
        .MEM_DW             ( DATA_WIDTH + DATA_WIDTH/8 ),
        .MEM_AW             ( MEM_AW                    ),
        .AXIS_DW            ( DATA_WIDTH                ),
        .FRAME_CNT_WIDTH    ( W_FCNT                    )
    )
    u_seed_cmt_adapter
    (
        .clk,
        .rst_n,
        .base_addr              ( ctrl_base_addr            ),
        .base_addr_valid        ( ctrl_base_addr_valid      ),
        .base_addr_wr_rd        ( ctrl_base_addr_wr_rd      ),
        .base_addr_frame_cnt    ( ctrl_base_addr_frame_cnt  ),
        .mem_en                 ( seed_cmt_mem_en           ),
        .mem_we                 ( seed_cmt_mem_we           ),
        .mem_addr               ( seed_cmt_mem_addr         ),
        .mem_wdata              ( seed_cmt_mem_wdata        ),
        .mem_rdata              ( seed_cmt_mem_rdata        ),
        .s_axis                 ( s_axis_mem                ),
        .m_axis                 ( m_axis_mem                )
    );


    //--------------------------------------------------
    // MEMORY for seeds and cmt_0
    //--------------------------------------------------
    sp_ram_parity
    #(
        .DATA_WIDTH     ( DATA_WIDTH + DATA_WIDTH/8 ),
        .PARITY_WIDTH   ( DATA_WIDTH/8              ),
        .DEPTH          ( MEM_DEPTH                 )
    )
    u_ram_no_tree
    (
        .clk,
        .en_i       ( seed_cmt_mem_en       ),
        .we_i       ( seed_cmt_mem_we       ),
        .addr_i     ( seed_cmt_mem_addr     ),
        .wdata_i    ( seed_cmt_mem_wdata    ),
        .rdata_o    ( seed_cmt_mem_rdata    )
    );

    //--------------------------------------------------
    // CTRL FSM
    //--------------------------------------------------
    always_ff @(posedge clk) begin
        if ( op_valid && op_ready ) begin
            unique if (op == M_SIGN) begin
                mode_sign <= 1'b1;
                mode_vrfy <= 1'b0;
            end else if (op == M_VERIFY) begin
                mode_sign <= 1'b0;
                mode_vrfy <= 1'b1;
            end
        end
    end

    assign op_ready = (state == S_IDLE);

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb
    begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if (op_valid && op_ready) begin
                    unique  if (op == M_SIGN)   n_state = S_SIGN_FETCH_MSEED;
                    else    if (op == M_VERIFY) n_state = S_VRFY_COPY_SEEDS;
                    else                        n_state = state;
                end
            end
            S_SIGN_FETCH_MSEED: begin
                if ( `AXIS_LAST(s_axis_mem) ) begin
                    n_state = S_SIGN_EXPAND_MSEED;
                end
            end
            S_SIGN_EXPAND_MSEED: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(4 - 1) ) begin
                    n_state = S_SIGN_EXPAND_QSEED;
                end
            end
            S_SIGN_EXPAND_QSEED: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(cross_pkg::T - 1) ) begin
                    n_state = S_SIGN_PROVIDE_SEEDS;
                end
            end
            S_SIGN_PROVIDE_SEEDS: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(cross_pkg::T - 1) ) begin
                    n_state = S_HASH_CMT_0;
                end
            end
            S_HASH_CMT_0: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(5 - 1) ) begin
                    n_state = S_PROVIDE_CMT_0_HASH;
                end
            end
            S_PROVIDE_CMT_0_HASH: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    unique if (mode_sign) begin
                        n_state = S_SIGN_WAIT_CH_B;
                    end else if (mode_vrfy) begin
                        n_state = S_IDLE;
                    end else begin
                        n_state = state;
                    end
                end
            end
            S_SIGN_WAIT_CH_B: begin
                if ( cnt >= W_CNT'(2 - 1) && `AXIS_LAST(m_axis_ch_fifo) ) begin
                    n_state = S_IDLE;
                end
            end
            S_VRFY_COPY_SEEDS: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(cross_pkg::W - 1) ) begin
                    n_state = S_VRFY_WAIT_CH_B;
                end
            end
            S_VRFY_WAIT_CH_B: begin
                if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(cross_pkg::T - 1) ) begin
                    n_state = S_HASH_CMT_0;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    always_comb
    begin
        ctrl_base_addr = '0;
        ctrl_base_addr_valid = 1'b0;
        ctrl_base_addr_wr_rd = 1'b0;
        ctrl_base_addr_frame_cnt = W_FCNT'(1);
        digest_size = sample_unit_pkg::LAMBDA;
        n_digests = W_NUM_DIGEST'(1);
        m_axis_ch_fifo.tready = 1'b0;
        {sel_mux_s_axis_mem, sel_mux_m_axis, sel_demux_m_axis_mem, sel_demux_s_axis_sig} = '1;
        unique case(state)
            S_SIGN_FETCH_MSEED: begin
                ctrl_base_addr = QUAD_SEED_ADDR_0;
                ctrl_base_addr_valid = 1'b1;
                ctrl_base_addr_wr_rd = 1'b1;
            end
            S_SIGN_EXPAND_MSEED: begin
                n_digests = W_NUM_DIGEST'(4);
                if ( wait_result ) begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b1;
                    unique if (fcnt_in == W_FCNT'(0)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_0;
                    end else if (fcnt_in == W_FCNT'(1)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_1;
                    end else if (fcnt_in == W_FCNT'(2)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_2;
                    end else begin
                        ctrl_base_addr = QUAD_SEED_ADDR_3;
                    end
                end else begin
                    ctrl_base_addr = QUAD_SEED_ADDR_0;
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b0;
                end
            end
            S_SIGN_EXPAND_QSEED: begin
                if ( wait_result ) begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b1;
                    unique if (fcnt_out == W_FCNT'(1)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_0;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_0);
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_0);
                    end else if (fcnt_out == W_FCNT'(2)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_1;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_1);
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_1);
                    end else if (fcnt_out == W_FCNT'(3)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_2;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_2);
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_2);
                    end else begin
                        ctrl_base_addr = QUAD_SEED_ADDR_3;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4);
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4);
                    end
                end else begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b0;
                    unique if (fcnt_out == W_FCNT'(0)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_0;
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_0);
                    end else if (fcnt_out == W_FCNT'(1)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_1;
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_1);
                    end else if (fcnt_out == W_FCNT'(2)) begin
                        ctrl_base_addr = QUAD_SEED_ADDR_2;
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4 + REM_2);
                    end else begin
                        ctrl_base_addr = QUAD_SEED_ADDR_3;
                        n_digests = W_NUM_DIGEST'(cross_pkg::T/4);
                    end
                end
            end
            S_SIGN_PROVIDE_SEEDS: begin
                if ( wait_result ) begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr = MEM_AW'( CMT_ADDR_0 + MEM_AW'( fcnt_in*W_FCNT'(WPH)) ); //TODO: replace by a register
                    ctrl_base_addr_wr_rd = 1'b1;
                    ctrl_base_addr_frame_cnt = W_FCNT'(1);
                end else begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr = MEM_AW'( fcnt_out*W_FCNT'(WPS) ); //TODO: replace by a register
                    ctrl_base_addr_wr_rd = 1'b0;
                end
            end
            S_HASH_CMT_0: begin
                digest_size = sample_unit_pkg::LAMBDA_2;
                if ( wait_result ) begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b1;
                    if ( fcnt_in >= W_FCNT'(4) ) begin
                        ctrl_base_addr = MROOT_ADDR;
                    end else begin
                        ctrl_base_addr = MROOT_ADDR + MEM_AW'(fcnt_in*W_FCNT'(WPH)); //TODO: replace by register
                    end
                end else begin
                    ctrl_base_addr_valid = 1'b1;
                    ctrl_base_addr_wr_rd = 1'b0;
                    unique if (fcnt_in == W_FCNT'(0)) begin
                        ctrl_base_addr = CMT_ADDR_0;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_0);
                    end else if (fcnt_in == W_FCNT'(1)) begin
                        ctrl_base_addr = CMT_ADDR_1;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_1);
                    end else if (fcnt_in == W_FCNT'(2)) begin
                        ctrl_base_addr = CMT_ADDR_2;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4 + REM_2);
                    end else if (fcnt_in == W_FCNT'(3)) begin
                        ctrl_base_addr = CMT_ADDR_3;
                        ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::T/4);
                    end else begin
                        ctrl_base_addr = MROOT_ADDR;
                        ctrl_base_addr_frame_cnt = W_FCNT'(4);
                    end
                end
            end
            S_PROVIDE_CMT_0_HASH: begin
                ctrl_base_addr = MROOT_ADDR;
                ctrl_base_addr_valid = 1'b1;
                ctrl_base_addr_wr_rd = 1'b0;
            end
            S_SIGN_WAIT_CH_B: begin
                ctrl_base_addr_wr_rd = 1'b0;
                sel_demux_m_axis_mem = 1'b0;
                if (cnt >= W_CNT'(2 - 1)) begin
                    ctrl_base_addr = QUAD_SEED_ADDR_0 + MEM_AW'(fcnt_out*WPS); //TODO: replace by register
                end else begin
                    ctrl_base_addr = CMT_ADDR_0 + MEM_AW'(fcnt_out*WPH); //TODO: replace by register
                end
                ctrl_base_addr_valid = m_axis_ch_fifo.tvalid & m_axis_ch_fifo.tdata[0];
                m_axis_ch_fifo.tready = `AXIS_LAST(m_axis_sig) || (m_axis_ch_fifo.tvalid & ~m_axis_ch_fifo.tdata[0]);
            end
            S_VRFY_COPY_SEEDS: begin
                ctrl_base_addr = QUAD_SEED_ADDR_0;
                ctrl_base_addr_valid = 1'b1;
                ctrl_base_addr_wr_rd = 1'b1;
                ctrl_base_addr_frame_cnt = W_FCNT'(cross_pkg::W);
                sel_mux_s_axis_mem = 1'b0;
            end
            S_VRFY_WAIT_CH_B: begin
                m_axis_ch_fifo.tready = `AXIS_LAST(s_axis_mem);
                ctrl_base_addr_valid = m_axis_ch_fifo.tvalid;
                if (m_axis_ch_fifo.tdata[0]) begin // b_i = 1
                    if ( wait_result ) begin // fetch cmt_0 from sig to mem
                        ctrl_base_addr = CMT_ADDR_0 + MEM_AW'(fcnt_in*WPH); // TODO:replace by regiser
                        ctrl_base_addr_wr_rd = 1'b1;
                        sel_mux_s_axis_mem = 1'b0;
                    end else begin // provide seed from memory two times
                        ctrl_base_addr = QUAD_SEED_ADDR_0 + MEM_AW'(fcnt_out*WPS); // TODO:replace by regiser
                        ctrl_base_addr_wr_rd = 1'b0;
                    end
                end else begin // b_i = 0, fetch cmt_0 from s_axis
                    ctrl_base_addr = CMT_ADDR_0 + MEM_AW'(fcnt_in*WPH); // TODO:replace by regiser
                    ctrl_base_addr_wr_rd = 1'b1;
                end
            end
            default: begin
                ctrl_base_addr = '0;
                ctrl_base_addr_valid = 1'b0;
                ctrl_base_addr_wr_rd = 1'b0;
                ctrl_base_addr_frame_cnt = W_FCNT'(1);
                m_axis_ch_fifo.tready = 1'b0;
                digest_size = sample_unit_pkg::LAMBDA;
                n_digests = W_NUM_DIGEST'(1);
                {sel_mux_s_axis_mem, sel_mux_m_axis, sel_demux_m_axis_mem,sel_demux_s_axis_sig}  = '1;
            end
        endcase
    end

    //-----------------------------------------------------------
    // FRAME COUNTERS
    //-----------------------------------------------------------
    counter
    #(
       .CNT_WIDTH( W_FCNT )
    )
    u_fcnt_in
    (
        .clk,
        .rst_n,
        .max_val    ( fcnt_in_max   ),
        .inc        ( W_FCNT'(1)    ),
        .trigger    ( fcnt_in_en    ),
        .cnt        ( fcnt_in       )
    );
    always_comb begin
        fcnt_in_en  = 1'b0;
        fcnt_in_max = W_FCNT'(4);
        unique case(state)
            S_SIGN_EXPAND_MSEED: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(4);
            end
            S_SIGN_EXPAND_QSEED: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(cross_pkg::T);
            end
            S_SIGN_PROVIDE_SEEDS: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(cross_pkg::T);
            end
            S_HASH_CMT_0: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(5);
            end
            S_VRFY_COPY_SEEDS: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(cross_pkg::W);
            end
            S_VRFY_WAIT_CH_B: begin
                fcnt_in_en  = `AXIS_LAST(s_axis_mem);
                fcnt_in_max = W_FCNT'(cross_pkg::T);
            end
            default: begin
                fcnt_in_en  = 1'b0;
                fcnt_in_max = W_FCNT'(4);
            end
        endcase
    end

    counter
    #(
       .CNT_WIDTH( W_FCNT )
    )
    u_fcnt_out
    (
        .clk,
        .rst_n,
        .max_val    ( fcnt_out_max  ),
        .inc        ( W_FCNT'(1)    ),
        .trigger    ( fcnt_out_en   ),
        .cnt        ( fcnt_out      )
    );
    always_comb begin
        fcnt_out_en     = 1'b0;
        fcnt_out_max    = W_FCNT'(4);
        unique case(state)
            S_SIGN_EXPAND_MSEED: begin
                fcnt_out_en     = `AXIS_LAST(s_axis);
                fcnt_out_max    = W_FCNT'(4);
            end
            S_SIGN_EXPAND_QSEED: begin
                fcnt_out_en     = `AXIS_LAST(m_axis);
                fcnt_out_max    = W_FCNT'(4);
            end
            S_SIGN_PROVIDE_SEEDS: begin
                fcnt_out_en     = `AXIS_LAST(m_axis) && (cnt >= W_CNT'(2 - 1));
                fcnt_out_max    = W_FCNT'(cross_pkg::T);
            end
            S_HASH_CMT_0: begin
                fcnt_out_en     = `AXIS_LAST(m_axis);
                fcnt_out_max    = W_FCNT'(cross_pkg::T + 4);
            end
            S_SIGN_WAIT_CH_B: begin
                fcnt_out_en     = `AXIS_TRANS(m_axis_ch_fifo);
                fcnt_out_max    = W_FCNT'(cross_pkg::T);
            end
            S_VRFY_WAIT_CH_B: begin
                fcnt_out_en     = `AXIS_LAST(m_axis) && (cnt >= W_CNT'(2 - 1));
                fcnt_out_max    = W_FCNT'(cross_pkg::W);
            end
            default: begin
                fcnt_out_en     = 1'b0;
                fcnt_out_max    = W_FCNT'(4);
            end
        endcase
    end

    counter
    #(
       .CNT_WIDTH( W_CNT )
    )
    u_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( cnt_max       ),
        .inc        ( W_CNT'(1)     ),
        .trigger    ( cnt_en        ),
        .cnt        ( cnt           )
    );
    always_comb begin
        cnt_en  = 1'b0;
        cnt_max = W_CNT'(2);
        unique case(state)
            S_SIGN_PROVIDE_SEEDS: begin
                cnt_en  = `AXIS_LAST(m_axis);
                cnt_max = W_CNT'(2);
            end
            S_SIGN_WAIT_CH_B: begin
                cnt_en  = `AXIS_LAST(m_axis_ch_fifo);
                cnt_max = W_CNT'(2);
            end
            S_VRFY_WAIT_CH_B: begin
                cnt_en  = `AXIS_LAST(m_axis);
                cnt_max = W_CNT'(2);
            end
            default: begin
                cnt_en  = 1'b0;
                cnt_max = W_CNT'(2);
            end
        endcase
    end

    counter
    #(
       .CNT_WIDTH( W_CNT_SIG )
    )
    u_cnt_sig
    (
        .clk,
        .rst_n,
        .max_val    ( W_CNT_SIG'(cross_pkg::TREE_NODES_TO_STORE) ),
        .inc        ( W_CNT_SIG'(1)     ),
        .trigger    ( cnt_sig_en        ),
        .cnt        ( cnt_sig           )
    );
    assign cnt_sig_en = `AXIS_LAST(m_axis_sig);

    //-----------------------------------------------------------
    // WAIT signal for easier state management
    //-----------------------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            wait_result <= 1'b0;
        end else begin
            unique case(state)
                S_SIGN_EXPAND_MSEED: begin
                    if ( wait_result ) begin
                        if ( `AXIS_LAST(s_axis_mem) && fcnt_in >= W_FCNT'(4 - 1) ) begin
                            wait_result <= 1'b0;
                        end
                    end else begin
                        if ( `AXIS_LAST(m_axis) ) begin
                            wait_result <= 1'b1;
                        end
                    end
                end
                S_SIGN_EXPAND_QSEED: begin
                    if ( wait_result ) begin
                        if ( `AXIS_LAST(s_axis_mem) ) begin
                            if (fcnt_out == W_FCNT'(1) && fcnt_in >= W_FCNT'(cross_pkg::T/4 + REM_0 - 1) ||
                                    fcnt_out == W_FCNT'(2) && fcnt_in >= W_FCNT'(2*(cross_pkg::T/4) + REM_0 + REM_1 - 1) ||
                                    fcnt_out == W_FCNT'(3) && fcnt_in >= W_FCNT'(3*(cross_pkg::T/4) + REM_0 + REM_1 + REM_2 - 1) ||
                                    fcnt_in >= W_FCNT'(cross_pkg::T - 1)) begin
                                wait_result <= 1'b0;
                            end
                        end
                    end else begin
                        if ( `AXIS_LAST(m_axis) ) begin
                            wait_result <= 1'b1;
                        end
                    end
                end
                S_SIGN_PROVIDE_SEEDS: begin
                    if ( wait_result ) begin
                        if ( `AXIS_LAST(s_axis_mem) ) begin
                            wait_result <= 1'b0;
                        end
                    end else begin
                        if ( `AXIS_LAST(m_axis) && cnt >= W_CNT'(2 - 1) ) begin
                            wait_result <= 1'b1;
                        end
                    end
                end
                S_HASH_CMT_0: begin
                    if ( wait_result ) begin
                        if ( `AXIS_LAST(s_axis_mem) ) begin
                            wait_result <= 1'b0;
                        end
                    end else begin
                        if ( `AXIS_LAST(m_axis) ) begin
                            if ( fcnt_in == W_FCNT'(0) && fcnt_out >= W_FCNT'(cross_pkg::T/4 + REM_0 - 1) ||
                                    fcnt_in == W_FCNT'(1) && fcnt_out >= W_FCNT'(2*(cross_pkg::T/4) + REM_0 + REM_1 - 1) ||
                                    fcnt_in == W_FCNT'(2) && fcnt_out >= W_FCNT'(3*(cross_pkg::T/4) + REM_0 + REM_1 + REM_2 - 1) ||
                                    fcnt_in == W_FCNT'(3) && fcnt_out >= W_FCNT'(cross_pkg::T - 1) ||
                                    fcnt_in == W_FCNT'(4) && fcnt_out >= W_FCNT'(cross_pkg::T + 4 - 1) ) begin
                                wait_result <= 1'b1;
                            end
                        end
                    end
                end
                S_VRFY_WAIT_CH_B: begin
                    if ( wait_result ) begin
                        if ( `AXIS_LAST(s_axis_mem) ) begin
                            wait_result <= 1'b0;
                        end
                    end else begin
                        if ( `AXIS_LAST(m_axis) && cnt >= W_CNT'(2 - 1) ) begin
                            wait_result <= 1'b1;
                        end
                    end
                end
                default: begin
                    wait_result <= wait_result;
                end
            endcase
        end
    end

endmodule
