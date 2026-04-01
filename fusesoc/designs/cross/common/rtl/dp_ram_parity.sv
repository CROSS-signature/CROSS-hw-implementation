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

module dp_ram_parity
#(
    // Having PARITY_WIDTH included in DATA_WIDTH is dirty but was done due
    // because of legacy issues and backwards compatibility, sorry.
    parameter int PARITY_WIDTH  = 4,
    parameter int DATA_WIDTH    = 32 + PARITY_WIDTH,
    parameter int DEPTH         = 1024,
    localparam int ADDR_WIDTH   = $clog2(DEPTH),
    localparam int WE_WIDTH     = (DATA_WIDTH - PARITY_WIDTH) / 8
)
(
    input logic                     clk_a,
    input logic                     en_a_i,
    input logic [WE_WIDTH-1:0]      we_a_i,
    input logic [ADDR_WIDTH-1:0]    addr_a_i,
    input logic [DATA_WIDTH-1:0]    wdata_a_i,
    output logic [DATA_WIDTH-1:0]   rdata_a_o,

    input logic                     clk_b,
    input logic                     en_b_i,
    input logic [WE_WIDTH-1:0]      we_b_i,
    input logic [ADDR_WIDTH-1:0]    addr_b_i,
    input logic [DATA_WIDTH-1:0]    wdata_b_i,
    output logic [DATA_WIDTH-1:0]   rdata_b_o
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always @(posedge clk_a)
    begin
        if (en_a_i) begin
            for (int i=0; i<WE_WIDTH; i++) begin
                if (we_a_i[i]) begin
                    mem[addr_a_i][(8+1)*i +: 8+1] <= wdata_a_i[(8+1)*i +: 8+1];
                end
            end
            rdata_a_o <= mem[addr_a_i];
        end
    end

    always @(posedge clk_b)
    begin
        if (en_b_i) begin
            for (int i=0; i<WE_WIDTH; i++) begin
                if (we_b_i[i])
                    mem[addr_b_i][(8+1)*i +: 8+1] <= wdata_b_i[(8+1)*i +: 8+1];
            end
            rdata_b_o <= mem[addr_b_i];
        end
    end

endmodule
