`timescale 1ps / 1ps

 /*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright 2026, Francesco Antognazza <francesco.antognazza@polimi.it>
 * Copyright 2013, Homer Hsing <homer.hsing@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by Francesco Antognazza to comply with SHA3 standard and improve performance.
 */

module f_permutation
    import common_pkg::*;
    import sha3_pkg::*;
#(
    parameter sha3_alg_t   SHA3_ALG      = SHA3_256,
    parameter int unsigned CAPACITY_SZ   = CAPACITIES            [SHA3_ALG],
    parameter int unsigned RATE_SZ       = STATE_SZ - CAPACITY_SZ,
    parameter int unsigned UNROLL_FACTOR = 1
) (
    input  logic               clk_i,
    input  logic               rst_n,
    input  logic               clear_i,
    input  logic [RATE_SZ-1:0] rate_i,
    input  logic               start_i,
    output logic               ack_o,
    output logic [RATE_SZ-1:0] rate_o,
    output logic               rate_ready_o
);

    `ASSERT_INIT(valid_parallel_rounds, ROUNDS % UNROLL_FACTOR == 0)

    logic [UNROLL_FACTOR-1:0][STATE_SZ-1:0] round_in;
    logic [UNROLL_FACTOR-1:0][STATE_SZ-1:0] round_out;
    logic [UNROLL_FACTOR-1:0][    Z_SZ-1:0] round_const;
    logic [UNROLL_FACTOR-1:0][  ROUNDS-1:0] round_idx;

    logic                                   update;

    logic [      RATE_SZ-1:0]               rate;
    logic [  CAPACITY_SZ-1:0]               capacity;

    logic accept_d, accept_q;
    logic calc_d, calc_q;
    logic [ROUNDS-1:0] round_idx_d, round_idx_q;
    logic [STATE_SZ-1:0] keccak_state_d, keccak_state_q;
    logic out_ready_d, out_ready_q;

    assign rate         = RATE_SZ'(keccak_state_q >> CAPACITY_SZ);
    assign capacity     = CAPACITY_SZ'(keccak_state_q);

    assign accept_d     = start_i && !calc_q;
    assign update       = calc_q | accept_d;
    assign ack_o        = accept_d;
    assign rate_ready_o = out_ready_q && !accept_q;
    assign rate_o       = rate;

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin
            keccak_state_q <= 'b0;
            out_ready_q    <= 1'b0;
            round_idx_q    <= 'b0;
            calc_q         <= 1'b0;
            accept_q       <= 1'b0;
        end else begin
            keccak_state_q <= keccak_state_d;
            out_ready_q    <= out_ready_d;
            round_idx_q    <= round_idx_d;
            calc_q         <= calc_d;
            accept_q       <= accept_d;
        end
    end

    always_comb begin
        out_ready_d = out_ready_q;

        if (accept_d || clear_i) begin  // synchronous reset
            out_ready_d = 1'b0;
        end else begin
            if (round_idx[UNROLL_FACTOR-1][ROUNDS-1]) begin
                out_ready_d = 1'b1;
            end
        end
    end

    always_comb begin
        keccak_state_d = keccak_state_q;
        round_idx_d    = round_idx_q;
        calc_d         = calc_q;

        if (clear_i) begin  // synchronous reset
            keccak_state_d = 'b0;
            round_idx_d    = 'b0;
            calc_d         = 1'b0;
        end else begin
            if (update) begin
                if (accept_d) begin
                    keccak_state_d = {rate_i, capacity};
                end else begin
                    // take the output of the last round block
                    keccak_state_d = round_out[UNROLL_FACTOR-1];
                end
            end
            if (accept_q) begin
                round_idx_d = {(ROUNDS - 1)'(0), 1'b1};
            end else begin
                for (int i = 0; i < UNROLL_FACTOR; i++) begin
                    round_idx_d = {(ROUNDS - 1)'(round_idx_d), 1'b0};
                end
            end
            calc_d = (calc_q && !out_ready_d) || accept_d;
        end
    end

    generate
        assign round_idx[0] = round_idx_d;
        for (genvar i = 1; i < UNROLL_FACTOR; i++) begin : gen_round_onehot_idxs
            assign round_idx[i] = {(ROUNDS - 1)'(round_idx[i-1]), 1'b0};
        end
    endgenerate

    assign round_in[0] = keccak_state_q;
    generate
        for (genvar i = 0; i < UNROLL_FACTOR; i++) begin : gen_parallel_rounds
            rconst rconst_i (
                .round_idx_i  (round_idx[i]),
                .round_const_o(round_const[i])
            );

            round round_i (
                .state_i(round_in[i]),
                .round_const_i(round_const[i]),
                .state_o(round_out[i])
            );
        end
        for (genvar j = 1; j < UNROLL_FACTOR; j++) begin : gen_round_connections
            assign round_in[j] = round_out[j-1];
        end
    endgenerate

endmodule
