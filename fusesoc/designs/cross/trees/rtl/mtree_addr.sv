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

module mtree_addr
    import mtree_pkg::*;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned WORDS_PER_HASH = cross_pkg::BYTES_HASH / (DATA_WIDTH/8),
    localparam int unsigned AW_INT = $clog2(2*cross_pkg::T-1),
    localparam int unsigned ADDR_WIDTH = $clog2((2*cross_pkg::T-1)*WORDS_PER_HASH),
    localparam int unsigned W_TNTS = $clog2(cross_pkg::TREE_NODES_TO_STORE),
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    input mtree_opcode_t            op,
    input logic                     op_valid,
    output logic                    op_ready,

    output logic                    sig_ctrl_mtree_done,
    output logic                    sig_ctrl_mtree_vrfy_done,
    output logic [W_TNTS-1:0]       sig_ctrl_proof_cnt,
    output logic                    sig_ctrl_proof_cnt_valid,
    input logic                     sig_ctrl_sign_done,

    output logic [AW_INT-1:0]       flag_addr,
    output logic                    flag_bit_wr,
    output logic                    flag_we,
    input logic                     flag_bit_rd,
    output logic                    flag_last,

    output logic [AW_INT-1:0]       proof_addr,
    output logic                    proof_addr_valid,

    output logic [ADDR_WIDTH-1:0]   addr,
    output logic                    addr_is_proof,
    output logic                    addr_we,
    output logic                    addr_valid,
    input logic                     addr_ready,
    output logic [W_FCNT-1:0]       addr_frame_cnt,

    AXIS.slave s_axis_ch
);

    typedef enum logic [3:0] {S_IDLE, S_PLACE_CMT, S_CHILD_ADDR, S_PARENT_ADDR, S_PROVIDE_ROOT,
                                S_PLACE_CH, S_CHILD_CH, S_PARENT_CH, S_WAIT_DONE,
                                S_PLACE_CMT_CURRENT_REGEN, S_PLACE_CMT_REGEN, S_CHILD_REGEN,
                                S_COMPRESS_REGEN, S_PARENT_REGEN, S_PROVIDE_ROOT_REGEN} fsm_t;
    fsm_t state, n_state;

    import cross_pkg::TREE_OFFSETS;
    import cross_pkg::TREE_NODES_PER_LEVEL;
    import cross_pkg::TREE_LEAVES_START_INDICES;
    import cross_pkg::TREE_CONSECUTIVE_LEAVES;
    import cross_pkg::TREE_NODES_PER_LEVEL;
    import cross_pkg::TREE_SUBROOTS;
    import cross_pkg::TREE_NODES_TO_STORE;

    import common_pkg::max;
    localparam int unsigned W_NPL_IDX = max($clog2($size(TREE_NODES_PER_LEVEL)), 1);
    localparam int unsigned W_NCL_IDX = max($clog2($size(TREE_CONSECUTIVE_LEAVES)), 1);


    localparam int unsigned W_SCNT = max($clog2(TREE_SUBROOTS),1);
    logic [W_SCNT-1:0] subroot_cnt;

    logic [AW_INT-1:0] addr_int;
    logic [AW_INT-1:0] parent_node_q, start_node_q, current_node_q;

    logic [cross_pkg::BITS_T-1:0] node_cnt_pl, node_cnt_pl_max;
    logic [cross_pkg::BITS_T-1:0] node_cnt_gen, node_cnt_gen_max;
    logic node_cnt_gen_soft_rst_n;

    localparam int unsigned W_LCNT = $clog2(cross_pkg::BITS_T) + 1;
    logic [W_LCNT-1:0] level_cnt;

    localparam int unsigned W_CCNT = $clog2(3);
    logic [W_CCNT-1:0] child_cnt, child_cnt_max;

    logic [W_TNTS-1:0] proof_cnt;
    logic proof_cnt_soft_rst;

    logic subroot_cnt_en, node_cnt_pl_en, node_cnt_gen_en, level_cnt_en, child_cnt_en, proof_cnt_en;
    logic addr_is_root;
    logic flag_bit_q, mode_gen;
    logic [1:0] flag_bit_regen_q;


    assign op_ready = ( state == S_IDLE );

    assign sig_ctrl_mtree_done      = ( state == S_CHILD_CH || state == S_PARENT_CH || state == S_WAIT_DONE );
    assign sig_ctrl_mtree_vrfy_done = ( state == S_PROVIDE_ROOT_REGEN );
    assign sig_ctrl_proof_cnt_valid = ( state == S_WAIT_DONE );
    assign sig_ctrl_proof_cnt       = proof_cnt;

    assign addr_is_root = ~(|addr_int);

    always_ff @(posedge clk) begin
        if (state == S_IDLE) begin
            mode_gen <= (op == M_GEN_TREE);
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if ( op_valid && op_ready ) begin
                    unique  if ( op == M_GEN_TREE  )    n_state = S_PLACE_CMT;
                    else    if ( op == M_REGEN_TREE )   n_state = S_PLACE_CH;
                    else n_state = S_IDLE;
                end
            end

            S_PLACE_CMT: begin
                if ( (addr_valid && addr_ready)
                    && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                    && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                    n_state = S_CHILD_ADDR;
                end
            end

            S_CHILD_ADDR: begin
                if ( addr_valid && addr_ready ) begin
                    n_state = S_PARENT_ADDR;
                end
            end

            S_PARENT_ADDR: begin
                if ( addr_valid && addr_ready ) begin
                    if ( addr_is_root ) begin
                        n_state = S_PROVIDE_ROOT;
                    end else begin
                        n_state = S_CHILD_ADDR;
                    end
                end
            end

            S_PROVIDE_ROOT: begin
                if ( addr_valid && addr_ready ) begin
                    n_state = S_PLACE_CH;
                end
            end

            S_PLACE_CH: begin
                if ( `AXIS_TRANS(s_axis_ch)
                    && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                    && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                    n_state = S_CHILD_CH;
                end
            end

            S_CHILD_CH: begin
                if ( child_cnt >= W_CCNT'(2 - 1) )begin
                    n_state = S_PARENT_CH;
                end
            end

            S_PARENT_CH: begin
                if ( flag_last ) begin
                    if ( mode_gen ) begin
                        n_state = S_WAIT_DONE;
                    end else begin
                        n_state = S_PLACE_CMT_CURRENT_REGEN;
                    end
                end else begin
                    n_state = S_CHILD_CH;
                end
            end

            S_WAIT_DONE: begin
                if ( sig_ctrl_sign_done ) begin
                    n_state = S_IDLE;
                end
            end

            S_PLACE_CMT_CURRENT_REGEN: begin
                n_state = S_PLACE_CMT_REGEN;
            end

            S_PLACE_CMT_REGEN: begin
                if ( !flag_bit_rd  ) begin // skip this leaf
                    if ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                        && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                        n_state = S_CHILD_REGEN;
                    end else begin
                        n_state = S_PLACE_CMT_CURRENT_REGEN;
                    end
                end else if ( addr_valid && addr_ready && flag_bit_rd  ) begin
                    if ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                        && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                        n_state = S_CHILD_REGEN;
                    end else begin
                        n_state = S_PLACE_CMT_CURRENT_REGEN;
                    end
                end
            end

            S_CHILD_REGEN: begin
                if ( child_cnt >= W_CCNT'(3 - 1) ) begin
                    n_state = S_COMPRESS_REGEN;
                end
            end

            S_COMPRESS_REGEN: begin
                // Early abort. No need to check if parent is root, as this
                // would not be skipped.
                if ( !flag_bit_regen_q[1] && !flag_bit_regen_q[0] ) begin
                    n_state = S_CHILD_REGEN;
                end else if ( addr_valid && addr_ready && child_cnt >= W_CCNT'(2-1) ) begin
                    n_state = S_PARENT_REGEN;
                end
            end

            S_PARENT_REGEN: begin
                if ( addr_valid && addr_ready ) begin
                    if ( parent_node_q == AW_INT'(0) ) begin
                        n_state = S_PROVIDE_ROOT_REGEN;
                    end else begin
                        n_state = S_CHILD_REGEN;
                    end
                end
            end

            S_PROVIDE_ROOT_REGEN: begin
                if ( addr_valid && addr_ready ) begin
                    n_state = S_IDLE;
                end
            end

            default: n_state = S_IDLE;
        endcase
    end

    always_comb begin
        addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
        addr_is_proof = 1'b0;
        addr_valid = 1'b0;
        addr_we = 1'b0;
        addr_frame_cnt = W_FCNT'(1);
        unique case(state)
            S_PLACE_CMT: begin
                addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
                addr_valid = 1'b1;
                addr_we = 1'b1;
            end

            S_CHILD_ADDR: begin
                addr_int = AW_INT'(start_node_q + AW_INT'(node_cnt_gen));
                addr_valid = 1'b1;
                addr_frame_cnt = W_FCNT'(2);
            end

            S_PARENT_ADDR,
            S_PARENT_REGEN: begin
                addr_int = parent_node_q;
                addr_valid = 1'b1;
                addr_we = 1'b1;
            end

            S_PROVIDE_ROOT,
            S_PROVIDE_ROOT_REGEN: begin
                addr_int = '0;
                addr_valid = 1'b1;
            end

            S_PLACE_CMT_REGEN: begin
                addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
                addr_valid = flag_bit_rd;
                addr_we = flag_bit_rd;
            end

            S_COMPRESS_REGEN: begin
                addr_int = AW_INT'(start_node_q + AW_INT'(node_cnt_gen) + AW_INT'(child_cnt));
                if ( child_cnt >= W_CCNT'(2 - 1) ) begin // right child
                    if ( !flag_bit_regen_q[0] ) begin // from tree
                        addr_int = AW_INT'( proof_cnt );
                        addr_is_proof = 1'b1;
                    end
                end else begin // left child
                    if ( !flag_bit_regen_q[1] ) begin // from tree
                        addr_int = AW_INT'( proof_cnt );
                        addr_is_proof = 1'b1;
                    end
                end
                addr_valid = flag_bit_regen_q[1] | flag_bit_regen_q[0];
            end

            default: begin
                addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
                addr_is_proof = 1'b0;
                addr_valid = 1'b0;
                addr_we = 1'b0;
            end
        endcase
    end
    assign addr = ADDR_WIDTH'( ADDR_WIDTH'(addr_int)*ADDR_WIDTH'(WORDS_PER_HASH) );

    always_comb begin
        flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
        flag_we = 1'b0;
        s_axis_ch.tready = 1'b0;
        unique case(state)
            S_PLACE_CH: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
                flag_we = s_axis_ch.tvalid;
                s_axis_ch.tready = 1'b1;
            end

            S_CHILD_CH: begin
                flag_addr = AW_INT'(start_node_q + AW_INT'(node_cnt_gen) + AW_INT'(child_cnt));
            end

            S_PARENT_CH: begin
                flag_addr = parent_node_q;
                flag_we = 1'b1;
            end

            S_PLACE_CMT_CURRENT_REGEN,
            S_PLACE_CMT_REGEN: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
            end

            S_CHILD_REGEN: begin
                flag_addr = AW_INT'(start_node_q + AW_INT'(node_cnt_gen) + AW_INT'(child_cnt));
            end

            default: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt_pl);
                flag_we = 1'b0;
                s_axis_ch.tready = 1'b0;
            end
        endcase
    end
    assign flag_last = ( (state == S_PARENT_CH) && (~(|flag_addr)) );

    always_comb begin
        proof_addr = AW_INT'( current_node_q + AW_INT'(child_cnt) );
        proof_addr_valid = 1'b0;

        // flag_bit_q corresponds to left child, flag_bit_rd to right child.
        // Proof FIFO is expected to never be full.
        if (state == S_PARENT_CH) begin
            if (flag_bit_q && !flag_bit_rd) begin
                proof_addr = AW_INT'( current_node_q + AW_INT'(1) );
            end else begin
                proof_addr = current_node_q;
            end
            proof_addr_valid = (flag_bit_q ^ flag_bit_rd) & mode_gen;
        end
    end

    // For the merkle tree, we label the node if the challenge bit is zero, thus invert
    // the input challenge bit. When labeling parents, we need to store the flag bit of the
    // left child in a register and use the memory output from the previous address
    // (synchronous output) to write the new flag bit.
    always_comb begin
        unique case(state)
            S_PLACE_CH: flag_bit_wr = ~s_axis_ch.tdata;
            S_PARENT_CH: flag_bit_wr = flag_bit_q | flag_bit_rd;
            default: flag_bit_wr = ~s_axis_ch.tdata;
        endcase
    end

    // Only register the flag input when we are at the right child node as
    // read data becomes valid after the rising edge (so we progressed one node)
    always_ff @(posedge clk) begin
        if ( state == S_CHILD_CH ) begin
            if ( child_cnt >= W_CCNT'(2 - 1) ) flag_bit_q <= flag_bit_rd;
        end
    end

    always_ff @(posedge clk) begin
        if ( state == S_CHILD_REGEN ) begin
            if ( child_cnt == W_CCNT'(2-1) ) flag_bit_regen_q[1] <= flag_bit_rd;
            if ( child_cnt == W_CCNT'(3-1) ) flag_bit_regen_q[0] <= flag_bit_rd;
        end
    end

    // While we are traversing through the tree from right to left on each level,
    // store the parent node every time we are at the right child
    always_ff @(posedge clk)
    begin
        unique case(state)
            S_CHILD_ADDR: begin
                if ( addr_valid && addr_ready ) begin
                    parent_node_q <= AW_INT'( ((start_node_q + AW_INT'(node_cnt_gen) - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                end
            end
            S_CHILD_CH: begin
                if ( child_cnt >= W_CCNT'(2 - 1) ) begin
                    parent_node_q <= AW_INT'( ((start_node_q + AW_INT'(node_cnt_gen) - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                end
            end
            S_CHILD_REGEN: begin
                if ( child_cnt >= W_CCNT'(3 - 1) ) begin
                    parent_node_q <= AW_INT'( ((start_node_q + AW_INT'(node_cnt_gen) - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                end
            end
            default: parent_node_q <= parent_node_q;
        endcase
    end

    always_ff @(posedge clk)
    begin
        unique case(state)
            S_CHILD_CH: begin
                if ( child_cnt >= W_CCNT'(2 - 1) ) begin
                    current_node_q <= AW_INT'( start_node_q + AW_INT'(node_cnt_gen) );
                end
            end
            default: current_node_q <= current_node_q;
        endcase
    end

    // Store the current start index (last level, leftmost leaf) that is required to traverse
    // the tree in a breadth-first manner from left to right
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
        end else begin
            unique case(state)
                S_IDLE: begin
                    start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                end
                S_CHILD_ADDR: begin
                    if ( addr_valid && addr_ready && node_cnt_gen <= cross_pkg::BITS_T'(1) ) begin
                        start_node_q <= AW_INT'( ((start_node_q - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                    end
                end
                S_PLACE_CH: begin
                    if ( `AXIS_TRANS(s_axis_ch)
                        && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                        && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                        start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                    end
                end
                S_CHILD_CH: begin
                    if ( node_cnt_gen <= cross_pkg::BITS_T'(1)
                        && child_cnt >= W_CCNT'(2-1) ) begin
                        start_node_q <= AW_INT'( ((start_node_q - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                    end
                end
                S_PARENT_ADDR: begin
                    if ( addr_is_root && addr_valid && addr_ready ) begin
                        start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                    end
                end
                S_PLACE_CMT_REGEN: begin
                    if ( !flag_bit_rd || (flag_bit_rd && addr_valid && addr_ready) ) begin
                        if ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                            && node_cnt_pl >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                            start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                        end
                    end
                end
                // In case of early abort, compute new start node
                S_COMPRESS_REGEN: begin
                    if ( !flag_bit_regen_q[1] && !flag_bit_regen_q[0] ) begin
                        if (node_cnt_gen <= cross_pkg::BITS_T'(1)) begin
                            start_node_q <= AW_INT'( ((start_node_q - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                        end
                    end
                end
                S_PARENT_REGEN: begin
                    if ( addr_valid && addr_ready && node_cnt_gen <= cross_pkg::BITS_T'(1) ) begin
                        if ( addr_is_root ) begin
                            start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                        end else begin
                            start_node_q <= AW_INT'( ((start_node_q - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[level_cnt-1] >> 1) );
                        end
                    end
                end
                default: start_node_q <= start_node_q;
            endcase
        end
    end

    /* count through the subroots */
    counter #(
        .CNT_WIDTH( W_SCNT )
    ) u_subroot_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n         ),
        .max_val    ( W_SCNT'(TREE_SUBROOTS)  ),
        .inc        ( W_SCNT'(1)    ),
        .trigger    ( subroot_cnt_en),
        .cnt        ( subroot_cnt   )
    );
    always_comb begin
        subroot_cnt_en = 1'b0;
        unique case (state)
            S_PLACE_CMT: subroot_cnt_en = (addr_valid && addr_ready)
                                        && (node_cnt_pl >= node_cnt_pl_max - cross_pkg::BITS_T'(1));
            S_PLACE_CH: subroot_cnt_en = ( `AXIS_TRANS(s_axis_ch) )
                                        && (node_cnt_pl >= node_cnt_pl_max - cross_pkg::BITS_T'(1));
            S_PLACE_CMT_REGEN: subroot_cnt_en = ( (node_cnt_pl >= node_cnt_pl_max - cross_pkg::BITS_T'(1))
                                                && ( !flag_bit_rd || (flag_bit_rd && addr_valid && addr_ready) ) );
            default: subroot_cnt_en = '0;
        endcase
    end

    // Node count for each level when placing nodes
    // Traverses from left to right for each level containing leaves
    counter #(
        .CNT_WIDTH( cross_pkg::BITS_T )
    ) u_node_cnt_pl (
        .clk        ( clk               ),
        .rst_n      ( rst_n             ),
        .max_val    ( node_cnt_pl_max   ),
        .inc        ( cross_pkg::BITS_T'(1) ),
        .trigger    ( node_cnt_pl_en    ),
        .cnt        ( node_cnt_pl       )
    );
    assign node_cnt_pl_max = cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]);

    always_comb begin
        node_cnt_pl_en = 1'b0;
        unique case (state)
            S_PLACE_CMT: node_cnt_pl_en = (addr_valid && addr_ready);
            S_PLACE_CH: node_cnt_pl_en = ( `AXIS_TRANS(s_axis_ch) );
            S_PLACE_CMT_REGEN: node_cnt_pl_en = ( !flag_bit_rd  || (flag_bit_rd && addr_valid && addr_ready) );
            default: node_cnt_pl_en = 1'b0;
        endcase
    end

    // Node count for each level when traversing tree for root generation
    // and labelling.
    // Traverses from right to left for each level containing leaves
    counter_dec #(
        .CNT_WIDTH  ( cross_pkg::BITS_T ),
        .MIN_VAL    ( 0                 )
    ) u_node_cnt_gen (
        .clk        ( clk                               ),
        .rst_n      ( rst_n & node_cnt_gen_soft_rst_n   ),
        .max_val    ( node_cnt_gen_max                  ),
        .dec        ( cross_pkg::BITS_T'(2)             ),
        .trigger    ( node_cnt_gen_en                   ),
        .cnt        ( node_cnt_gen                      )
    );

    always_comb begin
        node_cnt_gen_en = 1'b0;
        node_cnt_gen_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)] - 2);
        node_cnt_gen_soft_rst_n = 1'b1;
        unique case (state)
            S_IDLE: begin
                node_cnt_gen_soft_rst_n = 1'b0;
            end
            S_CHILD_ADDR: begin
                node_cnt_gen_en = (addr_valid && addr_ready);
                node_cnt_gen_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt-W_LCNT'(1))] - 2);
            end
            S_PARENT_ADDR: begin
                if ( addr_is_root && addr_valid && addr_ready ) begin
                    node_cnt_gen_soft_rst_n = 1'b0;
                end
            end
            S_CHILD_CH: begin
                node_cnt_gen_en = (child_cnt >= W_CCNT'(2 - 1));
                node_cnt_gen_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt-W_LCNT'(1))] - 2);
            end
            S_PARENT_CH: begin
                node_cnt_gen_soft_rst_n = ~flag_last;
            end
            S_COMPRESS_REGEN: begin
                // Early abort, populate counter
                if ( !flag_bit_regen_q[1] && !flag_bit_regen_q[0] ) begin
                    node_cnt_gen_en = 1'b1;
                    node_cnt_gen_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt-W_LCNT'(1))] - 2);
                end
            end
            S_PARENT_REGEN: begin
                node_cnt_gen_en = (addr_valid && addr_ready);
                node_cnt_gen_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt-W_LCNT'(1))] - 2);
            end
            default: begin
                node_cnt_gen_soft_rst_n = 1'b1;
                node_cnt_gen_en = 1'b0;
            end
        endcase
    end

    /* level counter */
    counter_dec #(
        .CNT_WIDTH  ( W_LCNT    ),
        .MIN_VAL    ( 1         )
    ) u_level_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n         ),
        .max_val    ( W_LCNT'(cross_pkg::BITS_T)    ),
        .dec        ( W_LCNT'(1)    ),
        .trigger    ( level_cnt_en  ),
        .cnt        ( level_cnt     )
    );
    always_comb begin
        level_cnt_en = 1'b0;
        unique case (state)
            S_CHILD_ADDR: level_cnt_en = (addr_valid && addr_ready) && (node_cnt_gen <= cross_pkg::BITS_T'(1));
            S_CHILD_CH: level_cnt_en = (node_cnt_gen <= cross_pkg::BITS_T'(1)) && (child_cnt >= W_CCNT'(2 - 1));
            S_COMPRESS_REGEN: begin
                if ( (!flag_bit_regen_q[1] && !flag_bit_regen_q[0]) && (node_cnt_gen <= cross_pkg::BITS_T'(1)) ) begin
                    level_cnt_en = 1'b1;
                end
            end
            S_PARENT_REGEN: level_cnt_en = (addr_valid && addr_ready) && (node_cnt_gen <= cross_pkg::BITS_T'(1));
            default: level_cnt_en = 1'b0;
        endcase
    end

    // Child counter used for regeneration of tree
    counter #(
        .CNT_WIDTH( W_CCNT )
    ) u_child_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n         ),
        .max_val    ( child_cnt_max ),
        .inc        ( W_CCNT'(1)    ),
        .trigger    ( child_cnt_en  ),
        .cnt        ( child_cnt     )
    );
    assign child_cnt_max = (state == S_CHILD_REGEN) ? W_CCNT'(3) : W_CCNT'(2);
    always_comb begin
        child_cnt_en = 1'b0;
        unique case(state)
            S_CHILD_CH: child_cnt_en = 1'b1;
            S_CHILD_REGEN: child_cnt_en = 1'b1;
            S_COMPRESS_REGEN: child_cnt_en = ( addr_valid && addr_ready );
            default: child_cnt_en = 1'b0;
        endcase
    end


    // Keep track of the number of proof nodes consumed
    counter #(
        .CNT_WIDTH( W_TNTS )
    ) u_proof_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n & ~proof_cnt_soft_rst   ),
        .max_val    ( W_TNTS'(TREE_NODES_TO_STORE)   ),
        .inc        ( W_TNTS'(1)    ),
        .trigger    ( proof_cnt_en  ),
        .cnt        ( proof_cnt     )
    );
    always_comb begin
        proof_cnt_soft_rst = 1'b0;
        proof_cnt_en = 1'b0;
        unique case(state)
            S_IDLE: begin
                proof_cnt_soft_rst = 1'b1;
            end
            S_PARENT_CH: begin
                proof_cnt_en = proof_addr_valid;
            end
            S_COMPRESS_REGEN: begin
                if ( addr_valid && addr_ready ) begin
                    if ( child_cnt >= W_CCNT'(2-1) ) begin // right child
                        proof_cnt_en = !flag_bit_regen_q[0];
                    end else begin
                        proof_cnt_en = !flag_bit_regen_q[1]; // left child
                    end
                end
            end
            default: begin
                proof_cnt_soft_rst = 1'b0;
                proof_cnt_en = 1'b0;
            end
        endcase
    end

endmodule
