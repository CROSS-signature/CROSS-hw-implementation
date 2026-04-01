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

module crandall_modulo
    import common_pkg::*;
#(
    parameter  int unsigned MODULO    = 509,
    parameter  int unsigned MAX_INPUT = 508**2,
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

    // `ASSERT_INIT(crandall_prime, is_crandall_prime(MODULO))

    localparam int unsigned NUM_SHIFTS = iceilfrac(INPUT_SZ - MOD_SZ, MOD_SZ);
    // the shift-and-add operation enlarges the accumulated result by 1 bit every operation
    // we need to consider that with "extra" operations
    localparam int unsigned NUM_OPS = NUM_SHIFTS + iceilfrac(NUM_SHIFTS, MOD_SZ);

    `ASSERT_INIT(pipeline_size, NUM_OPS >= STAGES)

    logic [MOD_SZ-1:0] hi;
    logic [MOD_SZ-1:0] lo;
    assign {hi, lo} = data_i;

    logic [  MOD_SZ:0] dobule_hi;
    logic [MOD_SZ+1:0] triple_hi;
    assign dobule_hi = {1'b0, hi} << 1;
    assign triple_hi = dobule_hi + {1'b0, hi};

    logic [MOD_SZ+1:0] temp_d, temp_q;
    assign temp_d = triple_hi + {1'b0, lo};

    logic [3:0][MOD_SZ-1:0] mux_in;
    logic [2:0][MOD_SZ+2:0] sub_res;

    assign mux_in[0] = MOD_SZ'(temp_q);
    assign mux_in[1] = MOD_SZ'(sub_res[0]);
    assign mux_in[2] = MOD_SZ'(sub_res[1]);
    assign mux_in[3] = MOD_SZ'(sub_res[2]);

    logic [1:0] sel;

    assign data_o = mux_in[sel];

    always_comb begin : mux_sel
        unique casez ({
            sub_res[0][MOD_SZ+2], sub_res[1][MOD_SZ+2], sub_res[2][MOD_SZ+2]
        })
            3'b111:  sel = 0;
            3'b01z:  sel = 1;
            3'bz01:  sel = 2;
            3'b000:  sel = 3;
            default: sel = 0;
        endcase
    end

    assign sub_res[0] = temp_q - (MOD_SZ + 3)'(MODULO);
    assign sub_res[1] = temp_q - (MOD_SZ + 3)'(2 * MODULO);
    assign sub_res[2] = temp_q - (MOD_SZ + 3)'(3 * MODULO);

    generate
        if (STAGES == 0) begin : gen_comb_design

            assign temp_q  = temp_d;

            assign last_o  = last_i;
            assign valid_o = req_i;
            assign ready_o = ready_i;

        end else begin : gen_pipelined_design

            spill_register #(
                .T(logic [MOD_SZ+2:0])
            ) u_reg (
                .clk_i,
                .rst_ni (rst_n),
                .valid_i(req_i),
                .ready_o(ready_o),
                .data_i ({last_i, temp_d}),
                .valid_o(valid_o),
                .ready_i(ready_i),
                .data_o ({last_o, temp_q})
            );

        end
    endgenerate

endmodule
