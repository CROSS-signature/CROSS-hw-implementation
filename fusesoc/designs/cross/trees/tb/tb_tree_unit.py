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
from cocotb.triggers import RisingEdge, Timer
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
TREE_NODES_TO_STORE = int(os.environ.get("TREE_NODES_TO_STORE"))

BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8
WPS = (BYTES_SEED+7)//8
WPH = (BYTES_HASH+7)//8

def clog2(a):
    return max(int(ceil(log(a,2))), 1)

def parent(a):
    return (a-1)//2 if a % 2 else (a-2)//2

def sibling(a):
    return (a+1) if a % 2 else (a-1)

def l_child(a):
    return 2*a + 1

def r_child(a):
    return 2*a + 2

# Compute the offsets for the truncated trees required to move between two levels
def tree_offsets_and_nodes(T):

    # Full trees on the left half, so we can already count (i.e. subtract) these values as well as the root node
    missing_nodes_per_level = [2**(i-1) for i in range(1, clog2(T)+1)]
    missing_nodes_per_level.insert(0,0)

    remaining_leaves = T - 2**(clog2(T)-1)
    level = 1

    # Starting from the first level, we construct the tree in a way that the left
    # subtree is always a full binary tree.
    while(remaining_leaves > 0):
        depth = 0
        stree_found = False
        while not stree_found:
            if (remaining_leaves <= 2**depth):
                for i in range(depth, 0, -1):
                    missing_nodes_per_level[level+i] -= 2**(i-1)
                remaining_leaves -= (2**clog2(remaining_leaves)) // 2

                # Subtract root and increase level for next iteration
                missing_nodes_per_level[level] -= 1
                level += 1
                stree_found = True
            else:
                depth += 1

    # The offsets are the missing nodes per level subtracted by the missing nodes of all previous levels, as this
    # is already included
    offsets = [missing_nodes_per_level[i] for i in range(len(missing_nodes_per_level))]
    for i in range(clog2(T), -1, -1):
        for j in range(i):
            offsets[i] -= offsets[j]

    nodes_per_level = [2**i - missing_nodes_per_level[i] for i in range(clog2(T)+1)]
    return offsets, nodes_per_level

# Compute the number of subtrees and corresponding start indices of the leaf nodes within
# the full tree.
def tree_leaves(T, offsets):
    leaves = [0]*T
    leaves_per_level = [0]*(clog2(T)+1)
    start_index_per_level = [0]*(clog2(T)+1)
    ctr = 0

    remaining_leaves = T
    depth = 0
    level = 0
    root_node = 0
    left_child = l_child(root_node) - offsets[level+depth]

    while (remaining_leaves > 0):
        depth = 1
        subtree_found = False
        while not subtree_found:
            if (remaining_leaves <= 2**depth):
                for i in range(2**clog2(remaining_leaves)//2):
                    leaves[ctr] = root_node if remaining_leaves==1 else left_child+i
                    if (remaining_leaves==1):
                        leaves_per_level[level] += 1
                        start_index_per_level[level] = root_node if start_index_per_level[level] == 0 else start_index_per_level[level]
                    else:
                        leaves_per_level[level+depth] += 1
                        start_index_per_level[level+depth] = left_child if start_index_per_level[level+depth] == 0 else start_index_per_level[level+depth]
                    ctr += 1
                root_node = r_child(root_node) - offsets[level]
                left_child = l_child(root_node) - offsets[level]
                level += 1
                remaining_leaves -= 2**clog2(remaining_leaves)//2
                subtree_found = True
            else:
                left_child = l_child(left_child) - offsets[level+depth]
                depth += 1

    # Now create array with start idx and number of leaves by removing zeros
    cons_leaves = [i for i in leaves_per_level if i != 0]
    start_index_per_level = [i for i in start_index_per_level if i != 0]

    return leaves_per_level, len(cons_leaves), start_index_per_level[::-1], cons_leaves[::-1]

def gen_path_proof(T, ch):
    off, npl = tree_offsets_and_nodes(T)
    lpl, subroots, idc, cons_leaves = tree_leaves(T, off)

    tree = [0]*(2*T-1)
    path = []

    # Place the challenge
    cnt = 0
    for i in range(subroots):
        for j in range(cons_leaves[i]):
            tree[idc[i]+j] = ch[cnt]
            cnt += 1

    # Now traverse through the tree and label the rest
    start_node = idc[0]
    for l in range(clog2(T), 0, -1):
        for n in range(npl[l]-2, -1, -2):
            c_node = start_node + n
            p_node = parent(c_node) + off[l-1]//2
            tree[p_node] = tree[c_node] and tree[sibling(c_node)]
        start_node = parent(start_node) + off[l-1]//2

    # Now traverse from root to bottom to collect the path nodes
    start_node = 1
    for l in range(1,clog2(T)+1):
        for n in range(npl[l]):
            c_node = start_node + n
            p_node = parent(c_node) + off[l-1]//2
            if tree[c_node] and not tree[p_node]:
                path.append(c_node)
        start_node = l_child(start_node) - off[l]

    return path

async def send_opcode(dut, op):
    dut.op.value = op
    dut.op_valid.value = 1
    await RisingEdge(dut.clk)
    while not (dut.op_valid.value and dut.op_ready.value):
        await RisingEdge(dut.clk)
    dut.op_valid.value = 0
    await RisingEdge(dut.clk)
    return

async def send_b(dut, b, s_axis_b):
    await s_axis_b.send(b)
    await s_axis_b.wait()
    return

async def reset(dut):
	dut.rst_n.value = 0
	await Timer(5, units="ns")
	dut.rst_n.value = 1
	await Timer(73, units="ns")
	return

async def send_expanded_seeds(dut, s_axis):
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    for _ in range(2*T - 2):
        await s_axis.send(node)
        await s_axis.wait()
    return

async def check_seeds_to_expand_send_cmt0(dut, s_axis, m_axis, mseed):
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    cmt = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    # Receive master seed once
    data = await m_axis.recv()
    assert len(data.tdata) == len(mseed.tdata), "Frame of wrong length (master seed) received!"
    assert list(data.tdata) == list(mseed.tdata), "Wrong master seed received!"

    # Tree consists of 2T - 1 nodes with T-1 inner nodes
    # Subtract root node
    for _ in range(T - 2):
        data = await m_axis.recv()
        assert (len(data.tdata) == len(node.tdata)), "Frame of wrong length received on m_axis (stree inner nodes)!"
        assert (list(data.tdata) == list(node.tdata)), "Wrong data received on m_axis (stree inner nodes)!"

    # Now read each leaf twice and send one cmt
    for i in range(2*T):
        data = await m_axis.recv()
        assert (len(data.tdata) == len(node.tdata)), "Frame of wrong length received on m_axis (stree leaves)!"
        assert (list(data.tdata) == list(node.tdata)), "Wrong data received on m_axis (stree leaves)!"
        if (i%2 == 1):
            await s_axis.send(cmt)
            await s_axis.wait()
    return

async def gen_mtree(dut, s_axis, m_axis):
    node = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])
    for _ in range(T-1):
        # Read two leaves
        for _ in range(2):
            data_rec = await m_axis.recv()
            assert len(data_rec.tdata) == len(node.tdata), "Frame of wrong length (mtree node) received!"
            assert list(data_rec.tdata) == list(node.tdata), "Wrong mtree node received!"
        # send parent
        await s_axis.send(node)
        await s_axis.wait()

    # Read mtree root
    data_rec = await m_axis.recv()
    assert len(data_rec.tdata) == len(node.tdata), "Frame of wrong length (mtree root) received!"
    assert list(data_rec.tdata) == list(node.tdata), "Wrong mtree root received!"
    return

async def check_proof_path(dut, m_axis_sig, ch, T):
    stree_node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    mtree_node = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])
    padding_node_stree = AxiStreamFrame([0 for i in range(BYTES_SEED)])
    padding_node_mtree = AxiStreamFrame([0 for i in range(BYTES_HASH)])

    proof = gen_path_proof(T, ch)

    # Read proof nodes
    for i in range(TREE_NODES_TO_STORE):
        data = await m_axis_sig.recv()
        if (i < len(proof)):
            assert (len(data.tdata) == len(mtree_node.tdata)), "Frame of wrong length received on m_axis (mtree proof node)!"
            assert (list(data.tdata) == list(mtree_node.tdata)), "Wrong data received on m_axis (mtree proof node)!"
        else:
            assert (len(data.tdata) == len(padding_node_mtree.tdata)), "Frame of wrong length received on m_axis (mtree padding node)!"
            assert (list(data.tdata) == list(padding_node_mtree.tdata)), "Wrong data received on m_axis (mtree padding node)!"

    # Now read path nodes
    for i in range(TREE_NODES_TO_STORE):
        data = await m_axis_sig.recv()
        if (i < len(proof)):
            assert (len(data.tdata) == len(stree_node.tdata)), "Frame of wrong length received on m_axis (stree inner nodes)!"
            assert (list(data.tdata) == list(stree_node.tdata)), "Wrong data received on m_axis (stree inner nodes)!"
        else:
            assert (len(data.tdata) == len(padding_node_stree.tdata)), "Frame of wrong length received on m_axis (stree padding node)!"
            assert (list(data.tdata) == list(padding_node_stree.tdata)), "Wrong data received on m_axis (stree padding node)!"
    return


async def send_path_and_proof(dut, s_axis):
    node_path = AxiStreamFrame([i for i in range(BYTES_SEED)])
    for _ in range(TREE_NODES_TO_STORE):
        await s_axis.send(node_path)
        await s_axis.wait()

    # Now send proof nodes
    node_proof = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])
    for _ in range(TREE_NODES_TO_STORE):
        await s_axis.send(node_proof)
        await s_axis.wait()
    return

async def expand_tree(dut, s_axis, m_axis):
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    while not dut.vrfy_stree_done.value:
        await RisingEdge(dut.clk)
        # Seed is to be expanded
        if (dut.u_tree_unit.stree_addr_valid.value and not dut.u_tree_unit.stree_addr_we.value \
        and not dut.u_tree_unit.stree_regen_fetch_path.value):
            data = await m_axis.recv()
            assert len(data.tdata) == len(node.tdata), "Frame of wrong length (seed tree) received!"
            assert list(data.tdata) == list(node.tdata), "Wrong node received (seed tree)!"
        # Send expanded children
        if (dut.u_tree_unit.stree_addr_valid.value and dut.u_tree_unit.stree_addr_we.value \
        and not dut.u_tree_unit.stree_regen_fetch_path.value):
            for _ in range(2):
                await s_axis.send(node)
                await s_axis.wait()
    return

async def read_round_seeds(dut, s_axis, m_axis):
    # Read the round seeds
    node = AxiStreamFrame([i for i in range(BYTES_SEED)])
    for _ in range(W):
        for _ in range(2):
            data = await m_axis.recv()
            assert len(data.tdata) == len(node.tdata), "Frame of wrong length (round seed) received!"
            assert list(data.tdata) == list(node.tdata), "Wrong node received (round seed)!"

    # Send the cmt_0
    cmt = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])
    for _ in range(T-W):
        await s_axis.send(cmt)
        await s_axis.wait()
    return

async def regen_mtree(dut, s_axis, m_axis):
    node = AxiStreamFrame([i+1 for i in range(BYTES_HASH)])

    # Otherwise read two children and send parent
    while(1):
        await RisingEdge(dut.clk)
        if (dut.vrfy_mtree_done.value):
            m_axis.pause = 1
            break
        else:
            for _ in range(2):
                data = await m_axis.recv()
                assert len(data.tdata) == len(node.tdata), "Frame of wrong length (mtree node) received!"
                assert list(data.tdata) == list(node.tdata), "Wrong node received (mtree node)!"
            await s_axis.send(node)
            await s_axis.wait()

    # If mtree done is set, it means root must be read
    while(1):
        await RisingEdge(dut.clk)
        if dut.u_tree_unit.sig_ctrl_vrfy_done.value:
            m_axis.pause = 0
            break
    data = await m_axis.recv()
    assert len(data.tdata) == len(node.tdata), "Frame of wrong length (mtree root) received!"
    assert list(data.tdata) == list(node.tdata), "Wrong node received (mtree root)!"
    return


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_sign_tree_unit(dut):
    s_axis_ch   = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis      = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis      = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig  = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)
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

        # Now mimick reading of SeedTree nodes and respond with 'expanded' seeds
        # mseed already there
        stree_nodes_proc = cocotb.start_soon(send_expanded_seeds(dut, s_axis))
        check_proc = cocotb.start_soon(check_seeds_to_expand_send_cmt0(dut, s_axis, m_axis, mseed))
        await stree_nodes_proc
        await check_proc

        # Send some nodes now to place the commitments on mtree and
        # compute the tree
        await gen_mtree(dut, s_axis, m_axis)

        # Now generate the challenge for the mtree proof and stree path
        ch_b = [0]*(T-W) + [1]*W
        ch_b = list(np.random.permutation(ch_b))
        ch_b = [int(b) for b in ch_b]
        await s_axis_ch.send(ch_b)
        await s_axis_ch.wait()

        # Now wait for the node in the mtree proof and stree path
        await check_proof_path(dut, m_axis_sig, ch_b, T)


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_verify_tree_unit(dut):
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

        # Generate the challenge
        ch_b = [0]*(T-W) + [1]*W
        ch_b = list(np.random.permutation(ch_b))
        ch_b = [int(b) for b in ch_b]
        await s_axis_ch.send(ch_b)
        await s_axis_ch.wait()

        # Now send seed nodes from signature concurrently, as it's not clear how many to send.
        # also send expanded nodes
        path_proc = cocotb.start_soon(send_path_and_proof(dut, s_axis_sig))
        await expand_tree(dut, s_axis, m_axis)

        # Read the round seeds twice and send cmt_0
        await read_round_seeds(dut, s_axis, m_axis)
        await regen_mtree(dut, s_axis, m_axis)
        await path_proc

        # Since we do not properly pad but send dummy counter nodes, the padding error
        # flag must be asserted here.
        assert dut.vrfy_pad_err.value == 1, "There was no padding error although the path/proof was not properly padded!"

        dut.vrfy_pad_err_clear.value = 1
        await RisingEdge(dut.clk)
        dut.vrfy_pad_err_clear.value = 0
        await RisingEdge(dut.clk)
        await reset(dut)
