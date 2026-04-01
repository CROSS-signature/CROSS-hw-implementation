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
`ifndef SAMPLE_UNIT_PKG_SV
`define SAMPLE_UNIT_PKG_SV

package sample_unit_pkg;

    /* Datatype for mode configuration */
    /* Same opcodes for RSDP and RSDPG, as only the dimension of F_z and the additional matrix W is sampled. */
    /* W is sampled from the same seed as V_T and thus, is only additional logic in the corresponding state. */
    /* This additional logic is fenced withim sample_unit.sv */
    typedef enum logic [2:0] {M_SQUEEZE, M_SAMPLE_FZ, M_SAMPLE_FZ_FP, M_SAMPLE_VT_W, M_SAMPLE_B, M_SAMPLE_BETA} sample_op_t;
    typedef enum logic [0:0] {LAMBDA, LAMBDA_2} digest_t;


endpackage

`endif
