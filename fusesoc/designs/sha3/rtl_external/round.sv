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

module round
    import sha3_pkg::*;
(
    input  logic [STATE_SZ-1:0] state_i,
    input  logic [    Z_SZ-1:0] round_const_i,
    output logic [STATE_SZ-1:0] state_o
);

    // left rotation (a right rotation would use `>> n`)
    function automatic logic [Z_SZ-1:0] rot_up(input logic [Z_SZ-1:0] in, input int n);
        rot_up = Z_SZ'({2{in}} >> (Z_SZ - n));
    endfunction

    logic [Z_SZ-1:0] in_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] theta_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] rho_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] pi_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] chi_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] iota_state[X_SZ-1:0][Y_SZ-1:0];
    logic [Z_SZ-1:0] column_checksum[X_SZ-1:0];

    /*
      Converting Strings to State Arrays, and viceversa.
      For all triples (x, y, z) such that 0 ≤ x <5, 0 ≤ y < 5, and 0 ≤ z < w,
          A[x, y, z] = S[w(5y +x) + z]
    */
    generate
        for (genvar y = 0; y < Y_SZ; y++) begin : gen_in_state_y_dim
            for (genvar x = 0; x < X_SZ; x++) begin : gen_in_state_x_dim
                assign in_state[x][y] = state_i[base_idx(x, y)+:LANE_SZ];
            end
        end

        for (genvar y = 0; y < Y_SZ; y++) begin : gen_state_y_dim
            for (genvar x = 0; x < X_SZ; x++) begin : gen_state_x_dim
                assign state_o[base_idx(x, y)+:LANE_SZ] = iota_state[x][y];
            end
        end
    endgenerate



    /*
     *
     * THETA COMPUTATION
     *
     * The effect of θ is to XOR each bit in the state with the parities of two columns in the array.
     * In particular, for the bit A[x_0, y_0, z_0], the x-coordinate of one of the columns is (x_0 - 1) mod 5,
     * with the same z-coordinate, z_0, while the x-coordinate of the other column is (x_0 + 1) mod 5, with
     * z-coordinate (z_0 - 1) mod w
     *
     */

    generate //  Theta subroutine: compute column checksums in_state[x][0] ^ in_state[x][1] ^ ... ^ in_state[x][4]
        for (genvar x = 0; x < X_SZ; x++) begin : gen_col_chksum
            // performed sheet-wise, so 64 checksums are carried out in parallel
            assign column_checksum[x] = in_state[x][0] ^ in_state[x][1] ^ in_state[x][2] ^ in_state[x][3] ^ in_state[x][4];
        end

        for (genvar y = 0; y < Y_SZ; y++) begin : gen_theta_state_y_dim
            for (genvar x = 0; x < X_SZ; x++) begin : gen_theta_state_x_dim
                // compute lane-wise, for each bit in the same column, the checksums used are the same
                assign theta_state[x][y] = in_state[x][y] ^ column_checksum[(5+x-1)%5] ^ rot_up(
                    column_checksum[(x+1)%5], 1
                );
            end
        end
    endgenerate



    /*
     *
     * RHO COMPUTATION
     *
     * The effect of ρ is to rotate the bits of each lane by a length, called the offset, which depends on
     * the fixed x and y coordinates of the lane.
     * Equivalently, for each bit in the lane, the z coordinate is modified by adding the offset, modulo the lane size.
     */
    assign rho_state[0][0] = theta_state[0][0];
    assign rho_state[1][0] = rot_up(theta_state[1][0], 1);
    assign rho_state[2][0] = rot_up(theta_state[2][0], 62);
    assign rho_state[3][0] = rot_up(theta_state[3][0], 28);
    assign rho_state[4][0] = rot_up(theta_state[4][0], 27);
    assign rho_state[0][1] = rot_up(theta_state[0][1], 36);
    assign rho_state[1][1] = rot_up(theta_state[1][1], 44);
    assign rho_state[2][1] = rot_up(theta_state[2][1], 6);
    assign rho_state[3][1] = rot_up(theta_state[3][1], 55);
    assign rho_state[4][1] = rot_up(theta_state[4][1], 20);
    assign rho_state[0][2] = rot_up(theta_state[0][2], 3);
    assign rho_state[1][2] = rot_up(theta_state[1][2], 10);
    assign rho_state[2][2] = rot_up(theta_state[2][2], 43);
    assign rho_state[3][2] = rot_up(theta_state[3][2], 25);
    assign rho_state[4][2] = rot_up(theta_state[4][2], 39);
    assign rho_state[0][3] = rot_up(theta_state[0][3], 41);
    assign rho_state[1][3] = rot_up(theta_state[1][3], 45);
    assign rho_state[2][3] = rot_up(theta_state[2][3], 15);
    assign rho_state[3][3] = rot_up(theta_state[3][3], 21);
    assign rho_state[4][3] = rot_up(theta_state[4][3], 8);
    assign rho_state[0][4] = rot_up(theta_state[0][4], 18);
    assign rho_state[1][4] = rot_up(theta_state[1][4], 2);
    assign rho_state[2][4] = rot_up(theta_state[2][4], 61);
    assign rho_state[3][4] = rot_up(theta_state[3][4], 56);
    assign rho_state[4][4] = rot_up(theta_state[4][4], 14);



    /*
     *
     * PI COMPUTATION
     *
     * The effect of π is to rearrange the positions of the lanes, as illustrated for any slice in Figure 5 below.
     * The bit with coordinates x = y = 0 is depicted at the center of the slice.
     *
     */
    assign pi_state[0][0]  = rho_state[0][0];
    assign pi_state[0][2]  = rho_state[1][0];
    assign pi_state[0][4]  = rho_state[2][0];
    assign pi_state[0][1]  = rho_state[3][0];
    assign pi_state[0][3]  = rho_state[4][0];
    assign pi_state[1][3]  = rho_state[0][1];
    assign pi_state[1][0]  = rho_state[1][1];
    assign pi_state[1][2]  = rho_state[2][1];
    assign pi_state[1][4]  = rho_state[3][1];
    assign pi_state[1][1]  = rho_state[4][1];
    assign pi_state[2][1]  = rho_state[0][2];
    assign pi_state[2][3]  = rho_state[1][2];
    assign pi_state[2][0]  = rho_state[2][2];
    assign pi_state[2][2]  = rho_state[3][2];
    assign pi_state[2][4]  = rho_state[4][2];
    assign pi_state[3][4]  = rho_state[0][3];
    assign pi_state[3][1]  = rho_state[1][3];
    assign pi_state[3][3]  = rho_state[2][3];
    assign pi_state[3][0]  = rho_state[3][3];
    assign pi_state[3][2]  = rho_state[4][3];
    assign pi_state[4][2]  = rho_state[0][4];
    assign pi_state[4][4]  = rho_state[1][4];
    assign pi_state[4][1]  = rho_state[2][4];
    assign pi_state[4][3]  = rho_state[3][4];
    assign pi_state[4][0]  = rho_state[4][4];



    /*
     *
     * CHI COMPUTATION
     *
     * The effect of χ is to XOR each bit with a non-linear function of two other bits in its row
     *
     */
    generate
        for (genvar y = 0; y < Y_SZ; y++) begin : gen_chi_state_y_dim
            for (genvar x = 0; x < X_SZ; x++) begin : gen_chi_state_x_dim
                assign chi_state[x][y] = pi_state[x][y] ^ ((~pi_state[(x+1)%5][y]) & pi_state[(x+2)%5][y]);
            end
        end
    endgenerate



    /*
     *
     * IOTA COMPUTATION
     *
     * The effect of ι is to modify some of the bits of Lane (0, 0) in a manner that depends on the round index ir.
     * The other 24 lanes are not affected by ι.
     *
     */
    always_comb begin
        iota_state = chi_state;
        iota_state[0][0] ^= round_const_i;
    end

endmodule
