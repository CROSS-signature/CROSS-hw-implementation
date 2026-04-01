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
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Combine, RisingEdge
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import cycle_reset, random_generator

random.seed(cocotb.RANDOM_SEED)
np.random.seed(cocotb.RANDOM_SEED)

operations_dict = {
    "ARITH_OP_ADD": 0,  # Representing addition
    "ARITH_OP_SUB": 1,  # Representing subtraction
}  # see arithmetic_unit_pkg


async def run_add_sub(dut, add_sub_select_op):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    await cycle_reset(dut)

    MODULO = int(dut.P.value)
    POLY_DEGREE = int(dut.N.value)

    op1_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "op1"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    op2_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "op2"),
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

    op1_source.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
    op2_source.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
    res_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

    # Generate test vectors
    op1 = np.random.randint(MODULO, size=(POLY_DEGREE), dtype=np.int32)
    op2 = np.random.randint(MODULO, size=(POLY_DEGREE), dtype=np.int32)

    # Calculate expected result
    if add_sub_select_op == "ARITH_OP_ADD":
        expected_result = np.mod(np.add(op1, op2), MODULO)
    else:
        expected_result = np.mod(np.subtract(op1, op2), MODULO)

    await ClockCycles(dut.clk_i, 5)

    # Start the computation
    dut.op_i.value = operations_dict[add_sub_select_op]

    op1_task = cocotb.start_soon(op1_source.send(AxiStreamFrame(tdata=op1.tolist())))
    op2_task = cocotb.start_soon(op2_source.send(AxiStreamFrame(tdata=op2.tolist())))
    res_task = cocotb.start_soon(res_sink.recv())

    await Combine(RisingEdge(dut.done_o), op1_task, op2_task, res_task)
    dut_result = res_task.result()

    await ClockCycles(dut.clk_i, 5)

    assert expected_result.tolist() == dut_result.tdata, f"{expected_result.tolist()} != {dut_result.tdata}"


@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_add_sub_vector(dut):
    for _ in range(10):
        await run_add_sub(dut, add_sub_select_op="ARITH_OP_ADD")
        await run_add_sub(dut, add_sub_select_op="ARITH_OP_SUB")


@cocotb.test(timeout_time=10, timeout_unit="us")
async def test_performance(dut):
    await run_add_sub(dut, add_sub_select_op="ARITH_OP_ADD")
