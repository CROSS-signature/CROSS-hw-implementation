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

package packing_unit_pkg;

    enum logic [1:0] {M_PASSTHROUGH=2'b00, M_PACK_FZ=2'b01, M_PACK_FP=2'b10, M_PACK_S=2'b11} pack_t;

    enum logic [1:0] {M_UNPACK_BP=2'b00, M_UNPACK_FZ=2'b01, M_UNPACK_FP=2'b10, M_UNPACK_S=2'b11} unpack_t;

    // Used externally
    typedef enum logic [$clog2(3)-1:0] {BP=2'b00, SYN=2'b01, RSP=2'b10} decomp_mode_t;

endpackage
