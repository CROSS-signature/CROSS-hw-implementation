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

module sha3_high_perf_core
    import sha3_pkg::*;
    import common_pkg::*;
#(
    parameter  sha3_alg_t   SHA3_ALG      = SHA3_256,
    parameter  int unsigned WORD_SZ       = 32,
    parameter  int unsigned UNROLL_FACTOR = 1,
    parameter  int unsigned SEED1_SZ      = 320,
    parameter  int unsigned SEED2_SZ      = 320,
    localparam int unsigned BYTES         = WORD_SZ / 8,
    localparam int unsigned BYTES_SZ      = $clog2(BYTES)
) (
    input  logic                clk_i,
    input  logic                rst_n,
    input  logic                clear_i,
    input  logic [ WORD_SZ-1:0] data_i,
    input  logic                data_ready_i,
    input  logic                is_last_i,
    input  logic [BYTES_SZ-1:0] in_bytes_i,
    output logic                buffer_full_o,
    output logic [ WORD_SZ-1:0] data_o,
    output logic                data_ready_o,
    input  logic                read_i
);

    localparam int unsigned CAPACITY_SZ = CAPACITIES[SHA3_ALG];
    localparam int unsigned RATE_SZ = STATE_SZ - CAPACITY_SZ;
    localparam int unsigned BUF_LEN = RATE_SZ / WORD_SZ;
    localparam int unsigned BUF_IDX_SZ = $clog2(BUF_LEN + 1);
    localparam int unsigned LAST_SEED1_WORD = iceilfrac(SEED1_SZ, WORD_SZ);
    localparam int unsigned LAST_SEED1_BYTES = (SEED1_SZ % WORD_SZ) / 8;
    localparam int unsigned LAST_SEED2_WORD = iceilfrac(SEED2_SZ, WORD_SZ);
    localparam int unsigned LAST_SEED2_BYTES = (SEED2_SZ % WORD_SZ) / 8;
    localparam int unsigned WORDS_IN_RATE = ifloorfrac(RATE_SZ, WORD_SZ);
    localparam int unsigned SEED1_BUFFER_BITS = (LAST_SEED1_WORD - 1) * WORD_SZ;
    localparam int unsigned SEED1_BUFFER_PAD_BITS = (WORDS_IN_RATE - LAST_SEED1_WORD) * WORD_SZ;
    localparam int unsigned SEED2_BUFFER_BITS = (LAST_SEED2_WORD - 1) * WORD_SZ;
    localparam int unsigned SEED2_BUFFER_PAD_BITS = (WORDS_IN_RATE - LAST_SEED2_WORD) * WORD_SZ;

    typedef enum logic [1:0] {
        ABSORB,
        PADDING,
        WAIT,
        SQUEEZE
    } fsm_state_t;

    fsm_state_t fsm_state_d, fsm_state_q;

    logic [RATE_SZ-1:0] padder_block;
    logic               padder_ready;

    logic               f_ack;
    logic [RATE_SZ-1:0] f_rate_in;
    logic [RATE_SZ-1:0] f_rate_out;
    logic               f_start;
    logic               f_done;

    logic               buf_update;
    logic               seed1_shortcut;
    logic               seed2_shortcut;
    logic [WORD_SZ-1:0] padder_in;
    logic [WORD_SZ-1:0] padder_out;
    logic [RATE_SZ-1:0] buffer_d, buffer_q;
    logic [BUF_IDX_SZ-1:0] buf_idx_d, buf_idx_q;

    assign data_ready_o = f_done;
    assign padder_in = data_i;
    assign seed1_shortcut = is_last_i && (buf_idx_q == BUF_IDX_SZ'(LAST_SEED1_WORD - 1)) && (in_bytes_i == BYTES_SZ'(LAST_SEED1_BYTES));
    assign seed2_shortcut = is_last_i && (buf_idx_q == BUF_IDX_SZ'(LAST_SEED2_WORD - 1)) && (in_bytes_i == BYTES_SZ'(LAST_SEED2_BYTES));
    /* last word of rate, change endianness */
    assign data_o = buffer_q[RATE_SZ-1-:WORD_SZ];
    assign buffer_full_o = buf_idx_q == BUF_IDX_SZ'(BUF_LEN);

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin  // asynchronous reset
            fsm_state_q <= ABSORB;
            buf_idx_q   <= 'b0;
        end else begin
            fsm_state_q <= fsm_state_d;
            buf_idx_q   <= buf_idx_d;
        end
    end

    // do not initialize the buffer
    always_ff @(posedge clk_i) begin
        buffer_q <= buffer_d;
    end

    always_comb begin : fsm_logic
        fsm_state_d = fsm_state_q;
        f_rate_in   = padder_block ^ f_rate_out;
        f_start     = 1'b0;
        buffer_d    = buffer_q;
        buf_idx_d   = buf_idx_q;

        if (clear_i) begin  // synchronous reset
            fsm_state_d = ABSORB;
            buf_idx_d   = BUF_IDX_SZ'(0);
        end else begin
            unique case (fsm_state_q)
                ABSORB: begin
                    f_start   = padder_ready;
                    f_rate_in = padder_block ^ f_rate_out;

                    // no new data from the write stream
                    if (is_last_i) begin
                        fsm_state_d = PADDING;
                    end

                    // insert new data into the buffer (input buffer)
                    if (buf_update) begin
                        if (seed1_shortcut) begin
                            buffer_d = {
                                SEED1_BUFFER_BITS'(buffer_q),
                                padder_out,
                                {SEED1_BUFFER_PAD_BITS{1'b0}}
                            };  // rotate by one word
                            buffer_d[7] = 1'b1;
                            buf_idx_d = BUF_IDX_SZ'(BUF_LEN);
                        end else if (seed2_shortcut) begin
                            buffer_d = {
                                SEED2_BUFFER_BITS'(buffer_q),
                                padder_out,
                                {SEED2_BUFFER_PAD_BITS{1'b0}}
                            };  // rotate by one word
                            buffer_d[7] = 1'b1;
                            buf_idx_d = BUF_IDX_SZ'(BUF_LEN);
                        end else begin
                            buffer_d = {
                                (RATE_SZ - WORD_SZ)'(buffer_q), padder_out
                            };  // rotate by one word
                            buf_idx_d = buf_idx_q + 1;
                        end
                    end

                    // data was consumed by the f-perm
                    if (f_ack) begin
                        buf_idx_d = BUF_IDX_SZ'(0);
                    end
                end

                PADDING: begin
                    if (padder_ready) begin
                        fsm_state_d = WAIT;
                        f_start     = 1'b1;  // absorb last block
                        f_rate_in   = padder_block ^ f_rate_out;
                    end

                    // insert new data into the buffer (input buffer)
                    if (buf_update) begin
                        buffer_d = {
                            (RATE_SZ - WORD_SZ)'(buffer_q), padder_out
                        };  // rotate by one word
                        buf_idx_d = buf_idx_q + 1;
                    end
                end

                WAIT: begin
                    if (f_done) begin
                        fsm_state_d = SQUEEZE;
                        buffer_d    = {<<LANE_SZ{{<<WORD_SZ{f_rate_out}}}};
                        buf_idx_d   = BUF_IDX_SZ'(0);  // reset buffer read counter
                        f_rate_in   = f_rate_out;
                        f_start     = 1'b1;  // produce new data
                    end
                end

                SQUEEZE: begin
                    f_rate_in = f_rate_out;

                    // consume data from buffer (output buffer)
                    if (read_i) begin
                        buffer_d = {
                            (RATE_SZ - WORD_SZ)'(buffer_q), padder_out
                        };  // rotate by one word
                        buf_idx_d = buf_idx_q + 1;
                    end

                    // the buffer was completely consumed
                    if (read_i && (buf_idx_q == BUF_IDX_SZ'(BUF_LEN - 1))) begin
                        // if f-perm has already new data
                        if (f_done) begin
                            // reverse order word-wise, and then reverse again lane-wise
                            // this changes the rate encoding to read the result with simple word rotations
                            buffer_d  = {<<LANE_SZ{{<<WORD_SZ{f_rate_out}}}};
                            buf_idx_d = BUF_IDX_SZ'(0);  // reset buffer read counter
                            f_start   = 1'b1;  // produce new data
                        end else begin
                            fsm_state_d = WAIT;
                        end
                    end
                end

                default: begin
                    buffer_d  = buffer_q;
                    buf_idx_d = buf_idx_q;
                end

            endcase
        end
    end

    always_comb begin  // change endianness
        for (int i = 0; i < RATE_SZ / LANE_SZ; i++) begin : gen_adder_out_lane
            padder_block[i*LANE_SZ+:LANE_SZ] = {<<byte{buffer_q[i*LANE_SZ+:LANE_SZ]}};
        end
    end

    padder #(
        .SHA3_ALG(SHA3_ALG),
        .CAPACITY_SZ(CAPACITY_SZ),
        .RATE_SZ(RATE_SZ),
        .WORD_SZ(WORD_SZ)
    ) padder_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .clear_i(clear_i),
        .data_i(padder_in),
        .data_ready_i(data_ready_i),
        .is_last_i(is_last_i),
        .in_bytes_i(in_bytes_i),
        .buffer_idx_i(buf_idx_q),
        .buffer_update_o(buf_update),
        .data_o(padder_out),
        .data_ready_o(padder_ready)
    );

    f_permutation #(
        .SHA3_ALG(SHA3_ALG),
        .CAPACITY_SZ(CAPACITY_SZ),
        .RATE_SZ(RATE_SZ),
        .UNROLL_FACTOR(UNROLL_FACTOR)
    ) f_permutation_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .start_i(f_start),
        .clear_i(clear_i),
        .rate_i(f_rate_in),
        .ack_o(f_ack),
        .rate_o(f_rate_out),
        .rate_ready_o(f_done)
    );

endmodule
