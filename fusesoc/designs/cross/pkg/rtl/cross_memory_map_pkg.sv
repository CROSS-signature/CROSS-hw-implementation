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

 // Below is auto-generated stuff that is partially useless but
 // included nevertheless due to lazyness of cleaning the script.

package cross_memory_map_pkg;

/* RSDP Parameters */
`ifdef RSDP

`ifdef CATEGORY_1
    `ifdef FAST
        localparam int unsigned MEM0_AW = 12;
        localparam int unsigned MEM0_DEPTH = 2859;
        localparam logic [12-1:0] MEM0_ADDR_SK_SEED        = 12'h000;
        localparam logic [12-1:0] MEM0_ADDR_PK_SEED        = 12'h004;
        localparam logic [12-1:0] MEM0_ADDR_PK_S           = 12'h008;
        localparam logic [12-1:0] MEM0_ADDR_SALT           = 12'h00e;
        localparam logic [12-1:0] MEM0_ADDR_D1_D01         = 12'h012;
        localparam logic [12-1:0] MEM0_ADDR_DM_DBETA_DB    = 12'h016;
        localparam logic [12-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 12'h01a;
        localparam logic [12-1:0] MEM0_ADDR_SEEDE_ETA      = 12'h465;
        localparam logic [12-1:0] MEM0_ADDR_SIGMA_I        = 12'h46c;
        localparam logic [12-1:0] MEM0_ADDR_CMT_1          = 12'h8b7;

        localparam int unsigned MEM1_AW = 12;
        localparam int unsigned MEM1_DEPTH = 2355;
        localparam logic [12-1:0] MEM1_ADDR_U_Y = 12'h000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 2304;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h004;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h008;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h0b0;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h1f8;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h324;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 4641;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED        = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED        = 13'h0004;
        localparam logic [13-1:0] MEM0_ADDR_PK_S           = 13'h0008;
        localparam logic [13-1:0] MEM0_ADDR_SALT           = 13'h000e;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01         = 13'h0012;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB    = 13'h0016;
        localparam logic [13-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 13'h001a;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA      = 13'h071a;
        localparam logic [13-1:0] MEM0_ADDR_SIGMA_I        = 13'h0721;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1          = 13'h0e21;

        localparam int unsigned MEM1_AW = 12;
        localparam int unsigned MEM1_DEPTH = 3840;
        localparam logic [12-1:0] MEM1_ADDR_U_Y = 12'h000;

        localparam int unsigned SIGMEM_AW = 11;
        localparam int unsigned SIGMEM_DEPTH = 1644;
        localparam logic [11-1:0] SIGMEM_ADDR_SALT          = 11'h000;
        localparam logic [11-1:0] SIGMEM_ADDR_D01           = 11'h004;
        localparam logic [11-1:0] SIGMEM_ADDR_DB            = 11'h008;
        localparam logic [11-1:0] SIGMEM_ADDR_SEED_PATHS    = 11'h00c;
        localparam logic [11-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 11'h0e4;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP1          = 11'h294;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP0          = 11'h338;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 9393;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED        = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED        = 14'h0004;
        localparam logic [14-1:0] MEM0_ADDR_PK_S           = 14'h0008;
        localparam logic [14-1:0] MEM0_ADDR_SALT           = 14'h000e;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01         = 14'h0012;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB    = 14'h0016;
        localparam logic [14-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 14'h001a;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA      = 14'h0e52;
        localparam logic [14-1:0] MEM0_ADDR_SIGMA_I        = 14'h0e59;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1          = 14'h1c91;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 7800;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 11;
        localparam int unsigned SIGMEM_DEPTH = 1554;
        localparam logic [11-1:0] SIGMEM_ADDR_SALT          = 11'h000;
        localparam logic [11-1:0] SIGMEM_ADDR_D01           = 11'h004;
        localparam logic [11-1:0] SIGMEM_ADDR_DB            = 11'h008;
        localparam logic [11-1:0] SIGMEM_ADDR_SEED_PATHS    = 11'h00c;
        localparam logic [11-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 11'h10e;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP1          = 11'h312;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP0          = 11'h392;
    `endif
`elsif CATEGORY_3
    `ifdef FAST
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 5784;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED        = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED        = 13'h0006;
        localparam logic [13-1:0] MEM0_ADDR_PK_S           = 13'h000c;
        localparam logic [13-1:0] MEM0_ADDR_SALT           = 13'h0015;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01         = 13'h001b;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB    = 13'h0021;
        localparam logic [13-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 13'h0027;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA      = 13'h088e;
        localparam logic [13-1:0] MEM0_ADDR_SIGMA_I        = 13'h0897;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1          = 13'h10fe;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 5019;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 5176;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0006;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h000c;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0012;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h0189;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h0477;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0723;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 9264;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED        = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED        = 14'h0006;
        localparam logic [14-1:0] MEM0_ADDR_PK_S           = 14'h000c;
        localparam logic [14-1:0] MEM0_ADDR_SALT           = 14'h0015;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01         = 14'h001b;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB    = 14'h0021;
        localparam logic [14-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 14'h0027;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA      = 14'h0da7;
        localparam logic [14-1:0] MEM0_ADDR_SIGMA_I        = 14'h0db0;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1          = 14'h1b30;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 8064;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 3732;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h006;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h012;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h201;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h5df;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h759;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 13968;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED        = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED        = 14'h0006;
        localparam logic [14-1:0] MEM0_ADDR_PK_S           = 14'h000c;
        localparam logic [14-1:0] MEM0_ADDR_SALT           = 14'h0015;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01         = 14'h001b;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB    = 14'h0021;
        localparam logic [14-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 14'h0027;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA      = 14'h148b;
        localparam logic [14-1:0] MEM0_ADDR_SIGMA_I        = 14'h1494;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1          = 14'h28f8;

        localparam int unsigned MEM1_AW = 14;
        localparam int unsigned MEM1_DEPTH = 12180;
        localparam logic [14-1:0] MEM1_ADDR_U_Y = 14'h0000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 3549;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h006;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h012;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h23a;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h68a;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h7c8;
    `endif
`elsif CATEGORY_5
    `ifdef FAST
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 10336;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED        = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED        = 14'h0008;
        localparam logic [14-1:0] MEM0_ADDR_PK_S           = 14'h0010;
        localparam logic [14-1:0] MEM0_ADDR_SALT           = 14'h001c;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01         = 14'h0024;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB    = 14'h002c;
        localparam logic [14-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 14'h0034;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA      = 14'h0f40;
        localparam logic [14-1:0] MEM0_ADDR_SIGMA_I        = 14'h0f4c;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1          = 14'h1e58;

        localparam int unsigned MEM1_AW = 14;
        localparam int unsigned MEM1_DEPTH = 8988;
        localparam logic [14-1:0] MEM1_ADDR_U_Y = 14'h0000;

        localparam int unsigned SIGMEM_AW = 14;
        localparam int unsigned SIGMEM_DEPTH = 9324;
        localparam logic [14-1:0] SIGMEM_ADDR_SALT          = 14'h0000;
        localparam logic [14-1:0] SIGMEM_ADDR_D01           = 14'h0008;
        localparam logic [14-1:0] SIGMEM_ADDR_DB            = 14'h0010;
        localparam logic [14-1:0] SIGMEM_ADDR_SEED_PATHS    = 14'h0018;
        localparam logic [14-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 14'h02b4;
        localparam logic [14-1:0] SIGMEM_ADDR_RSP1          = 14'h07ec;
        localparam logic [14-1:0] SIGMEM_ADDR_RSP0          = 14'h0cbc;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 15;
        localparam int unsigned MEM0_DEPTH = 16448;
        localparam logic [15-1:0] MEM0_ADDR_SK_SEED        = 15'h0000;
        localparam logic [15-1:0] MEM0_ADDR_PK_SEED        = 15'h0008;
        localparam logic [15-1:0] MEM0_ADDR_PK_S           = 15'h0010;
        localparam logic [15-1:0] MEM0_ADDR_SALT           = 15'h001c;
        localparam logic [15-1:0] MEM0_ADDR_D1_D01         = 15'h0024;
        localparam logic [15-1:0] MEM0_ADDR_DM_DBETA_DB    = 15'h002c;
        localparam logic [15-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 15'h0034;
        localparam logic [15-1:0] MEM0_ADDR_SEEDE_ETA      = 15'h1834;
        localparam logic [15-1:0] MEM0_ADDR_SIGMA_I        = 15'h1840;
        localparam logic [15-1:0] MEM0_ADDR_CMT_1          = 15'h3040;

        localparam int unsigned MEM1_AW = 14;
        localparam int unsigned MEM1_DEPTH = 14336;
        localparam logic [14-1:0] MEM1_ADDR_U_Y = 14'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 6691;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0008;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h0010;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0018;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h0388;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h0a68;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0d10;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 15;
        localparam int unsigned MEM0_DEPTH = 26688;
        localparam logic [15-1:0] MEM0_ADDR_SK_SEED        = 15'h0000;
        localparam logic [15-1:0] MEM0_ADDR_PK_SEED        = 15'h0008;
        localparam logic [15-1:0] MEM0_ADDR_PK_S           = 15'h0010;
        localparam logic [15-1:0] MEM0_ADDR_SALT           = 15'h001c;
        localparam logic [15-1:0] MEM0_ADDR_D1_D01         = 15'h0024;
        localparam logic [15-1:0] MEM0_ADDR_DM_DBETA_DB    = 15'h002c;
        localparam logic [15-1:0] MEM0_ADDR_ETA_ZETA_PRIME = 15'h0034;
        localparam logic [15-1:0] MEM0_ADDR_SEEDE_ETA      = 15'h2734;
        localparam logic [15-1:0] MEM0_ADDR_SIGMA_I        = 15'h2740;
        localparam logic [15-1:0] MEM0_ADDR_CMT_1          = 15'h4e40;

        localparam int unsigned MEM1_AW = 15;
        localparam int unsigned MEM1_DEPTH = 23296;
        localparam logic [15-1:0] MEM1_ADDR_U_Y = 15'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 6353;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0008;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h0010;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0018;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h0404;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h0bdc;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0e0c;
    `endif
`endif

/* RSDPG Parameters */
`elsif RSDPG
`ifdef CATEGORY_1
    `ifdef FAST
        localparam int unsigned MEM0_AW = 11;
        localparam int unsigned MEM0_DEPTH = 1503;
        localparam logic [11-1:0] MEM0_ADDR_SK_SEED     = 11'h000;
        localparam logic [11-1:0] MEM0_ADDR_PK_SEED     = 11'h004;
        localparam logic [11-1:0] MEM0_ADDR_PK_S        = 11'h008;
        localparam logic [11-1:0] MEM0_ADDR_SALT        = 11'h00b;
        localparam logic [11-1:0] MEM0_ADDR_D1_D01      = 11'h00f;
        localparam logic [11-1:0] MEM0_ADDR_DM_DBETA_DB = 11'h013;
        localparam logic [11-1:0] MEM0_ADDR_ZETA_PRIME  = 11'h017;
        localparam logic [11-1:0] MEM0_ADDR_ZETA        = 11'h1d0;
        localparam logic [11-1:0] MEM0_ADDR_SEEDE_ETA   = 11'h1d3;
        localparam logic [11-1:0] MEM0_ADDR_DELTA_I     = 11'h1da;
        localparam logic [11-1:0] MEM0_ADDR_CMT_1       = 11'h393;

        localparam int unsigned MEM1_AW = 11;
        localparam int unsigned MEM1_DEPTH = 1176;
        localparam logic [11-1:0] MEM1_ADDR_U_Y = 11'h000;

        localparam int unsigned SIGMEM_AW = 11;
        localparam int unsigned SIGMEM_DEPTH = 1498;
        localparam logic [11-1:0] SIGMEM_ADDR_SALT          = 11'h000;
        localparam logic [11-1:0] SIGMEM_ADDR_D01           = 11'h004;
        localparam logic [11-1:0] SIGMEM_ADDR_DB            = 11'h008;
        localparam logic [11-1:0] SIGMEM_ADDR_SEED_PATHS    = 11'h00c;
        localparam logic [11-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 11'h0a4;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP1          = 11'h1d4;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP0          = 11'h2f0;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 12;
        localparam int unsigned MEM0_DEPTH = 2593;
        localparam logic [12-1:0] MEM0_ADDR_SK_SEED     = 12'h000;
        localparam logic [12-1:0] MEM0_ADDR_PK_SEED     = 12'h004;
        localparam logic [12-1:0] MEM0_ADDR_PK_S        = 12'h008;
        localparam logic [12-1:0] MEM0_ADDR_SALT        = 12'h00b;
        localparam logic [12-1:0] MEM0_ADDR_D1_D01      = 12'h00f;
        localparam logic [12-1:0] MEM0_ADDR_DM_DBETA_DB = 12'h013;
        localparam logic [12-1:0] MEM0_ADDR_ZETA_PRIME  = 12'h017;
        localparam logic [12-1:0] MEM0_ADDR_ZETA        = 12'h317;
        localparam logic [12-1:0] MEM0_ADDR_SEEDE_ETA   = 12'h31a;
        localparam logic [12-1:0] MEM0_ADDR_DELTA_I     = 12'h321;
        localparam logic [12-1:0] MEM0_ADDR_CMT_1       = 12'h621;

        localparam int unsigned MEM1_AW = 11;
        localparam int unsigned MEM1_DEPTH = 2048;
        localparam logic [11-1:0] MEM1_ADDR_U_Y = 11'h000;

        localparam int unsigned SIGMEM_AW = 11;
        localparam int unsigned SIGMEM_DEPTH = 1140;
        localparam logic [11-1:0] SIGMEM_ADDR_SALT          = 11'h000;
        localparam logic [11-1:0] SIGMEM_ADDR_D01           = 11'h004;
        localparam logic [11-1:0] SIGMEM_ADDR_DB            = 11'h008;
        localparam logic [11-1:0] SIGMEM_ADDR_SEED_PATHS    = 11'h00c;
        localparam logic [11-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 11'h0d6;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP1          = 11'h26a;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP0          = 11'h2fa;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 5153;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED     = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED     = 13'h0004;
        localparam logic [13-1:0] MEM0_ADDR_PK_S        = 13'h0008;
        localparam logic [13-1:0] MEM0_ADDR_SALT        = 13'h000b;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01      = 13'h000f;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB = 13'h0013;
        localparam logic [13-1:0] MEM0_ADDR_ZETA_PRIME  = 13'h0017;
        localparam logic [13-1:0] MEM0_ADDR_ZETA        = 13'h0617;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA   = 13'h061a;
        localparam logic [13-1:0] MEM0_ADDR_DELTA_I     = 13'h0621;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1       = 13'h0c21;

        localparam int unsigned MEM1_AW = 12;
        localparam int unsigned MEM1_DEPTH = 4096;
        localparam logic [12-1:0] MEM1_ADDR_U_Y = 12'h000;

        localparam int unsigned SIGMEM_AW = 11;
        localparam int unsigned SIGMEM_DEPTH = 1120;
        localparam logic [11-1:0] SIGMEM_ADDR_SALT          = 11'h000;
        localparam logic [11-1:0] SIGMEM_ADDR_D01           = 11'h004;
        localparam logic [11-1:0] SIGMEM_ADDR_DB            = 11'h008;
        localparam logic [11-1:0] SIGMEM_ADDR_SEED_PATHS    = 11'h00c;
        localparam logic [11-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 11'h0f6;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP1          = 11'h2ca;
        localparam logic [11-1:0] SIGMEM_ADDR_RSP0          = 11'h33a;
    `endif
`elsif CATEGORY_3
    `ifdef FAST
        localparam int unsigned MEM0_AW = 12;
        localparam int unsigned MEM0_DEPTH = 3633;
        localparam logic [12-1:0] MEM0_ADDR_SK_SEED     = 12'h000;
        localparam logic [12-1:0] MEM0_ADDR_PK_SEED     = 12'h006;
        localparam logic [12-1:0] MEM0_ADDR_PK_S        = 12'h00c;
        localparam logic [12-1:0] MEM0_ADDR_SALT        = 12'h011;
        localparam logic [12-1:0] MEM0_ADDR_D1_D01      = 12'h017;
        localparam logic [12-1:0] MEM0_ADDR_DM_DBETA_DB = 12'h01d;
        localparam logic [12-1:0] MEM0_ADDR_ZETA_PRIME  = 12'h023;
        localparam logic [12-1:0] MEM0_ADDR_ZETA        = 12'h483;
        localparam logic [12-1:0] MEM0_ADDR_SEEDE_ETA   = 12'h488;
        localparam logic [12-1:0] MEM0_ADDR_DELTA_I     = 12'h491;
        localparam logic [12-1:0] MEM0_ADDR_CMT_1       = 12'h8f1;

        localparam int unsigned MEM1_AW = 12;
        localparam int unsigned MEM1_DEPTH = 2688;
        localparam logic [12-1:0] MEM1_ADDR_U_Y = 12'h000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 3347;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h006;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h012;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h177;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h441;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h6b7;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 4337;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED     = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED     = 13'h0006;
        localparam logic [13-1:0] MEM0_ADDR_PK_S        = 13'h000c;
        localparam logic [13-1:0] MEM0_ADDR_SALT        = 13'h0011;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01      = 13'h0017;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB = 13'h001d;
        localparam logic [13-1:0] MEM0_ADDR_ZETA_PRIME  = 13'h0023;
        localparam logic [13-1:0] MEM0_ADDR_ZETA        = 13'h055f;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA   = 13'h0564;
        localparam logic [13-1:0] MEM0_ADDR_DELTA_I     = 13'h056d;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1       = 13'h0aa9;

        localparam int unsigned MEM1_AW = 12;
        localparam int unsigned MEM1_DEPTH = 3216;
        localparam logic [12-1:0] MEM1_ADDR_U_Y = 12'h000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 2808;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h006;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h012;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h1b0;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h4ec;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h69c;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 8241;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED     = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED     = 14'h0006;
        localparam logic [14-1:0] MEM0_ADDR_PK_S        = 14'h000c;
        localparam logic [14-1:0] MEM0_ADDR_SALT        = 14'h0011;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01      = 14'h0017;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB = 14'h001d;
        localparam logic [14-1:0] MEM0_ADDR_ZETA_PRIME  = 14'h0023;
        localparam logic [14-1:0] MEM0_ADDR_ZETA        = 14'h0a23;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA   = 14'h0a28;
        localparam logic [14-1:0] MEM0_ADDR_DELTA_I     = 14'h0a31;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1       = 14'h1431;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 6144;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 12;
        localparam int unsigned SIGMEM_DEPTH = 2557;
        localparam logic [12-1:0] SIGMEM_ADDR_SALT          = 12'h000;
        localparam logic [12-1:0] SIGMEM_ADDR_D01           = 12'h006;
        localparam logic [12-1:0] SIGMEM_ADDR_DB            = 12'h00c;
        localparam logic [12-1:0] SIGMEM_ADDR_SEED_PATHS    = 12'h012;
        localparam logic [12-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 12'h201;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP1          = 12'h5df;
        localparam logic [12-1:0] SIGMEM_ADDR_RSP0          = 12'h705;
    `endif
`elsif CATEGORY_5
    `ifdef FAST
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 6064;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED     = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED     = 13'h0008;
        localparam logic [13-1:0] MEM0_ADDR_PK_S        = 13'h0010;
        localparam logic [13-1:0] MEM0_ADDR_SALT        = 13'h0016;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01      = 13'h001e;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB = 13'h0026;
        localparam logic [13-1:0] MEM0_ADDR_ZETA_PRIME  = 13'h002e;
        localparam logic [13-1:0] MEM0_ADDR_ZETA        = 13'h0736;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA   = 13'h073c;
        localparam logic [13-1:0] MEM0_ADDR_DELTA_I     = 13'h0748;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1       = 13'h0e50;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 4800;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 6013;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0008;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h0010;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0018;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h027c;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h0744;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0bdc;
    `elsif BALANCED
        localparam int unsigned MEM0_AW = 13;
        localparam int unsigned MEM0_DEPTH = 7184;
        localparam logic [13-1:0] MEM0_ADDR_SK_SEED     = 13'h0000;
        localparam logic [13-1:0] MEM0_ADDR_PK_SEED     = 13'h0008;
        localparam logic [13-1:0] MEM0_ADDR_PK_S        = 13'h0010;
        localparam logic [13-1:0] MEM0_ADDR_SALT        = 13'h0016;
        localparam logic [13-1:0] MEM0_ADDR_D1_D01      = 13'h001e;
        localparam logic [13-1:0] MEM0_ADDR_DM_DBETA_DB = 13'h0026;
        localparam logic [13-1:0] MEM0_ADDR_ZETA_PRIME  = 13'h002e;
        localparam logic [13-1:0] MEM0_ADDR_ZETA        = 13'h0886;
        localparam logic [13-1:0] MEM0_ADDR_SEEDE_ETA   = 13'h088c;
        localparam logic [13-1:0] MEM0_ADDR_DELTA_I     = 13'h0898;
        localparam logic [13-1:0] MEM0_ADDR_CMT_1       = 13'h10f0;

        localparam int unsigned MEM1_AW = 13;
        localparam int unsigned MEM1_DEPTH = 5696;
        localparam logic [13-1:0] MEM1_ADDR_U_Y = 13'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 5013;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0008;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h0010;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0018;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h02fc;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h08c4;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0bd4;
    `elsif SMALL
        localparam int unsigned MEM0_AW = 14;
        localparam int unsigned MEM0_DEPTH = 12904;
        localparam logic [14-1:0] MEM0_ADDR_SK_SEED     = 14'h0000;
        localparam logic [14-1:0] MEM0_ADDR_PK_SEED     = 14'h0008;
        localparam logic [14-1:0] MEM0_ADDR_PK_S        = 14'h0010;
        localparam logic [14-1:0] MEM0_ADDR_SALT        = 14'h0016;
        localparam logic [14-1:0] MEM0_ADDR_D1_D01      = 14'h001e;
        localparam logic [14-1:0] MEM0_ADDR_DM_DBETA_DB = 14'h0026;
        localparam logic [14-1:0] MEM0_ADDR_ZETA_PRIME  = 14'h002e;
        localparam logic [14-1:0] MEM0_ADDR_ZETA        = 14'h0f3a;
        localparam logic [14-1:0] MEM0_ADDR_SEEDE_ETA   = 14'h0f40;
        localparam logic [14-1:0] MEM0_ADDR_DELTA_I     = 14'h0f4c;
        localparam logic [14-1:0] MEM0_ADDR_CMT_1       = 14'h1e58;

        localparam int unsigned MEM1_AW = 14;
        localparam int unsigned MEM1_DEPTH = 10272;
        localparam logic [14-1:0] MEM1_ADDR_U_Y = 14'h0000;

        localparam int unsigned SIGMEM_AW = 13;
        localparam int unsigned SIGMEM_DEPTH = 4557;
        localparam logic [13-1:0] SIGMEM_ADDR_SALT          = 13'h0000;
        localparam logic [13-1:0] SIGMEM_ADDR_D01           = 13'h0008;
        localparam logic [13-1:0] SIGMEM_ADDR_DB            = 13'h0010;
        localparam logic [13-1:0] SIGMEM_ADDR_SEED_PATHS    = 13'h0018;
        localparam logic [13-1:0] SIGMEM_ADDR_MERKLE_PROOFS = 13'h0388;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP1          = 13'h0a68;
        localparam logic [13-1:0] SIGMEM_ADDR_RSP0          = 13'h0c80;
    `endif
`endif
`endif
endpackage
