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
// @author: Patrick Karl <patrick.karl@tum.de>

`timescale 1ps / 1ps
`include "axis_intf.svh"

module cross_alu_wrapper
    import arithmetic_unit_pkg::arithmetic_op_t;
#(
    parameter int unsigned DW = 64,
    parameter int unsigned MAT_DATA_WIDTH = 712
)
(
    input logic             clk,
    input logic             rst_n,

    input arithmetic_op_t   op,
    input logic             op_start,
    output logic            op_done,

    input logic             sel_mux_i1,
    input logic [1:0]       sel_mux_i2,
    input logic             sel_mux_i3,
    input logic             sel_demux_o0,

    AXIS.slave s_axis_i0,
    AXIS.slave s_axis_mux_i1[2],
    AXIS.slave s_axis_mux_i2[3],
    AXIS.slave s_axis_mux_i3[2],
    AXIS.slave s_axis_i4,
    AXIS.slave s_axis_i5,

    AXIS.master m_axis_o0[2],
    AXIS.master m_axis_o1,
    AXIS.master m_axis_o2
);

    AXIS #(.DATA_WIDTH(DW)) s_axis_i1(), s_axis_i1_int(), s_axis_i2(), s_axis_i2_int(), s_axis_i3(), s_axis_i3_int(),
        s_axis_demux_o0(), m_axis_o2_int(), s_axis_i5_int(), m_axis_o0_int[2]();

    localparam int unsigned FZ_PER_WORD = DW / cross_pkg::BITS_Z;
    localparam int unsigned WORDS_FZ_VEC = (cross_pkg::DIM_FZ + FZ_PER_WORD - 1) / FZ_PER_WORD;

    `ifdef RSDP
    localparam int unsigned FP_PER_WORD = DW / cross_pkg::BITS_P;
    localparam int unsigned DEPTH_FIFO_SYND =  (cross_pkg::N - cross_pkg::K + FP_PER_WORD - 1) / FP_PER_WORD;
    `endif

    //-------------------------------------------------
    // ALU instance
    //-------------------------------------------------
    arithmetic_unit
    #(
        .STREAM_WIDTH   ( DW    ),
        .MAT_DATA_WIDTH ( MAT_DATA_WIDTH )
    )
    u_alu
    (
        .clk_i      ( clk               ),
        .rst_n      ( rst_n             ),
        .op_i       ( op                ),
        .start_i    ( op_start          ),
        .done_o     ( op_done           ),
        .in_0       ( s_axis_i0         ),
        .in_1       ( s_axis_i1         ),
        .in_2       ( s_axis_i2         ),
        .in_3       ( s_axis_i3         ),
    `ifdef RSDPG
        .in_4       ( s_axis_i4         ),
    `endif
        .in_5       ( s_axis_i5_int     ),
        .out_0      ( s_axis_demux_o0   ),
        .out_1      ( m_axis_o1         ),
        .out_2      ( m_axis_o2_int     )
    );

    //-------------------------------------------------
    // FIFO for o2
    //-------------------------------------------------
    fifo #( .DEPTH(WORDS_FZ_VEC) )
    u_fifo_o2
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_o2_int ),
        .m_axis ( m_axis_o2     )
    );

    //-------------------------------------------------
    // MUXES and DEMUXES
    //-------------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_mux_i1
    (
        .sel    ( sel_mux_i1        ),
        .s_axis ( s_axis_mux_i1     ),
        .m_axis ( s_axis_i1_int     )
    );
    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_mux_i1 (
        .clk,
        .rst_n,
        .s_axis ( s_axis_i1_int     ),
        .m_axis ( s_axis_i1         )
    );

    axis_mux #( .N_SLAVES(3) )
    u_mux_i2
    (
        .sel    ( sel_mux_i2        ),
        .s_axis ( s_axis_mux_i2     ),
        .m_axis ( s_axis_i2_int     )
    );
    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_mux_i2 (
        .clk,
        .rst_n,
        .s_axis ( s_axis_i2_int ),
        .m_axis ( s_axis_i2     )
    );

    axis_mux #( .N_SLAVES(2) )
    u_mux_i3
    (
        .sel    ( sel_mux_i3        ),
        .s_axis ( s_axis_mux_i3     ),
        .m_axis ( s_axis_i3_int     )
    );
    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_mux_i3 (
        .clk,
        .rst_n,
        .s_axis ( s_axis_i3_int ),
        .m_axis ( s_axis_i3     )
    );

    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_mux_i5 (
        .clk,
        .rst_n,
        .s_axis ( s_axis_i5     ),
        .m_axis ( s_axis_i5_int )
    );

    axis_demux #( .N_MASTERS(2) )
    u_demux_o0
    (
        .sel    ( sel_demux_o0      ),
        .s_axis ( s_axis_demux_o0   ),
        .m_axis ( m_axis_o0_int     )
    );

    `AXIS_ASSIGN(m_axis_o0[0], m_axis_o0_int[0]);
    assign m_axis_o0[0].tuser = m_axis_o0_int[0].tuser;

`ifdef RSDP
    // This fifo does not store tuser, but we dont need it here
    fifo #( .DEPTH(DEPTH_FIFO_SYND) )
    u_fifo_o0_1
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_o0_int[1]  ),
        .m_axis ( m_axis_o0[1]      )
    );
`else
    `AXIS_ASSIGN(m_axis_o0[1], m_axis_o0_int[1]);
    assign m_axis_o0[1].tuser = m_axis_o0_int[1].tuser;
`endif


endmodule
