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

module parse_rsp0
    import packing_unit_pkg::*;
#(
    parameter int unsigned BYTES_Y,
    parameter int unsigned BYTES_DELTA_SIGMA
)
(
    input logic clk,
    input logic rst_n,

    output logic pad_error,
    input logic clear_err,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    localparam int unsigned W_BCNT = (BYTES_Y >= BYTES_DELTA_SIGMA) ? $clog2(BYTES_Y) : $clog2(BYTES_DELTA_SIGMA);
    logic [W_BCNT-1:0] byte_cnt, byte_cnt_max;

    // Padding check utilities
    localparam FZ_BITS_TAIL = (cross_pkg::DIM_FZ*cross_pkg::BITS_Z) % 8;
    localparam logic [7:0] PAD_MASK_FZ = (FZ_BITS_TAIL > 0) ? {{(8-FZ_BITS_TAIL){1'b1}}, {FZ_BITS_TAIL{1'b0}}} : '0;

    localparam FP_BITS_TAIL = (cross_pkg::N*cross_pkg::BITS_P) % 8;
    localparam logic [7:0] PAD_MASK_FP = (FP_BITS_TAIL > 0) ? {{(8-FP_BITS_TAIL){1'b1}}, {FP_BITS_TAIL{1'b0}}} : '0;

    logic pad_error_d, pad_error_q;

    // FSM variables
    typedef enum logic [0:0] {S_Y, S_DELTA_SIGMA} fsm_t;
    fsm_t n_state, state;

    assign pad_error = pad_error_q;

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            pad_error_q <= 1'b0;
        end else begin
            if ( !pad_error_q ) begin
                if ( `AXIS_LAST(m_axis) ) begin
                    pad_error_q <= pad_error_d;
                end
            end else begin
                if ( clear_err ) begin
                    pad_error_q <= 1'b0;
                end
            end
        end
    end

    always_comb begin
        `AXIS_ASSIGN_PROC(m_axis, s_axis);
        m_axis.tuser[0] = s_axis.tuser[0];
        pad_error_d = 1'b0;
        unique case (state)
            S_Y: begin
                m_axis.tuser[2:1]   = M_UNPACK_FP;
                if (byte_cnt >= W_BCNT'(BYTES_Y - 1)) begin
                    m_axis.tlast    = 1'b1;
                    pad_error_d     = |(s_axis.tdata & PAD_MASK_FP);
                end
            end
            S_DELTA_SIGMA: begin
                m_axis.tlast        = (byte_cnt >= W_BCNT'(BYTES_DELTA_SIGMA - 1));
                m_axis.tuser[2:1]   = M_UNPACK_FZ;
                if (byte_cnt >= W_BCNT'(BYTES_DELTA_SIGMA - 1)) begin
                    m_axis.tlast    = 1'b1;
                    pad_error_d     = |(s_axis.tdata & PAD_MASK_FZ);
                end
            end
            default: begin
                m_axis.tlast        = (byte_cnt >= W_BCNT'(BYTES_Y - 1));
                m_axis.tuser[2:1]   = M_UNPACK_FP;
                pad_error_d         = |(s_axis.tdata & PAD_MASK_FP);
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_Y;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case (state)
            S_Y: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_DELTA_SIGMA;
                end
            end
            S_DELTA_SIGMA: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_Y;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    counter #( .CNT_WIDTH(W_BCNT) )
    u_byte_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( byte_cnt_max          ),
        .inc        ( W_BCNT'(1)            ),
        .trigger    ( `AXIS_TRANS(s_axis)   ),
        .cnt        ( byte_cnt              )
    );
    assign byte_cnt_max = (state == S_Y) ? W_BCNT'(BYTES_Y) : W_BCNT'(BYTES_DELTA_SIGMA);

endmodule
