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

module stree_su_intf
#(
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 10,
    localparam int unsigned W_FCNT = $clog2(2 + 1)
)
(
    input logic clk,
    input logic rst_n,

    // Special control signals
    input logic stree_sign_done,
    input logic stree_vrfy_addr_is_path, // verify only, node is moved from signature to sample unit
    input logic stree_vrfy_copy_leaf,

    // Connections to Seed tree memory
    output logic                                mem_en,
    output logic [ADDR_WIDTH-1:0]               mem_addr,
    output logic [DATA_WIDTH/8-1:0]             mem_we,
    output logic [DATA_WIDTH+DATA_WIDTH/8-1:0]  mem_wdata,
    input logic [DATA_WIDTH+DATA_WIDTH/8-1:0]   mem_rdata,

    // Connections to stree_addr
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

    logic [ADDR_WIDTH-1:0] base_addr;
    logic base_addr_we, base_addr_valid;
    logic [W_FCNT-1:0] base_addr_frame_cnt;

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_mux_0[2](), s_axis_mux_1[2](), m_axis_demux[2](), m_axis_demux_0[2]();
    AXIS #(.DATA_WIDTH(DATA_WIDTH)) s_axis_adapter(), m_axis_adapter();

    //-----------------------------------------------
    // MUX for m_axis
    //-----------------------------------------------
    logic sel_m_axis_mux;
    assign sel_m_axis_mux = stree_vrfy_addr_is_path & ctrl_addr_valid;
    axis_mux
    #(
        .N_SLAVES ( 2 )
    )
    u_m_axis_mux
    (
        .sel    ( sel_m_axis_mux    ),
        .s_axis ( s_axis_mux_0      ),
        .m_axis ( m_axis            )
    );
    `AXIS_ASSIGN( s_axis_mux_0[1], m_axis_demux[0] );

    //-----------------------------------------------
    // MUX for s_axis
    //-----------------------------------------------
    logic sel_s_axis_mux;
    assign sel_s_axis_mux = stree_vrfy_copy_leaf & ctrl_addr_valid;
    axis_mux
    #(
        .N_SLAVES ( 2 )
    )
    u_s_axis_mux
    (
        .sel    ( sel_s_axis_mux    ),
        .s_axis ( s_axis_mux_1      ),
        .m_axis ( s_axis_adapter    )
    );
    `AXIS_ASSIGN( s_axis_mux_1[0], s_axis );
    `AXIS_ASSIGN( s_axis_mux_1[1], m_axis_demux[1] );

    //-----------------------------------------------
    // DEMUX for s_axis
    //-----------------------------------------------
    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_s_axis_sig_demux
    (
        .sel    ( sel_s_axis_mux    ),
        .s_axis ( s_axis_sig_ctrl   ),
        .m_axis ( m_axis_demux      )
    );

    //-----------------------------------------------
    // DEMUX for m_axis
    //-----------------------------------------------
    axis_demux
    #(
        .N_MASTERS ( 2 )
    )
    u_axis_demux_0
    (
        .sel    ( stree_sign_done   ),
        .s_axis ( m_axis_adapter    ),
        .m_axis ( m_axis_demux_0    )
    );
    // 1 -> to signature, 0 -> to m_axis
    `AXIS_ASSIGN( m_axis_sig_ctrl, m_axis_demux_0[1] );
    `AXIS_ASSIGN( s_axis_mux_0[0], m_axis_demux_0[0] );

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
    u_stree_mem_adapter
    (
        .clk,
        .rst_n,
        .base_addr              ( base_addr             ),
        .base_addr_valid        ( base_addr_valid && !stree_vrfy_addr_is_path ),
        .base_addr_wr_rd        ( base_addr_we          ),
        .base_addr_frame_cnt    ( base_addr_frame_cnt   ),
        .mem_en                 ( mem_en                ),
        .mem_we                 ( mem_we                ),
        .mem_addr               ( mem_addr              ),
        .mem_wdata              ( mem_wdata             ),
        .mem_rdata              ( mem_rdata             ),
        .s_axis                 ( s_axis_adapter        ),
        .m_axis                 ( m_axis_adapter        )
    );

    //-----------------------------------------------
    // MUX for memory adapter access
    //-----------------------------------------------
    assign base_addr            = stree_sign_done ? sig_addr            : ctrl_addr;
    assign base_addr_valid      = stree_sign_done ? sig_addr_valid      : ctrl_addr_valid;
    assign base_addr_we         = stree_sign_done ? sig_addr_we         : ctrl_addr_we;
    assign base_addr_frame_cnt  = stree_sign_done ? sig_addr_frame_cnt  : ctrl_addr_frame_cnt;

    assign sig_addr_ready       = `AXIS_LAST(m_axis_sig_ctrl);
    assign ctrl_addr_ready      = ctrl_addr_we ? `AXIS_LAST(s_axis_adapter) : `AXIS_LAST(m_axis);

endmodule
