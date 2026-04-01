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

`include "stream_r.sv"
`include "stream_w.sv"

module tb_sha3
    import common_pkg::*;
    import sha3_pkg::*;
#(
    parameter  int unsigned STREAM_WIDTH    = 64,
    parameter  sha3_alg_t   SHA3_ALG        = `ifdef SHA3_ALG `SHA3_ALG `else SHA3_256 `endif,
    parameter  int unsigned UNROLL_FACTOR   = 1,
    parameter  int unsigned SEED1_SZ        = 320,
    parameter  int unsigned SEED2_SZ        = 320,
    localparam int          STREAM_BYTES_SZ = $clog2(STREAM_WIDTH / 8)
) (
    input  logic                       clk_i,
    input  logic                       rst_n,
    // synchronous reset from logic
    input  logic                       clear_i,
    //
    input  logic [                0:0] sha3_r_request_i,
    output logic [                0:0] sha3_r_grant_o,
    output logic [   STREAM_WIDTH-1:0] sha3_r_data_o,
    output logic [STREAM_BYTES_SZ-1:0] sha3_r_bytes_o,
    output logic [                0:0] sha3_r_is_last_o,
    output logic [                0:0] sha3_r_valid_o,
    //
    input  logic [   STREAM_WIDTH-1:0] sha3_w_data_i,
    input  logic [                0:0] sha3_w_is_last_i,
    input  logic [STREAM_BYTES_SZ-1:0] sha3_w_bytes_i,
    input  logic [                0:0] sha3_w_request_i,
    output logic [                0:0] sha3_w_grant_o
);

    stream_r #(.WORD_SZ(STREAM_WIDTH)) sha3_r_stream ();

    stream_w #(.WORD_SZ(STREAM_WIDTH)) sha3_w_stream ();

    assign sha3_r_stream.request = sha3_r_request_i;
    assign sha3_r_grant_o        = sha3_r_stream.grant;
    assign sha3_r_bytes_o        = sha3_r_stream.bytes;
    assign sha3_r_is_last_o      = sha3_r_stream.is_last;
    assign sha3_r_valid_o        = sha3_r_stream.valid;
    assign sha3_r_data_o         = sha3_r_stream.data;

    assign sha3_w_stream.is_last = sha3_w_is_last_i;
    assign sha3_w_stream.bytes   = sha3_w_bytes_i;
    assign sha3_w_stream.request = sha3_w_request_i;
    assign sha3_w_grant_o        = sha3_w_stream.grant;
    assign sha3_w_stream.data    = sha3_w_data_i;

    ////////  DUT INSTANTIATION  ////////

    sha3 #(
        .SHA3_ALG(SHA3_ALG),
        .STREAM_WIDTH(STREAM_WIDTH),
        .UNROLL_FACTOR(UNROLL_FACTOR),
        .SEED1_SZ(SEED1_SZ),
        .SEED2_SZ(SEED2_SZ)
    ) sha3_i (
        .*
    );

endmodule
