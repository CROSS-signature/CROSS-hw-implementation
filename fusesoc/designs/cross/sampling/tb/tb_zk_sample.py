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
# @author: Patrick Karl <patrick.karl@tum.de>

import hashlib
import os
from math import ceil, log

import numpy as np

ITERATIONS = int(os.getenv("TB_ITERATIONS", 10))
np.random.seed(0)

import cocotb
import cross
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

CLIB_VERSION    = os.environ.get("CLIB")
N               = int(os.environ.get("N"))
Z               = int(os.environ.get("Z"))
BITS_Z          = ceil(log(Z,2))
LAMBDA          = int(os.environ.get("LAMBDA"))
M               = None
RSDPG           = None

BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8

if 'RSDPG' in CLIB_VERSION:
    RSDPG = True
    M = int(os.environ.get("M"))

async def reset(dut):
    await Timer(5, units="ns")
    dut.rst_n.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    return

async def read_fz(dut):
    out = []
    tmp = []
    pad = 0
    cnt = 0
    cnt_max = N if (M == None) else M

    # Read data until m_axis_tlast is detected
    while True:
        await RisingEdge(dut.clk)
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value):
            # Throw away padding bits, as it is padded
            val = dut.m_axis_tdata.value.binstr[pad:]
            tmp = [int(val[i:i+BITS_Z],2) for i in range(0, len(val), BITS_Z)]
            tmp = tmp[::-1]
            out += tmp
            cnt += dut.PAR_ELEMS.value

            if cnt >= cnt_max:
                break
    return out

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_fz_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await RisingEdge(dut.clk)

    cc_total = 0

    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        await reset(dut)
        din = np.random.bytes(BYTES_SEED)
        dsc = (0).to_bytes(2, byteorder='little')

        shake = hashlib.shake_128() if LAMBDA == 128 else hashlib.shake_256()
        shake.update(din + dsc)

        # Send input
        s_axis.send_nowait(AxiStreamFrame(shake.digest(1000)))

        got = await read_fz(dut)
        if RSDPG:
            got = got[:M]
        else:
            got = got[:N]
        exp = cross.test_zz_vec(din)

        print(f"Got: {got}")
        print(f"Exp: {exp}")
        if RSDPG:
            assert len(got) == len(exp) == M, "Vector has wrong length: " +str(len(got)) + " expect " + str(M)
        else:
            assert len(got) == len(exp) == N, "Vector has wrong length: " +str(len(got)) + " expect " + str(N)

        for i in range(len(exp)):
            assert exp[i] == got[i], "Wrong element at index " + str(i)
        for val in got:
            assert val < Z, "Not as expected!"
