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

GEN_TREE = 0
REGEN_TREE = 1

T = int(os.environ.get("T"))
W = int(os.environ.get("W"))
STREE_NODES = 2*T - 1

def clog2(a):
    return max(int(ceil(log(a,2))), 1)

def parent(a):
    return (a-1)//2 if a % 2 else (a-2)//2

def l_child(a):
    return 2*a + 1

def r_child(a):
    return 2*a + 2

def stree_compute_nodes_per_level_and_offsets():
    nodes_per_level = []
    nodes_curr_level = T
    total_nodes = 0
    for level in range(clog2(T),-1,-1):
        nodes_per_level = [nodes_curr_level] + nodes_per_level
        total_nodes += nodes_curr_level
        nodes_curr_level = ceil(nodes_curr_level/2)

    cumulative_offset = 0
    total_saved_nodes = 0
    level_offsets = []
    # Level 0, the root has no previous levels, no missing nodes before it
    missing_nodes_before_level = []
    cumul_saved_nodes = []
    for level in range(clog2(T)+1):
        level_offsets.append(cumulative_offset)
        cumulative_offset += nodes_per_level[level]
        if (level == 0):
            missing_nodes_before_level.append(0)
        else:
            missing_nodes_before_level.append(total_saved_nodes)
        total_saved_nodes += 2**level-nodes_per_level[level]

        cumul_saved_nodes.append(total_saved_nodes)

    return total_nodes,nodes_per_level,level_offsets,missing_nodes_before_level


def stree_path(ch):
    leaves_stencil = 2**(clog2(T))
    inner_nodes_stencil = leaves_stencil - 1
    nodes_stencil_tree = 2*leaves_stencil - 1
    n_nodes, npl, off, mnbl = stree_compute_nodes_per_level_and_offsets()

    flag_tree = [0] * nodes_stencil_tree

    for i in range(T):
        flag_tree[inner_nodes_stencil+i] = ch[i]

    for i in range(leaves_stencil-2, -1, -1):
        if flag_tree[l_child(i)] and flag_tree[r_child(i)]:
            flag_tree[i] = 1


    num_seed_published = 0
    node_idx = 1
    ancestors = 1
    cnt = 0
    path = []
    proper_label = []
    for l in range(1, clog2(T)+1, 1):
        for n in range(0, npl[l], 1):
            node_idx = ancestors + n
            node_storage_idx = node_idx - mnbl[l]
            if flag_tree[node_idx] and not flag_tree[parent(node_idx)]:
                path.append(node_storage_idx)
                cnt += 1
        ancestors += 2**l

    true_tree = []
    ancestors = 0
    for l in range(0, clog2(T)+1, 1):
        for n in range(npl[l]):
            father_node_idx = ancestors + n
            true_tree.append(flag_tree[father_node_idx])
        ancestors += 2**l


    return true_tree, path, cnt


async def read_path(dut):
    path = []
    while(True):
        await RisingEdge(dut.clk)
        if dut.path_addr_valid.value:
            path.append(int(dut.path_addr.value))
        if dut.path_last.value:
            break

    return path


async def send_mseed(dut, s_axis):
    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)
    mseed = AxiStreamFrame([i+128 for i in range(BYTES_SEED)])
    await s_axis.send(mseed)
    await s_axis.wait()
    return

async def send_expanded_seeds(dut, s_axis):
    # Send nodes that verifier computes on his own
    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    for _ in range(STREE_NODES-1):
        await s_axis.send(node)
        await s_axis.wait()
    return

async def check_seeds_to_expand(dut, m_axis):
    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)
    test_frame = AxiStreamFrame([i for i in range(BYTES_SEED)])

    # Receive master seed once
    mseed = AxiStreamFrame([i+128 for i in range(BYTES_SEED)])
    data = await m_axis.recv()
    assert list(data.tdata) == list(mseed.tdata), "Wrong master seed received!"

    # leaves start at STREE_NODES - T, subtract the root
    inode_cnt = 0
    while(inode_cnt < STREE_NODES - T - 1):
        data = await m_axis.recv()
        assert (list(data.tdata) == list(test_frame.tdata)), "Wrong data received on m_axis (inner nodes)!"
        inode_cnt += 1

    # Now read each leaf twice
    inode_cnt = 0
    while(inode_cnt < 2*T):
        data = await m_axis.recv()
        assert (list(data.tdata) == list(test_frame.tdata)), "Wrong data received on m_axis (leafs)!"
        inode_cnt += 1
    return

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_stree_gen(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_ch = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for _ in range(ITERATIONS):
        dut.op.value = GEN_TREE
        dut.op_valid.value = 1
        await cocotb.triggers.RisingEdge(dut.clk)
        while(not (dut.op_valid.value and dut.op_ready.value)):
            await cocotb.triggers.RisingEdge(dut.clk)
        dut.op_valid.value = 0

        await send_mseed(dut, s_axis)
        stree_nodes_proc = cocotb.start_soon(send_expanded_seeds(dut, s_axis))
        check_proc = cocotb.start_soon(check_seeds_to_expand(dut, m_axis))
        await check_proc

        # Now generate the path
        chall_b = [0]*(T-W) + [1]*W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]
        await s_axis_ch.send(chall_b)
        await s_axis_ch.wait()

        while(True):
            await cocotb.triggers.RisingEdge(dut.clk)
            if dut.path_last.value:
                break

        await cocotb.triggers.RisingEdge(dut.clk)
        dut.sign_done.value = 1

        while(True):
            await cocotb.triggers.RisingEdge(dut.clk)
            if not dut.path_last.value:
                dut.sign_done.value = 1
                break


async def send_paths(dut, s_axis_sig, chall_b):
    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)
    _, _, path_len = stree_path(chall_b)

    # Send some path nodes, do this without blocking because we also need to send computed hash nodes
    path_node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    for i in range(path_len):
        await s_axis_sig.send(path_node)
        await s_axis_sig.wait()
    return

async def send_expanded_seeds_regen(dut, s_axis_sig, m_axis):
    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])

    # Bit annyoing to compute how many expanded seeds we compute exactly,
    # so just send a bunch with non-blocking command
    for _ in range(STREE_NODES):
        s_axis_sig.send_nowait(node)


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def stree_regen(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_ch = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    BYTES_SEED = dut.WORDS_PER_SEED.value * (dut.DATA_WIDTH.value//8)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for _ in range(ITERATIONS):
        dut.op.value = REGEN_TREE
        dut.op_valid.value = 1
        await cocotb.triggers.RisingEdge(dut.clk)
        while(not (dut.op_valid.value and dut.op_ready.value)):
            await cocotb.triggers.RisingEdge(dut.clk)
        dut.op_valid.value = 0


        # Now generate the path
        chall_b = [0]*(T-W) + [1]*W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]
        await s_axis_ch.send(chall_b)
        await s_axis_ch.wait()
        path_proc = cocotb.start_soon(send_paths(dut, s_axis_sig, chall_b))
        stree_regen_proc = cocotb.start_soon(send_expanded_seeds_regen(dut, s_axis, m_axis))

        await path_proc
        await stree_regen_proc

        # Now read each leaf with b_i = 1 twice
        test_frame = AxiStreamFrame([i for i in range(BYTES_SEED)])
        for k in range(W):
            data_0 = await m_axis.recv()
            data_1 = await m_axis.recv()
            assert (list(data_0.tdata) == list(test_frame.tdata)), "Wrong data received on m_axis (leafs)!"
            assert (list(data_1.tdata) == list(test_frame.tdata)), "Wrong data received on m_axis (leafs)!"
            assert (list(data_1.tdata) == list(data_0.tdata)), "Wrong data received on m_axis (leafs)!"

        # Wait until FSM is idle again
        while True:
            await cocotb.triggers.RisingEdge(dut.clk)
            if (int(dut.u_stree_addr.state.value) == 0):
                break
