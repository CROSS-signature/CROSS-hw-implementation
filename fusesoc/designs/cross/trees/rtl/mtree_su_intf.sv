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

module mtree_su_intf
#(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 10,
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    // Special control signals
    input logic mtree_sign_done,
    input logic mtree_vrfy_addr_is_proof,

    // Connections to Merkle tree memory
    output logic                                mem_en,
    output logic [ADDR_WIDTH-1:0]               mem_addr,
    output logic [DATA_WIDTH/8-1:0]             mem_we,
    output logic [DATA_WIDTH+DATA_WIDTH/8-1:0]  mem_wdata,
    input logic [DATA_WIDTH+DATA_WIDTH/8-1:0]   mem_rdata,

    // Connections to mtree_addr
    input logic [ADDR_WIDTH-1:0]                ctrl_addr,
    input logic                                 ctrl_addr_we,
    input logic                                 ctrl_addr_valid,
    output logic                                ctrl_addr_ready,
    input logic [W_FCNT-1:0]                    ctrl_addr_frame_cnt,

    // Connections from signature controller
    input logic [ADDR_WIDTH-1:0]                sig_addr,
    input logic                                 sig_addr_we,
    input logic                                 sig_addr_valid,
    output logic                                sig_addr_ready,
    input logic [W_FCNT-1:0]                    sig_addr_frame_cnt,

    // Connection to/from signature controller
    AXIS.slave s_axis_sig_ctrl,
    AXIS.master m_axis_sig_ctrl,

    // Connection from sample unit
    AXIS.slave s_axis,

    // Connection to sample unit
    AXIS.master m_axis
);

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_adapter(), m_axis_adapter();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_demux[2](), s_axis_mux[2]();

    logic [ADDR_WIDTH-1:0] base_addr;
    logic base_addr_we, base_addr_valid;
    logic [W_FCNT-1:0] base_addr_frame_cnt;


    //-----------------------------------------------
    // MUX for m_axis
    //-----------------------------------------------
    logic sel_axis_mux;
    axis_mux
    #(
        .N_SLAVES ( 2 )
    )
    u_axis_mux
    (
        .sel    ( sel_axis_mux  ),
        .s_axis ( s_axis_mux    ),
        .m_axis ( m_axis        )
    );

    // 1 -> from signature, 0 -> from memory
    assign sel_axis_mux = mtree_vrfy_addr_is_proof & ctrl_addr_valid;
    `AXIS_ASSIGN( s_axis_mux[1], s_axis_sig_ctrl );
    `AXIS_ASSIGN( s_axis_mux[0], m_axis_demux[0] );

    //-----------------------------------------------
    // DEMUX for m_axis
    //-----------------------------------------------
    logic sel_axis_demux;
    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_axis_demux
    (
        .sel    ( sel_axis_demux    ),
        .s_axis ( m_axis_adapter    ),
        .m_axis ( m_axis_demux      )
    );
    // 1 -> to signature, 0 -> to sampler
    assign sel_axis_demux = mtree_sign_done;
    `AXIS_ASSIGN(m_axis_sig_ctrl, m_axis_demux[1]);

    //-----------------------------------------------
    // MEMORY ADAPTER
    //-----------------------------------------------
    axis_ram_adapter
    #(
        .MEM_DW             ( DATA_WIDTH + DATA_WIDTH/8 ),
        .MEM_AW             ( ADDR_WIDTH                ),
        .AXIS_DW            ( DATA_WIDTH                ),
        .FRAME_CNT_WIDTH    ( W_FCNT                    )
    )
    u_mtree_mem_adapter
    (
        .clk,
        .rst_n,
        .base_addr              ( base_addr             ),
        .base_addr_valid        ( base_addr_valid && !mtree_vrfy_addr_is_proof ),
        .base_addr_wr_rd        ( base_addr_we          ),
        .base_addr_frame_cnt    ( base_addr_frame_cnt   ),
        .mem_en                 ( mem_en                ),
        .mem_we                 ( mem_we                ),
        .mem_addr               ( mem_addr              ),
        .mem_wdata              ( mem_wdata             ),
        .mem_rdata              ( mem_rdata             ),
        .s_axis                 ( s_axis                ),
        .m_axis                 ( m_axis_adapter        )
    );

    //-----------------------------------------------
    // MUX for memory adapter access
    //-----------------------------------------------
    assign base_addr            = mtree_sign_done ? sig_addr            : ctrl_addr;
    assign base_addr_valid      = mtree_sign_done ? sig_addr_valid      : ctrl_addr_valid;
    assign base_addr_we         = mtree_sign_done ? sig_addr_we         : ctrl_addr_we;
    assign base_addr_frame_cnt  = mtree_sign_done ? sig_addr_frame_cnt  : ctrl_addr_frame_cnt;

    assign sig_addr_ready       = `AXIS_LAST(m_axis_sig_ctrl);
    assign ctrl_addr_ready      = ctrl_addr_we ? `AXIS_LAST(s_axis) : `AXIS_LAST(m_axis);

endmodule
