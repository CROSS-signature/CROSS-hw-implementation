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
`include "memctrl_intf.svh"

module cross_mem_wrapper
    import cross_memory_map_pkg::*;
    import common_pkg::max;
#(
  parameter int unsigned DW = 64
)
(
    input logic clk,
    input logic rst_n,

    // MEM0
    MEMCTRL.device      ctrl_mem0[2],
    input logic [1:0]   sel_demux0_mem0,
    AXIS.master         m_axis_demux0_mem0[3],

    input logic [1:0]   sel_demux1_mem0,
    AXIS.master         m_axis_demux1_mem0[3],

    input logic [1:0]   sel_mux0_mem0,
    AXIS.slave          s_axis_mux0_mem0[3],

    input logic [1:0]   sel_mux1_mem0,
    AXIS.slave          s_axis_mux1_mem0[3],

    // MEM1
    MEMCTRL.device      ctrl_mem1[2],
    input logic [1:0]   sel_demux0_mem1,
    AXIS.master         m_axis_demux0_mem1[3],

    input logic [1:0]   sel_mux0_mem1,
    AXIS.slave          s_axis_mux0_mem1[3],

    // SIGMEM
    MEMCTRL.device      ctrl_sigmem[2],
    AXIS.master         m_axis_demux0_sigmem,

    input logic         sel_demux1_sigmem,
    AXIS.master         m_axis_demux1_sigmem[2],

    input logic         sel_mux0_sigmem,
    AXIS.slave          s_axis_mux0_sigmem[2],

    input logic         sel_mux1_sigmem,
    AXIS.slave          s_axis_mux1_sigmem[2]
);

    // MEM0 connections (MEM0_AW and MEM0_DEPTH defined in memory_map_pkg)
    localparam int unsigned MEM0_PORTS = 2;
    localparam int unsigned MEM0_W_FCNT = max(cross_pkg::BITS_T + 1, $clog2(5+2*cross_pkg::TREE_NODES_TO_STORE));

    AXIS #(.DATA_WIDTH(DW)) s_axis_mem0_int[MEM0_PORTS](), m_axis_mem0_int[MEM0_PORTS]();

    logic               mem0_en[MEM0_PORTS];
    logic [DW/8-1:0]    mem0_we[MEM0_PORTS];
    logic [MEM0_AW-1:0] mem0_addr[MEM0_PORTS];
    logic [DW+DW/8-1:0] mem0_wdata[MEM0_PORTS];
    logic [DW+DW/8-1:0] mem0_rdata[MEM0_PORTS];

    // MEM1 connections (MEM1_AW and MEM1_DEPTH defined in memory_map_pkg)
    localparam int unsigned MEM1_PORTS = 2;
    localparam int unsigned MEM1_W_FCNT = cross_pkg::BITS_T+1;

    AXIS #(.DATA_WIDTH(DW)) s_axis_mem1_int[MEM1_PORTS](), m_axis_mem1_int[MEM1_PORTS]();

    logic               mem1_en[MEM1_PORTS];
    logic [DW/8-1:0]    mem1_we[MEM1_PORTS];
    logic [MEM1_AW-1:0] mem1_addr[MEM1_PORTS];
    logic [DW+DW/8-1:0] mem1_wdata[MEM1_PORTS];
    logic [DW+DW/8-1:0] mem1_rdata[MEM1_PORTS];

    // SIGMEM connections (SIGMEM_AW and SIGMEM_DEPTH defined in memory_map_pkg)
    localparam int unsigned SIGMEM_PORTS = 2;
    localparam int unsigned SIGMEM_W_FCNT = max(cross_pkg::BITS_T + 1, $clog2(3+2*cross_pkg::TREE_NODES_TO_STORE+(cross_pkg::T-cross_pkg::W)+1));

    AXIS #(.DATA_WIDTH(DW)) s_axis_sigmem_int[SIGMEM_PORTS](), m_axis_sigmem_int[SIGMEM_PORTS]();

    logic                   sigmem_en[SIGMEM_PORTS];
    logic [DW/8-1:0]        sigmem_we[SIGMEM_PORTS];
    logic [SIGMEM_AW-1:0]   sigmem_addr[SIGMEM_PORTS];
    logic [DW+DW/8-1:0]     sigmem_wdata[SIGMEM_PORTS];
    logic [DW+DW/8-1:0]     sigmem_rdata[SIGMEM_PORTS];


    //-------------------------------------------------
    // MEM ADAPTER INSTANCES
    //-------------------------------------------------
    generate
        // MEM0 PORTS
        for (genvar i=0; i<MEM0_PORTS; i++) begin
            axis_ram_adapter
            #(
                .MEM_DW             ( DW + DW/8     ),
                .MEM_AW             ( MEM0_AW       ),
                .AXIS_DW            ( DW            ),
                .FRAME_CNT_WIDTH    ( MEM0_W_FCNT   )
            )
            u_mem0_adapter
            (
                .clk,
                .rst_n,
                .base_addr              ( ctrl_mem0[i].addr         ),
                .base_addr_valid        ( ctrl_mem0[i].addr_valid   ),
                .base_addr_wr_rd        ( ctrl_mem0[i].we           ),
                .base_addr_frame_cnt    ( ctrl_mem0[i].fcnt         ),
                .mem_en                 ( mem0_en[i]                ),
                .mem_we                 ( mem0_we[i]                ),
                .mem_addr               ( mem0_addr[i]              ),
                .mem_wdata              ( mem0_wdata[i]             ),
                .mem_rdata              ( mem0_rdata[i]             ),
                .s_axis                 ( s_axis_mem0_int[i]        ),
                .m_axis                 ( m_axis_mem0_int[i]        )
            );
        end

        // SIGMEM PORTS
        for (genvar i=0; i<SIGMEM_PORTS; i++) begin
            axis_ram_adapter
            #(
                .MEM_DW             ( DW + DW/8     ),
                .MEM_AW             ( SIGMEM_AW     ),
                .AXIS_DW            ( DW            ),
                .FRAME_CNT_WIDTH    ( SIGMEM_W_FCNT )
            )
            u_sigmem_adapter
            (
                .clk,
                .rst_n,
                .base_addr              ( ctrl_sigmem[i].addr           ),
                .base_addr_valid        ( ctrl_sigmem[i].addr_valid     ),
                .base_addr_wr_rd        ( ctrl_sigmem[i].we             ),
                .base_addr_frame_cnt    ( ctrl_sigmem[i].fcnt           ),
                .mem_en                 ( sigmem_en[i]                  ),
                .mem_we                 ( sigmem_we[i]                  ),
                .mem_addr               ( sigmem_addr[i]                ),
                .mem_wdata              ( sigmem_wdata[i]               ),
                .mem_rdata              ( sigmem_rdata[i]               ),
                .s_axis                 ( s_axis_sigmem_int[i]          ),
                .m_axis                 ( m_axis_sigmem_int[i]          )
            );
        end

        // MEM1 MEMORY
        for (genvar i=0; i<MEM1_PORTS; i++) begin
            axis_ram_adapter
            #(
                .MEM_DW             ( DW + DW/8     ),
                .MEM_AW             ( MEM1_AW       ),
                .AXIS_DW            ( DW            ),
                .FRAME_CNT_WIDTH    ( MEM1_W_FCNT   )
            )
            u_mem1_adapter
            (
                .clk,
                .rst_n,
                .base_addr              ( ctrl_mem1[i].addr         ),
                .base_addr_valid        ( ctrl_mem1[i].addr_valid   ),
                .base_addr_wr_rd        ( ctrl_mem1[i].we           ),
                .base_addr_frame_cnt    ( ctrl_mem1[i].fcnt         ),
                .mem_en                 ( mem1_en[i]                ),
                .mem_we                 ( mem1_we[i]                ),
                .mem_addr               ( mem1_addr[i]              ),
                .mem_wdata              ( mem1_wdata[i]             ),
                .mem_rdata              ( mem1_rdata[i]             ),
                .s_axis                 ( s_axis_mem1_int[i]        ),
                .m_axis                 ( m_axis_mem1_int[i]        )
            );
        end
    endgenerate

    // For MEM1, parts of the ports are unused as we employ only 1 read and 1 write port
    assign s_axis_mem1_int[0].tvalid = 1'b0;
    assign m_axis_mem1_int[1].tready = 1'b0;

    //-------------------------------------------------
    // MEMORY INSTANCES
    //-------------------------------------------------
    dp_ram_parity
    #(
        .PARITY_WIDTH   ( DW/8          ),
        .DATA_WIDTH     ( DW + DW/8     ),
        .DEPTH          ( MEM0_DEPTH    )
    )
    u_mem0
    (
        .clk_a      ( clk           ),
        .en_a_i     ( mem0_en[0]    ),
        .we_a_i     ( mem0_we[0]    ),
        .addr_a_i   ( mem0_addr[0]  ),
        .wdata_a_i  ( mem0_wdata[0] ),
        .rdata_a_o  ( mem0_rdata[0] ),
        .clk_b      ( clk           ),
        .en_b_i     ( mem0_en[1]    ),
        .we_b_i     ( mem0_we[1]    ),
        .addr_b_i   ( mem0_addr[1]  ),
        .wdata_b_i  ( mem0_wdata[1] ),
        .rdata_b_o  ( mem0_rdata[1] )
    );

    dp_ram_parity
    #(
        .PARITY_WIDTH   ( DW/8          ),
        .DATA_WIDTH     ( DW + DW/8     ),
        .DEPTH          ( SIGMEM_DEPTH  )
    )
    u_sigmem
    (
        .clk_a      ( clk               ),
        .en_a_i     ( sigmem_en[0]      ),
        .we_a_i     ( sigmem_we[0]      ),
        .addr_a_i   ( sigmem_addr[0]    ),
        .wdata_a_i  ( sigmem_wdata[0]   ),
        .rdata_a_o  ( sigmem_rdata[0]   ),
        .clk_b      ( clk               ),
        .en_b_i     ( sigmem_en[1]      ),
        .we_b_i     ( sigmem_we[1]      ),
        .addr_b_i   ( sigmem_addr[1]    ),
        .wdata_b_i  ( sigmem_wdata[1]   ),
        .rdata_b_o  ( sigmem_rdata[1]   )
    );

    dp_ram_parity
    #(
        .PARITY_WIDTH   ( DW/8          ),
        .DATA_WIDTH     ( DW + DW/8     ),
        .DEPTH          ( MEM1_DEPTH    )
    )
    u_mem1
    (
        .clk_a      ( clk           ),
        .en_a_i     ( mem1_en[0]    ),
        .we_a_i     ( mem1_we[0]    ),
        .addr_a_i   ( mem1_addr[0]  ),
        .wdata_a_i  ( mem1_wdata[0] ),
        .rdata_a_o  ( mem1_rdata[0] ),
        .clk_b      ( clk           ),
        .en_b_i     ( mem1_en[1]    ),
        .we_b_i     ( mem1_we[1]    ),
        .addr_b_i   ( mem1_addr[1]  ),
        .wdata_b_i  ( mem1_wdata[1] ),
        .rdata_b_o  ( mem1_rdata[1] )
    );


    //-------------------------------------------------
    // Corresponding MUXES and DEMUXES
    //-------------------------------------------------

    // -----
    // MEM0
    // -----
    axis_demux #( .N_MASTERS(3) )
    u_demux0_mem0
    (
        .sel    ( sel_demux0_mem0       ),
        .s_axis ( m_axis_mem0_int[0]    ),
        .m_axis ( m_axis_demux0_mem0    )
    );

    axis_demux #( .N_MASTERS(3) )
    u_demux1_mem0
    (
        .sel    ( sel_demux1_mem0       ),
        .s_axis ( m_axis_mem0_int[1]    ),
        .m_axis ( m_axis_demux1_mem0    )
    );

    axis_mux #( .N_SLAVES(3) )
    u_mux0_mem0
    (
        .sel    ( sel_mux0_mem0         ),
        .s_axis ( s_axis_mux0_mem0      ),
        .m_axis ( s_axis_mem0_int[0]    )
    );

    axis_mux #( .N_SLAVES(3) )
    u_mux1_mem0
    (
        .sel    ( sel_mux1_mem0         ),
        .s_axis ( s_axis_mux1_mem0      ),
        .m_axis ( s_axis_mem0_int[1]    )
    );

    // -----
    // MEM1
    // -----

    axis_demux #( .N_MASTERS(3) )
    u_demux0_mem1
    (
        .sel    ( sel_demux0_mem1       ),
        .s_axis ( m_axis_mem1_int[0]    ),
        .m_axis ( m_axis_demux0_mem1    )
    );

    axis_mux #( .N_SLAVES(3) )
    u_mux0_mem1
    (
        .sel    ( sel_mux0_mem1         ),
        .s_axis ( s_axis_mux0_mem1      ),
        .m_axis ( s_axis_mem1_int[1]    )
    );


    // -----
    // SIGMEM
    // -----

    // Mimick a demux that is actually not present
    // for mental convenience
    `AXIS_ASSIGN( m_axis_demux0_sigmem, m_axis_sigmem_int[0] );

    axis_demux #( .N_MASTERS(2) )
    u_demux1_sigmem
    (
        .sel    ( sel_demux1_sigmem     ),
        .s_axis ( m_axis_sigmem_int[1]  ),
        .m_axis ( m_axis_demux1_sigmem  )
    );

    axis_mux #( .N_SLAVES(2) )
    u_mux0_sigmem
    (
        .sel    ( sel_mux0_sigmem       ),
        .s_axis ( s_axis_mux0_sigmem    ),
        .m_axis ( s_axis_sigmem_int[0]  )
    );

    axis_mux #( .N_SLAVES(2) )
    u_mux1_sigmem
    (
        .sel    ( sel_mux1_sigmem       ),
        .s_axis ( s_axis_mux1_sigmem    ),
        .m_axis ( s_axis_sigmem_int[1]  )
    );

endmodule
