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

/* "is_last_i" == 0 means byte number is 4, no matter what value "in_bytes_i" is. */
/* if "data_ready_i" == 0, then "is_last_i" should be 0. */
/* the user switch to next "in" only if "ack" == 1. */

module padder
    import common_pkg::*;
    import sha3_pkg::*;
#(
    parameter  sha3_alg_t   SHA3_ALG    = SHA3_256,
    parameter  int unsigned CAPACITY_SZ = CAPACITIES            [SHA3_ALG],
    parameter  int unsigned RATE_SZ     = STATE_SZ - CAPACITY_SZ,
    parameter  int unsigned WORD_SZ     = 32,
    parameter  bit          ENABLE_PAD  = 1'b1,
    localparam int unsigned BUF_LEN     = RATE_SZ / WORD_SZ,
    localparam int unsigned BUF_IDX_SZ  = $clog2(BUF_LEN + 1),
    localparam int unsigned BYTES       = WORD_SZ / 8,
    localparam int unsigned BYTES_SZ    = $clog2(BYTES)
) (
    input  logic                  clk_i,
    input  logic                  rst_n,
    input  logic                  clear_i,
    input  logic [   WORD_SZ-1:0] data_i,
    input  logic                  data_ready_i,
    input  logic                  is_last_i,
    input  logic [  BYTES_SZ-1:0] in_bytes_i,
    input  logic [BUF_IDX_SZ-1:0] buffer_idx_i,
    output logic [   WORD_SZ-1:0] data_o,
    output logic                  buffer_update_o,
    output logic                  data_ready_o
);

    `ASSERT_INIT(rate_multiple_of_word_sz, RATE_SZ % WORD_SZ == 0)

    localparam int unsigned MSB = 7;  // position of the MSB in the word
    localparam logic [8-1:0] DSEP_PAD10STAR[6] = '{
        8'h06,  // SHA3-224   *00001_10
        8'h06,  // SHA3-256   *00001_10
        8'h06,  // SHA3-384   *00001_10
        8'h06,  // SHA3-512   *00001_10
        8'h1F,  // SHAKE-128  *0001_111
        8'h1F  // SHAKE-256   *0001_111
    };  // no domain separation: 8'h01 -> *0000001

    typedef enum logic {
        ABSORB_INPUT,
        PADDING
    } fsm_state_t;

    fsm_state_t state_d, state_q;
    logic done_d, done_q;

    logic [  BYTES-1:0][WORD_SZ-1:0] msg_dsep_pad10star;
    logic                            accept;
    logic                            update;
    logic                            buffer_full;
    logic [WORD_SZ-1:0]              data_in;
    logic [WORD_SZ-1:0]              data_out;
    logic                            final_bit;

    assign data_in         = {<<byte{data_i}};
    assign data_o          = data_out;
    assign data_ready_o    = buffer_full;
    assign buffer_update_o = update;
    assign buffer_full     = buffer_idx_i == BUF_IDX_SZ'(BUF_LEN);
    // don't fill buffer if done
    assign update          = (accept || ((state_q == PADDING) && !buffer_full)) && !done_q;

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin  // asynchronous reset
            state_q <= ABSORB_INPUT;
            done_q  <= 1'b0;
        end else begin
            state_q <= state_d;
            done_q  <= done_d;
        end
    end

    // Add padding 10*
    generate
        logic [8-1:0] pad;
        if (ENABLE_PAD) begin : gen_pad
            assign pad = DSEP_PAD10STAR[SHA3_ALG];
            assign final_bit = (buffer_idx_i == BUF_IDX_SZ'(BUF_LEN - 1));
        end else begin : gen_null_pad
            assign pad = 'b0;
            assign final_bit = 1'b0;
        end
        assign msg_dsep_pad10star[0] = {pad, {(WORD_SZ - 8) {1'b0}}};
        for (genvar i = 1; i < BYTES; i++) begin : gen_pad10star
            assign msg_dsep_pad10star[i] = {data_in[WORD_SZ-1-:8*i], pad, {(WORD_SZ - 8 * (i + 1)) {1'b0}}};
        end
    endgenerate

    always_comb begin
        state_d  = state_q;
        data_out = data_in;
        accept   = 1'b0;
        done_d   = done_q;

        if (clear_i) begin  // synchronous reset
            state_d = ABSORB_INPUT;
            done_d  = 1'b0;
        end else begin

            unique case (state_q)
                ABSORB_INPUT: begin
                    if (is_last_i) begin
                        // padded value
                        data_out      = msg_dsep_pad10star[in_bytes_i];
                        // conclude the pad10*1 setting the last bit
                        data_out[MSB] = data_out[MSB] | final_bit;
                        state_d       = PADDING;
                    end else begin
                        data_out = data_in;
                    end

                    if (data_ready_i && !buffer_full) begin
                        accept = 1'b1;
                    end
                end

                PADDING: begin
                    data_out      = 'b0;
                    // conclude the pad10*1 setting the last bit
                    data_out[MSB] = data_out[MSB] | final_bit;
                    if (buffer_full) begin
                        done_d = 1'b1;
                    end
                end

                default: ;
            endcase

        end
    end
endmodule
