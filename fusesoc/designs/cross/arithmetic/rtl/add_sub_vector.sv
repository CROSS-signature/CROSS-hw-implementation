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

module add_sub_vector
    import common_pkg::*;
    import arithmetic_unit_pkg::add_sub_select_t;
#(
    parameter int unsigned TDATA_WIDTH = 64,
    parameter int unsigned MODULO      = cross_pkg::P
) (
    input  logic            clk_i,
    input  logic            rst_n,
    input  add_sub_select_t op_i,
    output logic            done_o,
           AXIS.slave       op1,
           AXIS.slave       op2,
           AXIS.master      res
);

    localparam int unsigned ELEM_WIDTH = $clog2(MODULO);
    localparam int unsigned UNITS = ifloorfrac(TDATA_WIDTH, ELEM_WIDTH);
    localparam int unsigned INFO_WIDTH = UNITS * ELEM_WIDTH;
    localparam int unsigned KEEP_WIDTH = `NON_NEG_MSB(UNITS);

    AXIS #(
        .DATA_WIDTH(TDATA_WIDTH),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) res_internal ();

    logic [UNITS-1:0][ELEM_WIDTH-1:0] op1_tdata;
    logic [UNITS-1:0][ELEM_WIDTH-1:0] op2_tdata;
    logic [UNITS-1:0][ELEM_WIDTH-1:0] res_tdata;
    logic [UNITS-1:0] valid_segments;
    logic [UNITS-1:0] req_int;

    `ASSERT(not_equally_long_vectors, `AXIS_LAST(op1) == `AXIS_LAST(op2))
    `ASSERT(operands_with_equal_size, (`AXIS_TRANS(op1) && `AXIS_TRANS(op2)
                                      ) |-> (op1.tkeep == op2.tkeep))


    /////////////////////////// in-flight modulo operations ///////////////////////////
    assign op1_tdata  = INFO_WIDTH'(op1.tdata);
    assign op1.tready = op2.tvalid & res_internal.tready;

    assign op2_tdata  = INFO_WIDTH'(op2.tdata);
    assign op2.tready = op1.tvalid & res_internal.tready;


    axis_reg #(
        .SPILL_REG (1),
        .ELEM_WIDTH(ELEM_WIDTH)
    ) u_axis_out_reg (
        .clk   (clk_i),
        .rst_n (rst_n),
        .s_axis(res_internal),
        .m_axis(res)
    );

    assign res_internal.tdata = TDATA_WIDTH'(res_tdata);
    assign res_internal.tkeep = KEEP_WIDTH'(valid_segments);
    assign res_internal.tvalid = |valid_segments;  // This is some kind of violation here
    assign res_internal.tlast =
        `AXIS_LAST(op1)
        &&
        `AXIS_LAST(op2);  // eventually needs a register if add_sub is pipelined
    assign done_o = res.tvalid & res.tlast;

    generate
        for (genvar i = 0; i < UNITS; i++) begin : gen_add_sub_segments
            add_sub #(
                .MODULO(MODULO)
            ) add_sub_i (
                .clk_i,
                .rst_n,
                .op1_i  (op1_tdata[i]),
                .op2_i  (op2_tdata[i]),
                .op_i   (op_i),
                .res_o  (res_tdata[i]),
                .req_i  (req_int[i]),
                .valid_o(valid_segments[i])
            );
            assign req_int[i] =
                `AXIS_TRANS(op1)
                &&
                `AXIS_TRANS(op2)
                && (op1.tkeep[i] & op2.tkeep[i]);
        end
    endgenerate

endmodule
