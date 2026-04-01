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

module b_sample
#(
    parameter int unsigned T = cross_pkg::T,
    parameter int unsigned W = cross_pkg::W
)
(
   input logic clk,
   input logic rst_n,

   AXIS.slave s_axis,
   AXIS.master m_axis
);

    localparam int unsigned BITS_T = $clog2(T);
    localparam int unsigned DW_IN = s_axis.DATA_WIDTH;

    /* Counter determining the cycles during flushing and initialization */
    localparam int unsigned W_FCNT = BITS_T;
    logic [W_FCNT-1:0] flush_cnt;
    logic flush_cnt_en;

    /* Memory interface */
    logic mem_we;
    logic [BITS_T-1:0] mem_addr;
    logic mem_wdata, mem_rdata;

    /* Ramp up counter */
    localparam int unsigned W_RUCNT = $clog2( 2 );
    logic [W_RUCNT-1:0] ru_cnt, ru_cnt_en;

    /* Shift register for index generation */
    localparam int unsigned W_SREG = DW_IN + 2*BITS_T;
    logic [W_SREG-1:0] sreg;
    logic [W_SREG-1:0] s_axis_tdata_pad;

    logic [DW_IN-1:0] s_axis_tdata_mask;

    localparam int unsigned BITS_BUF = $clog2(DW_IN+2*BITS_T)+1;
    logic [BITS_BUF-1:0] bits_in_buf;
    logic [$clog2(DW_IN):0] valid_inbits;

    /* Fix weight challenge vector */
    logic [BITS_T-1:0] cur_pos;
    logic [BITS_T-1:0] tm1mc;
    logic [BITS_T-1:0] mask_bits;
    logic [$clog2(BITS_T):0] popcnt_tm1mc;
    logic [BITS_T-1:0] cand_pos, cand_pos_q;
    logic swap_en_s;

    logic m_axis_tdata_q;

    /* FSM */
    typedef enum logic [2:0] {S_INIT, S_SAMPLE, S_WRITE_CUR, S_WRITE_CAND, S_FLUSH_RAMP_UP, S_FLUSH, S_FLUSH_LAST} fsm_state_t;
    fsm_state_t state, n_state;

    /* Fill sreg depending on number of bits inside */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            sreg        <= '0;
            bits_in_buf <= 0;
        end else begin
            if (state == S_SAMPLE) begin
                if (bits_in_buf <= BITS_BUF'(2*BITS_T)) begin: refill
                    if (swap_en_s) begin: valid_index
                        if ( `AXIS_TRANS(s_axis) ) begin
                            sreg        <= (sreg >> mask_bits) | (s_axis_tdata_pad << bits_in_buf - BITS_BUF'(mask_bits));
                            bits_in_buf <= bits_in_buf - BITS_BUF'(mask_bits) + BITS_BUF'(valid_inbits);
                        end else begin
                            sreg        <= sreg >> mask_bits;
                            bits_in_buf <= bits_in_buf - BITS_BUF'(mask_bits);
                        end
                    end else begin: no_valid_index
                        /* Enough bits but index rejected */
                        if (bits_in_buf >= BITS_BUF'(mask_bits)) begin
                            if ( `AXIS_TRANS(s_axis) ) begin
                                sreg        <= (sreg >> mask_bits) | (s_axis_tdata_pad << bits_in_buf - BITS_BUF'(mask_bits));
                                bits_in_buf <= bits_in_buf - BITS_BUF'(mask_bits) + BITS_BUF'(valid_inbits);
                            end else begin
                                sreg        <= sreg >> mask_bits;
                                bits_in_buf <= bits_in_buf - BITS_BUF'(mask_bits);
                            end
                        end else if ( `AXIS_TRANS(s_axis) ) begin
                            sreg        <= sreg | (s_axis_tdata_pad << bits_in_buf);
                            bits_in_buf <= bits_in_buf + BITS_BUF'(valid_inbits);
                        end
                    end
                end else begin: no_refill
                    sreg        <= sreg >> mask_bits;
                    bits_in_buf <= bits_in_buf - BITS_BUF'(mask_bits);
                end
            end
        end
    end
    /* Expand it internally for easier assignment above and mask it not to
    * keep dirty bits in sreg */
    assign s_axis_tdata_pad = {{2*BITS_T{1'b0}}, s_axis.tdata & s_axis_tdata_mask};

    generate
        for (genvar i=0; i<DW_IN/8; i++)
            assign s_axis_tdata_mask[8*i +: 8] = {8{s_axis.tkeep[i]}};
    endgenerate

    /* Count ones in s_axis_tkeep */
    always_comb begin
        valid_inbits = '0;
        foreach(s_axis.tkeep[i])
            valid_inbits += 8*s_axis.tkeep[i];
    end

    /* Generate counter for bits required by mask */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n)
            mask_bits <= $bits(mask_bits)'($clog2(T));
        else begin
            case (state)
                S_SAMPLE: begin
                    if (popcnt_tm1mc == 1 && swap_en_s) begin
                        if (cur_pos >= BITS_T'(T-1)) begin: last_idx
                            mask_bits <= BITS_T'(BITS_T);
                        end else
                            if (mask_bits > BITS_T'(1))
                                mask_bits <= mask_bits - BITS_T'(1);
                        end
                    end

                default:
                    mask_bits <= mask_bits;

            endcase
        end
    end

    /* T minus 1 minus current position (tm1mc) is the maximum index to be sampled.
    * Use it's popcount to detect when to decrement bit counter for mask */
    always_comb begin
        popcnt_tm1mc = '0;
        foreach (tm1mc[i]) begin
            popcnt_tm1mc += $bits(popcnt_tm1mc)'(tm1mc[i]);
        end
    end
    assign tm1mc = $bits(tm1mc)'(BITS_T'(T - 1) - cur_pos);

    assign swap_en_s = (state == S_SAMPLE && bits_in_buf >= BITS_BUF'(mask_bits) && cand_pos <= BITS_T'(T-1) - cur_pos);
    assign cand_pos = BITS_T'(sreg & W_SREG'(((1 << mask_bits) - 1)) );

    always_ff @(posedge clk)
    begin
        if (state == S_SAMPLE) begin
            cand_pos_q <= cand_pos;
        end
    end

    /* current position in shuffling vector */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            cur_pos <= '0;
        end else if (state == S_WRITE_CAND) begin
            if (cur_pos >= BITS_T'(T-1) ) begin
                cur_pos <= '0;
            end else begin
                cur_pos <= cur_pos + BITS_T'(1);
            end
        end
    end

    /*
    * FSM to control shuffling and flushing
    */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_INIT;
        else        state <= n_state;
    end

    always_comb
    begin
        n_state = state;
        unique case (state)
            S_INIT: begin
                if ( flush_cnt >= W_FCNT'(T - 1) ) begin
                    n_state = S_SAMPLE;
                end
            end
            S_SAMPLE: begin
                if ( swap_en_s ) begin
                    n_state = S_WRITE_CUR;
                end
            end

            S_WRITE_CUR: begin
                n_state = S_WRITE_CAND;
            end

            S_WRITE_CAND: begin
                if ( cur_pos >= BITS_T'(T - 1) ) begin
                    n_state = S_FLUSH_RAMP_UP;
                end else begin
                    n_state = S_SAMPLE;
                end
            end

            S_FLUSH_RAMP_UP: begin
                if (ru_cnt >= W_RUCNT'(2 - 1) ) begin
                    n_state = S_FLUSH;
                end
            end

            S_FLUSH: begin
                if ( `AXIS_TRANS(m_axis) && flush_cnt >= BITS_T'(T - 2)) begin
                    n_state = S_FLUSH_LAST;
                end
            end

            S_FLUSH_LAST: begin
                if ( `AXIS_LAST(m_axis) ) begin
                    n_state = S_INIT;
                end
            end

            default: begin
                n_state = state;
            end
        endcase
    end

    // Latch the output of the signature memory after short ramp-up phase
    // in order to perform a lookahead on the words.
    // This allows to stream out the data without bubble cycles.
    always_ff @(posedge clk) begin
        unique case(state)
            S_FLUSH,
            S_FLUSH_LAST: begin
                if ( `AXIS_TRANS(m_axis) ) begin
                    m_axis_tdata_q <= mem_rdata;
                end
            end
            default: begin
                m_axis_tdata_q <= mem_rdata;
            end
        endcase
    end

    assign m_axis.tdata = m_axis_tdata_q;
    assign m_axis.tvalid = (state == S_FLUSH || state == S_FLUSH_LAST);
    assign m_axis.tkeep = '1;
    assign m_axis.tlast = (state == S_FLUSH_LAST);

    assign s_axis.tready = (state == S_SAMPLE && bits_in_buf <= BITS_BUF'(2*BITS_T));


    //------------------------------------------
    // MEMORY storing the constant weight vector
    //------------------------------------------
    sp_lutram
    #(
        .DATA_WIDTH ( 1         ),
        .DEPTH      ( T         ),
        .OUTPUT_REG ( "true"    )
    )
    u_b_vec_ram
    (
        .clk,
        .we_i       ( mem_we    ),
        .addr_i     ( mem_addr  ),
        .wdata_i    ( mem_wdata ),
        .rdata_o    ( mem_rdata )
    );

    //------------------------------------------
    // COUNTER used for init and flush
    //------------------------------------------
    counter
    #(
        .CNT_WIDTH ( BITS_T )
    )
    u_flush_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( W_FCNT'(T)    ),
        .inc        ( W_FCNT'(1)    ),
        .trigger    ( flush_cnt_en  ),
        .cnt        ( flush_cnt     )
    );

    always_comb
    begin
        unique case(state)
            S_INIT:             flush_cnt_en = 1'b1;
            S_FLUSH:            flush_cnt_en = ( `AXIS_TRANS( m_axis ) );
            S_FLUSH_LAST:       flush_cnt_en = ( `AXIS_TRANS( m_axis ) );
            default:            flush_cnt_en = 1'b0;
        endcase
    end

    always_comb
    begin
        mem_we = 1'b0;
        mem_addr = flush_cnt;
        mem_wdata = 1'b0;
        unique case(state)
            S_INIT: begin
                mem_we      = 1'b1;
                mem_addr    = flush_cnt;
                mem_wdata   = (flush_cnt >= W_FCNT'(W)) ? 1'b0 : 1'b1;
            end
            S_SAMPLE: begin
                mem_addr = cur_pos + cand_pos;
            end
            S_WRITE_CUR: begin
                mem_addr    = cur_pos;
                mem_we      = 1'b1;
                mem_wdata   = mem_rdata;
            end
            S_WRITE_CAND: begin
                mem_addr    = cur_pos + cand_pos_q;
                mem_we      = 1'b1;
                mem_wdata   = mem_rdata;
            end
            S_FLUSH_RAMP_UP: begin
                mem_addr    = BITS_T'(ru_cnt);
            end
            S_FLUSH,
            S_FLUSH_LAST: begin
                mem_addr = flush_cnt + W_FCNT'(1);
                if ( `AXIS_TRANS(m_axis) ) begin
                    mem_addr = flush_cnt + W_FCNT'(2);
                end
            end
            default: begin
                mem_we      = 1'b0;
                mem_addr    = flush_cnt;
                mem_wdata   = 1'b0;
            end
        endcase
    end

    //-----------------------------------------------
    // COUNTER for duration of ramp up phase
    //-----------------------------------------------
    counter
    #(
        .CNT_WIDTH ( W_RUCNT )
    )
    u_ru_cnt
    (
        .clk,
        .rst_n,
        .max_val    ( W_RUCNT'(2)   ),
        .inc        ( W_RUCNT'(1)   ),
        .trigger    ( ru_cnt_en     ),
        .cnt        ( ru_cnt        )
    );
    assign ru_cnt_en = (state == S_FLUSH_RAMP_UP);


endmodule
