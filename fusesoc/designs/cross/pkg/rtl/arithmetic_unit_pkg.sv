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

package arithmetic_unit_pkg;
    // prefix enum values with `ARITH_OP_` to avoid definition clashing when importing the whole package content
    typedef enum logic [2:0] {
        ARITH_OP_INIT = 0,
        ARITH_OP_KEYGEN,
        ARITH_OP_SIGN_EXPAND_ETA,
        ARITH_OP_SIGN_COMMITMENTS_PREPARATION,
        ARITH_OP_SIGN_FIRST_ROUND_RESPONSES,
        ARITH_OP_VERIFY_CASE_B0,
        ARITH_OP_VERIFY_CASE_B1
    } arithmetic_op_t;

    typedef enum logic {
        ARITH_OP_ADD = 0,
        ARITH_OP_SUB
    } add_sub_select_t;

endpackage
