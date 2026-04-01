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
from cocotb.triggers import ClockCycles, Combine
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

sys.path.insert(0, str(Path(".").resolve()))
import itertools

from cocotb_utils import cycle_reset, random_generator

random.seed(cocotb.RANDOM_SEED)
np.random.seed(cocotb.RANDOM_SEED)


async def run_test(dut, data: list[int]):
    log = logging.getLogger("cocotb.tb")
    log.setLevel(logging.DEBUG)

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    await cycle_reset(dut)

    source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "s_axis"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "m_axis"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )

    # Start the computation
    await ClockCycles(dut.clk_i, 5)

    # sink.set_pause_generator(random_generator(yield_prob=0.5))
    # sink.set_pause_generator(itertools.cycle([True, False, False, True, False, True, True, False, False, True, False, False, True, True]))

    source_task = cocotb.start_soon(source.send(AxiStreamFrame(tdata=data)))
    sink_task = cocotb.start_soon(sink.recv())
    await Combine(source_task, sink_task)

    dut_result = sink_task.result()

    await ClockCycles(dut.clk_i, 5)

    assert bytearray(data) == dut_result.tdata, f"{bytearray(data)} != {dut_result.tdata}"


@cocotb.test(timeout_time=1, timeout_unit="ms")
async def tb_short_run(dut):
    dut._log.info("AXI stream asymmetric FIFO")

    WIDTH = int(dut.WIDTH.value)

    for _ in range(100):
        # Generate test vector
        length = np.random.randint(20, 100)
        data = np.random.randint(WIDTH, size=(length), dtype=np.int32)

        dut._log.info(f"Random data of {length} elements")
        await run_test(dut, data.tolist())
