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

module axis_ram_adapter
#(
    parameter int unsigned MEM_DW = 64,
    parameter int unsigned MEM_AW = 16,
    parameter int unsigned AXIS_DW = 64,
    parameter int unsigned FRAME_CNT_WIDTH = 8,
    localparam int unsigned WE_WIDTH = AXIS_DW / 8
)
(
    input logic clk,
    input logic rst_n,

    input logic [MEM_AW-1:0]            base_addr,
    input logic                         base_addr_valid,
    input logic                         base_addr_wr_rd, // 0 = read, 1 = write
    input logic [FRAME_CNT_WIDTH-1:0]   base_addr_frame_cnt,

    output logic                mem_en,
    output logic [WE_WIDTH-1:0] mem_we,
    output logic [MEM_AW-1:0]   mem_addr,
    output logic [MEM_DW-1:0]   mem_wdata,
    input logic [MEM_DW-1:0]    mem_rdata,

    AXIS.slave s_axis,
    AXIS.master m_axis
);
    logic [AXIS_DW+AXIS_DW/8-1:0] m_axis_tdata_q;
    logic [MEM_AW-1:0] base_addr_q;

    //TODO: check whether we can decrease the size here
    localparam int unsigned W_ACNT = MEM_AW;
    logic [W_ACNT-1:0] addr_cnt;

    logic [FRAME_CNT_WIDTH-1:0] n_frames_q, frame_cnt;

    // State definitions
    typedef enum logic [1:0] {S_IDLE, S_RAMP_UP, S_READ, S_WRITE} state_t;
    state_t state, n_state;

    assign mem_en       = base_addr_valid || ( state == S_RAMP_UP || state == S_READ || state == S_WRITE );

    // Allows to change base address as soon as transfer is initiated
    always_comb begin
        if (state == S_IDLE) begin
            mem_addr = `AXIS_TRANS(m_axis) ? base_addr + MEM_AW'(addr_cnt) + MEM_AW'(1) : base_addr + MEM_AW'(addr_cnt);
        end else begin
            mem_addr = `AXIS_TRANS(m_axis) ? base_addr_q + MEM_AW'(addr_cnt) + MEM_AW'(1) : base_addr_q + MEM_AW'(addr_cnt);
        end
    end

    // Always set all we bits to 1 such that we can properly use the parity
    // bits
    assign mem_we       = (state == S_WRITE) ? {(WE_WIDTH){s_axis.tvalid}} : '0;
    assign mem_wdata    = {s_axis.tkeep[1 +: AXIS_DW/8-1], s_axis.tlast, s_axis.tdata};

    assign s_axis.tready = ( state == S_WRITE );

    assign m_axis.tdata = m_axis_tdata_q[0 +: AXIS_DW];
    assign m_axis.tkeep = {m_axis_tdata_q[AXIS_DW+1 +: AXIS_DW/8-1], 1'b1};
    assign m_axis.tvalid = ( state == S_READ );
    assign m_axis.tlast = m_axis_tdata_q[AXIS_DW];


    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb
    begin
        n_state = state;
        unique case(state)
            S_IDLE: begin
                if ( base_addr_valid ) begin
                    if ( base_addr_wr_rd ) begin
                        n_state = S_WRITE;
                    end else begin
                        n_state = S_RAMP_UP;
                    end
                end
            end
            S_RAMP_UP: begin
                n_state = S_READ;
            end
            S_READ: begin
                if ( `AXIS_LAST(m_axis) && frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                    n_state = S_IDLE;
                end
            end
            S_WRITE: begin
                if ( `AXIS_LAST(s_axis) && frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end

    // Output register for data in memory for data lookahead
    // to enable proper handshaking.
    always_ff @(posedge clk) begin
        if (state == S_RAMP_UP) begin
            m_axis_tdata_q <= mem_rdata;
        end else begin
            if ( `AXIS_TRANS(m_axis) ) begin
                m_axis_tdata_q <= mem_rdata;
            end
        end
    end

    always_ff @(posedge clk) begin
		if (state == S_IDLE) begin
            if (base_addr_valid) begin
                n_frames_q  <= base_addr_frame_cnt;
                base_addr_q <= base_addr;
            end
        end
    end

    //-----------------------------------------------
    // Counter for address incrementation
    //-----------------------------------------------
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            addr_cnt <= '0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (base_addr_valid && !base_addr_wr_rd) begin
                        addr_cnt <= addr_cnt + W_ACNT'(1);
                    end
                end
                S_READ: begin
                    if ( `AXIS_TRANS(m_axis) ) begin
                        if (m_axis.tlast && frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                            addr_cnt <= '0;
                        end else begin
                            addr_cnt <= addr_cnt + W_ACNT'(1);
                        end
                    end
                end
                S_WRITE: begin
                    if ( `AXIS_TRANS(s_axis) ) begin
                        if (s_axis.tlast && frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                            addr_cnt <= '0;
                        end else begin
                            addr_cnt <= addr_cnt + W_ACNT'(1);
                        end
                    end
                end

                default: begin
                    addr_cnt <= addr_cnt;
                end
            endcase
        end
    end

    // Count the number of frames to prevent complex address generation
    // in CROSS top-level
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            frame_cnt <= '0;
        end else begin
            unique case(state)
                S_READ: begin
                    if ( `AXIS_LAST(m_axis) ) begin
                        if (frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                            frame_cnt <= '0;
                        end else begin
                            frame_cnt <= frame_cnt + FRAME_CNT_WIDTH'(1);
                        end
                    end
                end
                S_WRITE: begin
                    if ( `AXIS_LAST(s_axis) ) begin
                        if (frame_cnt >= n_frames_q - FRAME_CNT_WIDTH'(1)) begin
                            frame_cnt <= '0;
                        end else begin
                            frame_cnt <= frame_cnt + FRAME_CNT_WIDTH'(1);
                        end
                    end
                end
                default: begin
                    frame_cnt <= frame_cnt;
                end
            endcase
        end
    end

endmodule
