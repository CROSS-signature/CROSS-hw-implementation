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

module tb_add_sub_vector
    import arithmetic_unit_pkg::add_sub_select_t;
#(
    parameter  int DATA_WIDTH  = 64,
    parameter  int MODULO      = cross_pkg::P,
    localparam int ELEM_WIDTH  = $clog2(MODULO),
    localparam int TDATA_WIDTH = `MAX_DIV(DATA_WIDTH, ELEM_WIDTH),
    localparam int TKEEP_WIDTH = `NON_NEG_MSB(DATA_WIDTH / ELEM_WIDTH)
) (
    input  logic                              clk_i,
    input  logic                              rst_n,
    output logic                              done_o,
    input  add_sub_select_t                   op_i,
    //
    input  logic            [TDATA_WIDTH-1:0] op1_tdata,
    input  logic            [TKEEP_WIDTH-1:0] op1_tkeep,
    input  logic                              op1_tvalid,
    input  logic                              op1_tlast,
    output logic                              op1_tready,
    //
    input  logic            [TDATA_WIDTH-1:0] op2_tdata,
    input  logic            [TKEEP_WIDTH-1:0] op2_tkeep,
    input  logic                              op2_tvalid,
    input  logic                              op2_tlast,
    output logic                              op2_tready,
    //
    output logic            [TDATA_WIDTH-1:0] res_tdata,
    output logic            [TKEEP_WIDTH-1:0] res_tkeep,
    output logic                              res_tvalid,
    output logic                              res_tlast,
    input  logic                              res_tready
);

    localparam int P = cross_pkg::P;  // used by testbench
    localparam int N = cross_pkg::N;  // used by testbench

    AXIS #(
        .DATA_WIDTH(TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) op1 ();
    AXIS #(
        .DATA_WIDTH(TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) op2 ();
    AXIS #(
        .DATA_WIDTH(TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) res ();

    `AXIS_EXPORT_SLAVE(op1)
    `AXIS_EXPORT_SLAVE(op2)
    `AXIS_EXPORT_MASTER(res)

    add_sub_vector #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .MODULO(MODULO)
    ) add_sub_vector_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .op_i(op_i),
        .done_o(done_o),
        .op1(op1),
        .op2(op2),
        .res(res)
    );

endmodule
