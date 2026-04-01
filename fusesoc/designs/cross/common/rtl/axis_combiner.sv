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

module axis_combiner
(
    input logic clk,
    input logic rst_n,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    if (s_axis.DATA_WIDTH != m_axis.DATA_WIDTH)
        $error("s_axis and m_axis must have same data width!");

    if (s_axis.TUSER_WIDTH < 1)
        $error("Requires s_axis.tuser[0] to indicate last frame!");

    localparam DW = s_axis.DATA_WIDTH;
    localparam POPCNT_BITS = $clog2(DW/8)+1;

    logic [POPCNT_BITS-1:0] pcnt_tkeep;
	logic [POPCNT_BITS-1:0] bytes_to_store_d, bytes_to_store_q;

    logic [DW-1:0] data_reg, combined_data, data_reg_mask;
    logic [DW/8-1:0] keep_reg, combined_keep;
	logic last_reg;

    logic align_en, is_last_frame;

    assign is_last_frame = s_axis.tuser[0];

    assign m_axis.tdata = align_en ? combined_data : s_axis.tdata;
    assign m_axis.tkeep = align_en ? (last_reg ? keep_reg : combined_keep) : s_axis.tkeep;
    assign m_axis.tvalid = align_en ? (s_axis.tvalid & (&combined_keep)) | (s_axis.tvalid && s_axis.tlast && is_last_frame && bytes_to_store_q < POPCNT_BITS'(DW/8) ) | last_reg
                                    : (s_axis.tvalid & (&s_axis.tkeep)) | (s_axis.tvalid & s_axis.tlast & is_last_frame);
    assign s_axis.tready = m_axis.tready;

    always_comb begin
        m_axis.tlast = 1'b0;
        if ( `AXIS_LAST(s_axis) && is_last_frame) begin
            m_axis.tlast = (bytes_to_store_q + pcnt_tkeep <= POPCNT_BITS'(DW/8)) | !align_en;
        end else begin
           m_axis.tlast = last_reg;
        end
    end

    /* Register buffering the partial slices of last frame words
    * Most significant byte can be discarded as otherwise slice would not be
    * partially empty
    * */
    always_ff @(posedge clk)
    begin
        if ( `AXIS_TRANS(s_axis) ) begin
            if (s_axis.tlast) begin
                if (pcnt_tkeep + bytes_to_store_q > POPCNT_BITS'(DW/8)) begin
                    data_reg <= s_axis.tdata >> $clog2(DW)'(DW - 32'(8*bytes_to_store_q));
                    keep_reg <= s_axis.tkeep >> (POPCNT_BITS'(DW/8) - bytes_to_store_q);
                end else begin
                    data_reg <= (s_axis.tdata << 8*bytes_to_store_q) | (data_reg & data_reg_mask);
                    keep_reg <= (s_axis.tkeep << bytes_to_store_q) | keep_reg;
                end
            end else begin
                data_reg <= s_axis.tdata >> $clog2(DW)'(DW - 32'(8*bytes_to_store_q));
                keep_reg <= s_axis.tkeep >> (POPCNT_BITS'(DW/8) - bytes_to_store_q);
            end
        end
    end
    assign combined_data = (s_axis.tdata << 8*bytes_to_store_q) | (data_reg & data_reg_mask);
    assign combined_keep = (s_axis.tkeep << bytes_to_store_q) | keep_reg;


    generate
        for (genvar i=0; i<DW/8; i++) begin
            assign data_reg_mask[8*i +: 8] = {8{keep_reg[i]}};
        end
    endgenerate

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            align_en <= 1'b0;
        end else begin
            if ( `AXIS_LAST(m_axis) )
                align_en <= 1'b0;
            else if ( `AXIS_LAST(s_axis) )
                 //always align if its not multiple of word size
                align_en <= ( ((pcnt_tkeep + bytes_to_store_q) & POPCNT_BITS'({$clog2(DW/8){1'b1}})) > 0 );
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            last_reg <= 1'b0;
        end else begin
			if ( `AXIS_LAST(m_axis) )
				last_reg <= 1'b0;
			else if ( `AXIS_LAST(s_axis) && is_last_frame )
				last_reg <= |keep_reg;
		end
    end

    /* Popcount of previous stream required to align subsequent frame */
    always_comb begin
        pcnt_tkeep = '0;
        foreach(s_axis.tkeep[i]) begin
            pcnt_tkeep += POPCNT_BITS'(s_axis.tkeep[i]);
        end
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            bytes_to_store_q <= (POPCNT_BITS)'(DW/8);
        end else begin
            if ( `AXIS_LAST(m_axis) )
                bytes_to_store_q <= (POPCNT_BITS)'(DW/8);
            else if ( `AXIS_LAST(s_axis) )
                bytes_to_store_q <= bytes_to_store_d;
        end
    end
    assign bytes_to_store_d = (`AXIS_LAST(s_axis) && pcnt_tkeep + bytes_to_store_q > POPCNT_BITS'(DW/8))
                            ? (bytes_to_store_q + pcnt_tkeep - POPCNT_BITS'(DW/8))
                            : (bytes_to_store_q + pcnt_tkeep);


endmodule
