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

module rng_parser
(
    input logic clk,
    input logic rst_n,

    input logic is_keygen,
    input logic is_sign,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    if (s_axis.DATA_WIDTH != 64)
        $error("This module only works for a data width of 64, otherwise more sophisticated mechanism is required.");

    if (m_axis.DATA_WIDTH != 64)
        $error("This module only works for a data width of 64, otherwise more sophisticated mechanism is required.");

    localparam int unsigned WPH = cross_pkg::WORDS_PER_HASH;
    localparam int unsigned WPS = cross_pkg::WORDS_PER_SEED;

    typedef enum {S_IDLE, S_LAMBDA, S_2LAMBDA} fsm_t;
    fsm_t state, n_state;

    localparam int unsigned W_CNT0 = $clog2(WPH);
    logic [W_CNT0-1:0] cnt0, cnt0_max;

    logic s_axis_tlast_int;

    assign m_axis.tdata = s_axis.tdata;
    assign m_axis.tkeep = s_axis.tkeep;
    assign m_axis.tvalid = s_axis.tvalid;
    assign s_axis.tready = m_axis.tready;
    assign m_axis.tlast = s_axis.tlast | s_axis_tlast_int;
    assign m_axis.tuser = '0;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if ( s_axis.tvalid ) begin
                    unique if (is_keygen) begin
                        n_state = S_2LAMBDA;
                    end else if (is_sign) begin
                        n_state = S_LAMBDA;
                    end else begin
                        n_state = S_IDLE;
                    end
                end
            end
            S_LAMBDA: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_2LAMBDA;
                end
            end
            S_2LAMBDA: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    always_comb begin
        s_axis_tlast_int = 1'b0;
        cnt0_max = W_CNT0'(WPH);
        unique case(state)
            S_LAMBDA: begin
                s_axis_tlast_int    = (cnt0 >= W_CNT0'(WPS-1));
                cnt0_max            = W_CNT0'(WPS);
            end
            S_2LAMBDA: begin
                s_axis_tlast_int    = (cnt0 >= W_CNT0'(WPH-1));
                cnt0_max            = W_CNT0'(WPH);
            end
            default: begin
                s_axis_tlast_int    = 1'b0;
                cnt0_max            = W_CNT0'(WPH);
            end
        endcase
    end

    //-------------------------------------------------
    // Count words
    //-------------------------------------------------
    counter #( .CNT_WIDTH(W_CNT0) )
    u_cnt0
    (
        .clk,
        .rst_n,
        .max_val    ( cnt0_max              ),
        .inc        ( W_CNT0'(1)            ),
        .trigger    ( `AXIS_TRANS(m_axis)   ),
        .cnt        ( cnt0                  )
    );

endmodule
