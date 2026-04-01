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
// @author: Francesco Antognazza <francesco.antognazza@polimi.it>

/* verilator lint_off UNUSEDSIGNAL */
`timescale 1ps / 1ps

`ifndef COMMON_PKG
`define COMMON_PKG

`define REG_SENSITIVITY_LIST posedge clk_i `ifdef ASYNC_RST or negedge rst_n `endif
`define REG_SENSITIVITY_LIST_2 posedge clk `ifdef ASYNC_RST or negedge rst_n `endif

`define ASSERT_DEFAULT_CLK clk_i
`define ASSERT_DEFAULT_RST !rst_n

`define DEFAULT_CASE(DEFAULT_ACTION)  \
    `ifdef VERILATOR                    \
        $error("Caught default case!"); \
    `else                               \
        DEFAULT_ACTION                  \
    `endif

`define ASSERT(__name, __prop, __clk = `ASSERT_DEFAULT_CLK, __rst = `ASSERT_DEFAULT_RST) \
    /* verilator lint_off SYNCASYNCNET */                                                \
    __name: assert property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop))     \
    else begin                                                                           \
        $error("[ASSERT FAILED] [%m] %s: %s", `"__name`", `"__prop`");                   \
    end                                                                                  \
    /* verilator lint_on SYNCASYNCNET */

// Assertion in initial block. Can be used for things like parameter checking
`define ASSERT_INIT(__name, __prop)                                       \
    initial begin                                                           \
        __name: assert (__prop)                                             \
        else begin                                                          \
            $error("[ASSERT FAILED] [%m] %s: %s", `"__name`", `"__prop`");  \
        end                                                                 \
    end

// Assertion in final block. Can be used for things like state machines in idle at end of sim.
`define ASSERT_FINAL(__name, __prop)                                     \
    final begin                                                            \
        __name: assert (__prop)                                            \
        else begin                                                         \
            $error("[ASSERT FAILED] [%m] %s: %s", `"__name`", `"__prop`"); \
        end                                                                \
    end

`endif  // COMMON_PKG

package common_pkg;
    localparam int unsigned BITS_IN_BYTE = 8;

    // Lucas–Lehmer primality test
    function automatic bit is_mersenne_prime(int number);
        int s = 4;
        int p = $clog2(number + 1);
        for (int i = 0; i < p - 2; i++) begin
            s = ((s * s) - 2) % number;
        end
        return (s == 0) ? 1'b1 : 1'b0;
    endfunction

    function automatic int iceilfrac(int a, int b);
        return (a + b - 1) / b;
    endfunction

    function automatic int ifloorfrac(int a, int b);
        return a / b;
    endfunction

    function automatic longint lceilfrac(longint a, longint b);
        return (a + b - 1) / b;
    endfunction

    function automatic longint lfloorfrac(longint a, longint b);
        return a / b;
    endfunction

    function automatic int max(int a, int b);
        if (a >= b) begin
            max = a;
        end else begin
            max = b;
        end
        return max;
    endfunction

    function automatic int min(int a, int b);
        if (a <= b) begin
            min = a;
        end else begin
            min = b;
        end
        return min;
    endfunction

    // Function to compute the Greatest Common Divisor (GCD)
    function automatic int unsigned gcd(input int unsigned a, input int unsigned b);
        int unsigned temp, x, y;
        x = a;
        y = b;
        while (y != 0) begin
            temp = y;
            y = x % y;
            x = temp;
        end
        return x;
    endfunction

    // Function to compute the Least Common Multiple (LCM)
    function automatic int unsigned lcm(input int unsigned a, input int unsigned b);
        return (a * b) / gcd(a, b);
    endfunction


endpackage
