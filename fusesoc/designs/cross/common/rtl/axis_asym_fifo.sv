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

module axis_asym_fifo
    import common_pkg::*;
#(
    parameter int WIDTH        = 32,
    parameter int IN_BLOCK_SZ  = 9,
    parameter int OUT_BLOCK_SZ = 7
) (
    input  logic       clk_i,
    input  logic       rst_n,
    input  logic       clear_i,
    output logic       empty_o,
    output logic       full_o,
           AXIS.slave  s_axis,
           AXIS.master m_axis
);
    localparam int unsigned LCM_BLOCKS = lcm(IN_BLOCK_SZ, OUT_BLOCK_SZ);
    localparam int unsigned ITERS = LCM_BLOCKS / OUT_BLOCK_SZ;
    typedef int unsigned offsets_t[ITERS];

    generate
        if (IN_BLOCK_SZ == OUT_BLOCK_SZ) begin : gen_passthrough

            `AXIS_ASSIGN(m_axis, s_axis);
            assign empty_o = 1'b1;
            assign full_o  = 1'b0;

        end else if (IN_BLOCK_SZ % OUT_BLOCK_SZ == 0) begin : gen_fifo_0

            width_converter #(
                .ELEM_WIDTH(WIDTH)
            ) conv_i (
                .axis_aclk(clk_i),
                .axis_rst_n(rst_n),
                .s_axis(s_axis),
                .m_axis(m_axis)
            );
            assign empty_o = 1'b1;
            assign full_o  = 1'b0;

        end else if (IN_BLOCK_SZ > OUT_BLOCK_SZ) begin : gen_fifo_1
            localparam int unsigned BUF_SZ = 2;
            localparam int unsigned CTR_MAX = LCM_BLOCKS;

            localparam int unsigned IDX_CTR_SZ = $clog2(CTR_MAX);
            localparam int unsigned ITER_CTR_SZ = $clog2(ITERS);
            localparam int unsigned OFFSETS[ITERS] = compute_offset_table(ITERS);

            AXIS #(
                .DATA_WIDTH(WIDTH * OUT_BLOCK_SZ),
                .ELEM_WIDTH(WIDTH)
            ) m_axis_internal ();

            axis_reg #(
                .ELEM_WIDTH(WIDTH),
                .SPILL_REG (1)
            ) u_m_axis_reg (
                .clk(clk_i),
                .rst_n(rst_n),
                .s_axis(m_axis_internal),
                .m_axis(m_axis)
            );

            typedef enum logic [2:0] {
                IDLE = 0,
                WAIT,
                COMPUTE,
                FILL,
                SYNC
            } fsm_state_t;
            fsm_state_t r_state_d, r_state_q;
            fsm_state_t w_state_d, w_state_q;

            logic [IDX_CTR_SZ-1:0] r_ctr_d, r_ctr_q;
            logic [IDX_CTR_SZ-1:0] w_ctr_d, w_ctr_q;
            logic [ITER_CTR_SZ-1:0] ctr_d, ctr_q;
            logic [IDX_CTR_SZ-1:0] r_ctr_next, w_ctr_next;
            logic [ITER_CTR_SZ-1:0] ctr_next;

            logic [BUF_SZ*IN_BLOCK_SZ*WIDTH-1:0] data_buffer;
            logic [BUF_SZ*IN_BLOCK_SZ-1:0] keep_buffer;
            logic [BUF_SZ-1:0][IN_BLOCK_SZ-1:0][WIDTH-1:0] data_d, data_q;
            logic [BUF_SZ-1:0][IN_BLOCK_SZ-1:0] keep_d, keep_q;
            logic [ITERS-1:0][OUT_BLOCK_SZ-1:0][WIDTH-1:0] mux_data;
            logic [ITERS-1:0][OUT_BLOCK_SZ:0] mux_keep;
            logic shift_buffers;

            always_ff @(`REG_SENSITIVITY_LIST) begin
                if (!rst_n) begin
                    r_ctr_q   <= 'b0;
                    w_ctr_q   <= 'b0;
                    ctr_q     <= 'b0;
                    data_q    <= 'b0;
                    keep_q    <= 'b0;
                    r_state_q <= IDLE;
                    w_state_q <= IDLE;
                end else begin
                    if (clear_i) begin
                        r_ctr_q   <= '0;
                        keep_q    <= '0;
                        r_state_q <= IDLE;
                    end else begin
                        r_ctr_q   <= r_ctr_d;
                        keep_q    <= keep_d;
                        r_state_q <= r_state_d;
                    end
                    w_ctr_q   <= w_ctr_d;
                    ctr_q     <= ctr_d;
                    data_q    <= data_d;
                    w_state_q <= w_state_d;
                end
            end

            assign data_buffer = data_q;
            assign keep_buffer = keep_q;
            assign shift_buffers = OFFSETS[ctr_next] < IDX_CTR_SZ'(OUT_BLOCK_SZ);
            assign full_o = r_ctr_q > w_ctr_d;
            assign empty_o = r_ctr_q == w_ctr_q;

            assign r_ctr_next = (r_ctr_q + IDX_CTR_SZ'(IN_BLOCK_SZ) == IDX_CTR_SZ'(CTR_MAX)) ? IDX_CTR_SZ'(0) : r_ctr_q + IDX_CTR_SZ'(IN_BLOCK_SZ);
            assign w_ctr_next = (w_ctr_q + IDX_CTR_SZ'(OUT_BLOCK_SZ) == IDX_CTR_SZ'(CTR_MAX)) ? IDX_CTR_SZ'(0) : w_ctr_q + IDX_CTR_SZ'(OUT_BLOCK_SZ);
            assign ctr_next = (w_ctr_q + IDX_CTR_SZ'(OUT_BLOCK_SZ) == IDX_CTR_SZ'(CTR_MAX)) ? ITER_CTR_SZ'(0) : ctr_q + 1;

            assign m_axis_internal.tdata = mux_data[ctr_q];
            assign m_axis_internal.tkeep = OUT_BLOCK_SZ'(mux_keep[ctr_q]);

            for (genvar i = 0; i < ITERS; i++) begin : gen_mux_data
                assign mux_data[i] = (OUT_BLOCK_SZ * WIDTH)'(data_buffer >> (OFFSETS[i] * WIDTH));
                assign mux_keep[i] = (OUT_BLOCK_SZ + 1)'(keep_buffer >> OFFSETS[i]);
            end

            always_comb begin
                r_ctr_d       = r_ctr_q;
                data_d        = data_q;
                keep_d        = keep_q;
                r_state_d     = r_state_q;
                s_axis.tready = 1'b0;

                unique case (r_state_q)
                    IDLE: begin
                        s_axis.tready = m_axis_internal.tready;
                        if (`AXIS_TRANS(s_axis)) begin
                            data_d[1] = s_axis.tdata;
                            data_d[0] = data_q[1];
                            keep_d[1] = s_axis.tkeep;
                            keep_d[0] = keep_q[1];
                            r_ctr_d   = r_ctr_next;
                            if (`AXIS_LAST(s_axis)) begin
                                r_state_d = FILL;
                            end else begin
                                r_state_d = WAIT;
                            end
                        end
                    end

                    WAIT: begin
                        s_axis.tready = 1'b1;  // force another request to fill the buffer
                        if (`AXIS_TRANS(s_axis)) begin
                            data_d[1] = s_axis.tdata;
                            data_d[0] = data_q[1];
                            keep_d[1] = s_axis.tkeep;
                            keep_d[0] = keep_q[1];
                            r_ctr_d   = r_ctr_next;
                            if (`AXIS_LAST(s_axis)) begin
                                r_state_d = SYNC;
                            end else begin
                                r_state_d = COMPUTE;
                            end
                        end
                    end

                    COMPUTE: begin
                        s_axis.tready = m_axis_internal.tready && shift_buffers;
                        if (`AXIS_TRANS(s_axis)) begin
                            data_d[1] = s_axis.tdata;
                            data_d[0] = data_q[1];
                            keep_d[1] = s_axis.tkeep;
                            keep_d[0] = keep_q[1];
                            r_ctr_d   = r_ctr_next;
                        end
                        if (`AXIS_LAST(s_axis)) begin
                            r_state_d = SYNC;
                        end
                    end

                    FILL: begin
                        r_state_d = SYNC;
                        data_d[1] = s_axis.tdata;
                        data_d[0] = data_q[1];
                        keep_d[1] = 'b0;
                        keep_d[0] = keep_q[1];
                        r_ctr_d   = r_ctr_next;
                    end

                    SYNC: begin
                        if (m_axis_internal.tready && shift_buffers) begin
                            data_d[1] = 'b0;
                            data_d[0] = data_q[1];
                            keep_d[1] = 'b0;
                            keep_d[0] = keep_q[1];
                        end
                        if (`AXIS_LAST(m_axis_internal)) begin
                            r_state_d = IDLE;
                            r_ctr_d   = IDX_CTR_SZ'(0);
                        end
                    end

                    default: ;

                endcase
            end

            always_comb begin
                if (clear_i) begin : write_fsm
                    w_ctr_d                = 'b0;
                    ctr_d                  = ITER_CTR_SZ'(0);
                    w_state_d              = IDLE;
                    m_axis_internal.tvalid = 1'b0;
                    m_axis_internal.tlast  = 1'b0;
                end else begin
                    w_ctr_d                = w_ctr_q;
                    ctr_d                  = ctr_q;
                    w_state_d              = w_state_q;
                    m_axis_internal.tvalid = 1'b0;
                    m_axis_internal.tlast  = 1'b0;

                    unique case (w_state_q)
                        IDLE: begin
                            if (`AXIS_TRANS(s_axis)) begin
                                w_state_d = WAIT;
                            end
                        end

                        WAIT: begin
                            if (`AXIS_TRANS(s_axis) || (r_state_q == FILL)) begin
                                w_state_d = COMPUTE;
                            end
                        end

                        COMPUTE: begin
                            m_axis_internal.tvalid = s_axis.tvalid || (r_state_q == SYNC);
                            if (r_state_q == SYNC) begin
                                m_axis_internal.tlast = !mux_keep[ctr_q][OUT_BLOCK_SZ];
                            end
                            if (`AXIS_TRANS(m_axis_internal)) begin
                                w_ctr_d = w_ctr_next;
                                ctr_d   = ctr_next;
                            end
                            if (`AXIS_LAST(m_axis_internal)) begin
                                w_state_d = IDLE;
                                ctr_d     = ITER_CTR_SZ'(0);
                                w_ctr_d   = IDX_CTR_SZ'(0);
                            end
                        end

                        default: ;

                    endcase
                end
            end

        end else begin : gen_fifo_2
            $error("Unimplemented case!");
        end

    endgenerate

    function automatic offsets_t compute_offset_table(input int unsigned blocks);
        for (int unsigned i = 0; i < blocks; i++) begin
            compute_offset_table[i] = (i * OUT_BLOCK_SZ) % IN_BLOCK_SZ;
        end
    endfunction

endmodule
