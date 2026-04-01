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

module fp_sample
    import common_pkg::max;
#(
    parameter int unsigned MOD_P = 509,
    parameter int unsigned PAR_ELEMS = 1,
    localparam int unsigned BITS_P = $clog2(MOD_P)
)
(
   input logic clk,
   input logic rst_n,

   input logic en_mul_group,

   AXIS.slave s_axis,
   AXIS.master m_axis
);

    /* input data width and keep width */
    localparam int unsigned DW = s_axis.DATA_WIDTH;
    localparam int unsigned KW = s_axis.KEEP_WIDTH;

    logic [DW-1:0] s_axis_tdata_mask;

    logic [DW+2*BITS_P*PAR_ELEMS-1:0] sreg;
    logic [DW+2*BITS_P*PAR_ELEMS-1:0] s_axis_tdata_pad;

    localparam int unsigned BITS_BUF = $clog2(DW+2*BITS_P*PAR_ELEMS)+1;
    logic [BITS_BUF-1:0] bits_in_buf;
    logic [$clog2(DW):0] valid_inbits;

    logic par_en, buf_empty_q;


    AXIS #(.DATA_WIDTH(BITS_P), .ELEM_WIDTH(BITS_P)) s_axis_wc();
    AXIS #(.DATA_WIDTH(BITS_P*PAR_ELEMS), .ELEM_WIDTH(BITS_P)) s_axis_mux_int[2]();
    AXIS #(.DATA_WIDTH(BITS_P*PAR_ELEMS), .ELEM_WIDTH(BITS_P)) m_axis_par(), m_axis_wc();

    localparam int unsigned W_SHIFT_AMOUNT = $clog2(PAR_ELEMS*BITS_P);
    logic [W_SHIFT_AMOUNT-1:0] shift_amount;
    logic m_axis_tvalid_int, m_axis_tready_int;

    /* If output width is larger than required for sample, just zero-padd it. */
    assign s_axis.tready = (bits_in_buf <= BITS_BUF'(2*PAR_ELEMS*BITS_P));

    assign shift_amount = par_en ? W_SHIFT_AMOUNT'(PAR_ELEMS*BITS_P) : W_SHIFT_AMOUNT'(BITS_P);

    /* Fill sreg depending on number of bits inside */
    always_ff @(`REG_SENSITIVITY_LIST_2) begin
        if (!rst_n) begin
            sreg        <= '0;
            bits_in_buf <= 0;
        end else begin
            if (bits_in_buf <= BITS_BUF'(2*PAR_ELEMS*BITS_P)) begin: refill
                if (m_axis_tvalid_int) begin: valid_sample
                    /* Taken and re-filled */
                    if ( m_axis_tready_int && (s_axis.tvalid && s_axis.tready) ) begin
                        sreg        <= (sreg >> shift_amount) | (s_axis_tdata_pad << bits_in_buf - BITS_BUF'(shift_amount));
                        bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount) + BITS_BUF'(valid_inbits);
                    /* Taken and not re-filled */
                    end else if ( m_axis_tready_int && !(s_axis.tvalid && s_axis.tready) ) begin
                        sreg        <= sreg >> shift_amount;
                        bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount);
                    /* Not taken and re-filled */
                    end else if (!m_axis_tready_int && (s_axis.tvalid && s_axis.tready) ) begin
                        sreg        <= sreg | (s_axis_tdata_pad << bits_in_buf);
                        bits_in_buf <= bits_in_buf + BITS_BUF'(valid_inbits);
                    /* Not taken and not re-filled */
                    end else begin
                        sreg        <= sreg;
                        bits_in_buf <= bits_in_buf;
                    end
                end else begin: no_valid_sample
                    /* Enough bits but sample rejected */
                    if (bits_in_buf >= BITS_BUF'(2*PAR_ELEMS*BITS_P)) begin
                        if (s_axis.tvalid && s_axis.tready) begin
                            sreg        <= (sreg >> shift_amount) | (s_axis_tdata_pad << bits_in_buf - BITS_BUF'(shift_amount));
                            bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount) + BITS_BUF'(valid_inbits);
                        end else begin
                            sreg        <= sreg >> shift_amount;
                            bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount);
                        end
                    end else if ((s_axis.tvalid && s_axis.tready) || buf_empty_q) begin
                        sreg        <= sreg | (s_axis_tdata_pad << bits_in_buf);
                        bits_in_buf <= bits_in_buf + BITS_BUF'(valid_inbits);
                    end
                end
            end else begin: no_refill
                if (m_axis_tvalid_int) begin
                    if (m_axis_tready_int) begin
                        sreg        <= sreg >> shift_amount;
                        bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount);
                    end
                end else begin
                    sreg        <= sreg >> shift_amount;
                    bits_in_buf <= bits_in_buf - BITS_BUF'(shift_amount);
                end
            end
        end
    end
    /* Expand it internally for easier assignment above and mask it not to
    * keep dirty bits in sreg */
    assign s_axis_tdata_pad = {{2*BITS_P*PAR_ELEMS{1'b0}}, s_axis.tdata & s_axis_tdata_mask};
    assign m_axis_tvalid_int = (par_en & m_axis_par.tvalid) | (~par_en & s_axis_wc.tvalid);
    assign m_axis_tready_int = (par_en & m_axis_par.tready) | (~par_en & s_axis_wc.tready);

    /* Count ones in s_axis_tkeep */
    always_comb begin
        valid_inbits = '0;
        foreach(s_axis.tkeep[i])
            valid_inbits += 8*s_axis.tkeep[i];
    end

    generate
        for (genvar i=0; i<KW; i++)
            assign s_axis_tdata_mask[8*i +: 8] = {8{s_axis.tkeep[i]}};
    endgenerate


    /////////////////////////////////////////////////////
    // WIDTH CONVERTER
    /////////////////////////////////////////////////////
    width_converter #( .ELEM_WIDTH(BITS_P) )
    u_width_conv
    (
        .axis_aclk  ( clk       ),
        .axis_rst_n ( rst_n     ),
        .s_axis     ( s_axis_wc ),
        .m_axis     ( m_axis_wc )
    );

    /////////////////////////////////////////////////////
    // MULTIPLEXER
    /////////////////////////////////////////////////////

    if (PAR_ELEMS == 1) begin
        assign par_en = 1'b1;
        assign buf_empty_q = 1'b0;

        `AXIS_ASSIGN( m_axis, m_axis_par)

    end else begin

        localparam int unsigned W_WC_CNT = max($clog2(PAR_ELEMS), 1);
        logic [W_WC_CNT-1:0] wc_cnt;
        logic wc_cnt_en;

        // Multiplexer between parallel/sequential sampling
        axis_mux #(
            .N_SLAVES  ( 2      ),
            .BITS_ELEM ( BITS_P )
        ) u_mux (
            .sel    ( par_en            ),
            .s_axis ( s_axis_mux_int    ),
            .m_axis ( m_axis            )
        );
        `AXIS_ASSIGN( s_axis_mux_int[0], m_axis_wc)
        `AXIS_ASSIGN( s_axis_mux_int[1], m_axis_par)

        always_ff @(`REG_SENSITIVITY_LIST_2) begin
            if (!rst_n) begin
                buf_empty_q <= 1'b0;
            end else begin
                if (!buf_empty_q && `AXIS_LAST(s_axis)) begin
                    buf_empty_q <= 1'b1;
                end
                if (buf_empty_q && s_axis.tvalid) begin
                    buf_empty_q <= 1'b0;
                end
            end
        end

        assign par_en = m_axis_par.tvalid && (wc_cnt == W_WC_CNT'(0));

        // Counter to track filling of width converter
        counter #( .CNT_WIDTH(W_WC_CNT) )
        u_wc_cnt
        (
            .clk,
            .rst_n,
            .max_val    ( W_WC_CNT'(PAR_ELEMS)  ),
            .inc        ( W_WC_CNT'(1)          ),
            .trigger    ( wc_cnt_en             ),
            .cnt        ( wc_cnt                )
        );
        assign wc_cnt_en = s_axis_wc.tvalid && s_axis_wc.tready && !par_en;

    end

    /////////////////////////////////////////////////////
    // GENERATE SLICES
    /////////////////////////////////////////////////////
    generate
        for (genvar i=0; i<PAR_ELEMS; i++) begin
            assign m_axis_par.tdata[i*BITS_P +: BITS_P] = en_mul_group  ? BITS_P'(sreg[BITS_P*i +: BITS_P] + BITS_P'(1))
                                                                        : sreg[BITS_P*i +: BITS_P];
            assign m_axis_par.tkeep[i] = en_mul_group   ? (bits_in_buf >= BITS_BUF'(BITS_P*(i+1)) && sreg[BITS_P*i +: BITS_P] < BITS_P'(MOD_P-1))
                                                        : (bits_in_buf >= BITS_BUF'(BITS_P*(i+1)) && sreg[BITS_P*i +: BITS_P] < BITS_P'(MOD_P));
        end
    endgenerate
    assign m_axis_par.tvalid = &m_axis_par.tkeep;

    // Width converter always connected to a single coefficient
    assign s_axis_wc.tdata      = en_mul_group ? BITS_P'(sreg[0 +: BITS_P] + BITS_P'(1)) : sreg[0 +: BITS_P];
    assign s_axis_wc.tkeep[0]   = en_mul_group  ? (bits_in_buf >= BITS_BUF'(BITS_P) && sreg[0 +: BITS_P] < BITS_P'(MOD_P-1))
                                                : (bits_in_buf >= BITS_BUF'(BITS_P) && sreg[0 +: BITS_P] < BITS_P'(MOD_P));
    assign s_axis_wc.tvalid     = s_axis_wc.tkeep[0] && !par_en;
    assign s_axis_wc.tlast      = buf_empty_q && (bits_in_buf <= BITS_BUF'(BITS_P));


endmodule
