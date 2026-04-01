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
`ifdef RSDPG
module mul_vector_matrix_m
    import common_pkg::*;
    import cross_pkg::*;
#(
    parameter int unsigned MAT_TDATA_WIDTH = 64
) (
    input  logic       clk_i,
    input  logic       rst_n,
    input  logic       start_i,
    output logic       done_o,
    //
           AXIS.slave  vector,
           AXIS.slave  matrix,
           AXIS.master result
);

    localparam int unsigned MAT_KEEP_WIDTH = `NON_NEG_MSB(MAT_TDATA_WIDTH / BITS_Z);

    AXIS #(
        .DATA_WIDTH(BITS_Z),
        .ELEM_WIDTH(BITS_Z)
    ) vector_internal ();

    width_converter #(
        .ELEM_WIDTH(BITS_Z)
    ) vector_conv_i (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(vector),
        .m_axis(vector_internal)
    );

    AXIS #(
        .DATA_WIDTH(BITS_Z),
        .ELEM_WIDTH(BITS_Z)
    ) result_internal ();

    AXIS #(
        .DATA_WIDTH(result.DATA_WIDTH),
        .ELEM_WIDTH(BITS_Z)
    ) result_registered ();

    width_converter #(
        .ELEM_WIDTH(BITS_Z)
    ) result_conv_i (
        .axis_aclk(clk_i),
        .axis_rst_n(rst_n),
        .s_axis(result_internal),
        .m_axis(result_registered)
    );

    axis_reg #(
        .ELEM_WIDTH(BITS_Z),
        .SPILL_REG (1)
    ) u_axis_out_reg (
        .clk(clk_i),
        .rst_n(rst_n),
        .s_axis(result_registered),
        .m_axis(result)
    );

    localparam int unsigned MUL_UNITS = MAT_KEEP_WIDTH;
    localparam int unsigned NUM_ROWS_W = M;
    localparam int unsigned NUM_COLS_W = N - M;
    localparam int unsigned NUM_ROWS_I = M;
    // keep extra space for the buffer to have only rotations by MUL_UNITS and by 1
    localparam int unsigned MAT_ROW_TRANSFERS = iceilfrac(NUM_COLS_W, MUL_UNITS);
    localparam int unsigned ACC_LEN = MAT_ROW_TRANSFERS * MUL_UNITS;
    localparam int unsigned BUF_LEN = M;
    localparam int unsigned CTR_SZ = $clog2(
        max(max(max(NUM_ROWS_W, NUM_ROWS_I), BUF_LEN), NUM_COLS_W)
    );
    localparam int unsigned ACC_CTR_SZ = `NON_NEG_MSB($clog2(MAT_ROW_TRANSFERS));
    localparam int unsigned OUT_CTR_SZ = $clog2(MUL_UNITS);

    typedef enum logic [2:0] {
        IDLE,
        WAIT_VECTOR,
        COMPUTE_W,  // process a single vector coefficient using W matrix
        FLUSH_ACC,
        COMPUTE_IDENTITY,  // computation due to the identity matrix, expose immediately the result
        SYNC
    } fsm_state_t;
    fsm_state_t read_state_d, read_state_q;
    fsm_state_t compute_state_d, compute_state_q;

    logic [CTR_SZ-1:0] read_ctr_d, read_ctr_q;
    logic [CTR_SZ-1:0] compute_ctr_d, compute_ctr_q;
    logic [ACC_CTR_SZ-1:0] acc_ctr_d, acc_ctr_q;
    logic [OUT_CTR_SZ-1:0] out_ctr_d, out_ctr_q;
    logic [BITS_Z-1:0] vector_coeff_d, vector_coeff_q;

    logic multiplier_request;
    logic [MUL_UNITS-1:0] multiplier_valid;
    logic [MUL_UNITS-1:0] multiplier_ready_i;
    logic [MUL_UNITS-1:0][BITS_Z-1:0] multiplier_op1;
    logic [MUL_UNITS-1:0][BITS_Z-1:0] multiplier_op2;
    logic [MUL_UNITS-1:0][BITS_Z-1:0] multiplier_out;

    logic [MUL_UNITS-1:0][BITS_Z:0] temp_acc;

    logic [ACC_LEN-1:0][BITS_Z-1:0] accumulator_d, accumulator_q;
    logic [BUF_LEN-1:0][BITS_Z-1:0] buffer_d, buffer_q;

    logic done_d, done_q;

    assign done_o = done_q;

    assign multiplier_request = `AXIS_TRANS(matrix);

    always_comb begin
        vector_coeff_d = vector_coeff_q;
        if (`AXIS_TRANS(vector_internal)) begin
            vector_coeff_d = vector_internal.tdata;
        end
    end

    generate
        for (genvar i = 0; i < MUL_UNITS; i++) begin : gen_point_multiplication
            assign multiplier_op1[i] = vector_coeff_q;
            assign multiplier_op2[i] = matrix.tkeep[i] ? matrix.tdata[i*BITS_Z+:BITS_Z] : BITS_Z'(0);

            mul #(
                .MODULO(Z)
            ) multiplier_i (
                .clk_i(clk_i),
                .rst_n(rst_n),
                .op1_i(multiplier_op1[i]),
                .op2_i(multiplier_op2[i]),
                .req_i(multiplier_request),
                .ready_o(),  // unfortunately not supported straightforwardly
                .last_i(1'b0),  //TODO
                .res_o(multiplier_out[i]),
                .valid_o(multiplier_valid[i]),
                .ready_i(multiplier_ready_i[i]),
                .last_o()  //TODO
            );
        end
    endgenerate

    always_comb begin
        for (int unsigned i = 0; i < MUL_UNITS; i++) begin
            temp_acc[i] = accumulator_q[i] + multiplier_out[i];
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin
            read_state_q    <= IDLE;
            compute_state_q <= IDLE;
            read_ctr_q      <= 'b0;
            compute_ctr_q   <= 'b0;
            out_ctr_q       <= 'b0;
            acc_ctr_q       <= 'b0;
            accumulator_q   <= 'b0;
            buffer_q        <= 'b0;
            vector_coeff_q  <= 'b0;
            done_q          <= 1'b0;
        end else begin
            read_state_q    <= read_state_d;
            compute_state_q <= compute_state_d;
            read_ctr_q      <= read_ctr_d;
            compute_ctr_q   <= compute_ctr_d;
            out_ctr_q       <= out_ctr_d;
            acc_ctr_q       <= acc_ctr_d;
            accumulator_q   <= accumulator_d;
            buffer_q        <= buffer_d;
            vector_coeff_q  <= vector_coeff_d;
            done_q          <= done_d;
        end
    end

    always_comb begin : read_FSM
        read_state_d           = read_state_q;
        read_ctr_d             = read_ctr_q;
        vector_internal.tready = 1'b0;
        matrix.tready          = 1'b0;

        unique case (read_state_q)
            IDLE: begin
                if (start_i) begin
                    read_ctr_d = CTR_SZ'(0);
                    vector_internal.tready = 1'b1;
                    if (`AXIS_TRANS(vector_internal)) begin
                        read_state_d = COMPUTE_W;
                    end else begin
                        read_state_d = WAIT_VECTOR;
                    end
                end
            end

            WAIT_VECTOR: begin
                vector_internal.tready = 1'b1;
                if (`AXIS_TRANS(vector_internal)) begin
                    read_state_d = COMPUTE_W;
                end
            end

            COMPUTE_W: begin
                matrix.tready = 1'b1;
                if (`AXIS_LAST(matrix)) begin
                    if (read_ctr_q == CTR_SZ'(NUM_ROWS_W - 1)) begin
                        read_state_d = SYNC;
                        read_ctr_d   = CTR_SZ'(0);
                    end else begin
                        read_ctr_d = read_ctr_q + 1;
                        vector_internal.tready = 1'b1;
                        if (`AXIS_TRANS(vector_internal)) begin
                            read_state_d = COMPUTE_W;
                        end else begin
                            read_state_d = WAIT_VECTOR;
                        end
                    end
                end
            end

            SYNC: begin
                if (compute_state_d == IDLE) begin
                    read_state_d = IDLE;
                end
            end

            default: ;
        endcase
    end

    always_comb begin : compute_FSM
        compute_state_d        = compute_state_q;
        compute_ctr_d          = compute_ctr_q;
        out_ctr_d              = out_ctr_q;
        acc_ctr_d              = acc_ctr_q;
        accumulator_d          = accumulator_q;
        buffer_d               = buffer_q;
        done_d                 = 1'b0;
        multiplier_ready_i     = '0;
        result_internal.tdata  = accumulator_q[out_ctr_q];
        result_internal.tlast  = 1'b0;
        result_internal.tvalid = 1'b0;
        result_internal.tkeep  = 1'b1;

        unique case (compute_state_q)
            IDLE: begin
                if (start_i) begin
                    compute_state_d = COMPUTE_W;
                    compute_ctr_d   = CTR_SZ'(0);
                    out_ctr_d       = OUT_CTR_SZ'(0);
                    acc_ctr_d       = ACC_CTR_SZ'(0);
                end
            end

            COMPUTE_W: begin
                multiplier_ready_i = '1;
                if (`AXIS_TRANS(vector_internal)) begin
                    buffer_d[0] = vector_internal.tdata;
                    for (int i = 1; i < BUF_LEN; i++) begin
                        buffer_d[i] = buffer_q[i-1];
                    end
                end
                if (&(multiplier_valid & multiplier_ready_i)) begin
                    acc_ctr_d = acc_ctr_q + 1;
                    // compute the accumulation and rotation of the first MUL_UNITS elements
                    for (int unsigned i = 0; i < MUL_UNITS; i++) begin : gen_buffer
                        if (temp_acc[i] >= (BITS_Z + 1)'(Z)) begin
                            accumulator_d[ACC_LEN-MUL_UNITS+i] = BITS_Z'(temp_acc[i] - (BITS_Z + 1)'(Z));
                        end else begin
                            accumulator_d[ACC_LEN-MUL_UNITS+i] = BITS_Z'(temp_acc[i]);
                        end
                    end
                    // rotate the remaining elements by MUL_UNITS
                    for (int unsigned i = 0; i < ACC_LEN - MUL_UNITS; i++) begin
                        accumulator_d[i] = accumulator_q[MUL_UNITS+i];
                    end

                    if (acc_ctr_q == ACC_CTR_SZ'(MAT_ROW_TRANSFERS - 1)) begin
                        acc_ctr_d = ACC_CTR_SZ'(0);
                        compute_ctr_d = compute_ctr_q + 1;
                        if (compute_ctr_q == CTR_SZ'(NUM_ROWS_W - 1)) begin
                            compute_state_d = FLUSH_ACC;
                            compute_ctr_d   = CTR_SZ'(0);
                        end
                    end
                end
            end

            FLUSH_ACC: begin
                result_internal.tvalid = 1'b1;
                result_internal.tdata  = accumulator_q[out_ctr_q];
                if (result_internal.tready) begin
                    if (compute_ctr_q == CTR_SZ'(NUM_COLS_W - 1)) begin
                        compute_state_d = COMPUTE_IDENTITY;
                        compute_ctr_d   = CTR_SZ'(0);
                    end else begin
                        compute_ctr_d = compute_ctr_q + 1;
                    end

                    if (out_ctr_q == OUT_CTR_SZ'(MUL_UNITS - 1) || compute_ctr_q == CTR_SZ'(NUM_COLS_W - 1)) begin
                        // shift by MUL_UNITS and fill with zeros to clean the state for the next computation
                        for (int unsigned i = 0; i < ACC_LEN - MUL_UNITS; i++) begin
                            accumulator_d[i] = accumulator_q[MUL_UNITS+i];
                        end
                        for (int unsigned i = ACC_LEN - MUL_UNITS; i < ACC_LEN; i++) begin
                            accumulator_d[i] = 'b0;
                        end

                        out_ctr_d = OUT_CTR_SZ'(0);
                    end else begin
                        out_ctr_d = out_ctr_q + 1;
                    end
                end
            end

            COMPUTE_IDENTITY: begin
                result_internal.tvalid = 1'b1;
                result_internal.tdata  = buffer_q[BUF_LEN-1];
                result_internal.tlast  = (compute_ctr_q == CTR_SZ'(M - 1));
                if (`AXIS_TRANS(result_internal)) begin
                    compute_ctr_d = compute_ctr_q + 1;

                    // shift by 1 and fill with zeros to clean the state for the next computation
                    buffer_d[0]   = 'b0;
                    for (int unsigned i = 1; i < BUF_LEN; i++) begin
                        buffer_d[i] = buffer_q[i-1];
                    end
                end

                if (`AXIS_LAST(result_internal)) begin
                    compute_state_d = IDLE;
                    done_d = 1'b1;
                end
            end

            default: ;
        endcase
    end

endmodule
`endif  // RSDPG
