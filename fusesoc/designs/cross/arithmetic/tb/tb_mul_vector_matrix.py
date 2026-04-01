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


async def run_mul(dut):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    await cycle_reset(dut)

    # waiting for cocotb/cocotb#3536 to land in v2.0
    # MODULO = int(cocotb.packages.cross_pkg.Z.value)
    # N = int(cocotb.packages.cross_pkg.N.value)
    # K = int(cocotb.packages.cross_pkg.K.value)
    # M = int(cocotb.packages.cross_pkg.M.value)

    MODULO = int(dut.MODULO.value)
    FZ = int(dut.FZ.value)

    if FZ == 1:
        N = int(dut.N.value)
        M = int(dut.M.value)
        vect_size = M
        matrix_size = (M, N - M)
        identity_size = M
        concat_axis = 1
    elif FZ == 0:
        N = int(dut.N.value)
        K = int(dut.K.value)

        vect_size = N
        matrix_size = (K, N - K)
        identity_size = N - K
        concat_axis = 0
    else:
        raise RuntimeError("Invalid CROSS variant detected")

    vector_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "vector"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    matrix_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "matrix"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    result_sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "result"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )

    vector_source.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
    matrix_source.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
    result_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

    # Generate test vectors
    vector = np.random.randint(MODULO, size=vect_size, dtype=np.int32)
    dense_matrix = np.random.randint(MODULO, size=matrix_size, dtype=np.int32)
    identity_matrix = np.identity(identity_size, dtype=np.int32)
    matrix = np.concatenate([dense_matrix, identity_matrix], axis=concat_axis)

    # Calculate expected result
    expected_result = np.mod(np.matmul(vector, matrix), MODULO).flatten()

    await ClockCycles(dut.clk_i, 5)

    vector_task = cocotb.start_soon(vector_source.send(AxiStreamFrame(tdata=vector.tolist())))
    # each column is transmitted in a separated Frame (zero-padded transfer)
    for row in dense_matrix.tolist():
        matrix_source.send_nowait(AxiStreamFrame(tdata=row))
    matrix_task = cocotb.start_soon(matrix_source.wait())
    result_task = cocotb.start_soon(result_sink.recv())

    # Start the computation
    dut.start_i.value = 1
    await ClockCycles(dut.clk_i, 1)
    dut.start_i.value = 0

    await Combine(RisingEdge(dut.done_o), vector_task, matrix_task, result_task)
    dut_result = result_task.result()

    await ClockCycles(dut.clk_i, 5)

    assert expected_result.flatten().tolist() == dut_result.tdata, f"{expected_result.flatten().tolist()} != {dut_result.tdata}"


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def test_mul_vector_matrix(dut):
    for _ in range(10):
        await run_mul(dut)


@cocotb.test(timeout_time=100, timeout_unit="us")
async def test_performance(dut):
    await run_mul(dut)
