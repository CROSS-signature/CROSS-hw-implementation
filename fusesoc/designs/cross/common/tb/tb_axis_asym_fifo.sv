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

module tb_axis_asym_fifo #(
    parameter int WIDTH        = 32,
    parameter int IN_BLOCK_SZ  = 4,
    parameter int OUT_BLOCK_SZ = 3
) (
    input  logic                          clk_i,
    input  logic                          rst_n,
    //
    output logic                          empty_o,
    output logic                          full_o,
    //
    input  logic [ WIDTH*IN_BLOCK_SZ-1:0] s_axis_tdata,
    input  logic [       IN_BLOCK_SZ-1:0] s_axis_tkeep,
    input  logic                          s_axis_tvalid,
    input  logic                          s_axis_tlast,
    output logic                          s_axis_tready,
    //
    output logic [WIDTH*OUT_BLOCK_SZ-1:0] m_axis_tdata,
    output logic [      OUT_BLOCK_SZ-1:0] m_axis_tkeep,
    output logic                          m_axis_tvalid,
    output logic                          m_axis_tlast,
    input  logic                          m_axis_tready
);

    AXIS #(
        .DATA_WIDTH(WIDTH * IN_BLOCK_SZ),
        .ELEM_WIDTH(WIDTH)
    ) s_axis ();
    AXIS #(
        .DATA_WIDTH(WIDTH * OUT_BLOCK_SZ),
        .ELEM_WIDTH(WIDTH)
    ) m_axis ();

    `AXIS_EXPORT_SLAVE(s_axis)
    `AXIS_EXPORT_MASTER(m_axis)

    axis_asym_fifo #(
        .WIDTH(WIDTH),
        .IN_BLOCK_SZ(IN_BLOCK_SZ),
        .OUT_BLOCK_SZ(OUT_BLOCK_SZ)
    ) axis_asym_fifo_i (
        .clk_i  (clk_i),
        .rst_n  (rst_n),
        .clear_i(1'b0),
        .empty_o(empty_o),
        .full_o (full_o),
        .m_axis (m_axis),
        .s_axis (s_axis)
    );


endmodule
