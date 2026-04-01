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

module tb_exp_vector #(
    parameter  int IN_DATA_WIDTH   = 64,
    parameter  int OUT_DATA_WIDTH  = 64,
    localparam int IN_ELEM_WIDTH   = cross_pkg::BITS_Z,
    localparam int OUT_ELEM_WIDTH  = cross_pkg::BITS_P,
    localparam int IN_TDATA_WIDTH  = `MAX_DIV(IN_DATA_WIDTH, IN_ELEM_WIDTH),
    localparam int OUT_TDATA_WIDTH = `MAX_DIV(OUT_DATA_WIDTH, OUT_ELEM_WIDTH),
    localparam int IN_TKEEP_WIDTH  = `NON_NEG_MSB(IN_DATA_WIDTH / IN_ELEM_WIDTH),
    localparam int OUT_TKEEP_WIDTH = `NON_NEG_MSB(OUT_DATA_WIDTH / OUT_ELEM_WIDTH)
) (
    input  logic                       clk_i,
    input  logic                       rst_n,
    input  logic                       start_i,
    output logic                       done_o,
    //
    input  logic [ IN_TDATA_WIDTH-1:0] op_tdata,
    input  logic [ IN_TKEEP_WIDTH-1:0] op_tkeep,
    input  logic                       op_tvalid,
    input  logic                       op_tlast,
    output logic                       op_tready,
    //
    output logic [OUT_TDATA_WIDTH-1:0] res_tdata,
    output logic [OUT_TKEEP_WIDTH-1:0] res_tkeep,
    output logic                       res_tvalid,
    output logic                       res_tlast,
    input  logic                       res_tready
);

    localparam int GEN = cross_pkg::GEN;  // used by testbench
    localparam int P = cross_pkg::P;  // used by testbench
    localparam int Z = cross_pkg::Z;  // used by testbench
    localparam int N = cross_pkg::N;  // used by testbench

    AXIS #(
        .DATA_WIDTH(IN_TDATA_WIDTH),
        .ELEM_WIDTH(cross_pkg::BITS_Z)
    ) op ();
    AXIS #(
        .DATA_WIDTH(OUT_TDATA_WIDTH),
        .ELEM_WIDTH(cross_pkg::BITS_P)
    ) res ();

    `AXIS_EXPORT_SLAVE(op)
    `AXIS_EXPORT_MASTER(res)

    exp_vector #(
        .IN_TDATA_WIDTH (IN_TDATA_WIDTH),
        .OUT_TDATA_WIDTH(OUT_TDATA_WIDTH)
    ) exp_vector_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .start_i(start_i),
        .done_o(done_o),
        .op(op),
        .res(res)
    );

endmodule
