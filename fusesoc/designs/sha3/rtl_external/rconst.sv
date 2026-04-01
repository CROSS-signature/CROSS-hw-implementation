`timescale 1ps / 1ps

 /*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright 2026, Francesco Antognazza <francesco.antognazza@polimi.it>
 * Copyright 2013, Homer Hsing <homer.hsing@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Modified by Francesco Antognazza to comply with SHA3 standard and improve performance.
 */

module rconst
    import sha3_pkg::*;
(
    input  logic [ROUNDS-1:0] round_idx_i,
    output logic [  Z_SZ-1:0] round_const_o
);
    /*
    * One-hot counter to round constant combinatorial net
    */

    always_comb begin
        round_const_o = 'b0;

        round_const_o[0]  = round_idx_i[0]
                          | round_idx_i[4]
                          | round_idx_i[5]
                          | round_idx_i[6]
                          | round_idx_i[7]
                          | round_idx_i[10]
                          | round_idx_i[12]
                          | round_idx_i[13]
                          | round_idx_i[14]
                          | round_idx_i[15]
                          | round_idx_i[20]
                          | round_idx_i[22];

        round_const_o[1]  = round_idx_i[1]
                          | round_idx_i[2]
                          | round_idx_i[4]
                          | round_idx_i[8]
                          | round_idx_i[11]
                          | round_idx_i[12]
                          | round_idx_i[13]
                          | round_idx_i[15]
                          | round_idx_i[16]
                          | round_idx_i[18]
                          | round_idx_i[19];

        round_const_o[3]  = round_idx_i[2]
                          | round_idx_i[4]
                          | round_idx_i[7]
                          | round_idx_i[8]
                          | round_idx_i[9]
                          | round_idx_i[10]
                          | round_idx_i[11]
                          | round_idx_i[12]
                          | round_idx_i[13]
                          | round_idx_i[14]
                          | round_idx_i[18]
                          | round_idx_i[19]
                          | round_idx_i[23];

        round_const_o[7]  = round_idx_i[1]
                          | round_idx_i[2]
                          | round_idx_i[4]
                          | round_idx_i[6]
                          | round_idx_i[8]
                          | round_idx_i[9]
                          | round_idx_i[12]
                          | round_idx_i[13]
                          | round_idx_i[14]
                          | round_idx_i[17]
                          | round_idx_i[20]
                          | round_idx_i[21];

        round_const_o[15] = round_idx_i[1]
                          | round_idx_i[2]
                          | round_idx_i[3]
                          | round_idx_i[4]
                          | round_idx_i[6]
                          | round_idx_i[7]
                          | round_idx_i[10]
                          | round_idx_i[12]
                          | round_idx_i[14]
                          | round_idx_i[15]
                          | round_idx_i[16]
                          | round_idx_i[18]
                          | round_idx_i[20]
                          | round_idx_i[21]
                          | round_idx_i[23];

        round_const_o[31] = round_idx_i[3]
                          | round_idx_i[5]
                          | round_idx_i[6]
                          | round_idx_i[10]
                          | round_idx_i[11]
                          | round_idx_i[12]
                          | round_idx_i[19]
                          | round_idx_i[20]
                          | round_idx_i[22]
                          | round_idx_i[23];

        round_const_o[63] = round_idx_i[2]
                          | round_idx_i[3]
                          | round_idx_i[6]
                          | round_idx_i[7]
                          | round_idx_i[13]
                          | round_idx_i[14]
                          | round_idx_i[15]
                          | round_idx_i[16]
                          | round_idx_i[17]
                          | round_idx_i[19]
                          | round_idx_i[20]
                          | round_idx_i[21]
                          | round_idx_i[23];

    end
endmodule
