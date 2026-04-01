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
import random
import sys
from pathlib import Path

import cocotb
import galois
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Combine, RisingEdge
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import cycle_reset, random_generator

random.seed(cocotb.RANDOM_SEED)
np.random.seed(cocotb.RANDOM_SEED)


async def run_exp(dut):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    await cycle_reset(dut)

    MODZ = int(dut.Z.value)
    MODP = int(dut.P.value)
    POLY_DEGREE = int(dut.N.value)
    G = int(dut.GEN.value)
    GF = galois.GF(MODP)

    op_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "op"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    res_sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "res"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )

    op_source.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
    res_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

    # Generate test vectors
    op = np.random.randint(0, MODZ, size=(POLY_DEGREE), dtype=np.int32)

    # Calculate expected result
    expected_result = [int(GF(G) ** i) for i in op]

    await ClockCycles(dut.clk_i, 5)

    op_task = cocotb.start_soon(op_source.send(AxiStreamFrame(tdata=op.tolist())))
    res_task = cocotb.start_soon(res_sink.recv())

    # Start the computation
    dut.start_i.value = 1
    await ClockCycles(dut.clk_i, 1)
    dut.start_i.value = 0

    await Combine(RisingEdge(dut.done_o), op_task, res_task)
    dut_result = res_task.result()

    await ClockCycles(dut.clk_i, 5)

    assert expected_result == dut_result.tdata, f"{expected_result} != {dut_result.tdata}"


@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_exp_vector(dut):
    for _ in range(10):
        await run_exp(dut)


@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_performance(dut):
    await run_exp(dut)
