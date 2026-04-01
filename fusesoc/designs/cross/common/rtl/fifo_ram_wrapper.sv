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

module fifo_ram_wrapper
#(
    parameter int unsigned DW = 64,
    parameter int unsigned DEPTH = 32,
    parameter int unsigned REG_OUT = 0
)
(
    input logic             clk,
    input logic             rst_n,

    input logic [DW-1:0]    s_axis_tdata,
    input logic [DW/8-1:0]  s_axis_tkeep,
    input logic             s_axis_tvalid,
    output logic            s_axis_tready,
    input logic             s_axis_tlast,

    output logic [DW-1:0]   m_axis_tdata,
    output logic [DW/8-1:0] m_axis_tkeep,
    output logic            m_axis_tvalid,
    input logic             m_axis_tready,
    output logic            m_axis_tlast
);

    AXIS #(.DATA_WIDTH(DW)) s_axis_int(), m_axis_int(), m_axis_int2();

    assign s_axis_int.tdata = s_axis_tdata;
    assign s_axis_int.tkeep = s_axis_tkeep;
    assign s_axis_int.tvalid = s_axis_tvalid;
    assign s_axis_tready = s_axis_int.tready;
    assign s_axis_int.tlast = s_axis_tlast;

    fifo_ram #( .DEPTH(DEPTH) )
    u_fifo
    (
        .clk,
        .rst_n,
        .s_axis(s_axis_int),
        .m_axis(m_axis_int2)
    );

    if (REG_OUT) begin
        axis_reg #(.SPILL_REG(1))
        u_out_reg
        (
            .clk,
            .rst_n,
            .s_axis(m_axis_int2),
            .m_axis(m_axis_int)
        );
    end else begin
        `AXIS_ASSIGN(m_axis_int, m_axis_int2);
    end

    assign m_axis_tdata = m_axis_int.tdata;
    assign m_axis_tkeep = m_axis_int.tkeep;
    assign m_axis_tvalid = m_axis_int.tvalid;
    assign m_axis_int.tready = m_axis_tready;
    assign m_axis_tlast = m_axis_int.tlast;

endmodule
