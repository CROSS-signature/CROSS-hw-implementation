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

module add_sub
    import common_pkg::*;
    import arithmetic_unit_pkg::add_sub_select_t;
#(
    parameter  int unsigned MODULO            = 127,
    localparam int unsigned N                 = $clog2(MODULO),
    localparam bit          IS_MERSENNE_PRIME = is_mersenne_prime(MODULO)
) (
    input  logic                    clk_i,
    input  logic                    rst_n,
    input  logic            [N-1:0] op1_i,
    input  logic            [N-1:0] op2_i,
    input  add_sub_select_t         op_i,
    output logic            [N-1:0] res_o,
    input  logic                    req_i,
    output logic                    valid_o
);

    logic [N:0] temp;

    generate
        if (IS_MERSENNE_PRIME) begin : gen_mersenne
            logic [N-1:0] op2_i_compl;
            always_comb begin
                op2_i_compl = ~op2_i;
                temp = (op_i == arithmetic_unit_pkg::ARITH_OP_ADD) ? op1_i + op2_i : op1_i + op2_i_compl;
            end
        end else begin : gen_non_mersenne
            always_comb begin
                if (op_i == arithmetic_unit_pkg::ARITH_OP_ADD) begin
                    temp = op1_i + op2_i;
                end else begin
                    temp = op1_i - op2_i;
                    if (temp[N]) begin
                        // If subtraction resulted in a negative value
                        temp = temp + (N + 1)'(MODULO);
                    end
                end
            end
        end
    endgenerate

    always_comb begin
        if (temp >= (N + 1)'(MODULO)) begin
            res_o = N'(temp - (N + 1)'(MODULO));
        end else begin
            res_o = temp[N-1:0];
        end
        valid_o = req_i;
    end

endmodule
