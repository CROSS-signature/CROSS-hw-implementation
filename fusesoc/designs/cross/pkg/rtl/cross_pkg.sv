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

package cross_pkg;

    // Opcode definition for high-level API
    typedef enum logic [1:0] {OP_KEYGEN, OP_SIGN, OP_VERIFY} cross_opcode_t;


/* RSDP Parameters */
`ifdef RSDP
    // M should be unused, but that clashes with some modules upon syntax
    // checking
    localparam int M = 1;
    localparam int P = 127;
    localparam int Z = 7;
    localparam int GEN = 2;
    localparam int SAMPLE_PAR_FZ = 3;
    localparam int SAMPLE_PAR_FP = 9;

`ifdef CATEGORY_1
    localparam int LAMBDA = 128;
    localparam int N = 127;
    localparam int K = 76;
    localparam int BYTES_ZZ_CT_RNG = 90;
    localparam int BYTES_ZP_CT_RNG = 141;
    localparam int BYTES_V_CT_RNG = 3504;
    `ifdef FAST
        localparam int T = 157;
        localparam int W = 82;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 2, 2, 58, 58};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 30, 60, 64, 128};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 1, 0, 28, 0, 128};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {185, 93, 30};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {128, 28, 1};
        localparam int TREE_NODES_TO_STORE = 82;
        localparam int BYTES_CWSTR_RNG = 457;
        localparam int BYTES_BETA_RNG = 178;
    `elsif BALANCED
        localparam int T = 256;
        localparam int W = 215;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 256};
        localparam int TREE_SUBROOTS = 1;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {255};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256};
        localparam int TREE_NODES_TO_STORE = 108;
        localparam int BYTES_CWSTR_RNG = 597;
        localparam int BYTES_BETA_RNG = 272;
    `elsif SMALL
        localparam int T = 520;
        localparam int W = 488;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 16, 16, 16, 16, 16, 16};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 16, 32, 64, 128, 256, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 512};
        localparam int TREE_SUBROOTS = 2;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {527, 23};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512, 8};
        localparam int TREE_NODES_TO_STORE = 129;
        localparam int BYTES_CWSTR_RNG = 1299;
        localparam int BYTES_BETA_RNG = 517;
    `endif
`elsif CATEGORY_3
    localparam int LAMBDA = 192;
    localparam int N = 187;
    localparam int K = 111;
    localparam int BYTES_ZZ_CT_RNG = 134;
    localparam int BYTES_ZP_CT_RNG = 210;
    localparam int BYTES_V_CT_RNG = 7589;
    `ifdef FAST
        localparam int T = 239;
        localparam int W = 125;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 2, 30};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 126, 224};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 1, 14, 224};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {253, 239, 126};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {224, 14, 1};
        localparam int TREE_NODES_TO_STORE = 125;
        localparam int BYTES_CWSTR_RNG = 658;
        localparam int BYTES_BETA_RNG = 271;
    `elsif BALANCED
        localparam int T = 384;
        localparam int W = 321;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 256};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 128, 256};
        localparam int TREE_SUBROOTS = 2;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {511, 383};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256, 128};
        localparam int TREE_NODES_TO_STORE = 165;
        localparam int BYTES_CWSTR_RNG = 1074;
        localparam int BYTES_BETA_RNG = 407;
    `elsif SMALL
        localparam int T = 580;
        localparam int W = 527;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 8, 8, 8, 8, 136, 136};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 24, 48, 96, 192, 256, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 4, 0, 0, 0, 64, 0, 512};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {647, 327, 27};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512, 64, 4};
        localparam int TREE_NODES_TO_STORE = 184;
        localparam int BYTES_CWSTR_RNG = 1610;
        localparam int BYTES_BETA_RNG = 590;
    `endif
`elsif CATEGORY_5
    localparam int LAMBDA = 256;
    localparam int N = 251;
    localparam int K = 150;
    localparam int BYTES_ZZ_CT_RNG = 179;
    localparam int BYTES_ZP_CT_RNG = 281;
    localparam int BYTES_V_CT_RNG = 13587;
    `ifdef FAST
        localparam int T = 321;
        localparam int W = 167;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 2, 2, 2, 2, 2, 2, 130};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 6, 12, 24, 48, 96, 192, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 1, 0, 0, 0, 0, 0, 64, 256};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {385, 321, 6};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256, 64, 1};
        localparam int TREE_NODES_TO_STORE = 167;
        localparam int BYTES_CWSTR_RNG = 1043;
        localparam int BYTES_BETA_RNG = 364;
    `elsif BALANCED
        localparam int T = 512;
        localparam int W = 427;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 512};
        localparam int TREE_SUBROOTS = 1;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {511};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512};
        localparam int TREE_NODES_TO_STORE = 220;
        localparam int BYTES_CWSTR_RNG = 1344;
        localparam int BYTES_BETA_RNG = 544;
    `elsif SMALL
        localparam int T = 832;
        localparam int W = 762;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 128};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 384, 768};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 768};
        localparam int TREE_SUBROOTS = 2;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {895, 447};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {768, 64};
        localparam int TREE_NODES_TO_STORE = 251;
        localparam int BYTES_CWSTR_RNG = 2269;
        localparam int BYTES_BETA_RNG = 842;
    `endif
`endif
    localparam int DIM_FZ = N;

/* RSDPG Parameters */
`elsif RSDPG
    localparam int P = 509;
    localparam int Z = 127;
    localparam int GEN = 16;
    localparam int SAMPLE_PAR_FZ = 1;
    localparam int SAMPLE_PAR_FP = 1;
`ifdef CATEGORY_1
    localparam int LAMBDA = 128;
    localparam int N = 55;
    localparam int K = 36;
    localparam int M = 25;
    localparam int BYTES_ZZ_CT_RNG = 43;
    localparam int BYTES_ZP_CT_RNG = 92;
    localparam int BYTES_V_CT_RNG = 828;
    localparam int BYTES_W_CT_RNG = 710;
    `ifdef FAST
        localparam int T = 147;
        localparam int W = 76;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 2, 6, 6, 38, 38};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 14, 24, 48, 64, 128};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 1, 2, 0, 16, 0, 128};
        localparam int TREE_SUBROOTS = 4;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {165, 85, 27, 14};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {128, 16, 2, 1};
        localparam int TREE_NODES_TO_STORE = 76;
        localparam int BYTES_CWSTR_RNG = 434;
        localparam int BYTES_BETA_RNG = 206;
    `elsif BALANCED
        localparam int T = 256;
        localparam int W = 220;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 256};
        localparam int TREE_SUBROOTS = 1;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {255};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256};
        localparam int TREE_NODES_TO_STORE = 101;
        localparam int BYTES_CWSTR_RNG = 597;
        localparam int BYTES_BETA_RNG = 336;
    `elsif SMALL
        localparam int T = 512;
        localparam int W = 484;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 512};
        localparam int TREE_SUBROOTS = 1;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {511};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512};
        localparam int TREE_NODES_TO_STORE = 117;
        localparam int BYTES_CWSTR_RNG = 1145;
        localparam int BYTES_BETA_RNG = 636;
    `endif
`elsif CATEGORY_3
    localparam int LAMBDA = 192;
    localparam int N = 79;
    localparam int K = 48;
    localparam int M = 40;
    localparam int BYTES_ZZ_CT_RNG = 68;
    localparam int BYTES_ZP_CT_RNG = 134;
    localparam int BYTES_V_CT_RNG = 1777;
    localparam int BYTES_W_CT_RNG = 1457;
    `ifdef FAST
        localparam int T = 224;
        localparam int W = 119;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 64};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 192};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 32, 192};
        localparam int TREE_SUBROOTS = 2;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {255, 223};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {192, 32};
        localparam int TREE_NODES_TO_STORE = 119;
        localparam int BYTES_CWSTR_RNG = 641;
        localparam int BYTES_BETA_RNG = 313;
    `elsif BALANCED
        localparam int T = 268;
        localparam int W = 196;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 8, 24, 24, 24, 24};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 24, 32, 64, 128, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 4, 8, 0, 0, 0, 256};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {279, 47, 27};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256, 8, 4};
        localparam int TREE_NODES_TO_STORE = 138;
        localparam int BYTES_CWSTR_RNG = 806;
        localparam int BYTES_BETA_RNG = 366;
    `elsif SMALL
        localparam int T = 512;
        localparam int W = 463;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 512};
        localparam int TREE_SUBROOTS = 1;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {511};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512};
        localparam int TREE_NODES_TO_STORE = 165;
        localparam int BYTES_CWSTR_RNG = 1248;
        localparam int BYTES_BETA_RNG = 655;
    `endif
`elsif CATEGORY_5
    localparam int LAMBDA = 256;
    localparam int N = 106;
    localparam int K = 69;
    localparam int M = 48;
    localparam int BYTES_ZZ_CT_RNG = 85;
    localparam int BYTES_ZP_CT_RNG = 179;
    localparam int BYTES_V_CT_RNG = 3024;
    localparam int BYTES_W_CT_RNG = 2575;
    `ifdef FAST
        localparam int T = 300;
        localparam int W = 153;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 8, 24, 88, 88};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 56, 96, 128, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 4, 8, 32, 0, 256};
        localparam int TREE_SUBROOTS = 4;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {343, 183, 111, 59};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256, 32, 8, 4};
        localparam int TREE_NODES_TO_STORE = 153;
        localparam int BYTES_CWSTR_RNG = 992;
        localparam int BYTES_BETA_RNG = 420;
    `elsif BALANCED
        localparam int T = 356;
        localparam int W = 258;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 0, 0, 8, 8, 8, 200};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 16, 32, 56, 112, 224, 256};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 0, 0, 4, 0, 0, 96, 256};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {455, 359, 59};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {256, 96, 4};
        localparam int TREE_NODES_TO_STORE = 185;
        localparam int BYTES_CWSTR_RNG = 1118;
        localparam int BYTES_BETA_RNG = 488;
    `elsif SMALL
        localparam int T = 642;
        localparam int W = 575;
        localparam int TREE_OFFSETS [BITS_T+1] = {0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 260};
        localparam int TREE_NODES_PER_LEVEL [BITS_T+1] = {1, 2, 4, 8, 12, 24, 48, 96, 192, 384, 512};
        localparam int TREE_LEAVES_PER_LEVEL [BITS_T+1] = {0, 0, 0, 2, 0, 0, 0, 0, 0, 128, 512};
        localparam int TREE_SUBROOTS = 3;
        localparam int TREE_LEAVES_START_INDICES [TREE_SUBROOTS] = {771, 643, 13};
        localparam int TREE_CONSECUTIVE_LEAVES [TREE_SUBROOTS] = {512, 128, 2};
        localparam int TREE_NODES_TO_STORE = 220;
        localparam int BYTES_CWSTR_RNG = 1893;
        localparam int BYTES_BETA_RNG = 825;
    `endif
`endif
    localparam int DIM_FZ = M;
`endif

    localparam int BITS_P = $clog2(P);
    localparam int BITS_Z = $clog2(Z);
    localparam int BITS_T = $clog2(T);
    localparam int BYTES_HASH = 2*LAMBDA/8;
    localparam int BYTES_SEED = LAMBDA/8;
    localparam int WORDS_PER_HASH = BYTES_HASH/8;
    localparam int WORDS_PER_SEED = BYTES_SEED/8;

`ifdef RSDP
    localparam logic [BITS_P-1:0] TAB_EXP [Z]   = {7'h01, 7'h02, 7'h04, 7'h08, 7'h10, 7'h20, 7'h40};
`elsif RSDPG
    localparam logic [BITS_P-1:0] TAB_EXP [Z] = { 9'h001, 9'h010, 9'h100, 9'h018, 9'h180, 9'h024, 9'h043, 9'h036, 9'h163, 9'h051,
                                                  9'h116, 9'h178, 9'h1a1, 9'h037, 9'h173, 9'h151, 9'h12e, 9'h0fb, 9'h1c5, 9'h07a,
                                                  9'h1a9, 9'h0b7, 9'h17f, 9'h014, 9'h140, 9'h01e, 9'h1e0, 9'h02d, 9'h0d3, 9'h142,
                                                  9'h03e, 9'h1e3, 9'h05d, 9'h1d6, 9'h18a, 9'h0c4, 9'h052, 9'h126, 9'h07b, 9'h1b9,
                                                  9'h1b7, 9'h197, 9'h194, 9'h164, 9'h061, 9'h019, 9'h190, 9'h124, 9'h05b, 9'h1b6,
                                                  9'h187, 9'h094, 9'h14c, 9'h0de, 9'h1f2, 9'h14d, 9'h0ee, 9'h0f5, 9'h165, 9'h071,
                                                  9'h119, 9'h1a8, 9'h0a7, 9'h07f, 9'h1f9, 9'h1bd, 9'h1f7, 9'h19d, 9'h1f4, 9'h16d,
                                                  9'h0f1, 9'h125, 9'h06b, 9'h0b9, 9'h19f, 9'h017, 9'h170, 9'h121, 9'h02b, 9'h0b3,
                                                  9'h13f, 9'h00e, 9'h0e0, 9'h015, 9'h150, 9'h11e, 9'h1f8, 9'h1ad, 9'h0f7, 9'h185,
                                                  9'h074, 9'h149, 9'h0ae, 9'h0ef, 9'h105, 9'h068, 9'h089, 9'h09c, 9'h1cc, 9'h0ea,
                                                  9'h0b5, 9'h15f, 9'h011, 9'h110, 9'h118, 9'h198, 9'h1a4, 9'h067, 9'h079, 9'h199,
                                                  9'h1b4, 9'h167, 9'h091, 9'h11c, 9'h1d8, 9'h1aa, 9'h0c7, 9'h082, 9'h02c, 9'h0c3,
                                                  9'h042, 9'h026, 9'h063, 9'h039, 9'h193, 9'h154, 9'h15e };

`endif

    localparam int ELEM_TYPES = 7;
    localparam int ELEM_TYPES_SZ = $clog2(ELEM_TYPES);
    typedef enum logic [ELEM_TYPES_SZ-1:0] {
        ELEM_TYPE_FZ_NM   = 0,
        ELEM_TYPE_FZ_M,
        ELEM_TYPE_FZ_N,
        ELEM_TYPE_FP_NK,
        ELEM_TYPE_FP_N,
        ELEM_TYPE_FP_K,
        ELEM_TYPE_FP_STAR
    } element_type_t;
`ifdef RSDP
    // M is not defined, put a safe value (0 could trigger some problems)
    localparam int ELEM_COEFFS[ELEM_TYPES] = '{1, 1, N, N - K, N, K, 1};
`elsif RSDPG
    localparam int ELEM_COEFFS[ELEM_TYPES] = '{N - M, M, N, N - K, N, K, 1};
`endif

`ifdef FAST
    localparam int unsigned MAX_DIGESTS = cross_pkg::T/4 + 1;
`else
    localparam int unsigned MAX_DIGESTS = 2;
`endif

endpackage
