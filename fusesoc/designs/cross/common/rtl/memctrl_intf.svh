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

`ifndef MEMCTRL_INTF_SVH
`define MEMCTRL_INTF_SVH

interface MEMCTRL
#(
    parameter int unsigned MEM_AW = 64,
    parameter int unsigned W_FCNT = 1
);
    logic [MEM_AW-1:0]  addr;
    logic               addr_valid;
    logic               we;
    logic [W_FCNT-1:0]  fcnt;

    modport host
    (
        output addr, addr_valid, we, fcnt
    );

    modport device
    (
        input addr, addr_valid, we, fcnt
    );

endinterface

`endif
