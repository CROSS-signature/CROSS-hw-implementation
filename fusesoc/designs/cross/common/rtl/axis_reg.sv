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

module axis_reg #(
    parameter ELEM_WIDTH = 8,
    parameter SPILL_REG = 0
) (
    input logic clk,
    input logic rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);

    localparam int unsigned DW = s_axis.DATA_WIDTH;
    localparam int unsigned KW = DW / ELEM_WIDTH;
    localparam int unsigned UW = s_axis.TUSER_WIDTH;

    logic [DW+KW+UW-1:0] s_axis_tdata_int, m_axis_tdata_int;  //add tkeep, tlast, tuser
    logic m_axis_tvalid_int, m_axis_tready_int;

    generate
        if (KW == 1) begin : gen_s_no_tkeep
            assign s_axis_tdata_int = {s_axis.tuser, s_axis.tlast, s_axis.tdata};
        end else begin : gen_s_tkeep
            assign s_axis_tdata_int = {s_axis.tuser, s_axis.tkeep[1+:KW-1], s_axis.tlast, s_axis.tdata};
        end
    endgenerate

    if (SPILL_REG>0) begin
        spill_register #(
            .T(logic [DW+KW+UW-1:0]),
            .Bypass(1'b0)
        ) u_spill_reg (
            .clk_i     (clk),
            .rst_ni    (rst_n),
            .valid_i   (s_axis.tvalid),
            .ready_o   (s_axis.tready),
            .data_i    (s_axis_tdata_int),
            .valid_o   (m_axis_tvalid_int),
            .ready_i   (m_axis_tready_int),
            .data_o    (m_axis_tdata_int)
        );
    end else begin
        fall_through_register #(
            .T(logic [DW+KW+UW-1:0])
        ) u_ft_reg (
            .clk_i     (clk),
            .rst_ni    (rst_n),
            .clr_i     (1'b0),
            .testmode_i(1'b0),
            .valid_i   (s_axis.tvalid),
            .ready_o   (s_axis.tready),
            .data_i    (s_axis_tdata_int),
            .valid_o   (m_axis_tvalid_int),
            .ready_i   (m_axis_tready_int),
            .data_o    (m_axis_tdata_int)
        );
    end


    assign m_axis.tdata = m_axis_tdata_int[0+:DW];
    generate
        if (KW == 1) begin : gen_m_no_tkeep
            assign m_axis.tkeep = {1'b1};
        end else begin : gen_m_tkeep
            assign m_axis.tkeep = {m_axis_tdata_int[DW+1+:KW-1], 1'b1};
        end
    endgenerate
    assign m_axis.tvalid = m_axis_tvalid_int;
    assign m_axis.tlast = m_axis_tdata_int[DW];
    assign m_axis.tuser = m_axis_tdata_int[DW+KW+:UW];

    assign m_axis_tready_int = m_axis.tready;

endmodule
