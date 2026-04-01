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

module fifo
    import common_pkg::max;
#(
    parameter int DEPTH = 32
)
(
    input logic clk,
    input logic rst_n,

    AXIS.slave  s_axis,
    AXIS.master m_axis
);
    if (s_axis.DATA_WIDTH != m_axis.DATA_WIDTH)
        $error("s_axis.DATA_WDITH and m_axis.DATA_WIDTH must be equal!");

    localparam int unsigned DEPTH_BITS = (DEPTH == 1) ? 1 : $clog2(DEPTH);
    localparam int unsigned WIDTH = s_axis.DATA_WIDTH;
    localparam int unsigned W_KEEP = max(WIDTH/8, 1);

    /* Memory stores WIDTH data bits plus the upper KEEP-1 bits of tkeep */
    logic [WIDTH+W_KEEP-1:0] mem [DEPTH];
    logic [DEPTH_BITS-1:0] wr_ptr;
    logic [DEPTH_BITS-1:0] rd_ptr;
    logic [DEPTH_BITS:0] ctr;
    logic full, empty;

    assign full = (ctr >= (DEPTH_BITS+1)'(DEPTH));
    assign empty = (ctr == (DEPTH_BITS+1)'(0));


    /* Asynchronous read */
    /* Suitable for small memories using distributed memory */
    assign m_axis.tdata     = mem[rd_ptr][0 +: WIDTH];
    assign m_axis.tvalid    = ~empty;
    assign s_axis.tready    = ~full;


    if (WIDTH <= 8) begin : no_tkeep

        assign m_axis.tkeep = 1'b1;
        assign m_axis.tlast = mem[rd_ptr][WIDTH];

        /* Memory management */
        always_ff @(posedge clk)
            if (s_axis.tvalid && s_axis.tready)
                mem[wr_ptr] <= {s_axis.tlast, s_axis.tdata};

    end else begin : store_tkeep

        assign m_axis.tkeep = {mem[rd_ptr][WIDTH +: W_KEEP-1], 1'b1};
        assign m_axis.tlast = mem[rd_ptr][WIDTH+W_KEEP-1];

        /* Memory management */
        always_ff @(posedge clk)
            if (s_axis.tvalid && s_axis.tready)
                mem[wr_ptr] <= {s_axis.tlast, s_axis.tkeep[1 +: W_KEEP-1], s_axis.tdata};
    end


    /* Write control */
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else begin
            if (s_axis.tvalid && s_axis.tready) begin
                if (wr_ptr >= DEPTH_BITS'(DEPTH - 1))
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + DEPTH_BITS'(1);
            end
        end
    end

    /* Read control */
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else begin
            if (m_axis.tvalid && m_axis.tready) begin
                if (rd_ptr >= DEPTH_BITS'(DEPTH - 1))
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + DEPTH_BITS'(1);
            end
        end
    end

    /* Entry counter */
    /* Increase if data is written but not read */
    /* Decrease if data is read but not written */
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            ctr <= '0;
        end else begin
            if ( (s_axis.tvalid && s_axis.tready) && !(m_axis.tvalid && m_axis.tready) ) begin
                ctr <= ctr + (DEPTH_BITS+1)'(1);
            end
            if ( !(s_axis.tvalid && s_axis.tready) && (m_axis.tvalid && m_axis.tready) ) begin
                ctr <= ctr - (DEPTH_BITS+1)'(1);
            end
        end
    end

endmodule
