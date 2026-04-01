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

/*
* s_axis.tuser[2:1] 1 - Fz alignment, 2 - Fp alignment,
    * 3 - s alignment (syndrome)
*/

`include "axis_intf.svh"
module cross_unpack
    import packing_unit_pkg::*;
(
    input logic clk,
    input logic rst_n,

    output logic fz_error,
    input logic fz_error_clear,

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

    import cross_pkg::BITS_Z;
    import cross_pkg::BITS_P;
    localparam int unsigned DW = s_axis.DATA_WIDTH;
    localparam int unsigned W_DW = $clog2(DW);

    localparam int unsigned FZ_PAD_BITS = DW % BITS_Z;
    localparam int unsigned FZ_CYCLES = (BITS_Z*cross_pkg::DIM_FZ + DW - FZ_PAD_BITS - 1 ) / (DW - FZ_PAD_BITS);
    localparam int unsigned FZ_BYTES_KEEP = (DW - FZ_PAD_BITS + 7) / 8;
    localparam int unsigned FZ_BYTES_KEEP_LAST = (((cross_pkg::DIM_FZ * BITS_Z) % (DW-FZ_PAD_BITS)) + 7) / 8;
    localparam logic [DW/8-1:0] FZ_KEEP = {{(DW/8 - FZ_BYTES_KEEP){1'b0}}, {FZ_BYTES_KEEP{1'b1}}};
    localparam logic [DW/8-1:0] FZ_KEEP_LAST = {{(DW/8 - FZ_BYTES_KEEP_LAST){1'b0}}, {FZ_BYTES_KEEP_LAST{1'b1}}};

    localparam int unsigned FZ_BITS_LAST = (cross_pkg::DIM_FZ*BITS_Z) % (DW-FZ_PAD_BITS);

    localparam int unsigned FP_PAD_BITS = DW % BITS_P;
    localparam int unsigned FP_CYCLES = (BITS_P*cross_pkg::N + DW - FP_PAD_BITS - 1 ) / (DW - FP_PAD_BITS);
    localparam int unsigned FP_BYTES_KEEP = (DW - FP_PAD_BITS + 7) / 8;
    localparam int unsigned FP_BYTES_KEEP_LAST = (((cross_pkg::N * BITS_P) % (DW-FP_PAD_BITS)) + 7) / 8;
    localparam logic [DW/8-1:0] FP_KEEP = {{(DW/8 - FP_BYTES_KEEP){1'b0}}, {FP_BYTES_KEEP{1'b1}}};
    localparam logic [DW/8-1:0] FP_KEEP_LAST = {{(DW/8 - FP_BYTES_KEEP_LAST){1'b0}}, {FP_BYTES_KEEP_LAST{1'b1}}};

    localparam int unsigned FP_BITS_LAST = (cross_pkg::N*BITS_P) % (DW-FP_PAD_BITS);

    localparam int unsigned SYN_CYCLES = (BITS_P*(cross_pkg::N-cross_pkg::K) + DW - FP_PAD_BITS - 1 ) / (DW - FP_PAD_BITS);
    localparam int unsigned SYN_BYTES_KEEP = (DW - FP_PAD_BITS + 7) / 8;
    localparam int unsigned SYN_BYTES_KEEP_LAST = ((((cross_pkg::N-cross_pkg::K) * BITS_P) % (DW-FP_PAD_BITS)) + 7) / 8;
    localparam logic [DW/8-1:0] SYN_KEEP = {{(DW/8 - SYN_BYTES_KEEP){1'b0}}, {SYN_BYTES_KEEP{1'b1}}};
    localparam logic [DW/8-1:0] SYN_KEEP_LAST = {{(DW/8 - SYN_BYTES_KEEP_LAST){1'b0}}, {SYN_BYTES_KEEP_LAST{1'b1}}};

    localparam int unsigned SYN_BITS_LAST = ((cross_pkg::N-cross_pkg::K)*BITS_P) % (DW-FP_PAD_BITS);

    logic [DW-1:0] fz_mask, fp_mask, syn_mask;

    typedef enum logic [1:0] {S_IDLE, S_FZ, S_FP, S_SYN} fsm_state_t;
    fsm_state_t n_state, state;

    localparam MAX_CYCLES = FZ_CYCLES >= FP_CYCLES ? ( FZ_CYCLES >= SYN_CYCLES ? FZ_CYCLES : SYN_CYCLES ) : (FP_CYCLES > SYN_CYCLES ) ? FP_CYCLES : SYN_CYCLES;
    localparam MAX_PAD_BITS = MAX_CYCLES == FZ_CYCLES ? FZ_CYCLES*FZ_PAD_BITS : ( MAX_CYCLES == FP_CYCLES ? FP_CYCLES*FP_PAD_BITS : SYN_CYCLES*FP_PAD_BITS );

    localparam DREG_WIDTH = MAX_PAD_BITS;
    logic [DREG_WIDTH-1:0] data_reg;
    logic [DW-1:0] data_concat;

    localparam int unsigned CNT_WIDTH = $clog2(MAX_CYCLES);
    logic [CNT_WIDTH-1:0] cnt;

    localparam int unsigned FZ_IN_WORD = (DW-FZ_PAD_BITS)/BITS_Z;
    logic [FZ_IN_WORD-1:0] fz_error_vec;

    logic send_tail, unp_fz, unp_fp, unp_s;

    /* The endianess swap is only required when packing fz, fp or syndrome */
    assign unp_fz = ( s_axis.tvalid && s_axis.tuser[2:1] == M_UNPACK_FZ );
    assign unp_fp = ( s_axis.tvalid && s_axis.tuser[2:1] == M_UNPACK_FP );
    assign unp_s = ( s_axis.tvalid && s_axis.tuser[2:1] == M_UNPACK_S );

    assign fz_mask = m_axis.tlast ? {{(DW-FZ_BITS_LAST){1'b0}}, {FZ_BITS_LAST{1'b1}}} : '1;
    assign fp_mask = m_axis.tlast ? {{(DW-FP_BITS_LAST){1'b0}}, {FP_BITS_LAST{1'b1}}} : '1;
    assign syn_mask = m_axis.tlast ? {{(DW-SYN_BITS_LAST){1'b0}}, {SYN_BITS_LAST{1'b1}}} : '1;

    // CHECK FOR PADDING ERROR
    // In case we unpack a vector that is supposed to be in fz, double check
    // that each element is really < z and thus, lives in subgroup G
    generate
        for (genvar i=0; i<FZ_IN_WORD; i++) begin
            assign fz_error_vec[i] = !( m_axis.tdata[BITS_Z*i +: BITS_Z] < (BITS_Z)'(cross_pkg::Z) );
        end
    endgenerate

    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            fz_error <= 1'b0;
        end else begin
            if (fz_error_clear) begin
                fz_error <= 1'b0;
            end else begin
                if ((unp_fz || state == S_FZ) && m_axis.tvalid) begin
                    fz_error <= fz_error | (|fz_error_vec);
                end
            end
        end
    end

    // DETECT TAIL
    // In general, we need more cycles to send uncompressed data
    // than to receive compressed data. Indicate this using a dedicated signal
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            send_tail <= 1'b0;
        end else begin
            if ( `AXIS_LAST(s_axis) ) send_tail <= 1'b1;
            if ( `AXIS_LAST(m_axis) ) send_tail <= 1'b0;
        end
    end

    // DATA ALIGNMENT
    // Some vodoo that aligns the data. Basically uses a register to store the
    // compressed part not being send in the current cycle, then concatenate
    // register with current input stream. Finally, apply zero padding and
    // mask it to the proper format used in the HW implementation.
    always_comb begin
        unique case (state)
            S_IDLE: begin
                unique  if (unp_fz) m_axis.tdata = {{FZ_PAD_BITS{1'b0}}, data_concat[0 +: DW-FZ_PAD_BITS]} & fz_mask;
                else    if (unp_fp) m_axis.tdata = {{FP_PAD_BITS{1'b0}}, data_concat[0 +: DW-FP_PAD_BITS]} & fp_mask;
                else                m_axis.tdata = {{FP_PAD_BITS{1'b0}}, data_concat[0 +: DW-FP_PAD_BITS]} & syn_mask;
            end
            S_FZ:   m_axis.tdata = {{FZ_PAD_BITS{1'b0}}, data_concat[0 +: DW-FZ_PAD_BITS]} & fz_mask;
            S_FP:   m_axis.tdata = {{FP_PAD_BITS{1'b0}}, data_concat[0 +: DW-FP_PAD_BITS]} & fp_mask;
            S_SYN:  m_axis.tdata = {{FP_PAD_BITS{1'b0}}, data_concat[0 +: DW-FP_PAD_BITS]} & syn_mask;
            default: m_axis.tdata = {{FZ_PAD_BITS{1'b0}}, data_concat[0 +: DW-FZ_PAD_BITS]} & fz_mask;
        endcase
    end

    always_comb begin
        unique case (state)
            S_IDLE: begin
                unique if (unp_fz)  data_concat = (s_axis.tdata << $clog2(DW)'(cnt*CNT_WIDTH'(FZ_PAD_BITS))) | DW'(data_reg);
                else                data_concat = (s_axis.tdata << $clog2(DW)'(cnt*CNT_WIDTH'(FP_PAD_BITS))) | DW'(data_reg);
            end
            S_FZ:           data_concat = (s_axis.tdata << $clog2(DW)'(cnt*CNT_WIDTH'(FZ_PAD_BITS))) | DW'(data_reg);
            S_FP, S_SYN:    data_concat = (s_axis.tdata << $clog2(DW)'(cnt*CNT_WIDTH'(FP_PAD_BITS))) | DW'(data_reg);
            default:        data_concat = (s_axis.tdata << $clog2(DW)'(cnt*CNT_WIDTH'(FZ_PAD_BITS))) | DW'(data_reg);
        endcase
    end

    always_ff @(posedge clk)
    begin
        unique case (state)
            S_IDLE: begin
                if ( `AXIS_TRANS(m_axis) ) begin
                    unique if (unp_fz)  data_reg <= DREG_WIDTH'( s_axis.tdata >> W_DW'(DW) - (W_DW'(cnt)+W_DW'(1))*W_DW'(FZ_PAD_BITS) );
                    else                data_reg <= DREG_WIDTH'( s_axis.tdata >> W_DW'(DW) - (W_DW'(cnt)+W_DW'(1))*W_DW'(FP_PAD_BITS) );
                end
            end
            S_FZ: begin
                if ( `AXIS_TRANS(s_axis))   data_reg <= DREG_WIDTH'( s_axis.tdata >> W_DW'(DW) - (W_DW'(cnt)+W_DW'(1))*W_DW'(FZ_PAD_BITS) );
                if ( `AXIS_LAST(m_axis) )   data_reg <= '0;
            end
            S_FP, S_SYN: begin
                if ( `AXIS_TRANS(s_axis))   data_reg <= DREG_WIDTH'( s_axis.tdata >> W_DW'(DW) - (W_DW'(cnt)+W_DW'(1))*W_DW'(FP_PAD_BITS) );
                if ( `AXIS_LAST(m_axis) )   data_reg <= '0;
            end
            default: data_reg <= data_reg;
        endcase
    end

    // CONTROL FLAGS
    // Since we have a tail that is more or less independent of the input
    // flags, we need to generate the output flags separately.
    always_comb begin
        m_axis.tvalid = s_axis.tvalid;
        m_axis.tkeep = '1;
        m_axis.tlast = 1'b0;
        unique case (state)
            S_IDLE: begin
                unique  if (unp_fz) m_axis.tkeep = FZ_KEEP;
                else    if (unp_fp) m_axis.tkeep = FP_KEEP;
                else    if (unp_s)  m_axis.tkeep = SYN_KEEP;
                else                m_axis.tkeep = '1;
            end
            S_FZ: begin
                m_axis.tkeep    = ( cnt >= CNT_WIDTH'(FZ_CYCLES-1) ) ? FZ_KEEP_LAST : FZ_KEEP;
                m_axis.tvalid   = send_tail ? (cnt >= CNT_WIDTH'(FZ_CYCLES-1)) : s_axis.tvalid;
                m_axis.tlast    = ( cnt >= CNT_WIDTH'(FZ_CYCLES-1) );
            end
            S_FP: begin
                m_axis.tkeep    = ( cnt >= CNT_WIDTH'(FP_CYCLES-1) ) ? FP_KEEP_LAST : FP_KEEP;
                m_axis.tvalid   = send_tail ? (cnt >= CNT_WIDTH'(FP_CYCLES-1)) : s_axis.tvalid;
                m_axis.tlast    = ( cnt >= CNT_WIDTH'(FP_CYCLES-1) );
            end
            S_SYN: begin
                m_axis.tkeep    = ( cnt >= CNT_WIDTH'(SYN_CYCLES-1) ) ? SYN_KEEP_LAST : SYN_KEEP;
                m_axis.tvalid   = send_tail ? (cnt >= CNT_WIDTH'(SYN_CYCLES-1)) : s_axis.tvalid;
                m_axis.tlast    = ( cnt >= CNT_WIDTH'(SYN_CYCLES-1) );
            end
            default: begin
                m_axis.tkeep    = '1;
                m_axis.tvalid   = s_axis.tvalid;
                m_axis.tlast    = 1'b0;
            end
        endcase
    end
    assign m_axis.tuser = s_axis.tuser;
    assign s_axis.tready = m_axis.tready & ~send_tail;

    // SIMPLE FSM AND A PARAMETER DEPENDENT COUNTER
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case (state)
            S_IDLE: begin
                if ( `AXIS_TRANS(m_axis) ) begin
                    unique  if (unp_fz)  n_state = S_FZ;
                    else    if (unp_fp)  n_state = S_FP;
                    else    if (unp_s)   n_state = S_SYN;
                    else                 n_state = state;
                end
            end
            S_FZ, S_FP, S_SYN: begin
                if ( `AXIS_LAST(m_axis) )
                    n_state = S_IDLE;
            end
            default: n_state = state;
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            cnt <= '0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    if ( `AXIS_TRANS(m_axis) ) begin
                        unique if (unp_fz) begin
                            if (cnt >= CNT_WIDTH'(FZ_CYCLES - 1))
                                cnt <= '0;
                            else
                                cnt <= cnt + CNT_WIDTH'(1);
                        end else if (unp_fp) begin
                            if (cnt >= CNT_WIDTH'(FP_CYCLES - 1))
                                cnt <= '0;
                            else
                                cnt <= cnt + CNT_WIDTH'(1);
                        end else if (unp_s) begin
                            if (cnt >= CNT_WIDTH'(SYN_CYCLES - 1))
                                cnt <= '0;
                            else
                                cnt <= cnt + CNT_WIDTH'(1);
                        end else begin
                            if (cnt >= CNT_WIDTH'(FZ_CYCLES - 1))
                                cnt <= '0;
                            else
                                cnt <= cnt + CNT_WIDTH'(1);
                        end
                    end
                end
                S_FZ: begin
                    if ( `AXIS_TRANS(m_axis) ) begin
                        if (cnt >= CNT_WIDTH'(FZ_CYCLES - 1))
                            cnt <= '0;
                        else
                            cnt <= cnt + CNT_WIDTH'(1);
                    end
                end
                S_FP: begin
                    if ( `AXIS_TRANS(m_axis) ) begin
                        if (cnt >= CNT_WIDTH'(FP_CYCLES - 1))
                            cnt <= '0;
                        else
                            cnt <= cnt + CNT_WIDTH'(1);
                    end
                end
                S_SYN: begin
                    if ( `AXIS_TRANS(m_axis) ) begin
                        if (cnt >= CNT_WIDTH'(SYN_CYCLES - 1))
                            cnt <= '0;
                        else
                            cnt <= cnt + CNT_WIDTH'(1);
                    end
                end
                default: begin
                    cnt <= '0;
                end
            endcase
        end
    end

endmodule
