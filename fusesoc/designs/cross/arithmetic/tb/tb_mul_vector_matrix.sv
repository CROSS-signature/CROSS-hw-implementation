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

module tb_mul_vector_matrix #(
    parameter  int VEC_DATA_WIDTH  = 64,
    parameter  int MAT_DATA_WIDTH  = 64,
    parameter  int RES_DATA_WIDTH  = 64,
    parameter  int FZ              = 0,
    localparam int MODULO          = (FZ == 0) ? cross_pkg::P : cross_pkg::Z,
    localparam int ELEM_WIDTH      = $clog2(MODULO),
    localparam int VEC_TDATA_WIDTH = `MAX_DIV(VEC_DATA_WIDTH, ELEM_WIDTH),
    localparam int VEC_TKEEP_WIDTH = `NON_NEG_MSB(VEC_DATA_WIDTH / ELEM_WIDTH),
    localparam int MAT_TDATA_WIDTH = `MAX_DIV(MAT_DATA_WIDTH, ELEM_WIDTH),
    localparam int MAT_TKEEP_WIDTH = `NON_NEG_MSB(MAT_DATA_WIDTH / ELEM_WIDTH),
    localparam int RES_TDATA_WIDTH = `MAX_DIV(RES_DATA_WIDTH, ELEM_WIDTH),
    localparam int RES_TKEEP_WIDTH = `NON_NEG_MSB(RES_DATA_WIDTH / ELEM_WIDTH)
) (
    input  logic                       clk_i,
    input  logic                       rst_n,
    input  logic                       start_i,
    output logic                       done_o,
    //
    input  logic [VEC_TDATA_WIDTH-1:0] vector_tdata,
    input  logic [VEC_TKEEP_WIDTH-1:0] vector_tkeep,
    input  logic                       vector_tvalid,
    input  logic                       vector_tlast,
    output logic                       vector_tready,
    //
    input  logic [MAT_TDATA_WIDTH-1:0] matrix_tdata,
    input  logic [MAT_TKEEP_WIDTH-1:0] matrix_tkeep,
    input  logic                       matrix_tvalid,
    input  logic                       matrix_tlast,
    output logic                       matrix_tready,
    //
    output logic [RES_TDATA_WIDTH-1:0] result_tdata,
    output logic [RES_TKEEP_WIDTH-1:0] result_tkeep,
    output logic                       result_tvalid,
    output logic                       result_tlast,
    input  logic                       result_tready
);

    // used in simulation to get the parameters
    // waiting for cocotb/cocotb#3536 to land in v2.0
    localparam int P = cross_pkg::P;
    localparam int Z = cross_pkg::Z;
    localparam int N = cross_pkg::N;
    localparam int K = cross_pkg::K;
`ifdef RSDPG
    localparam int M = cross_pkg::M;
`endif

    AXIS #(
        .DATA_WIDTH(VEC_TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) vector ();
    AXIS #(
        .DATA_WIDTH(MAT_TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) matrix ();
    AXIS #(
        .DATA_WIDTH(RES_TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) result ();

    `AXIS_EXPORT_SLAVE(vector)
    `AXIS_EXPORT_SLAVE(matrix)
    `AXIS_EXPORT_MASTER(result)

    generate
        if (FZ != 0) begin : gen_m_vmmul
`ifdef RSDPG
            mul_vector_matrix_m #(
                .MAT_TDATA_WIDTH(MAT_TDATA_WIDTH)
            ) mul_vector_matrix_i (
                .clk_i  (clk_i),
                .rst_n  (rst_n),
                .start_i(start_i),
                .done_o (done_o),
                .vector (vector),
                .matrix (matrix),
                .result (result)
            );
`endif
        end else begin : gen_h_tr_vmmul
            mul_vector_matrix_h_tr #(
                .MAT_TDATA_WIDTH(MAT_TDATA_WIDTH)
            ) mul_vector_matrix_i (
                .clk_i  (clk_i),
                .rst_n  (rst_n),
                .start_i(start_i),
                .done_o (done_o),
                .vector (vector),
                .matrix (matrix),
                .result (result)
            );
        end
    endgenerate

endmodule
