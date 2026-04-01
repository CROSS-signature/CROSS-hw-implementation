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

`ifndef STREAM_W_SV
`define STREAM_W_SV

`timescale 1ps / 1ps

interface stream_w #(
    parameter int WORD_SZ = 32
) ();

    import common_pkg::*;

    localparam int BYTES_IN_BLOCK = iceilfrac(WORD_SZ, 8);
    localparam int BYTES_SZ = max($clog2(BYTES_IN_BLOCK), 1);

    logic request;
    logic grant;
    logic [WORD_SZ-1:0] data;
    logic [BYTES_SZ-1:0] bytes;
    logic is_last;  // "is_last_i" == 0 means byte number is 4, no matter what value "byte_num_i" is

    modport prod(output data, output is_last, output bytes, output request, input grant);
    modport cons(input data, input is_last, input bytes, input request, output grant);

    function automatic int get_block_sz;
        return WORD_SZ;
    endfunction

endinterface

`endif
