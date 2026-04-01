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

module axis_circular_buffer #(
    parameter  int ELEM_WIDTH = 8,
    parameter  int DEPTH      = 8,
    localparam int DEPTH_SZ   = $clog2(DEPTH)
) (
    input  logic                      clk,
    input  logic                      rst_n,
    output logic       [DEPTH_SZ-1:0] usage_o,
           AXIS.slave                 s_axis,
           AXIS.master                m_axis
);

    localparam int unsigned DW = s_axis.DATA_WIDTH;
    localparam int unsigned KW = DW / ELEM_WIDTH;
    localparam int unsigned UW = s_axis.TUSER_WIDTH;

    logic [DW+KW+UW-1:0] s_axis_tdata_int, m_axis_tdata_int;  //add tkeep, tlast, tuser

    generate
        if (KW == 1) begin : gen_s_no_tkeep
            assign s_axis_tdata_int = {s_axis.tuser, s_axis.tlast, s_axis.tdata};
        end else begin : gen_s_tkeep
            assign s_axis_tdata_int = {
                s_axis.tuser, s_axis.tkeep[1+:KW-1], s_axis.tlast, s_axis.tdata
            };
        end
    endgenerate

    logic fifo_empty, fifo_full;

    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .DEPTH       (DEPTH),
        .dtype       (logic [DW+KW+UW-1:0])
    ) i_fifo (
        .clk_i     (clk),
        .rst_ni    (rst_n),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (fifo_full),
        .empty_o   (fifo_empty),
        .usage_o   (usage_o),
        .data_i    (s_axis_tdata_int),
        .push_i    (s_axis.tvalid & ~fifo_full),
        .data_o    (m_axis_tdata_int),
        .pop_i     (m_axis.tready & ~fifo_empty)
    );

    assign s_axis.tready = ~fifo_full;

    assign m_axis.tdata  = m_axis_tdata_int[0+:DW];
    generate
        if (KW == 1) begin : gen_m_no_tkeep
            assign m_axis.tkeep = {1'b1};
        end else begin : gen_m_tkeep
            assign m_axis.tkeep = {m_axis_tdata_int[DW+1+:KW-1], 1'b1};
        end
    endgenerate
    assign m_axis.tvalid = ~fifo_empty;
    assign m_axis.tlast  = m_axis_tdata_int[DW];
    assign m_axis.tuser  = m_axis_tdata_int[DW+KW+:UW];

endmodule
