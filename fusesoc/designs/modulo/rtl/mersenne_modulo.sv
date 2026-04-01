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

module mersenne_modulo
    import common_pkg::*;
#(
    parameter  int unsigned MODULO    = 31,
    parameter  int unsigned MAX_INPUT = 2 ** 32 - 1,
    parameter  int unsigned STAGES    = 1,
    localparam int unsigned INPUT_SZ  = $clog2(MAX_INPUT),
    localparam int unsigned MOD_SZ    = $clog2(MODULO)
) (
    input  logic                clk_i,
    input  logic                rst_n,
    input  logic [INPUT_SZ-1:0] data_i,
    input  logic                last_i,
    input  logic                req_i,
    output logic                ready_o,
    output logic [  MOD_SZ-1:0] data_o,
    output logic                valid_o,
    input  logic                ready_i,
    output logic                last_o
);

    `ASSERT_INIT(mersenne_prime, is_mersenne_prime(MODULO))

    localparam int unsigned NUM_SHIFTS = iceilfrac(INPUT_SZ - MOD_SZ, MOD_SZ);
    // the shift-and-add operation enlarges the accumulated result by 1 bit every operation
    // we need to consider that with "extra" operations
    localparam int unsigned NUM_OPS = NUM_SHIFTS + iceilfrac(NUM_SHIFTS, MOD_SZ);

    `ASSERT_INIT(pipeline_size, NUM_OPS >= STAGES)

    generate
        if (STAGES == 0) begin : gen_comb_design

            logic [INPUT_SZ-1:0] temp;

            always_comb begin
                temp = data_i;

                // Perform shift-and-add operations
                for (int unsigned i = 0; i < NUM_OPS; i++) begin
                    // i = (K & p) + (K >> s); #####
                    temp = INPUT_SZ'(MOD_SZ'(temp)) + INPUT_SZ'(temp[INPUT_SZ-1:MOD_SZ]);
                end

                if (temp >= INPUT_SZ'(MODULO)) begin
                    // i = ( i>= p ) ? i-p : i;
                    temp = temp - INPUT_SZ'(MODULO);
                end

                data_o  = temp[MOD_SZ-1:0];

                valid_o = req_i;
                ready_o = ready_i;
                last_o  = last_i;
            end

        end else begin : gen_pipelined_design

            localparam int unsigned MAX_OPS_PER_STAGE = iceilfrac(NUM_OPS, STAGES);

            for (genvar i = 0; i < STAGES; i++) begin : gen_pipeline_stage
                localparam int unsigned STAGE_OPS = (i != (STAGES-1)) ? MAX_OPS_PER_STAGE : (NUM_OPS-MAX_OPS_PER_STAGE*i);
                localparam int unsigned CURR_OVERFLOW_BITS = $clog2(STAGE_OPS + 1);
                localparam int unsigned PREV_OVERFLOW_BITS = $clog2(MAX_OPS_PER_STAGE + 1);
                localparam int unsigned IN_STAGE_SZ = INPUT_SZ - i * ( MAX_OPS_PER_STAGE * MOD_SZ - PREV_OVERFLOW_BITS );
                localparam int unsigned OUT_STAGE_SZ = max(
                    IN_STAGE_SZ - (STAGE_OPS * MOD_SZ) + CURR_OVERFLOW_BITS, MOD_SZ
                );

                // data is registered at the end of the stage
                logic [OUT_STAGE_SZ-1:0] data_d, data_q;
                logic [OUT_STAGE_SZ:0] data_reg_d, data_reg_q;
                logic [IN_STAGE_SZ-1:0] in;
                logic [IN_STAGE_SZ-1:0] temp;
                logic valid_d, valid_q, ready_tmp_i, ready_tmp_o, last_d, last_q;

                if (i == 0) begin : gen_first_stage
                    assign valid_d = req_i;
                    assign last_d = last_i;
                    assign in = data_i;
                end else begin : gen_regular_stage
                    assign valid_d = gen_pipeline_stage[i-1].valid_q;
                    assign last_d = gen_pipeline_stage[i-1].last_q;
                    assign in = gen_pipeline_stage[i-1].data_q;
                end

                if (i == STAGES - 1) begin
                    assign gen_pipeline_stage[i].ready_tmp_i = ready_i;
                end else begin
                    assign gen_pipeline_stage[i].ready_tmp_i = gen_pipeline_stage[i+1].ready_tmp_o;
                end

                spill_register #(
                    .T(logic [OUT_STAGE_SZ:0])
                ) u_reg (
                    .clk_i,
                    .rst_ni (rst_n),
                    .valid_i(valid_d),
                    .ready_o(ready_tmp_o),
                    .data_i (data_reg_d),
                    .valid_o(valid_q),
                    .ready_i(ready_tmp_i),
                    .data_o (data_reg_q)
                );
                assign data_reg_d = {last_d, data_d};
                assign {last_q, data_q} = data_reg_q;

                always_comb begin
                    temp = in;
                    for (int unsigned j = 0; j < STAGE_OPS; j++) begin
                        temp = IN_STAGE_SZ'(MOD_SZ'(temp)) + IN_STAGE_SZ'(temp[IN_STAGE_SZ-1:MOD_SZ]);
                    end
                    data_d = OUT_STAGE_SZ'(temp);
                end
            end

            assign data_o = (MOD_SZ'(gen_pipeline_stage[STAGES-1].data_q) >= MOD_SZ'(MODULO)) ? '0 : gen_pipeline_stage[STAGES-1].data_q;
            assign valid_o = gen_pipeline_stage[STAGES-1].valid_q;
            assign ready_o = gen_pipeline_stage[0].ready_tmp_o;
            assign last_o = gen_pipeline_stage[STAGES-1].last_q;

        end
    endgenerate

endmodule
