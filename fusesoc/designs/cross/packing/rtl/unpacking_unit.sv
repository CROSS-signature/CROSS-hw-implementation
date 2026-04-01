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

module unpacking_unit
    import packing_unit_pkg::*;
#(
    parameter OUT_REG = 0
)
(
    input logic clk,
    input logic rst_n,

    input decomp_mode_t mode,
    input logic mode_valid,
    output logic mode_ready,

    output logic fz_error,
    output logic pad_rsp0_error,
    input logic error_clear,

    AXIS.slave s_axis,
    AXIS.master m_axis
);

    logic [1:0] sel_demux;
    logic sel_mux0, sel_mux1;
    logic busy;

    localparam int unsigned DW = s_axis.DATA_WIDTH;
    AXIS #(.DATA_WIDTH(DW), .TUSER_WIDTH(3)) s_axis_tmp(),
        m_axis_demux[3](), s_axis_mux0[2](), s_axis_mux1[2](),
        s_axis_unpack(), m_axis_unpack(), m_axis_int();
    AXIS #(.DATA_WIDTH(8), .TUSER_WIDTH(3)) s_axis_rsp0(), m_axis_rsp0();


    // FSM variables
    typedef enum logic [2:0] {S_IDLE, S_RSP, S_SYN, S_BP} fsm_t;
    fsm_t n_state, state;

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) state <= S_IDLE;
        else        state <= n_state;
    end

    always_comb begin
        n_state = state;
        unique case (state)
            S_IDLE: begin
                if (mode_valid && mode_ready && !busy) begin
                    unique  if ( mode == RSP ) n_state = S_RSP;
                    else    if ( mode == SYN ) n_state = S_SYN;
                    else                       n_state = S_BP;
                end
            end
            S_RSP, S_SYN, S_BP: begin
                if ( `AXIS_LAST(m_axis) && m_axis.tuser[0] ) begin
                    n_state = S_IDLE;
                end
            end
            default: begin
                n_state = state;
            end
        endcase
    end
    assign mode_ready = (state == S_IDLE) & ~busy;

    always_comb begin
        {sel_demux, sel_mux0, sel_mux1} = '0;
        unique case (state)
            S_IDLE: begin
                unique if (mode == RSP) begin
                    sel_demux = RSP;
                    sel_mux0 = 1'b1;
                    sel_mux1 = 1'b1;
                end else if (mode == SYN) begin
                    sel_demux = SYN;
                    sel_mux0 = 1'b0;
                    sel_mux1 = 1'b1;
                end else begin
                    sel_demux = BP;
                    sel_mux1 = 1'b0;
                end
            end
            S_BP: begin
                sel_demux = BP;
                sel_mux1 = 1'b0;
            end
            S_RSP: begin
                sel_demux = RSP;
                sel_mux0 = 1'b1;
                sel_mux1 = 1'b1;
            end
            S_SYN: begin
                sel_demux = SYN;
                sel_mux0 = 1'b0;
                sel_mux1 = 1'b1;
            end
            default: begin
                {sel_demux, sel_mux0, sel_mux1} = '0;
            end
        endcase
    end

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            busy <= 1'b0;
        end else begin
            if ( `AXIS_LAST(s_axis) && s_axis.tuser[0] ) begin
                busy <= 1'b1;
            end
            if ( `AXIS_LAST(m_axis) && m_axis.tuser[0] ) begin
                busy <= 1'b0;
            end
        end
    end

    //-----------------------------------------------
    // AXIS DEMUX
    //-----------------------------------------------
    axis_demux #( .N_MASTERS(3) )
    u_axis_demux
    (
        .sel    ( sel_demux     ),
        .s_axis ( s_axis_tmp    ),
        .m_axis ( m_axis_demux  )
    );
    `AXIS_ASSIGN(s_axis_mux0[0], m_axis_demux[1]);
    assign s_axis_mux0[0].tuser = m_axis_demux[1].tuser;

    always_comb begin
        `AXIS_ASSIGN_PROC(s_axis_tmp, s_axis)
        s_axis.tready = s_axis_tmp.tready & ~busy;
        s_axis_tmp.tvalid = s_axis.tvalid & ~busy;
    end
    assign s_axis_tmp.tuser = s_axis.tuser;

    //-----------------------------------------------
    // AXIS WIDTH CONVERTER BEFORE RESPONSE PARSER
    //-----------------------------------------------
    width_converter #( .ELEM_WIDTH(8) )
    u_width_converter_0
    (
        .axis_aclk  ( clk               ),
        .axis_rst_n ( rst_n             ),
        .s_axis     ( m_axis_demux[2]   ),
        .m_axis     ( s_axis_rsp0       )
    );

    //-----------------------------------------------
    // RESPONSE PARSER
    //-----------------------------------------------
    parse_rsp0
    #(
        .BYTES_Y            ( (cross_pkg::N * cross_pkg::BITS_P + 7)/8      ),
        .BYTES_DELTA_SIGMA  ( (cross_pkg::DIM_FZ * cross_pkg::BITS_Z + 7)/8 )
    )
    u_pars_rsp0
    (
        .clk,
        .rst_n,
        .clear_err  ( error_clear       ),
        .pad_error  ( pad_rsp0_error    ),
        .s_axis     ( s_axis_rsp0       ),
        .m_axis     ( m_axis_rsp0       )
    );

    //-----------------------------------------------
    // AXIS WIDTH CONVERTER AFTER RESPONSE PARSER
    //-----------------------------------------------
    width_converter #( .ELEM_WIDTH(8) )
    u_width_converter_1
    (
        .axis_aclk  ( clk               ),
        .axis_rst_n ( rst_n             ),
        .s_axis     ( m_axis_rsp0       ),
        .m_axis     ( s_axis_mux0[1]    )
    );

    //-----------------------------------------------
    // AXIS MUX 0
    //-----------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_axis_mux0
    (
        .sel    ( sel_mux0      ),
        .s_axis ( s_axis_mux0   ),
        .m_axis ( s_axis_unpack )
    );

    //-----------------------------------------------
    // UNPACKING
    //-----------------------------------------------
    cross_unpack
    u_cross_unpack
    (
        .clk,
        .rst_n,
        .fz_error       ( fz_error      ),
        .fz_error_clear ( error_clear   ),
        .s_axis         ( s_axis_unpack ),
        .m_axis         ( m_axis_unpack )
    );

    //-----------------------------------------------
    // AXIS MUX 1
    //-----------------------------------------------
    axis_mux #( .N_SLAVES(2) )
    u_axis_mux1
    (
        .sel    ( sel_mux1      ),
        .s_axis ( s_axis_mux1   ),
        .m_axis ( m_axis_int    )
    );
    `AXIS_ASSIGN(s_axis_mux1[0], m_axis_demux[0])
    assign s_axis_mux1[0].tuser = m_axis_demux[0].tuser;

    `AXIS_ASSIGN(s_axis_mux1[1], m_axis_unpack)
    assign s_axis_mux1[1].tuser = m_axis_unpack.tuser;

if (OUT_REG > 0) begin
    axis_reg #( .SPILL_REG(1) )
    u_axis_reg_out
    (
        .clk,
        .rst_n,
        .s_axis ( m_axis_int    ),
        .m_axis ( m_axis        )
    );
end else begin
    `AXIS_ASSIGN(m_axis, m_axis_int);
    assign m_axis.tuser = m_axis_int.tuser;
end

endmodule
