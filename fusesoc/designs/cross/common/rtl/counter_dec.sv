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

module counter_dec
#(
    parameter int unsigned CNT_WIDTH = 8,
    parameter int unsigned MIN_VAL = 0
)
(
    input logic clk,
    input logic rst_n,

    input logic [CNT_WIDTH-1:0] max_val,
    input logic [CNT_WIDTH-1:0] dec,

    input logic trigger,
    output logic [CNT_WIDTH-1:0] cnt
);

    always_ff @(`REG_SENSITIVITY_LIST_2)
    begin
        if (!rst_n) begin
            cnt <= max_val;
        end else begin
            if (trigger) begin
                if ( cnt <= CNT_WIDTH'(MIN_VAL) ) begin
                    cnt <= max_val;
                end else begin
                    cnt <= cnt - dec;
                end
            end
        end
    end

endmodule
