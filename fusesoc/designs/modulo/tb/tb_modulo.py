# Copyright 2026, Technical University of Munich
# Copyright 2026, Politecnico di Milano.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Licensed under the Solderpad Hardware License v 2.1 (the "License");
# you may not use this file except in compliance with the License, or,
# at your option, the Apache License version 2.0. You may obtain a
# copy of the License at
#
# https://solderpad.org/licenses/SHL-2.1/
#
# Unless required by applicable law or agreed to in writing, any work
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------
#
# CROSS - Codes and Restricted Objects Signature Scheme
#
# @version 1.0 (April 2026)
#
# @author: Francesco Antognazza <francesco.antognazza@polimi.it>

import logging
import os
import random
import sys
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import cycle_reset

random.seed(cocotb.RANDOM_SEED)
np.random.seed(cocotb.RANDOM_SEED)


async def drive_input(dut, input: list[int]):
    for data in input:
        dut.data_i.value = data
        dut.req_i.value = 1
        await RisingEdge(dut.clk_i)

    dut.data_i.value = 0
    dut.req_i.value = 0


async def run_modulo(dut, seq_len: int, values: list[int] | None = None):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    await cycle_reset(dut)

    MODULO = int(dut.MODULO.value)
    MAX_INPUT = int(dut.MAX_INPUT.value)

    if values is None:
        # Generate test vectors
        dut_in = np.random.randint(MAX_INPUT, size=seq_len, dtype=np.int32).tolist()
    else:
        dut_in = values

    # Calculate expected result
    expected_result = np.mod(dut_in, MODULO)

    # Start the computation
    await ClockCycles(dut.clk_i, 5)
    cocotb.start_soon(drive_input(dut, dut_in))

    dut_result = []
    dut.ready_i.value = 1
    for _ in range(seq_len):
        await ReadOnly()
        if dut.valid_o.value != 1:
            # Wait for the computation to complete
            await RisingEdge(dut.valid_o)

        dut_result += [int(dut.data_o.value)]
        await RisingEdge(dut.clk_i)

    await ClockCycles(dut.clk_i, 5)

    assert expected_result.tolist() == dut_result


@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_single_random_modulo(dut):
    for _ in range(10):
        await run_modulo(dut, 1)


@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_sequence_random_modulo(dut):
    for _ in range(2):
        seq_len = np.random.randint(3, 15)
        for _ in range(3):
            await run_modulo(dut, seq_len)


@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_domain_boundaries_modulo(dut):
    MODULO = int(dut.MODULO.value)
    MAX_INPUT = int(dut.MAX_INPUT.value)

    values = np.array([0, MODULO, MODULO - 1, MODULO + 1, MAX_INPUT]).tolist()
    await run_modulo(dut, len(values), values)


@cocotb.test(timeout_time=10, timeout_unit="ms", skip=("TB_EXHAUSTIVE" not in os.environ))
async def test_exhaustive_modulo(dut):
    MAX_INPUT = int(dut.MAX_INPUT.value)

    values = list(range(MAX_INPUT))
    await run_modulo(dut, len(values), values)
