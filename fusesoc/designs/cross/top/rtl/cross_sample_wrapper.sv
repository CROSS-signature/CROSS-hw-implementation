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

module cross_sample_wrapper
    import sample_unit_pkg::*;
    import cross_pkg::MAX_DIGESTS;
#(
    parameter int unsigned DW = 64,
    parameter int unsigned KECCAK_UNROLL_FACTOR = 1,
    localparam int unsigned W_TRANS = $clog2(MAX_DIGESTS) + 1
)
(
    input logic clk,
    input logic rst_n,

    input sample_op_t           op,
    input logic                 op_valid,
    output logic                op_ready,
    output logic                busy,

    input digest_t              digest_type,
    input logic [W_TRANS-1:0]   n_digests,

    input logic [3-1:0] sel_mux,
    AXIS.slave s_axis_mux[7],

    input logic sel_demux_i0,
    AXIS.master m_axis_pack,

    input logic sel_demux_o0,
    AXIS.master m_axis_o0[2],

    input logic [1:0] sel_demux_o1,
    AXIS.master m_axis_o1[4],

    AXIS.master m_axis_b,
    AXIS.master m_axis_w,
    AXIS.master m_axis_v_beta
);

    AXIS #(.DATA_WIDTH(DW)) s_axis_int(), s_axis_demux_o0(), s_axis_demux_o1(), s_axis_demux_o1_int();
    AXIS #(.DATA_WIDTH(DW)) m_axis_mux(), m_axis_pack_int();
    AXIS #(.DATA_WIDTH(DW)) m_axis_demux_i0[2](), m_axis_mux_int();

    //-------------------------------------------------
    // SAMPLE UNIT instance
    //-------------------------------------------------
    sample_unit
    #(
        .KECCAK_UNROLL_FACTOR(KECCAK_UNROLL_FACTOR)
    )
    u_sample_unit
    (
        .clk,
        .rst_n,
        .mode           ( op                ),
        .mode_valid     ( op_valid          ),
        .mode_ready     ( op_ready          ),
        .busy           ( busy              ),
        .digest_type    ( digest_type       ),
        .n_digests      ( n_digests         ),
        .s_axis         ( s_axis_int        ),
        .m_axis_0       ( s_axis_demux_o0   ),
        .m_axis_1       ( s_axis_demux_o1_int   ),
        .m_axis_b       ( m_axis_b          ),
        .m_axis_w       ( m_axis_w          ),
        .m_axis_v_beta  ( m_axis_v_beta     )
    );


    //-------------------------------------------------
    // PACKING UNIT instance
    //-------------------------------------------------
    packing_unit
    u_packing_unit
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_mux        ),
        .m_axis ( m_axis_pack_int   )
    );


    //-------------------------------------------------
    // MUXES and DEMUXES
    //-------------------------------------------------
    axis_demux #( .N_MASTERS(2) )
    u_demux_o0
    (
        .sel    ( sel_demux_o0      ),
        .s_axis ( s_axis_demux_o0   ),
        .m_axis ( m_axis_o0         )
    );

    axis_demux #( .N_MASTERS(4) )
    u_demux_o1
    (
        .sel    ( sel_demux_o1      ),
        .s_axis ( s_axis_demux_o1   ),
        .m_axis ( m_axis_o1         )
    );
    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_demux (
        .clk,
        .rst_n,
        .s_axis ( s_axis_demux_o1_int   ),
        .m_axis ( s_axis_demux_o1       )
    );

    axis_mux #( .N_SLAVES(7) )
    u_mux
    (
        .sel    ( sel_mux           ),
        .s_axis ( s_axis_mux        ),
        .m_axis ( m_axis_mux_int    )
    );

    axis_reg #(
        .ELEM_WIDTH(8),
        .SPILL_REG(1)
    ) u_reg_mux (
        .clk,
        .rst_n,
        .s_axis ( m_axis_mux_int   ),
        .m_axis ( m_axis_mux       )
    );

    axis_demux #( .N_MASTERS(2) )
    u_demux_i0
    (
        .sel    ( sel_demux_i0      ),
        .s_axis ( m_axis_pack_int   ),
        .m_axis ( m_axis_demux_i0   )
    );

    axis_reg #( .SPILL_REG(1) )
    u_reg_demux_bp
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_demux_i0[0]    ),
        .m_axis ( m_axis_pack           )
    );

    `AXIS_ASSIGN(s_axis_int, m_axis_demux_i0[1]);
    assign s_axis_int.tuser = m_axis_demux_i0[1].tuser;

endmodule
