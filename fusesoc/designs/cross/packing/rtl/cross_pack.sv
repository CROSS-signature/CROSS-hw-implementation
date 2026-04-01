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

/*
* s_axis.tuser[2:1] -> 0 - pass, 1 - Fz alignment, 2 - Fp alignment,
    * 3 - s alignment (syndrome)
*/

`timescale 1ps / 1ps
`include "axis_intf.svh"

module cross_pack
    import packing_unit_pkg::*;
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    if (s_axis.DATA_WIDTH != m_axis.DATA_WIDTH)
        $error("s_axis.DATA_WIDTH and m_axis.DATA_WIDTH must be equal.");

    if (s_axis.DATA_WIDTH != 64)
        $error("This module only works for a data width of 64, otherwise more sophisticated mechanism is required.");

    if (s_axis.TUSER_WIDTH < 3)
        $error("s_axis.TUSER_WIDTH must be >= 3, LSB is indicating last frame, \
                remaining two bits the field size of the input stream.");

    if (m_axis.TUSER_WIDTH < 1)
        $error("m_axis.TUSER_WIDTH must be >= 1, LSB is indicating last frame of input stream.");

    localparam int unsigned DW = s_axis.DATA_WIDTH;

    localparam int unsigned FZ_PAD_BITS = DW % cross_pkg::BITS_Z;
    localparam int unsigned FZ_CYCLES_IN = (cross_pkg::DIM_FZ * cross_pkg::BITS_Z + DW-FZ_PAD_BITS-1) / (DW-FZ_PAD_BITS);
    localparam int unsigned FZ_CYCLES_OUT = (cross_pkg::DIM_FZ * cross_pkg::BITS_Z + DW-1) / DW;
    localparam int unsigned FZ_BYTES_LAST = (((cross_pkg::DIM_FZ * cross_pkg::BITS_Z) % DW) + 7) / 8;
    localparam logic [DW/8-1:0] FZ_KEEP_LAST = {{(DW/8 - FZ_BYTES_LAST){1'b0}}, {FZ_BYTES_LAST{1'b1}}};
    localparam int unsigned FZ_CNT_CYCLES = DW-FZ_PAD_BITS;

    localparam int unsigned FP_PAD_BITS = DW % cross_pkg::BITS_P;
    localparam int unsigned FP_CYCLES_IN = (cross_pkg::N * cross_pkg::BITS_P + DW-FP_PAD_BITS-1) / (DW-FP_PAD_BITS);
    localparam int unsigned FP_CYCLES_OUT = (cross_pkg::N * cross_pkg::BITS_P + DW-1) / DW;
    localparam int unsigned FP_BYTES_LAST = (((cross_pkg::N * cross_pkg::BITS_P) % DW) + 7) / 8;
    localparam logic [DW/8-1:0] FP_KEEP_LAST = {{(DW/8 - FP_BYTES_LAST){1'b0}}, {FP_BYTES_LAST{1'b1}}};
    localparam int unsigned FP_CNT_CYCLES = DW-FP_PAD_BITS;

    localparam int unsigned SYN_CYCLES_IN = ((cross_pkg::N-cross_pkg::K) * cross_pkg::BITS_P + DW-FP_PAD_BITS-1) / (DW-FP_PAD_BITS);
    localparam int unsigned SYN_CYCLES_OUT = ((cross_pkg::N-cross_pkg::K) * cross_pkg::BITS_P + DW-1) / DW;
    localparam int unsigned SYN_BYTES_LAST = ((((cross_pkg::N-cross_pkg::K) * cross_pkg::BITS_P) % DW) + 7) / 8;
    localparam logic [DW/8-1:0] SYN_KEEP_LAST = {{(DW/8 - SYN_BYTES_LAST){1'b0}}, {SYN_BYTES_LAST{1'b1}}};

    typedef enum logic [2:0] {S_IDLE, S_PASSTHROUGH, S_FZ, S_FP, S_LAST_FZ, S_LAST_FP, S_SYN, S_LAST_SYN} fsm_state_t;
    fsm_state_t n_state, state;

    localparam int unsigned FZ_BITS_LAST = (cross_pkg::DIM_FZ*cross_pkg::BITS_Z) % DW;
    localparam int unsigned FP_BITS_LAST = (cross_pkg::N*cross_pkg::BITS_P) % DW;
    localparam int unsigned SYN_BITS_LAST = ((cross_pkg::N-cross_pkg::K)*cross_pkg::BITS_P) % DW;
    logic [DW-1:0] fz_mask, fp_mask, syn_mask;
    logic [DW-1:0] dreg, packed_tdata;
    logic ureg;

    localparam int unsigned W_CNT = $clog2(DW);
    logic [W_CNT-1:0] cnt;

    logic passthrough, pack_fz, pack_fp, pack_s;

    /* The endianess swap is only required when packing fz, fp or syndrome */
    assign m_axis.tdata = passthrough ? s_axis.tdata : packed_tdata;

    /* Combining latched data with corresponding data of current slice */
    always_comb begin
        unique  if (pack_fz) packed_tdata = (dreg | (s_axis.tdata << (W_CNT'(DW) - W_CNT'(FZ_PAD_BITS)*cnt))) & fz_mask;
        else    if (pack_fp) packed_tdata = (dreg | (s_axis.tdata << (W_CNT'(DW) - W_CNT'(FP_PAD_BITS)*cnt))) & fp_mask;
        else                 packed_tdata = (dreg | (s_axis.tdata << (W_CNT'(DW) - W_CNT'(FP_PAD_BITS)*cnt))) & syn_mask;
    end

    assign fz_mask = m_axis.tlast ? {{(DW-FZ_BITS_LAST){1'b0}}, {FZ_BITS_LAST{1'b1}}} : '1;
    assign fp_mask = m_axis.tlast ? {{(DW-FP_BITS_LAST){1'b0}}, {FP_BITS_LAST{1'b1}}} : '1;
    assign syn_mask = m_axis.tlast ? {{(DW-SYN_BITS_LAST){1'b0}}, {SYN_BITS_LAST{1'b1}}} : '1;

    /* Register for storing the unsent portion for each cycle */
    always_ff @(posedge clk)
    begin
        if ( `AXIS_TRANS(s_axis) ) begin
            if (pack_fz)    dreg <= (s_axis.tdata >> (cnt * W_CNT'(FZ_PAD_BITS)));
            else            dreg <= (s_axis.tdata >> (cnt * W_CNT'(FP_PAD_BITS)));
            ureg <= s_axis.tuser[0];
        end
    end

    /* Just some control signal to detect the mode */
    assign passthrough = ( (state == S_IDLE && s_axis.tvalid && s_axis.tuser[2:1] == M_PASSTHROUGH) || (state == S_PASSTHROUGH) ) ;
    assign pack_fz = ( (state == S_IDLE && s_axis.tvalid && s_axis.tuser[2:1] == M_PACK_FZ) || (state == S_FZ) || (state == S_LAST_FZ) );
    assign pack_fp = ( (state == S_IDLE && s_axis.tvalid && s_axis.tuser[2:1] == M_PACK_FP) || (state == S_FP) ||  (state == S_LAST_FP) );
    assign pack_s = ( (state == S_IDLE && s_axis.tvalid && s_axis.tuser[2:1] == M_PACK_S) || (state == S_SYN) || (state == S_LAST_SYN) );

    /* AXIS mux */
    always_comb begin
        s_axis.tready = 1'b0;
        m_axis.tkeep = '1;
        m_axis.tvalid = s_axis.tvalid;
        m_axis.tlast = s_axis.tlast;
        m_axis.tuser[0] = s_axis.tuser[0];
        case (state)
            S_IDLE: begin
                if ( s_axis.tvalid ) begin
                    if ( passthrough ) begin
                        m_axis.tkeep = s_axis.tkeep;
                        s_axis.tready = m_axis.tready;
                    end else begin
                        m_axis.tvalid = s_axis.tlast;
                        s_axis.tready = 1'b1;
                    end
                end
            end
            S_PASSTHROUGH: begin
                m_axis.tkeep = s_axis.tkeep;
                s_axis.tready = m_axis.tready;
            end

            S_FZ: begin
                s_axis.tready = m_axis.tready;
                m_axis.tlast = (FZ_CYCLES_OUT > FZ_CYCLES_IN - 1) ? 1'b0 : s_axis.tlast;
            end

            S_FP: begin
                s_axis.tready = m_axis.tready;
                m_axis.tlast = (FP_CYCLES_OUT > FP_CYCLES_IN - 1) ? 1'b0 : s_axis.tlast;
            end

            S_SYN: begin
                s_axis.tready = m_axis.tready;
                m_axis.tlast = (SYN_CYCLES_OUT > SYN_CYCLES_IN - 1) ? 1'b0 : s_axis.tlast;
            end

            S_LAST_FZ: begin
                m_axis.tkeep = FZ_KEEP_LAST;
                {m_axis.tvalid, m_axis.tlast} = '1;
                m_axis.tuser[0] = ureg;
            end

            S_LAST_FP: begin
                m_axis.tkeep = FP_KEEP_LAST;
                {m_axis.tvalid, m_axis.tlast} = '1;
                m_axis.tuser[0] = ureg;
            end

            S_LAST_SYN: begin
                m_axis.tkeep = SYN_KEEP_LAST;
                {m_axis.tvalid, m_axis.tlast} = '1;
                m_axis.tuser[0] = ureg;
            end

            default: begin
                s_axis.tready = 1'b0;
                m_axis.tkeep = '1;
                {m_axis.tvalid, m_axis.tlast} = '0;
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case (state)
            S_IDLE: begin
                if (s_axis.tvalid && !(`AXIS_LAST(m_axis))) begin
                    unique if (passthrough) n_state = S_PASSTHROUGH;
                    else if (pack_fz)       n_state = S_FZ;
                    else if (pack_fp)       n_state = S_FP;
                    else if (pack_s)        n_state = S_SYN;
                    else                    n_state = state;
                end
            end
            S_FZ: begin
                if ( `AXIS_LAST(s_axis) ) begin
                    /* We might need an extra cycle depending on vector length */
                    if ( FZ_CYCLES_OUT > FZ_CYCLES_IN - 1 )
                        n_state = S_LAST_FZ;
                    else
                        n_state = S_IDLE;
                end
            end
            S_FP: begin
                if ( `AXIS_LAST(s_axis) ) begin
                    if ( FP_CYCLES_OUT > FP_CYCLES_IN - 1 )
                        n_state = S_LAST_FP;
                    else
                        n_state = S_IDLE;
                end
            end
            S_SYN: begin
                if ( `AXIS_LAST(s_axis) ) begin
                    if ( SYN_CYCLES_OUT > SYN_CYCLES_IN - 1 )
                        n_state = S_LAST_SYN;
                    else
                        n_state = S_IDLE;
                end
            end
            S_LAST_FZ, S_LAST_FP, S_LAST_SYN, S_PASSTHROUGH: begin
                if ( `AXIS_LAST(m_axis) )
                    n_state = S_IDLE;
            end
            default: n_state = state;
        endcase
    end

    /* Counting the periodicity of the shifting for fz, fp and syndrome */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            cnt <= '0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if (pack_fz || pack_fp || pack_s) begin
                        if ( `AXIS_TRANS(s_axis) ) begin
                            if (m_axis.tlast)
                                cnt <= '0;
                            else
                                cnt <= cnt + W_CNT'(1);
                        end
                    end
                end
                S_FZ: begin
                    if ( `AXIS_TRANS(s_axis) ) begin
                        if (cnt >= W_CNT'(FZ_CNT_CYCLES - 1) || m_axis.tlast)
                            cnt <= '0;
                        else
                            cnt <= cnt + W_CNT'(1);
                    end
                end
                S_FP, S_SYN: begin
                    if ( `AXIS_TRANS(s_axis) ) begin
                        if (cnt >= W_CNT'(FP_CNT_CYCLES - 1) || m_axis.tlast)
                            cnt <= '0;
                        else
                            cnt <= cnt + W_CNT'(1);
                    end
                end
                S_LAST_FZ,
                S_LAST_FP,
                S_LAST_SYN: begin
                    if ( `AXIS_LAST(m_axis) ) begin
                        cnt <= '0;
                    end
                end
                default: begin
                    cnt <= '0;
                end
            endcase
        end
    end

endmodule
