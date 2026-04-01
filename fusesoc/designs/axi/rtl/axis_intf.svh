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

`ifndef AXIS_INTF_SVH
`define AXIS_INTF_SVH

`define NON_NEG_MSB( a ) ( ( a>0 ) ? ( a ) : ( 1 ) )
`define MAX_DIV( a, b ) ( a / b * b )

interface AXIS
#(
    parameter DATA_WIDTH = 64,
    parameter TUSER_WIDTH = 3,
    parameter ELEM_WIDTH = 8,
    localparam KEEP_WIDTH = `NON_NEG_MSB(DATA_WIDTH/ELEM_WIDTH)
);
    logic [DATA_WIDTH-1:0]                  tdata;
    logic [KEEP_WIDTH-1:0]                  tkeep;
    logic                                   tvalid;
    logic                                   tready;
    logic [`NON_NEG_MSB(TUSER_WIDTH)-1:0]   tuser;
    logic                                   tlast;

    modport master
    (
        output tdata, tkeep, tvalid, tuser, tlast,
        input tready
    );

    modport slave
    (
        input tdata, tkeep, tvalid, tuser, tlast,
        output tready
    );

    /*
    * tuser omitted in the following cases as I only use it rarely and thus,
    * make it explicitely
    */
    `define AXIS_ASSIGN_MIN(lhs, rhs) \
        assign lhs.tdata = rhs.tdata; \
        assign lhs.tvalid = rhs.tvalid; \
        assign rhs.tready = lhs.tready;

    `define AXIS_ASSIGN(lhs, rhs) \
        assign lhs.tdata = rhs.tdata; \
        assign lhs.tkeep = rhs.tkeep; \
        assign lhs.tvalid = rhs.tvalid; \
        assign rhs.tready = lhs.tready; \
        assign lhs.tlast = rhs.tlast;

    `define AXIS_ASSIGN_GATED(lhs, rhs, en) \
        assign lhs.tdata = rhs.tdata; \
        assign lhs.tkeep = rhs.tkeep; \
        assign lhs.tvalid = rhs.tvalid & en; \
        assign rhs.tready = lhs.tready & en; \
        assign lhs.tlast = rhs.tlast;

    `define AXIS_ASSIGN_IMPL_LAST(lhs, rhs) \
        assign lhs.tdata = rhs.tdata; \
        assign lhs.tkeep = rhs.tkeep; \
        assign lhs.tvalid = rhs.tvalid; \
        assign rhs.tready = lhs.tready; \
        assign lhs.tlast = (rhs.tlast || ~&rhs.tkeep);

    `define AXIS_ASSIGN_PROC(lhs, rhs) \
        lhs.tdata = rhs.tdata; \
        lhs.tkeep = rhs.tkeep; \
        lhs.tvalid = rhs.tvalid; \
        rhs.tready = lhs.tready; \
        lhs.tlast = rhs.tlast;

    `define AXIS_ASSIGN_MIN_PROC(lhs, rhs) \
        lhs.tdata = rhs.tdata; \
        lhs.tvalid = rhs.tvalid; \
        rhs.tready = lhs.tready;

    `define AXIS_TRANS(a) (a.tvalid && a.tready)
    `define AXIS_LAST(a) (a.tvalid && a.tready && a.tlast)

    `define AXIS_EXPORT_MASTER(axis) \
        assign ``axis``_tdata = axis.tdata; \
        assign ``axis``_tkeep = axis.tkeep; \
        assign ``axis``_tvalid = axis.tvalid; \
        assign axis.tready = ``axis``_tready; \
        assign ``axis``_tlast = axis.tlast;

    `define AXIS_EXPORT_SLAVE(axis) \
        assign axis.tdata = ``axis``_tdata; \
        assign axis.tkeep = ``axis``_tkeep; \
        assign axis.tvalid = ``axis``_tvalid; \
        assign ``axis``_tready = axis.tready; \
        assign axis.tlast = ``axis``_tlast;

endinterface

`endif
