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

module sp_lutram
#(
    parameter int DATA_WIDTH    = 32,
    parameter int DEPTH         = 1024,
    parameter string OUTPUT_REG = "true",
    localparam int unsigned ADDR_WIDTH = $clog2( DEPTH )
)
(
    input logic                     clk,
    input logic                     we_i,
    input logic [ADDR_WIDTH-1:0]    addr_i,
    input logic [DATA_WIDTH-1:0]    wdata_i,
    output logic [DATA_WIDTH-1:0]   rdata_o
);

    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk)
    begin
        if (we_i) begin
            mem[addr_i] <= wdata_i;
        end
    end

    generate
        if (OUTPUT_REG == "true") begin

            always_ff @(posedge clk)
            begin
                rdata_o <= mem[addr_i];
            end

        end else begin

            assign rdata_o = mem[addr_i];

        end
    endgenerate

endmodule
