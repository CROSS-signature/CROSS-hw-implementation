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

module mul
    import common_pkg::is_mersenne_prime;
#(
    parameter  int MODULO            = 127,
    localparam int N                 = $clog2(MODULO),
    localparam bit IS_MERSENNE_PRIME = is_mersenne_prime(MODULO),
    localparam int MAX_MUL           = (MODULO - 1) ** 2
) (
    input  logic         clk_i,
    input  logic         rst_n,
    input  logic [N-1:0] op1_i,
    input  logic [N-1:0] op2_i,
    input  logic         req_i,
    output logic         ready_o,
    input  logic         last_i,
    output logic [N-1:0] res_o,
    output logic         valid_o,
    input  logic         ready_i,
    output logic         last_o
);

    logic [2*N-1:0] mul_d, mul_q;
    logic valid;
    logic mod_ready;
    logic last;

    always_comb begin
        mul_d = op1_i * op2_i;
    end

    spill_register #(
        .T(logic [2*N:0])
    ) u_reg (
        .clk_i,
        .rst_ni (rst_n),
        .ready_i(mod_ready),
        .ready_o(ready_o),
        .data_i ({last_i, mul_d}),
        .data_o ({last, mul_q}),
        .valid_i(req_i),
        .valid_o(valid)
    );

    generate
        if (IS_MERSENNE_PRIME) begin : gen_mersenne_modulo
            mersenne_modulo #(
                .MODULO(MODULO),
                .MAX_INPUT(MAX_MUL),
                .STAGES(MODULO < 64 ? 1 : 2)
            ) mers_prime_i (
                .clk_i  (clk_i),
                .rst_n  (rst_n),
                .data_i (mul_q),
                .req_i  (valid),
                .ready_o(mod_ready),
                .last_i (last),
                .data_o (res_o),
                .valid_o(valid_o),
                .ready_i(ready_i),
                .last_o (last_o)
            );
        end else begin : gen_crandall_modulo
            crandall_modulo #(
                .MODULO(MODULO),
                .MAX_INPUT(MODULO ** 2),
                .STAGES(1)
            ) crandall_i (
                .clk_i  (clk_i),
                .rst_n  (rst_n),
                .data_i (mul_q),
                .req_i  (valid),
                .ready_o(mod_ready),
                .last_i (last),
                .data_o (res_o),
                .valid_o(valid_o),
                .ready_i(ready_i),
                .last_o (last_o)
            );
        end
    endgenerate

endmodule
