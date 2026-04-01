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

package sha3_pkg;

    import common_pkg::*;

    typedef enum int {
        SHA3_224  = 0,
        SHA3_256,
        SHA3_384,
        SHA3_512,
        SHAKE_128,
        SHAKE_256
    } sha3_alg_t;

    localparam int unsigned ROW_SZ = 5;
    localparam int unsigned COLUMN_SZ = 5;
    localparam int unsigned LANE_SZ = 64;  // Keccak[1600]
    localparam int unsigned X_SZ = ROW_SZ;
    localparam int unsigned Y_SZ = COLUMN_SZ;
    localparam int unsigned Z_SZ = LANE_SZ;
    localparam int unsigned STATE_SZ = ROW_SZ * COLUMN_SZ * LANE_SZ;  // X*Y*Z
    localparam int unsigned ROUNDS = 24;

    localparam int unsigned CAPACITIES[6] = '{
        448,  // SHA3_224
        512,  // SHA3_256
        768,  // SHA3_384
        1024,  // SHA3_512
        256,  // SHAKE_128
        512  // SHAKE_256
    };

    // conversion from bit string to Keccak[1600] state
    function automatic int base_idx(input int x, input int y);
        base_idx = STATE_SZ - 1 - LANE_SZ * (COLUMN_SZ * y + x) - (LANE_SZ - 1);
    endfunction

endpackage
