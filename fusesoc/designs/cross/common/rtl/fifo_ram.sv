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

module fifo_ram
#(
    parameter int unsigned DEPTH = 1024,
    parameter REG_OUT = 0
)
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    localparam int unsigned DATA_WIDTH = s_axis.DATA_WIDTH;
    localparam int unsigned KEEP_WIDTH = DATA_WIDTH/8;

    if ( s_axis.DATA_WIDTH != m_axis.DATA_WIDTH )
        $error("Data widths of s_axis and m_axis must be equal!");

    /* tdata, tlast and tkeep (except for lsb) are stored in mem */
    logic [DATA_WIDTH+KEEP_WIDTH-1:0] wr_data, rd_data;
    logic [DATA_WIDTH+KEEP_WIDTH-1:0] mem [DEPTH];

    localparam int unsigned W_WCNT = $clog2(DEPTH) + 1;
    logic [W_WCNT-1:0] word_cnt, word_cnt_r;
    logic [W_WCNT-2:0] wr_addr, rd_addr, n_rd_addr;

    logic wr_en, rd_en;
    logic rd_while_wr, rd_while_wr_r;

    AXIS #(.DATA_WIDTH(DATA_WIDTH)) m_axis_int();

    /* Opional output register */
    if (REG_OUT) begin
        axis_reg #(
            .ELEM_WIDTH ( DATA_WIDTH/KEEP_WIDTH ),
            .SPILL_REG  ( DATA_WIDTH/KEEP_WIDTH )
        ) u_reg_out (
            .clk,
            .rst_n,
            .s_axis ( m_axis_int    ),
            .m_axis ( m_axis        )
        );
    end else begin
        `AXIS_ASSIGN(m_axis, m_axis_int);
        assign m_axis.tuser = m_axis_int.tuser;
    end


    /* No need to store lsb of tkeep, as its per AXIS definition always 1 upon valid data */
    if (KEEP_WIDTH > 1) begin
        assign wr_data = {s_axis.tlast, s_axis.tkeep[1 +: KEEP_WIDTH-1], s_axis.tdata};
        assign m_axis_int.tkeep = {rd_data[DATA_WIDTH +: KEEP_WIDTH-1], 1'b1};
    end else begin
        assign wr_data = {s_axis.tlast, s_axis.tdata};
        assign m_axis_int.tkeep = 1'b1;
    end
    assign m_axis_int.tdata = rd_data[0 +: DATA_WIDTH];
    assign m_axis_int.tlast = rd_data[DATA_WIDTH+KEEP_WIDTH-1];

    assign rd_en = (word_cnt > 0);
    assign wr_en = s_axis.tvalid & s_axis.tready;
    assign s_axis.tready = (word_cnt < $bits(word_cnt)'(DEPTH));

    /* Two conditions here disable m_axis_int.tvalid:
    * 1) word_cnt was zero, so we need to wait an additional clock
    * cycle, therefore also check word_cnt_r for being zero
    * 2) Fifo was almost empty, we wrote and read but the newly stored word
    * needs an additional cycle to propagate to the output, thus disable tvalid
    * for one cycle.
    */
    assign m_axis_int.tvalid = !( (word_cnt == 0 || word_cnt_r == 0) || (word_cnt == 1 && rd_while_wr_r) );

    always @(posedge clk)
    begin
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    always @(posedge clk)
    begin
        if (rd_en) rd_data <= mem[n_rd_addr];
    end


    /* WORD COUNTER */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if ( !rst_n ) begin
            word_cnt <= '0;
        end else begin
            /* Write but no read */
            unique if ( (s_axis.tvalid && s_axis.tready) && !(m_axis_int.tvalid && m_axis_int.tready) ) begin
                word_cnt <= word_cnt + W_WCNT'(1);
            /* Read but no write */
            end else if ( !(s_axis.tvalid && s_axis.tready) && (m_axis_int.tvalid && m_axis_int.tready) ) begin
                word_cnt <= word_cnt - W_WCNT'(1);
            /* Neither written nor read, or written and read */
            end else begin
                word_cnt <= word_cnt;
            end
        end
    end

    /* Registered word counter */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) word_cnt_r <= '0;
        else        word_cnt_r <= word_cnt;
    end

    /* Registered read while write detection */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) rd_while_wr_r <= '0;
        else        rd_while_wr_r <= rd_while_wr;
    end
    assign rd_while_wr = (s_axis.tvalid && s_axis.tready && m_axis_int.tvalid && m_axis_int.tready);

    /* Write address */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if ( !rst_n ) begin
            wr_addr <= '0;
        end else begin
            if ( s_axis.tvalid && s_axis.tready) begin
                if (wr_addr >= $bits(wr_addr)'(DEPTH-1))
                    wr_addr <= '0;
                else
                    wr_addr <= wr_addr + $bits(wr_addr)'(1);
            end
        end
    end

    /* Read address */
    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) rd_addr <= '0;
        else        rd_addr <= n_rd_addr;
    end

    /* Next read address required for look-ahead due to read delay */
    always_comb
    begin
        n_rd_addr = rd_addr;
        if (m_axis_int.tvalid && m_axis_int.tready) begin
            if (rd_addr >= $bits(rd_addr)'(DEPTH-1))
                n_rd_addr = '0;
            else
                n_rd_addr = rd_addr + $bits(rd_addr)'(1);
        end

    end

endmodule
