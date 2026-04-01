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
// @author: Francesco Antognazza <francesco.antognazza@polimi.it>

`timescale 1ps / 1ps

`include "axis_intf.svh"

module tb_arithmetic_unit
    import common_pkg::*;
    import cross_pkg::*;
    import arithmetic_unit_pkg::*;
#(
    parameter  int STREAM_WIDTH      = 64,
    parameter  int MAT_DATA_WIDTH    = 192,
    localparam int K1                = STREAM_WIDTH / BITS_Z,
    localparam int K2                = STREAM_WIDTH / BITS_P,
    //
    localparam int IN0_COEFF_WIDTH   = BITS_P,
    localparam int IN0_WORD_COEFFS   = 1,
    localparam int IN0_WORD_WIDTH    = IN0_COEFF_WIDTH * IN0_WORD_COEFFS,
    //
    localparam int IN1_COEFF_WIDTH   = BITS_Z,
    localparam int IN1_WORD_COEFFS   = K1,
    localparam int IN1_WORD_WIDTH    = IN1_COEFF_WIDTH * IN1_WORD_COEFFS,
    localparam int IN1_STREAM_WIDTH  = STREAM_WIDTH,
    localparam int IN1_BYTES_WIDTH   = iceilfrac(IN1_STREAM_WIDTH, 8),
    //
    localparam int IN2_COEFF_WIDTH   = BITS_P,
    localparam int IN2_WORD_COEFFS   = K2,
    localparam int IN2_WORD_WIDTH    = IN2_COEFF_WIDTH * IN2_WORD_COEFFS,
    localparam int IN2_STREAM_WIDTH  = STREAM_WIDTH,
    localparam int IN2_BYTES_WIDTH   = iceilfrac(IN2_STREAM_WIDTH, 8),
    //
    localparam int IN3_COEFF_WIDTH   = BITS_P,
    localparam int IN3_WORD_COEFFS   = K2,
    localparam int IN3_WORD_WIDTH    = IN3_COEFF_WIDTH * IN3_WORD_COEFFS,
    localparam int IN3_STREAM_WIDTH  = STREAM_WIDTH,
    localparam int IN3_BYTES_WIDTH   = iceilfrac(IN3_STREAM_WIDTH, 8),
    //
`ifdef RSDPG
    localparam int IN4_COEFF_WIDTH   = BITS_Z,
    localparam int IN4_WORD_COEFFS   = 1,
    localparam int IN4_WORD_WIDTH    = IN4_COEFF_WIDTH * IN4_WORD_COEFFS,
`endif
    //
    localparam int IN5_COEFF_WIDTH   = BITS_Z,
    localparam int IN5_WORD_COEFFS   = K1,
    localparam int IN5_WORD_WIDTH    = IN5_COEFF_WIDTH * IN5_WORD_COEFFS,
    localparam int IN5_STREAM_WIDTH  = STREAM_WIDTH,
    localparam int IN5_BYTES_WIDTH   = iceilfrac(IN5_STREAM_WIDTH, 8),
    //
    localparam int OUT0_COEFF_WIDTH  = BITS_P,
    localparam int OUT0_WORD_COEFFS  = K2,
    localparam int OUT0_WORD_WIDTH   = OUT0_COEFF_WIDTH * OUT0_WORD_COEFFS,
    localparam int OUT0_STREAM_WIDTH = STREAM_WIDTH,
    localparam int OUT0_BYTES_WIDTH  = iceilfrac(OUT0_STREAM_WIDTH, 8),
    //
    localparam int OUT1_COEFF_WIDTH  = BITS_P,
    localparam int OUT1_WORD_COEFFS  = K2,
    localparam int OUT1_WORD_WIDTH   = OUT1_COEFF_WIDTH * OUT1_WORD_COEFFS,
    localparam int OUT1_STREAM_WIDTH = STREAM_WIDTH,
    localparam int OUT1_BYTES_WIDTH  = iceilfrac(OUT1_STREAM_WIDTH, 8),
    //
    localparam int OUT2_COEFF_WIDTH  = BITS_Z,
    localparam int OUT2_WORD_COEFFS  = K1,
    localparam int OUT2_WORD_WIDTH   = OUT2_COEFF_WIDTH * OUT2_WORD_COEFFS,
    localparam int OUT2_STREAM_WIDTH = STREAM_WIDTH,
    localparam int OUT2_BYTES_WIDTH  = iceilfrac(OUT2_STREAM_WIDTH, 8)
) (
    input  logic                                  clk_i,
    input  logic                                  rst_n,
    input  arithmetic_op_t                        op_i,
    input  logic                                  start_i,
    output logic                                  done_o,
    //
    input  logic           [  IN0_WORD_WIDTH-1:0] in_0_tdata,
    input  logic           [ IN0_WORD_COEFFS-1:0] in_0_tkeep,
    input  logic                                  in_0_tvalid,
    input  logic                                  in_0_tlast,
    output logic                                  in_0_tready,
    //
    input  logic           [  IN1_WORD_WIDTH-1:0] in_1_tdata,
    input  logic           [ IN1_WORD_COEFFS-1:0] in_1_tkeep,
    input  logic                                  in_1_tvalid,
    input  logic                                  in_1_tlast,
    output logic                                  in_1_tready,
    //
    input  logic           [  IN2_WORD_WIDTH-1:0] in_2_tdata,
    input  logic           [ IN2_WORD_COEFFS-1:0] in_2_tkeep,
    input  logic                                  in_2_tvalid,
    input  logic                                  in_2_tlast,
    output logic                                  in_2_tready,
    //
    input  logic           [  IN3_WORD_WIDTH-1:0] in_3_tdata,
    input  logic           [ IN3_WORD_COEFFS-1:0] in_3_tkeep,
    input  logic                                  in_3_tvalid,
    input  logic                                  in_3_tlast,
    output logic                                  in_3_tready,
    //
`ifdef RSDPG
    input  logic           [  IN4_WORD_WIDTH-1:0] in_4_tdata,
    input  logic           [ IN4_WORD_COEFFS-1:0] in_4_tkeep,
    input  logic                                  in_4_tvalid,
    input  logic                                  in_4_tlast,
    output logic                                  in_4_tready,
`endif
    //
    input  logic           [  IN5_WORD_WIDTH-1:0] in_5_tdata,
    input  logic           [ IN5_WORD_COEFFS-1:0] in_5_tkeep,
    input  logic                                  in_5_tvalid,
    input  logic                                  in_5_tlast,
    output logic                                  in_5_tready,
    //
    output logic           [ OUT0_WORD_WIDTH-1:0] out_0_tdata,
    output logic           [OUT0_WORD_COEFFS-1:0] out_0_tkeep,
    output logic                                  out_0_tvalid,
    output logic                                  out_0_tlast,
    input  logic                                  out_0_tready,
    //
    output logic           [ OUT1_WORD_WIDTH-1:0] out_1_tdata,
    output logic           [OUT1_WORD_COEFFS-1:0] out_1_tkeep,
    output logic                                  out_1_tvalid,
    output logic                                  out_1_tlast,
    input  logic                                  out_1_tready,
    //
    output logic           [ OUT2_WORD_WIDTH-1:0] out_2_tdata,
    output logic           [OUT2_WORD_COEFFS-1:0] out_2_tkeep,
    output logic                                  out_2_tvalid,
    output logic                                  out_2_tlast,
    input  logic                                  out_2_tready
);

    // used in simulation to get the parameters
    // waiting for cocotb/cocotb#3536 to land in v2.0
    localparam int P = cross_pkg::P;
    localparam int Z = cross_pkg::Z;
    localparam int N = cross_pkg::N;
    localparam int K = cross_pkg::K;
    localparam int GEN = cross_pkg::GEN;
    localparam int T = cross_pkg::T;
    localparam int W = cross_pkg::W;
`ifdef RSDPG
    localparam int M = cross_pkg::M;
    localparam int RSDPG = 1;
`else
    localparam int RSDPG = 0;
`endif

    AXIS #(
        .DATA_WIDTH(IN0_WORD_WIDTH),
        .ELEM_WIDTH(IN0_COEFF_WIDTH)
    ) in_0 ();
    AXIS #(
        .DATA_WIDTH(IN1_WORD_WIDTH),
        .ELEM_WIDTH(IN1_COEFF_WIDTH)
    ) in_1 ();
    AXIS #(
        .DATA_WIDTH(IN2_WORD_WIDTH),
        .ELEM_WIDTH(IN2_COEFF_WIDTH)
    ) in_2 ();
    AXIS #(
        .DATA_WIDTH(IN3_WORD_WIDTH),
        .ELEM_WIDTH(IN3_COEFF_WIDTH)
    ) in_3 ();
`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(IN4_WORD_WIDTH),
        .ELEM_WIDTH(IN4_COEFF_WIDTH)
    ) in_4 ();
`endif
    AXIS #(
        .DATA_WIDTH(IN5_WORD_WIDTH),
        .ELEM_WIDTH(IN5_COEFF_WIDTH)
    ) in_5 ();
    AXIS #(
        .DATA_WIDTH(OUT0_WORD_WIDTH),
        .ELEM_WIDTH(OUT0_COEFF_WIDTH)
    ) out_0 ();
    AXIS #(
        .DATA_WIDTH(OUT1_WORD_WIDTH),
        .ELEM_WIDTH(OUT1_COEFF_WIDTH)
    ) out_1 ();
    AXIS #(
        .DATA_WIDTH(OUT2_WORD_WIDTH),
        .ELEM_WIDTH(OUT2_COEFF_WIDTH)
    ) out_2 ();

    `AXIS_EXPORT_SLAVE(in_0)
    `AXIS_EXPORT_SLAVE(in_1)
    `AXIS_EXPORT_SLAVE(in_2)
    `AXIS_EXPORT_SLAVE(in_3)
`ifdef RSDPG
    `AXIS_EXPORT_SLAVE(in_4)
`endif
    `AXIS_EXPORT_SLAVE(in_5)
    `AXIS_EXPORT_MASTER(out_0)
    `AXIS_EXPORT_MASTER(out_1)
    `AXIS_EXPORT_MASTER(out_2)

    AXIS #(
        .DATA_WIDTH(IN1_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) in_1_internal ();
    AXIS #(
        .DATA_WIDTH(IN2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) in_2_internal ();
    AXIS #(
        .DATA_WIDTH(IN3_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) in_3_internal ();
    AXIS #(
        .DATA_WIDTH(IN5_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) in_5_internal ();
    AXIS #(
        .DATA_WIDTH(OUT0_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) out_0_internal ();
    AXIS #(
        .DATA_WIDTH(OUT1_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) out_1_internal ();
    AXIS #(
        .DATA_WIDTH(OUT2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) out_2_internal ();

    AXIS #(
        .DATA_WIDTH(IN1_WORD_WIDTH),
        .ELEM_WIDTH(IN1_COEFF_WIDTH)
    ) kcomp1_in ();
    AXIS #(
        .DATA_WIDTH(IN1_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp1_out ();

    AXIS #(
        .DATA_WIDTH(IN2_WORD_WIDTH),
        .ELEM_WIDTH(IN2_COEFF_WIDTH)
    )
        kcomp2a_in (), kcomp2b_in ();
    AXIS #(
        .DATA_WIDTH(IN2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    )
        kcomp2a_out (), kcomp2b_out ();

    AXIS #(
        .DATA_WIDTH(IN3_WORD_WIDTH),
        .ELEM_WIDTH(IN3_COEFF_WIDTH)
    ) kcomp3_in ();
    AXIS #(
        .DATA_WIDTH(IN3_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kcomp3_out ();

    AXIS #(
        .DATA_WIDTH(IN5_WORD_WIDTH),
        .ELEM_WIDTH(IN5_COEFF_WIDTH)
    )
        kcomp5a_in (), kcomp5b_in ();
    AXIS #(
        .DATA_WIDTH(IN5_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    )
        kcomp5a_out (), kcomp5b_out ();

    AXIS #(
        .DATA_WIDTH(OUT0_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp0_in ();
    AXIS #(
        .DATA_WIDTH(OUT0_WORD_WIDTH),
        .ELEM_WIDTH(OUT0_COEFF_WIDTH)
    ) kdecomp0_out ();

    AXIS #(
        .DATA_WIDTH(OUT1_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp1_in ();
    AXIS #(
        .DATA_WIDTH(OUT1_WORD_WIDTH),
        .ELEM_WIDTH(OUT1_COEFF_WIDTH)
    ) kdecomp1_out ();

`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(OUT2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    )
        kdecomp2a_in (), kdecomp2b_in ();
    AXIS #(
        .DATA_WIDTH(OUT2_WORD_WIDTH),
        .ELEM_WIDTH(OUT2_COEFF_WIDTH)
    )
        kdecomp2a_out (), kdecomp2b_out ();
`else
    AXIS #(
        .DATA_WIDTH(OUT2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    ) kdecomp2_in ();
    AXIS #(
        .DATA_WIDTH(OUT2_WORD_WIDTH),
        .ELEM_WIDTH(OUT2_COEFF_WIDTH)
    ) kdecomp2_out ();
`endif

    AXIS #(
        .DATA_WIDTH(IN2_WORD_WIDTH),
        .ELEM_WIDTH(IN2_COEFF_WIDTH)
    )
        demux2_in (), demux2_out[2] ();
    AXIS #(
        .DATA_WIDTH(IN5_WORD_WIDTH),
        .ELEM_WIDTH(IN5_COEFF_WIDTH)
    )
        demux5_in (), demux5_out[2] ();
    logic demux2_sel, demux5_sel;

`ifdef RSDPG
    AXIS #(
        .DATA_WIDTH(OUT2_STREAM_WIDTH),
        .ELEM_WIDTH(8)
    )
        demuxout2_in (), demuxout2_out[2] ();
    logic demuxout2_sel;
`endif


    `AXIS_ASSIGN(kcomp1_in, in_1);
    `AXIS_ASSIGN(demux2_in, in_2);
    `AXIS_ASSIGN(kcomp3_in, in_3);
    `AXIS_ASSIGN(demux5_in, in_5);

    `AXIS_ASSIGN(kdecomp0_in, out_0_internal);
    `AXIS_ASSIGN(kdecomp1_in, out_1_internal);
`ifdef RSDPG
    `AXIS_ASSIGN(demuxout2_in, out_2_internal);
    `AXIS_ASSIGN(kdecomp2a_in, demuxout2_out[0]);
    `AXIS_ASSIGN(kdecomp2b_in, demuxout2_out[1]);
`else
    `AXIS_ASSIGN(kdecomp2_in, out_2_internal);
`endif

    `AXIS_ASSIGN(in_1_internal, kcomp1_out);
    `AXIS_ASSIGN(in_3_internal, kcomp3_out);
    `AXIS_ASSIGN(out_0, kdecomp0_out);
    `AXIS_ASSIGN(out_1, kdecomp1_out);

    `AXIS_ASSIGN(kcomp2a_in, demux2_out[0]);
    `AXIS_ASSIGN(kcomp2b_in, demux2_out[1]);
    `AXIS_ASSIGN(kcomp5a_in, demux5_out[0]);
    `AXIS_ASSIGN(kcomp5b_in, demux5_out[1]);


    localparam element_type_t ELEM_TYPE_KCOMP3 = ELEM_TYPE_FP_N;  // u', y
    localparam element_type_t ELEM_TYPE_KDECOMP0 = ELEM_TYPE_FP_NK;  // s
    localparam element_type_t ELEM_TYPE_KDECOMP1 = ELEM_TYPE_FP_N;  // y
`ifdef RSDP
    localparam element_type_t ELEM_TYPE_KCOMP1 = ELEM_TYPE_FZ_N;  // eta, eta', sigma
    localparam element_type_t ELEM_TYPE_KDECOMP2 = ELEM_TYPE_FZ_N;  // sigma
`elsif RSDPG
    localparam element_type_t ELEM_TYPE_KCOMP1 = ELEM_TYPE_FZ_M;  // zeta, zeta', delta
    localparam element_type_t ELEM_TYPE_KDECOMP2A = ELEM_TYPE_FZ_N;  // eta
    localparam element_type_t ELEM_TYPE_KDECOMP2B = ELEM_TYPE_FZ_M;  // delta
`endif

    localparam element_type_t ELEM_TYPE_KCOMP2A = ELEM_TYPE_FP_N;  // u'
    localparam element_type_t ELEM_TYPE_KCOMP2B = ELEM_TYPE_FP_NK;  // s
    localparam element_type_t ELEM_TYPE_KCOMP5A = ELEM_TYPE_FZ_N;  // eta
    localparam element_type_t ELEM_TYPE_KCOMP5B = ELEM_TYPE_FZ_M;  // zeta

    axis_keep_compress #(
        .ELEM_WIDTH(IN1_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP1)
    ) u_kcomp1 (
        .s_axis(kcomp1_in),
        .m_axis(kcomp1_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(IN2_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP2A)
    ) u_kcomp2a (
        .s_axis(kcomp2a_in),
        .m_axis(kcomp2a_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(IN2_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP2B)
    ) u_kcomp2b (
        .s_axis(kcomp2b_in),
        .m_axis(kcomp2b_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(IN3_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP3)
    ) u_kcomp3 (
        .s_axis(kcomp3_in),
        .m_axis(kcomp3_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(IN5_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP5A)
    ) u_kcomp5a (
        .s_axis(kcomp5a_in),
        .m_axis(kcomp5a_out)
    );
    axis_keep_compress #(
        .ELEM_WIDTH(IN5_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KCOMP5B)
    ) u_kcomp5b (
        .s_axis(kcomp5b_in),
        .m_axis(kcomp5b_out)
    );

    axis_keep_decompress #(
        .ELEM_WIDTH(OUT0_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KDECOMP0)
    ) u_kdecomp0 (
        .s_axis(kdecomp0_in),
        .m_axis(kdecomp0_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(OUT1_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KDECOMP1)
    ) u_kdecomp1 (
        .s_axis(kdecomp1_in),
        .m_axis(kdecomp1_out)
    );
`ifdef RSDPG
    axis_keep_decompress #(
        .ELEM_WIDTH(OUT2_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KDECOMP2A)
    ) u_kdecomp2a (
        .s_axis(kdecomp2a_in),
        .m_axis(kdecomp2a_out)
    );
    axis_keep_decompress #(
        .ELEM_WIDTH(OUT2_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KDECOMP2B)
    ) u_kdecomp2b (
        .s_axis(kdecomp2b_in),
        .m_axis(kdecomp2b_out)
    );
`else
    axis_keep_decompress #(
        .ELEM_WIDTH(OUT2_COEFF_WIDTH),
        .ELEM_TYPE (ELEM_TYPE_KDECOMP2)
    ) u_kdecomp2 (
        .s_axis(kdecomp2_in),
        .m_axis(kdecomp2_out)
    );
`endif

    axis_demux #(
        .N_MASTERS(2)
    ) u_axis_demux2 (
        .sel   (demux2_sel),
        .s_axis(demux2_in),
        .m_axis(demux2_out)
    );
    axis_demux #(
        .N_MASTERS(2)
    ) u_axis_demux5 (
        .sel   (demux5_sel),
        .s_axis(demux5_in),
        .m_axis(demux5_out)
    );
`ifdef RSDPG
    axis_demux #(
        .N_MASTERS(2)
    ) u_axis_demuxout2 (
        .sel   (demuxout2_sel),
        .s_axis(demuxout2_in),
        .m_axis(demuxout2_out)
    );
`endif

    arithmetic_op_t op_d, op_q;
    logic sel_d, sel_q;

    always_ff @(`REG_SENSITIVITY_LIST) begin
        if (!rst_n) begin
            op_q  <= ARITH_OP_INIT;
            sel_q <= 1'b0;
        end else begin
            op_q  <= op_d;
            sel_q <= sel_d;
        end
    end

    always_comb begin
        op_d  = op_q;
        sel_d = sel_q;
        if (start_i) begin
            op_d = op_i;
        end
        if (`AXIS_LAST(in_5)) begin
            sel_d = 1'b1;
        end
        if (done_o) begin
            sel_d = 1'b0;
        end
    end

    always_comb begin
        demux2_sel = 1'b0;
        demux5_sel = 1'b0;
`ifdef RSDPG
        demuxout2_sel = 1'b0;
        `AXIS_ASSIGN_PROC(out_2, kdecomp2a_out);
`else
        `AXIS_ASSIGN_PROC(out_2, kdecomp2_out);
`endif
        `AXIS_ASSIGN_PROC(in_2_internal, kcomp2a_out);
        `AXIS_ASSIGN_PROC(in_5_internal, kcomp5a_out);
`ifdef RSDPG
        if (op_q == ARITH_OP_SIGN_COMMITMENTS_PREPARATION) begin
            demuxout2_sel = 1'b1;
            `AXIS_ASSIGN_PROC(out_2, kdecomp2b_out);
        end
`endif
        if (op_q == ARITH_OP_VERIFY_CASE_B0) begin
            demux2_sel = 1'b1;
            `AXIS_ASSIGN_PROC(in_2_internal, kcomp2b_out);
        end
        if (1'(RSDPG) && (sel_q == 1'b0)) begin
            demux5_sel = 1'b1;
            `AXIS_ASSIGN_PROC(in_5_internal, kcomp5b_out);
        end
    end

    arithmetic_unit #(
        .STREAM_WIDTH  (STREAM_WIDTH),
        .MAT_DATA_WIDTH(MAT_DATA_WIDTH)
    ) arithmetic_unit_i (
        .clk_i(clk_i),
        .rst_n(rst_n),
        .start_i(start_i),
        .op_i(op_i),
        .done_o(done_o),
        .in_0(in_0),
        .in_1(in_1_internal),
        .in_2(in_2_internal),
        .in_3(in_3_internal),
`ifdef RSDPG
        .in_4(in_4),
`endif
        .in_5(in_5_internal),
        .out_0(out_0_internal),
        .out_1(out_1_internal),
        .out_2(out_2_internal)
    );

endmodule
