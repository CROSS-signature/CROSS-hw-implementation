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

module exp_vector
    import common_pkg::*;
    import cross_pkg::*;
#(
    parameter int IN_TDATA_WIDTH  = 64,
    parameter int OUT_TDATA_WIDTH = 64,
    parameter bit PARALLEL_IMPL   = 1'b1
) (
    input  logic       clk_i,
    input  logic       rst_n,
    input  logic       start_i,
    output logic       done_o,
           AXIS.slave  op,
           AXIS.master res
);

    localparam int IN_KEEP = `NON_NEG_MSB(ifloorfrac(IN_TDATA_WIDTH, BITS_Z));
    localparam int OUT_KEEP = `NON_NEG_MSB(ifloorfrac(OUT_TDATA_WIDTH, BITS_P));

    generate
        if (PARALLEL_IMPL) begin : gen_parallel_impl
            localparam int PARALLEL_UNITS = OUT_KEEP;

            AXIS #(
                .DATA_WIDTH(PARALLEL_UNITS * BITS_Z),
                .ELEM_WIDTH(BITS_Z)
            ) op_internal ();

            logic [PARALLEL_UNITS-1:0][BITS_P-1:0] res_tdata;
            logic fifo_empty;
            logic fifo_full;
            logic fifo_clear;
            logic running_d, running_q;

            always_ff @(`REG_SENSITIVITY_LIST) begin
                if (!rst_n) begin
                    running_q <= 1'b0;
                end else begin
                    running_q <= running_d;
                end
            end

            always_comb begin
                running_d = running_q;
                if (done_o) begin
                    running_d = 1'b0;
                end
                if (start_i) begin
                    running_d = 1'b1;
                end
            end

            `ASSERT(start_fifo_not_empty, start_i |-> fifo_empty)
            `ASSERT(fifo_used_while_not_started, !fifo_empty |-> running_q)

            // use a FIFO with asymmetric read and write ports to remove the complexity
            // of misaligned data read
            axis_asym_fifo #(
                .WIDTH(BITS_Z),
                .IN_BLOCK_SZ(IN_KEEP),
                .OUT_BLOCK_SZ(OUT_KEEP)
            ) axis_asym_fifo_i (
                .clk_i  (clk_i),
                .rst_n  (rst_n),
                .clear_i(fifo_clear),
                .empty_o(fifo_empty),
                .full_o (fifo_full),
                .m_axis (op_internal),
                .s_axis (op)
            );

            AXIS #(
                .DATA_WIDTH(OUT_TDATA_WIDTH),
                .ELEM_WIDTH(BITS_P)
            ) res_internal ();

            axis_reg #(
                .ELEM_WIDTH(BITS_P),
                .SPILL_REG (1)
            ) u_axis_out_reg (
                .clk(clk_i),
                .rst_n(rst_n),
                .s_axis(res_internal),
                .m_axis(res)
            );

            for (genvar i = 0; i < PARALLEL_UNITS; i++) begin : gen_lookup_tables
                assign res_tdata[i] = TAB_EXP[op_internal.tdata[i*BITS_Z+:BITS_Z]];
            end

            assign done_o = `AXIS_LAST(res);
            assign fifo_clear = done_o;

            assign op_internal.tready = running_q && res_internal.tready;

            assign res_internal.tdata = res_tdata;
            assign res_internal.tkeep = op_internal.tkeep;
            assign res_internal.tlast = op_internal.tlast;
            assign res_internal.tvalid = op_internal.tvalid;

        end else begin : gen_sequential_impl

            localparam int IN_CTR_SZ = $clog2(IN_KEEP + 1);
            localparam int OUT_CTR_SZ = $clog2(OUT_KEEP + 1);

            logic started_d, started_q;
            logic ended_d, ended_q;
            logic compute;

            logic [IN_CTR_SZ-1:0] in_ctr_d, in_ctr_q;
            logic [OUT_CTR_SZ-1:0] out_ctr_d, out_ctr_q;

            logic [IN_KEEP-1:0][BITS_Z-1:0] op_tdata_d, op_tdata_q;
            logic [IN_KEEP-1:0] op_tkeep_d, op_tkeep_q;

            logic [OUT_KEEP-1:0][BITS_P-1:0] res_tdata_d, res_tdata_q;
            logic [OUT_KEEP-1:0] res_tkeep_d, res_tkeep_q;
            logic res_tvalid_d, res_tvalid_q;
            logic res_tlast_d, res_tlast_q;

            always_ff @(`REG_SENSITIVITY_LIST) begin
                if (!rst_n) begin
                    op_tdata_q <= 'b0;
                    op_tkeep_q <= 'b0;
                    //
                    res_tdata_q <= 'b0;
                    res_tkeep_q <= 'b0;
                    res_tvalid_q <= 1'b0;
                    res_tlast_q <= 1'b0;
                    //
                    in_ctr_q <= IN_CTR_SZ'(0);
                    out_ctr_q <= OUT_CTR_SZ'(0);
                    started_q <= 1'b0;
                    ended_q <= 1'b0;
                end else begin
                    op_tdata_q <= op_tdata_d;
                    op_tkeep_q <= op_tkeep_d;
                    //
                    res_tdata_q <= res_tdata_d;
                    res_tkeep_q <= res_tkeep_d;
                    res_tvalid_q <= res_tvalid_d;
                    res_tlast_q <= res_tlast_d;
                    //
                    in_ctr_q <= in_ctr_d;
                    out_ctr_q <= out_ctr_d;
                    started_q <= started_d;
                    ended_q <= ended_d;
                end
            end

            assign op.tready = started_q && (in_ctr_q == IN_CTR_SZ'(0));
            assign res_tvalid_d = compute && (out_ctr_q == OUT_CTR_SZ'(OUT_KEEP - 1));
            assign res_tlast_d = ended_q && res_tvalid_d && (in_ctr_q == IN_CTR_SZ'(0));
            assign ended_d = start_i ? 1'b0 : (ended_q | `AXIS_LAST(op));
            assign done_o = res_tlast_q;
            assign started_d = done_o ? 1'b0 : (started_q | start_i);
            assign compute = ((in_ctr_q != 0) || ended_q) && (out_ctr_q != OUT_CTR_SZ'(OUT_KEEP));

            assign res.tdata = res_tdata_q;
            assign res.tkeep = res_tkeep_q;
            assign res.tlast = res_tlast_q;
            assign res.tvalid = res_tvalid_q;

            always_comb begin : module_logic
                in_ctr_d = in_ctr_q;
                out_ctr_d = out_ctr_q;

                op_tkeep_d = op_tkeep_q;
                op_tdata_d = op_tdata_q;

                res_tdata_d = res_tdata_q;
                res_tkeep_d = res_tkeep_q;

                if (compute) begin  // compute
                    // shifting the input buffer towards 0 index
                    in_ctr_d = in_ctr_q - 1;
                    op_tkeep_d[IN_KEEP-1] = 1'b0;
                    op_tdata_d[IN_KEEP-1] = 'b0;
                    for (int i = 0; i < IN_KEEP - 1; i++) begin
                        op_tkeep_d[i] = op_tkeep_q[i+1];
                        op_tdata_d[i] = op_tdata_q[i+1];
                    end

                    // shifting the output buffer towards 0 index
                    out_ctr_d = out_ctr_q + 1;
                    res_tkeep_d[OUT_KEEP-1] = op_tkeep_q[0];
                    // use the look-up table for the exponentiation result computation
                    res_tdata_d[OUT_KEEP-1] = TAB_EXP[op_tdata_q[0]];
                    for (int i = 0; i < OUT_KEEP - 1; i++) begin
                        res_tkeep_d[i] = res_tkeep_q[i+1];
                        res_tdata_d[i] = res_tdata_q[i+1];
                    end
                end

                if (`AXIS_TRANS(op)) begin
                    in_ctr_d   = IN_CTR_SZ'(IN_KEEP);
                    op_tkeep_d = op.tkeep;
                    op_tdata_d = op.tdata;
                end
                if (`AXIS_TRANS(res)) begin
                    out_ctr_d   = OUT_CTR_SZ'(0);
                    res_tkeep_d = 'b0;
                    // res_tdata_d = 'b0;
                end
            end
        end  // gen_sequential_impl
    endgenerate

endmodule
