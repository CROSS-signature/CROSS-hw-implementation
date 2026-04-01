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
`ifndef TREE_UNIT_PKG_SV
`define TREE_UNIT_PKG_SV

package tree_unit_pkg;

    typedef enum logic [0:0] {M_SIGN, M_VERIFY} tree_unit_opcode_t;

    localparam int unsigned REM_0 = int'(cross_pkg::T % 4 > 0);
    localparam int unsigned REM_1 = int'(cross_pkg::T % 4 > 1);
    localparam int unsigned REM_2 = int'(cross_pkg::T % 4 > 2);

    localparam int unsigned OFF_1 = REM_0;
    localparam int unsigned OFF_2 = REM_0 + REM_1;
    localparam int unsigned OFF_3 = REM_0 + REM_1 + REM_2;

endpackage

`endif
