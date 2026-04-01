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

module sig_parser
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    if (s_axis.DATA_WIDTH != 64)
        $error("This module only works for a data width of 64, otherwise more sophisticated mechanism is required.");

    if (m_axis.DATA_WIDTH != 64)
        $error("This module only works for a data width of 64, otherwise more sophisticated mechanism is required.");

    import common_pkg::max;
    localparam int unsigned WPH = cross_pkg::WORDS_PER_HASH;
    localparam int unsigned WPS = cross_pkg::WORDS_PER_SEED;
    localparam int unsigned WPR = ((((cross_pkg::N*cross_pkg::BITS_P+7)/8 + (cross_pkg::DIM_FZ*cross_pkg::BITS_Z+7)/8)*(cross_pkg::T-cross_pkg::W)+7)/ 8);

    typedef enum {S_SALT, S_D01, S_DB, S_STP, S_MTP, S_RSP1, S_RSP0} fsm_t;
    fsm_t state, n_state;

    localparam int unsigned W_CNT0 = max($clog2(cross_pkg::TREE_NODES_TO_STORE), $clog2(cross_pkg::T-cross_pkg::W));
    logic [W_CNT0-1:0] cnt0, cnt0_max;

    localparam int unsigned W_CNT1 = max($clog2(WPH), $clog2(WPR));
    logic [W_CNT1-1:0] cnt1, cnt1_max;

    logic s_axis_tlast_int;


    assign m_axis.tdata = s_axis.tdata;
    assign m_axis.tkeep = s_axis.tkeep;
    assign m_axis.tvalid = s_axis.tvalid;
    assign s_axis.tready = m_axis.tready;
    assign m_axis.tlast = s_axis.tlast | s_axis_tlast_int;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_SALT;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case(state)
            S_SALT: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_D01;
                end
            end
            S_D01: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_DB;
                end
            end
            S_DB: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_STP;
                end
            end
            S_STP: begin
                if ( `AXIS_LAST(m_axis) && cnt0 >= W_CNT0'(cross_pkg::TREE_NODES_TO_STORE-1) ) begin
                    n_state = S_MTP;
                end
            end
            S_MTP: begin
                if ( `AXIS_LAST(m_axis) && cnt0 >= W_CNT0'(cross_pkg::TREE_NODES_TO_STORE-1) ) begin
                    n_state = S_RSP1;
                end
            end
            S_RSP1: begin
                if ( `AXIS_LAST(m_axis) && cnt0 >= W_CNT0'(cross_pkg::T-cross_pkg::W-1) ) begin
                    n_state = S_RSP0;
                end
            end
            S_RSP0: begin
                if ( `AXIS_LAST(m_axis) && cnt1 >= W_CNT1'(WPR-1) ) begin
                    n_state = S_SALT;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    always_comb begin
        s_axis_tlast_int = 1'b0;
        m_axis.tuser = 3'h0;
        cnt0_max = W_CNT0'(1);
        cnt1_max = W_CNT1'(WPH);
        unique case(state)
            S_SALT: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPH-1));
                cnt0_max            = W_CNT0'(1);
                cnt1_max            = W_CNT1'(WPH);
            end
            S_D01: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPH-1));
                cnt0_max            = W_CNT0'(1);
                cnt1_max            = W_CNT1'(WPH);
            end
            S_DB: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPH-1));
                cnt0_max            = W_CNT0'(1);
                cnt1_max            = W_CNT1'(WPH);
            end
            S_STP: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPS-1));
                cnt0_max            = W_CNT0'(cross_pkg::TREE_NODES_TO_STORE);
                cnt1_max            = W_CNT1'(WPS);
            end
            S_MTP: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPH-1));
                cnt0_max            = W_CNT0'(cross_pkg::TREE_NODES_TO_STORE);
                cnt1_max            = W_CNT1'(WPH);
            end
            S_RSP1: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPH-1));
                cnt0_max            = W_CNT0'(cross_pkg::T-cross_pkg::W);
                cnt1_max            = W_CNT1'(WPH);
            end
            S_RSP0: begin
                s_axis_tlast_int    = (cnt1 >= W_CNT1'(WPR-1));
                cnt0_max            = W_CNT0'(1);
                cnt1_max            = W_CNT1'(WPR);
                m_axis.tuser[0]     = (cnt1 >= W_CNT1'(WPR-1));
            end
            default: begin
                s_axis_tlast_int    = 1'b0;
                m_axis.tuser        = 3'h0;
                cnt0_max = W_CNT0'(1);
                cnt1_max = W_CNT1'(WPH);
            end
        endcase
    end

    //-------------------------------------------------
    // Count frames in segments
    //-------------------------------------------------
    counter #( .CNT_WIDTH(W_CNT0) )
    u_cnt0
    (
        .clk,
        .rst_n,
        .max_val    ( cnt0_max              ),
        .inc        ( W_CNT0'(1)            ),
        .trigger    ( `AXIS_LAST(m_axis)    ),
        .cnt        ( cnt0                  )
    );

    //-------------------------------------------------
    // Count words in segments
    //-------------------------------------------------
    counter #( .CNT_WIDTH(W_CNT1) )
    u_cnt1
    (
        .clk,
        .rst_n,
        .max_val    ( cnt1_max              ),
        .inc        ( W_CNT1'(1)            ),
        .trigger    ( `AXIS_TRANS(m_axis)   ),
        .cnt        ( cnt1                  )
    );

endmodule
