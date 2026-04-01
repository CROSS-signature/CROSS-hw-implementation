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

module tree_unit
    import tree_unit_pkg::*;
    import cross_pkg::MAX_DIGESTS;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned W_DIGESTS = $clog2(MAX_DIGESTS) + 1,
	localparam int unsigned AW_INT_STREE = $clog2(2*cross_pkg::T - 1)
)
(
	input logic clk,
	input logic rst_n,

    input tree_unit_opcode_t            op,
    input logic                         op_valid,
    output logic                        op_ready,
    output logic                        sign_done,
    output logic                        vrfy_done,
    output logic                        vrfy_stree_done,
    output logic                        vrfy_mtree_done,
    output logic                        vrfy_pad_err,
    input logic                         vrfy_pad_err_clear,

    output sample_unit_pkg::digest_t    digest_size,
    output logic [W_DIGESTS-1:0]        n_digests,
    output logic [AW_INT_STREE-1:0]     stree_parent_idx,
    output logic                        stree_tree_computed,

    // Connection to sample unit
    AXIS.slave s_axis,
    AXIS.master m_axis,

    // Connectios to signature
    AXIS.slave s_axis_sig,
    AXIS.master m_axis_sig,

    // Connection to dedicated challenge port (2nd challenge b) of sample unit
	AXIS.slave s_axis_ch
);

	// -----------------------------------------------
    // MERKLE TREE SIGNALS
	// -----------------------------------------------
    mtree_pkg::mtree_opcode_t mtree_op;
	logic mtree_op_valid, mtree_op_ready;

    localparam int unsigned WORDS_PER_HASH = cross_pkg::BYTES_HASH / (DATA_WIDTH/8);
	localparam int unsigned AW_INT_MTREE = $clog2(2*cross_pkg::T-1);
	localparam int unsigned AW_MTREE = $clog2( ((2*cross_pkg::T-1)*WORDS_PER_HASH) );
    localparam int unsigned W_FCNT = $clog2(2 + 1);

	logic [AW_INT_MTREE-1:0] mtree_flag_addr;
	logic mtree_flag_wr, mtree_flag_rd, mtree_flag_we;

	logic [AW_INT_MTREE-1:0] mtree_proof_addr;
	logic mtree_proof_addr_valid;

	logic [AW_MTREE-1:0] mtree_addr;
	logic mtree_addr_is_proof, mtree_addr_we, mtree_addr_valid, mtree_addr_ready;
    logic [W_FCNT-1:0] mtree_addr_fcnt;

    // Connections to mtree memory
    logic [AW_MTREE-1:0] mtree_mem_addr;
    logic mtree_mem_en;
    logic [DATA_WIDTH/8-1:0] mtree_mem_we;
    logic [DATA_WIDTH+DATA_WIDTH/8-1:0] mtree_mem_wdata, mtree_mem_rdata;

	// -----------------------------------------------
    // SEED TREE SIGNALS
	// -----------------------------------------------
    stree_pkg::stree_opcode_t stree_op;
	logic stree_op_valid, stree_op_ready;

    localparam int unsigned WORDS_PER_SEED = cross_pkg::BYTES_SEED / (DATA_WIDTH/8);
	localparam int unsigned AW_STREE = $clog2( ((2*cross_pkg::T-1)*WORDS_PER_SEED) );

    logic [AW_INT_STREE-1:0] stree_flag_addr;
    logic stree_flag_wr, stree_flag_rd, stree_flag_we;

	logic [AW_INT_STREE-1:0] stree_path_addr;
	logic stree_path_addr_valid;

	logic [AW_STREE-1:0] stree_addr;
	logic stree_addr_we, stree_addr_valid, stree_addr_ready, stree_addr_last_seed;
    logic [W_FCNT-1:0] stree_addr_fcnt;

    logic stree_addr_is_path, stree_regen_fetch_path, stree_leaves_done, stree_leaves_done_q;

    // Connections to stree memory
    logic [AW_STREE-1:0] stree_mem_addr;
    logic stree_mem_en;
    logic [DATA_WIDTH/8-1:0] stree_mem_we;
    logic [DATA_WIDTH+DATA_WIDTH/8-1:0] stree_mem_wdata, stree_mem_rdata;

    // Signature controller
    logic [AW_MTREE-1:0] sig_mtree_addr;
    logic sig_mtree_addr_we, sig_mtree_addr_valid, sig_mtree_addr_ready;
    logic [W_FCNT-1:0] sig_mtree_addr_fcnt;

    logic [AW_STREE-1:0] sig_stree_addr;
    logic sig_stree_addr_we, sig_stree_addr_valid, sig_stree_addr_ready;
    logic [W_FCNT-1:0] sig_stree_addr_fcnt;

    logic sig_ctrl_sign_start, sig_ctrl_mtree_done, sig_ctrl_stree_done, sig_ctrl_sign_done;
    logic sig_ctrl_vrfy_start, sig_ctrl_vrfy_done, sig_ctrl_stree_vrfy_done, sig_ctrl_mtree_vrfy_done;
    logic [$clog2(cross_pkg::TREE_NODES_TO_STORE)-1:0] sig_ctrl_proof_cnt, sig_ctrl_path_cnt;
    logic sig_ctrl_proof_cnt_valid, sig_ctrl_path_cnt_valid, sig_ctrl_proof_cnt_valid_q, sig_ctrl_path_cnt_valid_q;

	// -----------------------------------------------
    // FSM SIGNALS
	// -----------------------------------------------
    typedef enum logic [2:0] {S_IDLE, S_GEN_STREE, S_GEN_MTREE,
                                S_REGEN_STREE, S_REGEN_MTREE, S_REGEN_PROVIDE_ROOT} tree_ctrl_t;
    tree_ctrl_t state, n_state;

	// -----------------------------------------------
    // Internal AXIS interfaces
	// -----------------------------------------------
    AXIS #(.DATA_WIDTH(s_axis_ch.DATA_WIDTH)) s_axis_mtree_ch(), s_axis_stree_ch();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mtree(), m_axis_mtree();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_stree(), m_axis_stree();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_sig_ctrl_mtree_su(), m_axis_sig_ctrl_mtree_su(), s_axis_sig_ctrl_stree_su(), m_axis_sig_ctrl_stree_su();
    AXIS #(.DATA_WIDTH(AW_INT_STREE)) s_axis_fifo(), m_axis_fifo();

    assign sign_done            = sig_ctrl_sign_done;
    assign vrfy_done            = sig_ctrl_vrfy_done;
    assign vrfy_stree_done      = sig_ctrl_stree_vrfy_done;
    assign vrfy_mtree_done      = sig_ctrl_mtree_vrfy_done;
    assign stree_tree_computed  = stree_leaves_done;

	// -----------------------------------------------
	// Gate the challenge inputs to synchronize for
	// both mtree and stree
	// -----------------------------------------------
    assign s_axis_mtree_ch.tdata = s_axis_ch.tdata;
    assign s_axis_stree_ch.tdata = s_axis_ch.tdata;

    assign s_axis_mtree_ch.tvalid = s_axis_ch.tvalid & s_axis_stree_ch.tready;
    assign s_axis_stree_ch.tvalid = s_axis_ch.tvalid & s_axis_mtree_ch.tready;

    assign s_axis_mtree_ch.tlast = s_axis_ch.tlast;
    assign s_axis_stree_ch.tlast = s_axis_ch.tlast;

    assign s_axis_ch.tready = s_axis_mtree_ch.tready & s_axis_stree_ch.tready;

	// -----------------------------------------------
	// AXIS Demux s-axis -> s_axis_stree / s_axis_mtree
	// -----------------------------------------------
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_demux_in[2]();
    logic sel_s_axis;

    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_axis_demux
    (
        .sel        ( sel_s_axis        ),
        .s_axis     ( s_axis            ),
        .m_axis     ( m_axis_demux_in   )
    );
    `AXIS_ASSIGN( s_axis_stree, m_axis_demux_in[0] )
    `AXIS_ASSIGN( s_axis_mtree, m_axis_demux_in[1] )

	// -----------------------------------------------
	// AXIS Mux m_axis_stree / m_axis_mtree -> m_axis
	// -----------------------------------------------
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mux_out[2](), m_axis_mux_out();
    logic sel_m_axis;

    axis_mux
    #(
        .N_SLAVES( 2 )
    )
    u_axis_mux
    (
        .sel        ( sel_m_axis        ),
        .s_axis     ( s_axis_mux_out    ),
        .m_axis     ( m_axis            )
    );
    `AXIS_ASSIGN( s_axis_mux_out[0], m_axis_stree );
    `AXIS_ASSIGN( s_axis_mux_out[1], m_axis_mtree );

	// -----------------------------------------------
	// Merkle tree addressing module
	// -----------------------------------------------
	mtree_addr
	#(
		.DATA_WIDTH( DATA_WIDTH )
	)
	u_mtree_addr
	(
		.clk,
		.rst_n,
		.op 				        ( mtree_op 			        ),
		.op_valid			        ( mtree_op_valid 	        ),
		.op_ready			        ( mtree_op_ready 	        ),
        .sig_ctrl_mtree_done        ( sig_ctrl_mtree_done       ),
        .sig_ctrl_mtree_vrfy_done   ( sig_ctrl_mtree_vrfy_done  ),
        .sig_ctrl_proof_cnt         ( sig_ctrl_proof_cnt        ),
        .sig_ctrl_proof_cnt_valid   ( sig_ctrl_proof_cnt_valid  ),
        .sig_ctrl_sign_done         ( sig_ctrl_sign_done        ),
		.flag_addr			        ( mtree_flag_addr	        ),
		.flag_bit_wr		        ( mtree_flag_wr 	        ),
		.flag_we			        ( mtree_flag_we 	        ),
		.flag_bit_rd		        ( mtree_flag_rd 	        ),
		.flag_last			        ( ),
		.proof_addr			        ( mtree_proof_addr 	        ),
		.proof_addr_valid	        ( mtree_proof_addr_valid    ),
		.addr				        ( mtree_addr			    ),
		.addr_is_proof		        ( mtree_addr_is_proof 	    ),
		.addr_we			        ( mtree_addr_we			    ),
		.addr_valid			        ( mtree_addr_valid		    ),
		.addr_ready			        ( mtree_addr_ready		    ),
        .addr_frame_cnt             ( mtree_addr_fcnt           ),
		.s_axis_ch			        ( s_axis_mtree_ch 		    )
	);

	// -----------------------------------------------
	// Merkle tree interfacing module
	// -----------------------------------------------
    mtree_su_intf
    #(
        .DATA_WIDTH ( DATA_WIDTH    ),
        .ADDR_WIDTH ( AW_MTREE      )
    )
    u_mtree_su_intf
    (
        .clk,
        .rst_n,
        .mtree_sign_done            ( sig_ctrl_mtree_done       ),
        .mtree_vrfy_addr_is_proof   ( mtree_addr_is_proof       ),
        .mem_en                     ( mtree_mem_en              ),
        .mem_addr                   ( mtree_mem_addr            ),
        .mem_we                     ( mtree_mem_we              ),
        .mem_wdata                  ( mtree_mem_wdata           ),
        .mem_rdata                  ( mtree_mem_rdata           ),
        .ctrl_addr                  ( mtree_addr                ),
        .ctrl_addr_we               ( mtree_addr_we             ),
        .ctrl_addr_valid            ( mtree_addr_valid          ),
        .ctrl_addr_ready            ( mtree_addr_ready          ),
        .ctrl_addr_frame_cnt        ( mtree_addr_fcnt           ),
        .sig_addr                   ( sig_mtree_addr            ),
        .sig_addr_we                ( sig_mtree_addr_we         ),
        .sig_addr_valid             ( sig_mtree_addr_valid      ),
        .sig_addr_ready             ( sig_mtree_addr_ready      ),
        .sig_addr_frame_cnt         ( sig_mtree_addr_fcnt       ),
        .s_axis_sig_ctrl            ( m_axis_sig_ctrl_mtree_su  ),
        .m_axis_sig_ctrl            ( s_axis_sig_ctrl_mtree_su  ),
        .s_axis                     ( s_axis_mtree              ),
        .m_axis                     ( m_axis_mtree              )
    );

	// -----------------------------------------------
	// Flag tree for merkle tree
	// -----------------------------------------------
    sp_lutram
    #(
        .DATA_WIDTH ( 1                 ),
        .DEPTH      ( (2*cross_pkg::T-1)),
        .OUTPUT_REG ( "true"            )
    )
    u_mtree_flag_mem
    (
        .clk,
        .we_i       ( mtree_flag_we     ),
        .addr_i     ( mtree_flag_addr   ),
        .wdata_i    ( mtree_flag_wr     ),
        .rdata_o    ( mtree_flag_rd     )
    );

	// -----------------------------------------------
	// Memory for the actual Merkle tree
	// -----------------------------------------------
    sp_ram_parity
    #(
        .DATA_WIDTH     ( DATA_WIDTH + DATA_WIDTH/8         ),
        .PARITY_WIDTH   ( DATA_WIDTH/8                      ),
        .DEPTH          ( (2*cross_pkg::T-1)*WORDS_PER_HASH )
    )
    u_mtree_mem
    (
        .clk,
        .en_i     ( mtree_mem_en    ),
        .we_i     ( mtree_mem_we    ),
        .addr_i   ( mtree_mem_addr  ),
        .wdata_i  ( mtree_mem_wdata ),
        .rdata_o  ( mtree_mem_rdata )
    );

	// -----------------------------------------------
	// Seed tree addressing module
	// -----------------------------------------------
    stree_addr
    #(
        .DATA_WIDTH ( DATA_WIDTH )
    )
    u_stree_addr
    (
        .clk,
        .rst_n,
        .op                         ( stree_op                  ),
        .op_valid                   ( stree_op_valid            ),
        .op_ready                   ( stree_op_ready            ),
        .regen_done                 ( ), // only used internally and in testing
        .regen_is_leaf              ( ), // only used internally and in testing
        .regen_fetch_path           ( stree_regen_fetch_path    ),
        .sig_ctrl_path_cnt          ( sig_ctrl_path_cnt         ),
        .sig_ctrl_path_cnt_valid    ( sig_ctrl_path_cnt_valid   ),
        .sig_ctrl_stree_done        ( sig_ctrl_stree_done       ),
        .sig_ctrl_sign_done         ( sig_ctrl_sign_done        ),
        .sig_ctrl_stree_vrfy_done   ( sig_ctrl_stree_vrfy_done  ),
        .stree_leaves_done          ( stree_leaves_done         ),
        .parent_idx                 ( stree_parent_idx          ),
        .flag_addr                  ( stree_flag_addr           ),
        .flag_bit_wr                ( stree_flag_wr             ),
        .flag_we                    ( stree_flag_we             ),
        .flag_bit_rd                ( stree_flag_rd             ),
        .flag_last                  ( ),
        .path_addr                  ( stree_path_addr           ),
        .path_addr_valid            ( stree_path_addr_valid     ),
        .path_last                  ( ),
        .addr                       ( stree_addr                ),
        .addr_is_path               ( stree_addr_is_path        ),
        .addr_we                    ( stree_addr_we             ),
        .addr_valid                 ( stree_addr_valid          ),
        .addr_ready                 ( stree_addr_ready          ),
        .addr_last_seed             ( stree_addr_last_seed      ),
        .addr_frame_cnt             ( stree_addr_fcnt           ),
        .s_axis_ch                  ( s_axis_stree_ch           )
    );

	// -----------------------------------------------
	// Seed tree interfacing module
	// -----------------------------------------------
    stree_su_intf
    #(
        .DATA_WIDTH ( DATA_WIDTH    ),
        .ADDR_WIDTH ( AW_STREE      )
    )
    u_stree_su_intf
    (
        .clk,
        .rst_n,
        .stree_vrfy_copy_leaf       ( stree_regen_fetch_path    ),
        .stree_vrfy_addr_is_path    ( stree_addr_is_path        ),
        .stree_sign_done            ( sig_ctrl_stree_done       ),
        .mem_en                     ( stree_mem_en              ),
        .mem_addr                   ( stree_mem_addr            ),
        .mem_we                     ( stree_mem_we              ),
        .mem_wdata                  ( stree_mem_wdata           ),
        .mem_rdata                  ( stree_mem_rdata           ),
        .ctrl_addr                  ( stree_addr                ),
        .ctrl_addr_we               ( stree_addr_we             ),
        .ctrl_addr_valid            ( stree_addr_valid          ),
        .ctrl_addr_ready            ( stree_addr_ready          ),
        .ctrl_addr_frame_cnt        ( stree_addr_fcnt           ),
        .sig_addr                   ( sig_stree_addr            ),
        .sig_addr_we                ( sig_stree_addr_we         ),
        .sig_addr_valid             ( sig_stree_addr_valid      ),
        .sig_addr_ready             ( sig_stree_addr_ready      ),
        .sig_addr_frame_cnt         ( sig_stree_addr_fcnt       ),
        .s_axis_sig_ctrl            ( m_axis_sig_ctrl_stree_su  ),
        .m_axis_sig_ctrl            ( s_axis_sig_ctrl_stree_su  ),
        .s_axis                     ( s_axis_stree              ),
        .m_axis                     ( m_axis_stree              )
    );

	// -----------------------------------------------
	// Flag tree for seed tree
	// -----------------------------------------------
    sp_lutram
    #(
        .DATA_WIDTH ( 1                     ),
        .DEPTH      ( 2*cross_pkg::T - 1    ),
        .OUTPUT_REG ( "true"                )
    )
    u_stree_flag_mem
    (
        .clk,
        .we_i       ( stree_flag_we     ),
        .addr_i     ( stree_flag_addr   ),
        .wdata_i    ( stree_flag_wr     ),
        .rdata_o    ( stree_flag_rd     )
    );

	// -----------------------------------------------
	// Memory for the actual Seed tree
	// -----------------------------------------------
    sp_ram_parity
    #(
        .DATA_WIDTH     ( DATA_WIDTH + DATA_WIDTH/8             ),
        .PARITY_WIDTH   ( DATA_WIDTH/8                          ),
        .DEPTH          ( (2*cross_pkg::T - 1)*WORDS_PER_SEED   )
    )
    u_stree_mem
    (
        .clk,
        .en_i     ( stree_mem_en      ),
        .we_i     ( stree_mem_we      ),
        .addr_i   ( stree_mem_addr    ),
        .wdata_i  ( stree_mem_wdata   ),
        .rdata_o  ( stree_mem_rdata   )
    );

	// -----------------------------------------------
	// Proof / Path FIFO
	// -----------------------------------------------
    fifo_ram
    #(
        .DEPTH ( 2*cross_pkg::TREE_NODES_TO_STORE )
    )
    u_proof_path_fifo
    (
        .clk,
        .rst_n,
        .s_axis ( s_axis_fifo ),
        .m_axis ( m_axis_fifo )
    );
    assign s_axis_fifo.tdata    = !(sig_ctrl_proof_cnt_valid) ? mtree_proof_addr        : stree_path_addr;
    assign s_axis_fifo.tvalid   = !(sig_ctrl_proof_cnt_valid) ? mtree_proof_addr_valid  : stree_path_addr_valid;

    // Need a cycle delay here because of the fifo above
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            sig_ctrl_path_cnt_valid_q   <= 1'b0;
            sig_ctrl_proof_cnt_valid_q  <= 1'b0;
        end else begin
            sig_ctrl_path_cnt_valid_q   <= sig_ctrl_path_cnt_valid;
            sig_ctrl_proof_cnt_valid_q  <= sig_ctrl_proof_cnt_valid;
        end
    end



	//------------------------------------------------
	// Signature Controller
	//------------------------------------------------
    sig_ctrl
    #(
        .DATA_WIDTH             ( DATA_WIDTH            ),
        .MTREE_ADDR_WIDTH       ( AW_MTREE              ),
        .STREE_ADDR_WIDTH       ( AW_STREE              )
    )
    u_sig_ctrl
    (
        .clk,
        .rst_n,
        .sign_start             ( sig_ctrl_sign_start           ),
        .sign_done              ( sig_ctrl_sign_done            ),
        .proof_cnt              ( sig_ctrl_proof_cnt            ),
        .proof_cnt_valid        ( sig_ctrl_proof_cnt_valid_q    ),
        .path_cnt               ( sig_ctrl_path_cnt             ),
        .path_cnt_valid         ( sig_ctrl_path_cnt_valid_q     ),
        .vrfy_start             ( sig_ctrl_vrfy_start           ),
        .vrfy_done              ( sig_ctrl_vrfy_done            ),
        .vrfy_stree_done        ( sig_ctrl_stree_vrfy_done      ),
        .vrfy_mtree_done        ( sig_ctrl_mtree_vrfy_done      ),
        .vrfy_pad_err           ( vrfy_pad_err                  ),
        .vrfy_pad_err_clear     ( vrfy_pad_err_clear            ),
        .s_axis_proof_path      ( m_axis_fifo                   ),
        .mtree_addr             ( sig_mtree_addr                ),
        .mtree_addr_we          ( sig_mtree_addr_we             ),
        .mtree_addr_valid       ( sig_mtree_addr_valid          ),
        .mtree_addr_ready       ( sig_mtree_addr_ready          ),
        .mtree_addr_frame_cnt   ( sig_mtree_addr_fcnt           ),
        .stree_addr             ( sig_stree_addr                ),
        .stree_addr_we          ( sig_stree_addr_we             ),
        .stree_addr_valid       ( sig_stree_addr_valid          ),
        .stree_addr_ready       ( sig_stree_addr_ready          ),
        .stree_addr_frame_cnt   ( sig_stree_addr_fcnt           ),
        .s_axis_stree_su        ( s_axis_sig_ctrl_stree_su      ),
        .m_axis_stree_su        ( m_axis_sig_ctrl_stree_su      ),
        .s_axis_mtree_su        ( s_axis_sig_ctrl_mtree_su      ),
        .m_axis_mtree_su        ( m_axis_sig_ctrl_mtree_su      ),
        .s_axis_sig             ( s_axis_sig                    ),
        .m_axis_sig             ( m_axis_sig                    )
    );


	// -----------------------------------------------
	// Control FSM
	// -----------------------------------------------

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if (op_valid && op_ready) begin
                    unique  if (op == M_SIGN)   n_state = S_GEN_STREE;
                    else    if (op == M_VERIFY) n_state = S_REGEN_STREE;
                    else                        n_state = state;
                end
            end
            S_GEN_STREE: begin
                if (stree_addr_last_seed && `AXIS_LAST(m_axis_stree)) begin
                    n_state = S_GEN_MTREE;
                end
            end
            S_GEN_MTREE: begin
                if (sig_ctrl_sign_done) begin
                    n_state = S_IDLE;
                end
            end
            S_REGEN_STREE: begin
                if (stree_addr_last_seed) begin
                    n_state = S_REGEN_MTREE;
                end
            end
            S_REGEN_MTREE: begin
                if (sig_ctrl_vrfy_done) begin
                    n_state = S_REGEN_PROVIDE_ROOT;
                end
            end
            S_REGEN_PROVIDE_ROOT: begin
                if ( `AXIS_LAST(m_axis_mtree) ) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    always_comb
    begin
        //Defaults
        stree_op = stree_pkg::M_GEN_TREE;
        mtree_op = mtree_pkg::M_GEN_TREE;
        {sig_ctrl_sign_start, sig_ctrl_vrfy_start} = '0;
        {sel_s_axis, sel_m_axis} = '0;
        digest_size = sample_unit_pkg::LAMBDA_2;
        n_digests = W_DIGESTS'(1);

        unique case(state)
            S_IDLE: begin
                unique if (op_valid && op == M_SIGN) begin
                    stree_op = stree_pkg::M_GEN_TREE;
                    mtree_op = mtree_pkg::M_GEN_TREE;
                    sig_ctrl_sign_start = 1'b1;
                end else if (op_valid && op == M_VERIFY) begin
                    stree_op = stree_pkg::M_REGEN_TREE;
                    mtree_op = mtree_pkg::M_REGEN_TREE;
                    sig_ctrl_vrfy_start = 1'b1;
                end else begin
                    stree_op = stree_pkg::M_GEN_TREE;
                    mtree_op = mtree_pkg::M_GEN_TREE;
                    {sig_ctrl_sign_start, sig_ctrl_vrfy_start} = '0;
                end
            end

            // sel = 0 corresponds to stree
            // switch input demux as soon as seeds are provided,
            // which means that cmt_0 is computed and stored in mtree
            S_GEN_STREE,
            S_REGEN_STREE: begin
                sel_s_axis = stree_leaves_done | stree_leaves_done_q;
                sel_m_axis = 1'b0;
                digest_size = sample_unit_pkg::LAMBDA;
                n_digests = W_DIGESTS'(2);
            end

            // sel = 0 corresponds to stree
            S_GEN_MTREE,
            S_REGEN_MTREE,
            S_REGEN_PROVIDE_ROOT: begin
                digest_size = sample_unit_pkg::LAMBDA_2;
                n_digests = W_DIGESTS'(1);
                sel_s_axis = 1'b1;
                sel_m_axis = 1'b1;
            end

            default: begin
                stree_op = stree_pkg::M_GEN_TREE;
                mtree_op = mtree_pkg::M_GEN_TREE;
                {sig_ctrl_sign_start, sig_ctrl_vrfy_start} = '0;
                {sel_s_axis, sel_m_axis} = '0;
                digest_size = sample_unit_pkg::LAMBDA_2;
                n_digests = W_DIGESTS'(1);
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            stree_leaves_done_q <= 1'b0;
        end else begin
            if (!stree_leaves_done_q) begin
                stree_leaves_done_q <= (state == S_REGEN_STREE && stree_leaves_done);
            end else begin
                stree_leaves_done_q <= (state == S_REGEN_STREE);
            end
        end
    end

    assign stree_op_valid = op_valid & mtree_op_ready;
    assign mtree_op_valid = op_valid & stree_op_ready;
    assign op_ready = stree_op_ready & mtree_op_ready;

endmodule
