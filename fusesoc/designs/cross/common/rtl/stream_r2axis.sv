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
`include "stream_r.sv"

module stream_r2axis
(
    stream_r.cons   stream_r_cons,
    AXIS.master     m_axis
);

    if (stream_r_cons.WORD_SZ != m_axis.DATA_WIDTH)
        $error("m_axis.DATA_WIDTH and stream_r_cons.WORD_SZ must be equal!");

    assign m_axis.tdata = stream_r_cons.data;

    /* sha3 output is always aligned with sha3 rates */
    assign m_axis.tkeep = '1; // bytes == 0 as it is always aligned with rates

    assign m_axis.tvalid = stream_r_cons.valid & stream_r_cons.grant;

    assign stream_r_cons.request = m_axis.tready;

    assign m_axis.tlast = stream_r_cons.is_last;

    logic unused = |stream_r_cons.bytes;

endmodule
