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
`include "axis_intf.svh"

module axis_replicate
    import common_pkg::*;
#(
    parameter int ELEM_WIDTH = 8,
    parameter int COUNT = 1
) (
    input logic axis_aclk,
    input logic axis_rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);

    localparam int WIDTH_OUT = m_axis.DATA_WIDTH;
    localparam int ELEM_OUT = WIDTH_OUT / ELEM_WIDTH;
    localparam int TRANSACTIONS = iceilfrac(COUNT, ELEM_OUT);
    localparam int LAST_ELEMENTS = COUNT - (TRANSACTIONS - 1) * ELEM_OUT;
    localparam int CTR_SZ = $clog2(TRANSACTIONS);

    logic [ELEM_OUT-1:0] last_tkeep;
    generate
        if (ELEM_OUT == 1) begin : gen_single_elem_out_tkeep
            assign last_tkeep = 1'b1;
        end else begin : gen_multi_elem_out_tkeep
            assign last_tkeep = {{(ELEM_OUT - LAST_ELEMENTS) {1'b0}}, {LAST_ELEMENTS{1'b1}}};
        end
    endgenerate

    typedef enum logic {
        IDLE = 0,
        REPLICATE
    } fsm_state_t;

    fsm_state_t state_d, state_q;
    logic [ELEM_WIDTH-1:0] data_d, data_q;
    logic [CTR_SZ-1:0] ctr_d, ctr_q;

    // always_ff @(posedge axis_aclk, negedge axis_rst_n) begin
    always_ff @(posedge axis_aclk) begin
        if (!axis_rst_n) begin
            data_q  <= 'b0;
            ctr_q   <= 'b0;
            state_q <= IDLE;
        end else begin
            data_q  <= data_d;
            ctr_q   <= ctr_d;
            state_q <= state_d;
        end
    end

    always_comb begin
        s_axis.tready = 1'b0;
        //
        m_axis.tdata  = {ELEM_OUT{data_q}};
        m_axis.tkeep  = 'b0;
        m_axis.tvalid = 1'b0;
        m_axis.tlast  = 1'b0;
        //
        ctr_d         = ctr_q;
        data_d        = data_q;
        state_d       = state_q;

        unique case (state_q)
            IDLE: begin
                s_axis.tready = m_axis.tready;
                m_axis.tdata  = {ELEM_OUT{s_axis.tdata}};
                m_axis.tkeep  = (TRANSACTIONS == 1) ? last_tkeep : {ELEM_OUT{1'b1}};
                m_axis.tvalid = s_axis.tvalid;
                // we expect a transaction with a single element
                if (`AXIS_TRANS(s_axis) && (s_axis.tkeep == 1'b1) && (TRANSACTIONS > 1)) begin
                    ctr_d   = CTR_SZ'(TRANSACTIONS - 2);
                    data_d  = s_axis.tdata;
                    state_d = REPLICATE;
                end
            end

            REPLICATE: begin
                m_axis.tvalid = 1'b1;
                if (`AXIS_TRANS(m_axis)) begin
                    ctr_d = ctr_q - 1;
                    if (ctr_q == CTR_SZ'(0)) begin
                        m_axis.tlast = 1'b1;
                        m_axis.tkeep = last_tkeep;
                        // s_axis.tready = 1'b1;
                        // // we expect a transaction with a single element
                        // if (`AXIS_LAST(s_axis) && (s_axis.tkeep == 1'b1)) begin
                        //     ctr_d   = CTR_SZ'(TRANSACTIONS - 1);
                        //     data_d  = s_axis.tdata;
                        //     state_d = REPLICATE;
                        // end else begin
                        state_d = IDLE;
                        // end
                    end else begin
                        m_axis.tkeep = {ELEM_OUT{1'b1}};
                    end
                end
            end

            default: begin
                $error("Un-handled unique case");
            end
        endcase
    end

endmodule
