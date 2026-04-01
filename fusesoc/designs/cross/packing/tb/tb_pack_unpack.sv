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

module tb_pack_unpack
#(
    parameter DATA_WIDTH = 64,
    localparam KEEP = DATA_WIDTH/8,
    localparam TUSER_WIDTH = 3
)
(
    input logic clk,
    input logic rst_n,
    input logic pack_en,

    output logic fz_error,
    input logic fz_error_clear,

    input logic [DATA_WIDTH-1:0]    s_axis_tdata,
    input logic [KEEP-1:0]          s_axis_tkeep,
    input logic                     s_axis_tvalid,
    output logic                    s_axis_tready,
    input logic [TUSER_WIDTH-1:0]   s_axis_tuser,
    input logic                     s_axis_tlast,

    output logic [DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [KEEP-1:0]         m_axis_tkeep,
    output logic                    m_axis_tvalid,
    input logic                     m_axis_tready,
    output logic [TUSER_WIDTH-1:0]  m_axis_tuser,
    output logic                    m_axis_tlast
);

    AXIS #(.DATA_WIDTH(DATA_WIDTH),
        .TUSER_WIDTH(TUSER_WIDTH)) s_axis_pack_dut(), m_axis_pack_dut(), s_axis_unpack_dut(), m_axis_unpack_dut();

    cross_pack
    u_dut_pack
    (
        .clk,
        .rst_n,
        .s_axis (s_axis_pack_dut),
        .m_axis (m_axis_pack_dut)
    );


    cross_unpack
    u_dut_unpack
    (
        .clk,
        .rst_n,
        .fz_error,
        .fz_error_clear,
        .s_axis (s_axis_unpack_dut),
        .m_axis (m_axis_unpack_dut)
    );

    always_comb begin
        s_axis_tready = 1'b0;
        m_axis_pack_dut.tready = 1'b0;
        m_axis_unpack_dut.tready = 1'b0;

        s_axis_pack_dut.tdata = '0;
        s_axis_pack_dut.tkeep = '0;
        s_axis_pack_dut.tvalid = 1'b0;
        s_axis_pack_dut.tlast = 1'b0;
        s_axis_pack_dut.tuser = '0;

        s_axis_unpack_dut.tdata = '0;
        s_axis_unpack_dut.tkeep = '0;
        s_axis_unpack_dut.tvalid = 1'b0;
        s_axis_unpack_dut.tuser = '0;
        s_axis_unpack_dut.tlast = 1'b0;

        m_axis_tdata = '0;
        m_axis_tkeep = '0;
        m_axis_tvalid = 1'b0;
        m_axis_tuser = '0;
        m_axis_tlast = 1'b0;

        unique if (pack_en) begin
            s_axis_pack_dut.tdata = s_axis_tdata;
            s_axis_pack_dut.tkeep = s_axis_tkeep;
            s_axis_pack_dut.tvalid = s_axis_tvalid;
            s_axis_pack_dut.tuser = s_axis_tuser;
            s_axis_tready = s_axis_pack_dut.tready;
            s_axis_pack_dut.tlast = s_axis_tlast;

            m_axis_tdata = m_axis_pack_dut.tdata;
            m_axis_tkeep = m_axis_pack_dut.tkeep;
            m_axis_tvalid = m_axis_pack_dut.tvalid;
            m_axis_pack_dut.tready = m_axis_tready;
            m_axis_tuser = m_axis_pack_dut.tuser;
            m_axis_tlast = m_axis_pack_dut.tlast;
        end else begin
            s_axis_unpack_dut.tdata = s_axis_tdata;
            s_axis_unpack_dut.tkeep = s_axis_tkeep;
            s_axis_unpack_dut.tvalid = s_axis_tvalid;
            s_axis_unpack_dut.tuser = s_axis_tuser;
            s_axis_tready = s_axis_unpack_dut.tready;
            s_axis_unpack_dut.tlast = s_axis_tlast;

            m_axis_tdata = m_axis_unpack_dut.tdata;
            m_axis_tkeep = m_axis_unpack_dut.tkeep;
            m_axis_tvalid = m_axis_unpack_dut.tvalid;
            m_axis_unpack_dut.tready = m_axis_tready;
            m_axis_tuser = m_axis_unpack_dut.tuser;
            m_axis_tlast = m_axis_unpack_dut.tlast;
        end
    end

endmodule
