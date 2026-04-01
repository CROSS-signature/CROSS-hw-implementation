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

import os
from math import ceil, log

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

ITERATIONS = int(os.getenv("TB_ITERATIONS", 50))

OP_SIGN = 0
OP_VERIFY = OP_SIGN + 1

CLIB_VERSION = os.environ.get("CLIB")
T = int(os.environ.get("T"))
W = int(os.environ.get("W"))
N = int(os.environ.get("N"))
P = int(os.environ.get("P"))
BITS_P = int(ceil(log(P, 2)))
LAMBDA = int(os.environ.get("LAMBDA"))
BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8
WPS = (BYTES_SEED+7)//8
WPH = (BYTES_HASH+7)//8

async def reset(dut):
	dut.rst_n.value = 0
	await Timer(5, units="ns")
	dut.rst_n.value = 1
	await Timer(73, units="ns")
	return

async def send_opcode(dut, op):
    dut.op.value = op
    dut.op_valid.value = 1
    await cocotb.triggers.RisingEdge(dut.clk)
    while not (dut.op_valid.value and dut.op_ready.value):
        await cocotb.triggers.RisingEdge(dut.clk)
    dut.op_valid.value = 0
    await cocotb.triggers.RisingEdge(dut.clk)
    return

async def send_b(dut, b, s_axis_b):
    await s_axis_b.send(b)
    await s_axis_b.wait()
    return

async def gen_stree(dut, s_axis, m_axis, mseed):
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])

    # Receive master seed once
    data = await m_axis.recv()
    assert len(data.tdata) == len(mseed.tdata), "Frame of wrong length (master seed) received!"
    assert list(data.tdata) == list(mseed.tdata), "Wrong master seed received!"

    # Send quad seeds
    for _ in range(4):
        await s_axis.send(node)
        await s_axis.wait()

    rem = [0]*4
    rem[0] += 1 if (T%4 >= 1) else 0
    rem[1] += 1 if (T%4 >= 2) else 0
    rem[2] += 1 if (T%4 >= 3) else 0

    # Read quad seeds and respond with corresponding T/4 + rem seeds
    for i in range(4):
        data = await m_axis.recv()
        assert (len(data.tdata) == len(node.tdata)), "Frame of wrong length received on m_axis (quad seeds)!"
        assert (list(data.tdata) == list(node.tdata)), "Wrong data received on m_axis (quad seeds)!"
        for _ in range(T//4 + rem[i]):
            await s_axis.send(node)
            await s_axis.wait()

    return

async def check_seeds_and_send_cmt_0(dut, s_axis, m_axis):
    seed = AxiStreamFrame([i for i in range(BYTES_SEED)])
    cmt_0 = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])
    for _ in range(T):
        for _ in range(2):
            data = await m_axis.recv()
            assert (len(data.tdata) == len(seed.tdata)), "Frame of wrong length received on m_axis (round seeds)!"
            assert (list(data.tdata) == list(seed.tdata)), "Wrong data received on m_axis (round seeds)!"
        await s_axis.send(cmt_0)
        await s_axis.wait()
    return

async def gen_mtree(dut, s_axis, m_axis):
    cmt_0 = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    rem = [0]*4
    rem[0] += 1 if (T%4 >= 1) else 0
    rem[1] += 1 if (T%4 >= 2) else 0
    rem[2] += 1 if (T%4 >= 3) else 0

    # Read cmt_0 leafs and send corresponding hashes
    for i in range(4):
        for _ in range(T//4 + rem[i]):
            data = await m_axis.recv()
            assert (len(data.tdata) == len(cmt_0.tdata)), "Frame of wrong length received on m_axis (cmt_0)!"
            assert (list(data.tdata) == list(cmt_0.tdata)), "Wrong data received on m_axis (cmt_0)!"
        await s_axis.send(cmt_0)
        await s_axis.wait()

    # Read quad hashes
    for i in range(4):
        data = await m_axis.recv()
        assert (len(data.tdata) == len(cmt_0.tdata)), "Frame of wrong length received on m_axis (quad hash)!"
        assert (list(data.tdata) == list(cmt_0.tdata)), "Wrong data received on m_axis (quad hash)!"

    # Send mroot
    await s_axis.send(cmt_0)
    await s_axis.wait()

    # Read provisioned mroot again (bit stupid, I know)
    data = await m_axis.recv()
    assert (len(data.tdata) == len(cmt_0.tdata)), "Frame of wrong length received on m_axis (mroot)!"
    assert (list(data.tdata) == list(cmt_0.tdata)), "Wrong data received on m_axis (mroot)!"
    return

async def check_proof_path(dut, m_axis_sig):
    stree_node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    mtree_node = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    # Read proof nodes
    for i in range(W):
        data = await m_axis_sig.recv()
        assert (len(data.tdata) == len(mtree_node.tdata)), "Frame of wrong length received on m_axis (proof value)!"
        assert (list(data.tdata) == list(mtree_node.tdata)), "Wrong data received on m_axis (proof value)!"

    # Now read path nodes, not checked for correctness since stree
    # needs to be revised first
    for _ in range(W):
        data = await m_axis_sig.recv()
        assert (len(data.tdata) == len(stree_node.tdata)), "Frame of wrong length received on m_axis (path value)!"
        assert (list(data.tdata) == list(stree_node.tdata)), "Wrong data received on m_axis (path value)!"
    return

async def send_proof_path(dut, s_axis):
    path = AxiStreamFrame([i for i in range(BYTES_SEED)])
    proof = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    # First send paths
    for _ in range(W):
        await s_axis.send(path)
        await s_axis.wait()

    # Then send proof
    for _ in range(W):
        await s_axis.send(proof)
        await s_axis.wait()
    return

async def read_seed_send_cmt(dut, s_axis, m_axis, ch_b):
    seed = AxiStreamFrame([i for i in range(BYTES_SEED)])
    cmt_0 = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    for b in ch_b:
        if b == 1:
            for _ in range(2):
                data = await m_axis.recv()
                assert (len(data.tdata) == len(seed.tdata)), "Frame of wrong length received on m_axis (seed)!"
                assert (list(data.tdata) == list(seed.tdata)), "Wrong data received on m_axis (seed)!"
        else:
            await s_axis.send(cmt_0)
            await s_axis.wait()
    return



@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_sign_no_tree_unit(dut):
    s_axis_ch   = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis      = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis      = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_sig  = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset(dut)

    for _ in range(ITERATIONS):
        # Send opcode
        await send_opcode(dut, OP_SIGN)

        # Now send mseed
        mseed = AxiStreamFrame([i+128 for i in range(BYTES_SEED)])
        await s_axis.send(mseed)
        await s_axis.wait()

        # # Generate the 'seedtree'
        await gen_stree(dut, s_axis, m_axis, mseed)
        await check_seeds_and_send_cmt_0(dut, s_axis, m_axis)
        await gen_mtree(dut, s_axis, m_axis)

        # # Now generate the challenge for the 'mtree proof' and 'stree path'
        ch_b = [0]*(T-W) + [1]*W
        ch_b = list(np.random.permutation(ch_b))
        ch_b = [int(b) for b in ch_b]
        await s_axis_ch.send(ch_b)
        await s_axis_ch.wait()

        # # Now wait for the node in the mtree proof and stree path
        await check_proof_path(dut, m_axis_sig)


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_vrfy_no_tree_unit(dut):
    s_axis_ch   = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis      = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis      = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig  = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset(dut)

    for _ in range(ITERATIONS):
        # Send opcode
        await send_opcode(dut, OP_VERIFY)

        # Generate random challenge
        ch_b = [0]*(T-W) + [1]*W
        ch_b = list(np.random.permutation(ch_b))
        ch_b = [int(b) for b in ch_b]

        # Send the challenge b and the proof/path nodes concurrently
        b_proc = cocotb.start_soon(send_b(dut, ch_b, s_axis_ch))
        proof_path_proc = cocotb.start_soon(send_proof_path(dut, s_axis_sig))

        # # In the id loop, W seeds are read and T-W cmt_0 are sent, depending on b
        await read_seed_send_cmt(dut, s_axis, m_axis, ch_b)

        # # Now regenerate the mroot
        await gen_mtree(dut, s_axis, m_axis)

        # # Wait until all processes have terminated
        await b_proc
        await proof_path_proc

        # Padding errors not possible, check it nevertheless
        assert dut.vrfy_pad_err.value == 0, "There was a technically impossible padding error!"
