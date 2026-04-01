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

module stree_addr
    import stree_pkg::*;
#(
    parameter DATA_WIDTH = 64,
    localparam int unsigned WORDS_PER_SEED = cross_pkg::BYTES_SEED / (DATA_WIDTH/8),
    localparam int unsigned AW_INT = $clog2(2*cross_pkg::T-1),
    localparam int unsigned ADDR_WIDTH = $clog2((2*cross_pkg::T-1)*WORDS_PER_SEED),
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    output logic [$clog2(cross_pkg::TREE_NODES_TO_STORE)-1:0] sig_ctrl_path_cnt,
    output logic                    sig_ctrl_path_cnt_valid,

    output logic                    sig_ctrl_stree_done,
    input logic                     sig_ctrl_sign_done, // TODO: check if we really need this
    output logic                    sig_ctrl_stree_vrfy_done,
    output logic                    stree_leaves_done,
    output logic [AW_INT-1:0]       parent_idx,

    output logic                    regen_done,
    output logic                    regen_is_leaf,
    output logic                    regen_fetch_path,

    input stree_opcode_t            op,
    input logic                     op_valid,
    output logic                    op_ready,

    output logic [AW_INT-1:0]       flag_addr,
    output logic                    flag_bit_wr,
    output logic                    flag_we,
    input logic                     flag_bit_rd,
    output logic                    flag_last,

    output logic [AW_INT-1:0]       path_addr,
    output logic                    path_addr_valid,
    output logic                    path_last,

    output logic [ADDR_WIDTH-1:0]   addr,
    output logic                    addr_is_path,
    output logic                    addr_we,
    output logic                    addr_valid,
    input logic                     addr_ready,
    output logic                    addr_last_seed,
    output logic [W_FCNT-1:0]       addr_frame_cnt,

    AXIS.slave s_axis_ch
);

    typedef enum logic [3:0] {S_IDLE, S_STORE_MSEED, S_PARENT_ADDR, S_CHILD_ADDR,
                                S_PROVIDE_SEEDS, S_PLACE_CH, S_CHILD_CH, S_PARENT_CH,
                                S_PARENT_PATH, S_CHILD_PATH, S_WAIT_PATH, S_WAIT_SIGN_DONE,
                                S_CURRENT_REGEN, S_EXPAND_REGEN, S_LEAF_FLAG_REGEN, S_PROVIDE_SEEDS_REGEN} fsm_t;
    fsm_t state, n_state;

    logic [AW_INT-1:0] start_node_q, current_node_q, parent_node_q, child_node_q, addr_int;

    import cross_pkg::TREE_OFFSETS;
    import cross_pkg::TREE_NODES_PER_LEVEL;
    import cross_pkg::TREE_LEAVES_PER_LEVEL;
    import cross_pkg::TREE_LEAVES_START_INDICES;
    import cross_pkg::TREE_CONSECUTIVE_LEAVES;
    import cross_pkg::TREE_NODES_PER_LEVEL;
    import cross_pkg::TREE_SUBROOTS;
    import cross_pkg::TREE_NODES_TO_STORE;

    localparam int unsigned W_NPL_IDX = max($clog2($size(TREE_NODES_PER_LEVEL)), 1);
    localparam int unsigned W_LPL_IDX = max($clog2($size(TREE_LEAVES_PER_LEVEL)), 1);
    localparam int unsigned W_NCL_IDX = max($clog2($size(TREE_CONSECUTIVE_LEAVES)), 1);
    localparam int unsigned W_OFF_IDX = max($clog2($size(TREE_OFFSETS)), 1);

    import common_pkg::max;

    localparam int unsigned W_LCNT = $clog2(cross_pkg::BITS_T) + 1 + 1;
    logic [W_LCNT-1:0] level_cnt, level_cnt_dec, level_cnt_max;

    localparam int unsigned W_NCNT = cross_pkg::BITS_T;
    logic [W_NCNT-1:0] node_cnt, node_cnt_max;

    localparam int unsigned W_CCNT = $clog2(3);
    logic [W_CCNT-1:0] child_cnt, child_cnt_max;

    localparam int unsigned W_TNTS = $clog2(cross_pkg::TREE_NODES_TO_STORE);
    logic [W_TNTS-1:0] path_cnt;
    logic path_cnt_soft_rst;

    localparam int unsigned W_SCNT = max($clog2(TREE_SUBROOTS), 1);
    logic [W_SCNT-1:0] subroot_cnt;

    logic level_cnt_en, level_cnt_dec_en, node_cnt_en, child_cnt_en, path_cnt_en, subroot_cnt_en;

    logic last_parent_q, flag_bit_q, regen_is_leaf_d, regen_is_leaf_q;
    logic flag_bit_regen_q [2];
    logic addr_last;

    logic mode_path, mode_regen;


    assign sig_ctrl_path_cnt_valid  = (state == S_WAIT_SIGN_DONE);
    assign sig_ctrl_path_cnt        = path_cnt;
    assign sig_ctrl_stree_done      = (state == S_WAIT_PATH || state == S_WAIT_SIGN_DONE || state == S_CHILD_PATH || state == S_PARENT_PATH);
    assign sig_ctrl_stree_vrfy_done = (state == S_LEAF_FLAG_REGEN) || (state == S_PROVIDE_SEEDS_REGEN);

    always_comb begin
        unique case (state)
            S_PROVIDE_SEEDS: begin
                addr_last_seed = addr_last;
            end
            S_PROVIDE_SEEDS_REGEN: begin
                if ( flag_bit_rd ) begin
                    addr_last_seed = (child_cnt >= W_CCNT'(2-1)) && addr_valid && addr_ready && addr_last;
                end else begin
                    addr_last_seed = addr_last;
                end
            end
            default: begin
                addr_last_seed = 1'b0;
            end
        endcase
    end

    always_comb begin
        stree_leaves_done = 1'b0;
        unique case(state)
            S_PROVIDE_SEEDS,
            S_CHILD_PATH,
            S_PARENT_PATH,
            S_LEAF_FLAG_REGEN,
            S_PROVIDE_SEEDS_REGEN,
            S_WAIT_PATH,
            S_WAIT_SIGN_DONE: stree_leaves_done = 1'b1;

            S_PLACE_CH,
            S_CHILD_CH,
            S_PARENT_CH: stree_leaves_done = mode_path;

            default: begin
                stree_leaves_done = 1'b0;
            end
        endcase
    end

    // Use the parent idx as domain separator
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            parent_idx <= '0;
        end else begin
            if (state == S_PARENT_ADDR || state == S_CURRENT_REGEN) begin
                parent_idx <= AW_INT'( start_node_q + AW_INT'(node_cnt) );
            end
        end
    end

    always_ff @(posedge clk) begin
        if (state == S_IDLE) begin
            mode_path <= (op == M_GEN_TREE);
            mode_regen <= (op == M_REGEN_TREE);
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
                    unique if ( op == M_GEN_TREE ) begin
                        n_state = S_STORE_MSEED;
                    end else if ( op == M_REGEN_TREE ) begin
                        n_state = S_PLACE_CH;
                    end else begin
                        n_state = S_IDLE;
                    end
                end
            end

            S_STORE_MSEED: begin
                if ( addr_valid && addr_ready ) begin
                    n_state = S_PARENT_ADDR;
                end
            end

            S_PARENT_ADDR: begin
                if ( addr_valid && addr_ready ) begin
                    n_state = S_CHILD_ADDR;
                end
            end

            S_CHILD_ADDR: begin
                if ( addr_valid && addr_ready && child_cnt >= W_CCNT'(2 - 1) ) begin
                    if ( addr_last ) begin
                        n_state = S_PROVIDE_SEEDS;
                    end else begin
                        n_state = S_PARENT_ADDR;
                    end
                end
            end
            S_PROVIDE_SEEDS: begin
                if ( (addr_valid && addr_ready)
                    && child_cnt >= W_CCNT'(2 - 1)
                    && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                    && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                    n_state = S_PLACE_CH;
                end
            end
            S_PLACE_CH: begin
                if ( `AXIS_TRANS(s_axis_ch)
                    && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                    && node_cnt >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                    n_state = S_CHILD_CH;
                end
            end

            S_CHILD_CH: begin
                if (node_cnt[0]) begin
                    n_state = S_PARENT_CH;
                end
            end

            S_PARENT_CH: begin
                if ( flag_last ) begin
                    unique if ( mode_path ) begin
                        n_state = S_PARENT_PATH;
                    end else if ( mode_regen ) begin
                        n_state = S_CURRENT_REGEN;
                    end else begin
                        n_state = S_PARENT_CH;
                    end
                end else begin
                    n_state = S_CHILD_CH;
                end
            end

            S_PARENT_PATH: begin
                n_state = S_CHILD_PATH;
            end

            S_CHILD_PATH: begin
                if ( child_cnt >= child_cnt_max - W_CCNT'(1) ) begin
                    n_state = S_WAIT_PATH;
                end
            end

            S_WAIT_PATH: begin
                if ( path_last ) begin
                    n_state = S_WAIT_SIGN_DONE;
                end else begin
                    n_state = S_PARENT_PATH;
                end
            end

            S_WAIT_SIGN_DONE: begin
                if ( sig_ctrl_sign_done ) begin
                    n_state = S_IDLE;
                end
            end

            // If current node is root, simply skip the cycle, i.e. stay here
            S_CURRENT_REGEN: begin
                if ( child_cnt >= W_CCNT'(3 - 1) ) begin
                    // we dont expand node or it's a leaf that is already been expanded
                    if ( !(|current_node_q) || !flag_bit_regen_q[0] || (regen_is_leaf_d && flag_bit_rd) ) begin
                        // if it's the last node, continue to leaf provisioning, else stay here
                        if ( current_node_q >= AW_INT'(2*cross_pkg::T - 1 - 1) ) begin
                            n_state = S_LEAF_FLAG_REGEN;
                        end
                    end else begin
                        n_state = S_EXPAND_REGEN;
                    end
                end
            end

            S_EXPAND_REGEN: begin
                if ( addr_valid && addr_ready && child_cnt >= child_cnt_max - W_CCNT'(1) ) begin
                    if ( current_node_q >= AW_INT'(2*cross_pkg::T - 1 - 1) ) begin
                        n_state = S_LEAF_FLAG_REGEN;
                    end else begin
                        n_state = S_CURRENT_REGEN;
                    end
                end
            end

            S_LEAF_FLAG_REGEN: begin
                n_state = S_PROVIDE_SEEDS_REGEN;
            end

            S_PROVIDE_SEEDS_REGEN: begin
                if ( flag_bit_rd ) begin
                    if ( addr_valid && addr_ready && child_cnt >= W_CCNT'(2 - 1) ) begin
                        if ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1) && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]-1) ) begin
                            n_state = S_IDLE;
                        end else begin
                            n_state = S_LEAF_FLAG_REGEN;
                        end
                    end
                end else begin
                    if ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1) && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]-1) ) begin
                        n_state = S_IDLE;
                    end else begin
                        n_state = S_LEAF_FLAG_REGEN;
                    end
                end
            end

            default: n_state = S_IDLE;
        endcase
    end
    assign op_ready = ( state == S_IDLE );

    always_comb begin
        addr_int = AW_INT'( start_node_q + AW_INT'(node_cnt) );
        addr_valid = 1'b0;
        addr_we = 1'b0;
        addr_is_path = 1'b0;
        addr_frame_cnt = W_FCNT'(1);
        unique case(state)
            // addr_int is actually zero but to prevent additional logic
            // we keep it at this combination, since start_node_q and
            // node_cnt as well as the offset are zero anyway at this
            // point
            S_STORE_MSEED: begin
                addr_int = AW_INT'( start_node_q + AW_INT'(node_cnt) );
                addr_valid = 1'b1;
                addr_we = 1'b1;
            end
            S_PROVIDE_SEEDS: begin
                addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
                addr_valid = 1'b1;
            end
            S_PARENT_ADDR: begin
                addr_int = AW_INT'( start_node_q + AW_INT'(node_cnt) );
                addr_valid = 1'b1;
            end
            S_CHILD_ADDR: begin
                addr_int = child_node_q;
                addr_valid = 1'b1;
                addr_we = 1'b1;
                addr_frame_cnt =  W_FCNT'(2);
            end
            S_EXPAND_REGEN: begin
                addr_valid = 1'b1;
                if ( !regen_is_leaf_q ) begin
                    if ( flag_bit_regen_q[1] ) begin
                        if ( child_cnt >= W_CCNT'(2 - 1) ) begin // expanded nodes are copied to leaf position
                            addr_int = child_node_q;
                            addr_we = 1'b1;
                            addr_frame_cnt = W_FCNT'(2);
                        end else begin // absorb seed from seed tree
                            addr_int = current_node_q;
                        end
                    end else begin
                        if ( child_cnt >= W_CCNT'(2 - 1) ) begin // path node is copied to child position
                            addr_int = child_node_q;
                            addr_we = 1'b1;
                            addr_frame_cnt = W_FCNT'(2);
                        end else begin // path is absorbed
                            addr_int = AW_INT'(path_cnt); //TODO: check if we can remove, only for test
                            addr_is_path = 1'b1;
                        end
                    end
                end else begin
                    addr_int = current_node_q;
                    addr_we = 1'b1;
                end
            end
            S_PROVIDE_SEEDS_REGEN: begin
                addr_int = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
                addr_valid = flag_bit_rd;
            end

            default: begin
                addr_int = AW_INT'( start_node_q + AW_INT'(node_cnt) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                addr_valid = 1'b0;
                addr_we = 1'b0;
                addr_is_path = 1'b0;
                addr_frame_cnt = W_FCNT'(1);
            end
        endcase
    end
    assign addr = ADDR_WIDTH'( ADDR_WIDTH'(addr_int)*ADDR_WIDTH'(WORDS_PER_SEED) );
    assign regen_is_leaf = regen_is_leaf_q;
    assign regen_is_leaf_d = ( mode_regen && node_cnt >= W_NCNT'( TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]
                                        - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)]) );

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            regen_is_leaf_q <= 1'b0;
        end else begin
            if (state == S_CURRENT_REGEN) begin
                regen_is_leaf_q <= regen_is_leaf_d;
            end
        end
    end

    // This is used in regeneration to tell the signature controller to move
    // the path node to one of the leaf positions.
    assign regen_fetch_path = ( state == S_EXPAND_REGEN && regen_is_leaf_q && !flag_bit_regen_q[1] );

    always_comb begin
        flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
        flag_we = 1'b0;
        s_axis_ch.tready = 1'b0;
        unique case(state)
            S_PLACE_CH: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
                flag_we = s_axis_ch.tvalid;
                s_axis_ch.tready = 1'b1;
            end
            S_PARENT_CH: begin
                flag_addr = parent_node_q;
                flag_we = 1'b1;
            end
            S_CHILD_CH,
            S_PARENT_PATH: begin
                flag_addr = AW_INT'(start_node_q + AW_INT'(node_cnt));
            end
            S_CURRENT_REGEN: begin
                if ( child_cnt >= W_CCNT'(2 - 1) ) begin
                    flag_addr = parent_node_q;
                end else begin
                    flag_addr = AW_INT'(start_node_q + AW_INT'(node_cnt));
                end
            end
            S_CHILD_PATH: begin
                flag_addr = AW_INT'(child_node_q + AW_INT'(child_cnt));
            end
            S_LEAF_FLAG_REGEN,
            S_PROVIDE_SEEDS_REGEN: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
            end
            default: begin
                flag_addr = AW_INT'(TREE_LEAVES_START_INDICES[subroot_cnt]) + AW_INT'(node_cnt);
                flag_we = 1'b0;
                s_axis_ch.tready = 1'b0;
            end
        endcase
    end
    assign flag_last = ( (state == S_PARENT_CH) && !(|flag_addr) );

    // For the seed tree, we label the node if the challenge bit is one and
    // if both children are labelled.
    always_comb begin
        unique case(state)
            S_PLACE_CH: begin
                flag_bit_wr = s_axis_ch.tdata;
            end
            S_PARENT_CH: begin
                flag_bit_wr = flag_bit_q & flag_bit_rd;
            end
            default: flag_bit_wr = s_axis_ch.tdata;
        endcase
    end

    // Only register the flag input when we are at the right child node as
    // read data becomes valid after the rising edge (so we progressed one node)
    always_ff @(posedge clk)
    begin
        unique case(state)
            S_IDLE: begin
                flag_bit_q <= 1'b0;
                flag_bit_regen_q <= '{default:'0};
            end
            // Here we use it for the left child node
            S_CHILD_CH: begin
                if ( node_cnt[0] ) begin
                    flag_bit_q <= flag_bit_rd;
                end
            end
            // Here we use it for the current's parent node
            S_CHILD_PATH: begin
                if ( !child_cnt[0] ) begin
                    flag_bit_q <= flag_bit_rd;
                end
            end
            S_CURRENT_REGEN: begin
                if ( child_cnt >= W_CCNT'(3 - 1) ) begin // parent node
                    flag_bit_regen_q[1] <= flag_bit_rd;
                end else if ( child_cnt == W_CCNT'(2 - 1) ) begin // current node
                    flag_bit_regen_q[0] <= flag_bit_rd;
                end
            end
            default: begin
                flag_bit_q          <= flag_bit_q;
                flag_bit_regen_q    <= flag_bit_regen_q;
            end
        endcase
    end

    always_comb begin
        path_addr = child_node_q;
        path_addr_valid = 1'b0;

        // flag_bit_q corresponds to flag of parent node
        // Only include leaf to path if parent is not to send and leaf node is to send
        unique case(state)
            S_CHILD_PATH: begin
                if ( child_cnt[0] ) begin
                    path_addr = child_node_q;
                    path_addr_valid = flag_bit_rd & ~flag_bit_q & mode_path;
                end
            end
            S_WAIT_PATH: begin
                path_addr = child_node_q + AW_INT'(1);
                path_addr_valid = flag_bit_rd & ~flag_bit_q & mode_path;
            end
            default: begin
                path_addr = child_node_q;
                path_addr_valid = 1'b0;
            end
        endcase
    end
    assign path_last = (state == S_WAIT_PATH) && (last_parent_q == 1'b1);

    // While we are traversing through the tree from left to right on each level,
    // store the left child node every time we are done with the parent
    always_ff @(posedge clk)
    begin
        unique case(state)
            S_IDLE: begin
                child_node_q <= '0;
            end
            S_PARENT_ADDR: begin
                if ( addr_valid && addr_ready ) begin
                    child_node_q <= AW_INT'( (((start_node_q + AW_INT'(node_cnt)) << 1) + AW_INT'(1)) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                end
            end

            S_CURRENT_REGEN: begin
                if ( child_cnt == W_CCNT'(0) ) begin
                    child_node_q <= AW_INT'( (((start_node_q + AW_INT'(node_cnt)) << 1) + AW_INT'(1)) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                end
            end

            S_PARENT_PATH: begin
                child_node_q <= AW_INT'( (((start_node_q + AW_INT'(node_cnt)) << 1) + AW_INT'(1)) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]));
            end

            default: begin
                child_node_q <= child_node_q;
            end
        endcase
    end

    // While we are traversing through the tree from right to left on each level,
    // store the parent node every time we are at the right child
    always_ff @(posedge clk)
    begin
        unique case(state)
            S_CHILD_CH: begin
                if ( !node_cnt[0] ) begin
                    parent_node_q <= AW_INT'( ((start_node_q + AW_INT'(node_cnt) - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt_dec-W_LCNT'(1))] >> 1) );
                end
            end
            S_CURRENT_REGEN: begin
                if ( child_cnt == W_CCNT'(0) ) begin
                    parent_node_q <= AW_INT'( ((start_node_q + AW_INT'(node_cnt) - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt-W_LCNT'(1))] >> 1) );
                end
            end
            default: parent_node_q <= parent_node_q;
        endcase
    end

    // For regeneration of seed tree, latch the current node for later re-use
    always_ff @(posedge clk) begin
        unique case(state)
            S_CURRENT_REGEN: begin
                if ( child_cnt == W_CCNT'(0) ) begin
                    current_node_q <= AW_INT'( start_node_q + AW_INT'(node_cnt) );
                end
            end
            default: current_node_q <= current_node_q;
        endcase
    end

    // Store the current start index (root node) that is required to traverse
    // the tree in a breadth-first manner from left to right
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            start_node_q <= AW_INT'(0);
        end else begin
            unique case(state)
                S_IDLE: begin
                    start_node_q <= AW_INT'(0);
                end
                S_PARENT_ADDR: begin
                    if ( addr_valid && addr_ready
                        && ( node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]
                                        - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)] - 1 )) ) begin
                        start_node_q <= AW_INT'( (start_node_q << 1) + AW_INT'(1) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                    end
                end
                S_PLACE_CH: begin
                    if ( `AXIS_TRANS(s_axis_ch)
                        && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1)
                        && node_cnt >= cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) ) begin
                        start_node_q <= AW_INT'(TREE_LEAVES_START_INDICES[0]);
                    end
                end
                S_CHILD_CH: begin
                    if ( node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt_dec)]) - cross_pkg::BITS_T'(1) ) begin
                        start_node_q <= AW_INT'( ((start_node_q - AW_INT'(1)) >> 1) + AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt_dec-W_LCNT'(1))] >> 1) );
                    end
                end
                S_PARENT_PATH: begin
                    if ( ( node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]
                                        - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)] - 1 )) ) begin
                        start_node_q <= AW_INT'( (start_node_q << 1) + AW_INT'(1) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                    end
                end
                S_CURRENT_REGEN: begin
                    if ( child_cnt >= W_CCNT'(3 - 1)
                    && node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]) - cross_pkg::BITS_T'(1) ) begin
                        start_node_q <= AW_INT'( (start_node_q << 1) + AW_INT'(1) - AW_INT'(TREE_OFFSETS[W_OFF_IDX'(level_cnt)]) );
                    end
                end
                default: start_node_q <= start_node_q;
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        unique case(state)
            S_IDLE, S_PARENT_CH: begin
                last_parent_q <= 1'b0;
            end
            S_PARENT_ADDR,
            S_PARENT_PATH: begin
                if (level_cnt >= W_LCNT'(cross_pkg::BITS_T-1) &&
                    node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[cross_pkg::BITS_T-1] - TREE_LEAVES_PER_LEVEL[cross_pkg::BITS_T-1] - 1) ) begin
                    last_parent_q <= 1'b1;
                end
            end
            default: last_parent_q <= last_parent_q;
        endcase
    end

    // Indicate that we are done with the operation
    always_comb
    begin
        addr_last = 1'b0;
        unique case(state)
            S_CHILD_ADDR: begin
                addr_last = last_parent_q;
            end
            S_CURRENT_REGEN: begin
                addr_last = ( current_node_q >= AW_INT'(2*cross_pkg::T - 1 - 1)
							&& child_cnt >= W_CCNT'(3 - 1) && (!flag_bit_regen_q[0] || flag_bit_regen_q[1]) );
            end
            S_EXPAND_REGEN: begin
                addr_last = ( current_node_q >= AW_INT'(2*cross_pkg::T - 1 - 1)
							&& child_cnt >= child_cnt_max - W_CCNT'(1) );
            end
            S_PROVIDE_SEEDS: begin
                addr_last = ( child_cnt >= W_CCNT'(2 - 1) && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1) && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[TREE_SUBROOTS-1] - 1) );
            end
            S_PROVIDE_SEEDS_REGEN: begin
                if ( flag_bit_rd ) begin
                    addr_last = ( child_cnt >= W_CCNT'(2 - 1) && subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1) && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]-1) );
                end else begin
                    addr_last = ( subroot_cnt >= W_SCNT'(TREE_SUBROOTS - 1) && node_cnt >= W_NCNT'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]-1) );
                end
            end
            default: begin
                addr_last = 1'b0;
            end
        endcase
    end
    assign regen_done = addr_last;

    // Level counter from root to leaves
    counter #(
        .CNT_WIDTH( W_LCNT )
    ) u_level_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n         ),
        .max_val    ( level_cnt_max ),
        .inc        ( W_LCNT'(1)    ),
        .trigger    ( level_cnt_en  ),
        .cnt        ( level_cnt     )
    );
    always_comb begin
        unique case (state)
            S_PARENT_ADDR: begin
                level_cnt_en = (addr_valid && addr_ready)
                            && (node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]
                                            - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)] - 1) );
                level_cnt_max = W_LCNT'(cross_pkg::BITS_T);
            end
            S_PARENT_PATH: begin
                level_cnt_en = (node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]
                                            - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)] - 1) );
                level_cnt_max = W_LCNT'(cross_pkg::BITS_T);
            end
            S_CHILD_PATH, S_WAIT_PATH: begin
                level_cnt_en = 1'b0;
                level_cnt_max = W_LCNT'(cross_pkg::BITS_T);
            end
            S_CURRENT_REGEN: begin
                level_cnt_en = ( node_cnt >= cross_pkg::BITS_T'( TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]) - cross_pkg::BITS_T'(1)
                                && child_cnt >= W_CCNT'(3 - 1) );
                level_cnt_max = W_LCNT'(cross_pkg::BITS_T) + W_LCNT'(1);
            end
            default: begin
                level_cnt_en = 1'b0;
                level_cnt_max = W_LCNT'(cross_pkg::BITS_T);
            end
        endcase
    end

    /* level counter decrementing */
    counter_dec #(
        .CNT_WIDTH  ( W_LCNT    ),
        .MIN_VAL    ( 1         )
    ) u_level_cnt_dec (
        .clk        ( clk               ),
        .rst_n      ( rst_n             ),
        .max_val    ( W_LCNT'(cross_pkg::BITS_T)    ),
        .dec        ( W_LCNT'(1)        ),
        .trigger    ( level_cnt_dec_en  ),
        .cnt        ( level_cnt_dec     )
    );
    always_comb begin
        level_cnt_dec_en = 1'b0;
        unique case (state)
            S_CHILD_CH: level_cnt_dec_en = ( node_cnt >= cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt_dec)] - 1'b1) );
            default: level_cnt_dec_en = 1'b0;
        endcase
    end

    // Node counter from 0 to nodes per level - 1
    counter #(
        .CNT_WIDTH( cross_pkg::BITS_T )
    ) u_node_cnt (
        .clk        ( clk           ),
        .rst_n      ( rst_n         ),
        .max_val    ( node_cnt_max  ),
        .inc        ( cross_pkg::BITS_T'(1) ),
        .trigger    ( node_cnt_en   ),
        .cnt        ( node_cnt      )
    );

    always_comb begin
        node_cnt_en = 1'b0;
        node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]);
        unique case (state)
            S_PARENT_ADDR: begin
                node_cnt_en = (addr_valid && addr_ready);
                node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)] - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)]);
            end
            S_PROVIDE_SEEDS: begin
                node_cnt_en = (addr_valid && addr_ready) && (child_cnt >= W_CCNT'(2 - 1));
                node_cnt_max = W_NCNT'( TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]);
            end
            S_PLACE_CH: begin
                node_cnt_en = `AXIS_TRANS(s_axis_ch);
                node_cnt_max = W_NCNT'( TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]);
            end
            S_CHILD_CH: begin
                node_cnt_en = 1'b1;
                node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt_dec)]);
            end
            S_PARENT_PATH: begin
                node_cnt_en = 1'b1;
                node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)] - TREE_LEAVES_PER_LEVEL[W_LPL_IDX'(level_cnt)]);
            end
            S_CURRENT_REGEN: begin
                node_cnt_en = ( child_cnt >= W_CCNT'(3 - 1) );
                node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]);
            end
            S_PROVIDE_SEEDS_REGEN: begin
                node_cnt_en = flag_bit_rd ? (addr_valid && addr_ready && (child_cnt >= W_CCNT'(2 - 1))) : 1'b1;
                node_cnt_max = cross_pkg::BITS_T'(TREE_CONSECUTIVE_LEAVES[W_NCL_IDX'(subroot_cnt)]);
            end
            default: begin
                node_cnt_en = 1'b0;
                node_cnt_max = cross_pkg::BITS_T'(TREE_NODES_PER_LEVEL[W_NPL_IDX'(level_cnt)]);
            end
        endcase
    end

    // Count the children during labeling of the flag tree.
    // Could abuse the word counter here, but that is also required for
    // re-generation of the tree, so we use a separate one here instead
    // Abuse this counter also for seed provisioning, since it's the same
    // width.
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
    always_comb begin
        unique case(state)
            S_CHILD_PATH: begin
                child_cnt_max = W_CCNT'(2);
                child_cnt_en = 1'b1;
            end
            S_CHILD_ADDR: begin
                child_cnt_max = W_CCNT'(2);
                child_cnt_en = (addr_valid && addr_ready);
            end
            S_PROVIDE_SEEDS: begin
                child_cnt_max = W_CCNT'(2);
                child_cnt_en = (addr_valid && addr_ready);
            end
            S_CURRENT_REGEN: begin
                child_cnt_max = W_CCNT'(3);
                child_cnt_en = 1'b1;
            end
            S_EXPAND_REGEN: begin
				if (regen_is_leaf_q) begin
                    child_cnt_max = W_CCNT'(1);
                end else begin
                    child_cnt_max = W_CCNT'(3);
                end
                child_cnt_en = ( addr_valid && addr_ready );
            end
            S_PROVIDE_SEEDS_REGEN: begin
                child_cnt_max = W_CCNT'(2);
                child_cnt_en = ( addr_valid && addr_ready );
            end
            default: begin
                child_cnt_max = W_CCNT'(2);
                child_cnt_en = 1'b0;
            end
        endcase
    end

    // Keep track of the number of seed path nodes consumed
    counter #(
        .CNT_WIDTH( W_TNTS )
    ) u_path_cnt (
        .clk        ( clk               ),
        .rst_n      ( rst_n & ~path_cnt_soft_rst          ),
        .max_val    ( W_TNTS'(cross_pkg::TREE_NODES_TO_STORE)   ),
        .inc        ( W_TNTS'(1)        ),
        .trigger    ( path_cnt_en ),
        .cnt        ( path_cnt    )
    );
    always_comb begin
        path_cnt_soft_rst = 1'b0;
        path_cnt_en = 1'b0;
        unique case(state)
            S_IDLE: begin
                path_cnt_soft_rst = 1'b1;
            end
            S_CHILD_PATH,
            S_WAIT_PATH: begin
                path_cnt_en = path_addr_valid;
            end
            // Enable the path counter only for inner nodes that must be placed
            // or if the parent was not to revealed. Not for final seed nodes.
            S_EXPAND_REGEN: begin
                path_cnt_en = (addr_valid && addr_ready && !regen_is_leaf_q && !flag_bit_regen_q[1]
                            && child_cnt >= child_cnt_max - W_CCNT'(1));
            end
            default: begin
                path_cnt_soft_rst = 1'b0;
                path_cnt_en = 1'b0;
            end
        endcase
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
            S_PROVIDE_SEEDS: subroot_cnt_en = (addr_valid && addr_ready)
                                            && (child_cnt >= W_CCNT'(2 - 1))
                                            && (node_cnt >= node_cnt_max - cross_pkg::BITS_T'(1));
            S_PROVIDE_SEEDS_REGEN: subroot_cnt_en = ((addr_valid && addr_ready && child_cnt >= W_CCNT'(2 - 1)) || ~flag_bit_rd)
                                            && (node_cnt >= node_cnt_max - cross_pkg::BITS_T'(1));
            S_PLACE_CH: subroot_cnt_en = ( `AXIS_TRANS(s_axis_ch) )
                                            && (node_cnt >= node_cnt_max - cross_pkg::BITS_T'(1));
            default: subroot_cnt_en = '0;
        endcase
    end

endmodule
