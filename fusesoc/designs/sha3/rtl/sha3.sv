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

module sha3
    import common_pkg::*;
    import sha3_pkg::*;
#(
    parameter sha3_alg_t   SHA3_ALG      = SHA3_256,
    parameter int unsigned UNROLL_FACTOR = 1,
    parameter int unsigned STREAM_WIDTH  = 32,
    parameter int unsigned SEED1_SZ      = 320,
    parameter int unsigned SEED2_SZ      = 320
) (
    input logic         clk_i,
    input logic         rst_n,
    input logic         clear_i,
          stream_r.prod sha3_r_stream,
          stream_w.cons sha3_w_stream
);

    localparam int unsigned CAPACITY_SZ = CAPACITIES[SHA3_ALG];
    localparam int unsigned RATE_SZ = STATE_SZ - CAPACITY_SZ;
    localparam int unsigned WORDS_IN_RATE = ifloorfrac(RATE_SZ, STREAM_WIDTH);
    localparam int unsigned IDX_SZ = $clog2(WORDS_IN_RATE);
    localparam int unsigned BYTES_SZ = $clog2(STREAM_WIDTH / BITS_IN_BYTE);

    logic                    in_ready;
    logic                    in_last;
    logic [STREAM_WIDTH-1:0] in_data;
    logic [    BYTES_SZ-1:0] in_bytes;

    logic                    out_request;
    logic [STREAM_WIDTH-1:0] out_data;

    logic input_ended_d, input_ended_q;
    logic sha3_rate_full;
    logic data_absorbed;
    logic read_rate;
    logic out_ready;
    logic word_valid;
    logic last_block_absorbed;
    logic [IDX_SZ-1:0] buffer_idx_d, buffer_idx_q;

    typedef enum logic [2:0] {
        ABSORB,
        FILL_RATE,
        APPLY_F_PERM,
        READ_OUT,
        ERROR
    } fsm_state_t;
    fsm_state_t state_d, state_q;

    sha3_high_perf_core #(
        .SHA3_ALG(SHA3_ALG),
        .WORD_SZ(STREAM_WIDTH),
        .UNROLL_FACTOR(UNROLL_FACTOR),
        .SEED1_SZ(SEED1_SZ),
        .SEED2_SZ(SEED2_SZ)
    ) sha3_core_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .clear_i(clear_i),
        .data_i(in_data),
        .data_ready_i(&in_ready),
        .is_last_i(last_block_absorbed),
        .in_bytes_i(in_bytes),
        .buffer_full_o(sha3_rate_full),
        .data_o(out_data),
        .data_ready_o(out_ready),
        .read_i(read_rate)
    );

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin
            state_q       <= ABSORB;
            buffer_idx_q  <= 'b0;
            input_ended_q <= 1'b0;
        end else begin
            state_q       <= state_d;
            buffer_idx_q  <= buffer_idx_d;
            input_ended_q <= input_ended_d;
        end
    end

    assign in_ready              = (state_q == ABSORB) && sha3_w_stream.request;
    assign sha3_w_stream.grant   = !rst_n ? 1'b0 : data_absorbed;
    assign in_last               = sha3_w_stream.is_last;
    assign in_data               = sha3_w_stream.data;
    assign in_bytes              = sha3_w_stream.bytes;

    assign out_request           = sha3_r_stream.request;
    assign sha3_r_stream.data    = out_data;
    // full block
    assign sha3_r_stream.bytes   = 'b0;
    assign sha3_r_stream.grant   = word_valid;
    assign sha3_r_stream.valid   = word_valid;
    assign sha3_r_stream.is_last = 1'b0;

    assign data_absorbed         = &in_ready && !sha3_rate_full && (state_q == ABSORB);
    assign last_block_absorbed   = data_absorbed && &in_last;

    always_comb begin : FSM_logic
        state_d       = state_q;
        word_valid    = 1'b0;
        read_rate     = 1'b0;
        input_ended_d = input_ended_q;
        buffer_idx_d  = buffer_idx_q;

        unique case (state_q)
            ABSORB: begin
                input_ended_d = input_ended_q | last_block_absorbed;
                unique case ({
                    last_block_absorbed, sha3_rate_full
                })
                    2'b00:   state_d = ABSORB;
                    2'b01:   state_d = APPLY_F_PERM;
                    2'b10:   state_d = FILL_RATE;
                    default: `DEFAULT_CASE(state_d = ABSORB;)
                endcase
            end

            FILL_RATE: begin
                if (sha3_rate_full) begin
                    state_d = APPLY_F_PERM;
                end
            end

            APPLY_F_PERM: begin
                if (out_ready) begin
                    if (!input_ended_q) begin
                        state_d = ABSORB;
                    end else begin
                        state_d      = READ_OUT;
                        buffer_idx_d = 0;
                    end
                end
                if (clear_i) begin
                    state_d       = ABSORB;
                    input_ended_d = 1'b0;
                end
            end

            READ_OUT: begin
                if (clear_i) begin
                    state_d       = ABSORB;
                    input_ended_d = 1'b0;
                end
                if (&out_request) begin
                    word_valid   = 1'b1;
                    read_rate    = 1'b1;
                    buffer_idx_d = buffer_idx_q + 1;

                    if (buffer_idx_q == IDX_SZ'(WORDS_IN_RATE - 1)) begin
                        if (out_ready) begin
                            buffer_idx_d = 0;
                        end else begin
                            state_d = APPLY_F_PERM;
                        end
                    end
                end
            end

            default: `DEFAULT_CASE(state_d = ERROR;)

        endcase
    end


endmodule
