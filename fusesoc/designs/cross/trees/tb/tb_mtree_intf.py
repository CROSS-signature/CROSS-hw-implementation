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

GEN_TREE = 0
REGEN_TREE = 1

S_PARENT_REGEN = 11
S_COMPRESS_REGEN = 10

ITERATIONS = int(os.getenv("TB_ITERATIONS", 50))

T = int(os.environ.get("T"))
W = int(os.environ.get("W"))
LAMBDA = int(os.environ.get("LAMBDA"))
BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8
WPS = (BYTES_SEED+7)//8
WPH = (BYTES_HASH+7)//8

def to_c_array(values, name="foo", formatter=str):
    values = [formatter(v) for v in values]
    body = ', '.join(values)
    return '#define {} {{{}}}'.format(name, body)

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

def mtree_offsets_and_nodes():
    # Full trees on the left half, so we can already count (i.e. subtract) these values as well as the root node
    offsets = [2**(i-1) for i in range(1, clog2(T)+1)]
    offsets.insert(0,0)

    remaining_leaves = T - 2**(clog2(T)-1)
    level = 1

    while(remaining_leaves > 0):
        depth = 0
        stree_found = False

        while(stree_found == False):
            if (remaining_leaves <= 2**depth):
                for i in range(depth, 0, -1):
                    offsets[level+i] -= 2**(i-1)

                remaining_leaves -= (2**clog2(remaining_leaves)) // 2
                offsets[level] -= 1
                level += 1
                stree_found = True
            else:
                depth += 1


    nodes_per_level = [0]*(clog2(T)+1)
    for i in range(clog2(T), -1, -1):
        nodes_per_level[i] = 2**i - offsets[i]
        for j in range(i-1, -1, -1):
            offsets[i] -= offsets[j]
        offsets[i] >>= 1

    cnt = 0
    idx_per_level = []
    for d in range(len(nodes_per_level)):
        tmp = []
        for n in range(nodes_per_level[d]):
            tmp.append(cnt)
            cnt += 1
        idx_per_level.append(tmp)

    return idx_per_level, offsets, nodes_per_level


def mtree_leaves():
    leaves = [0]*T
    leaves_per_level = [0]*(clog2(T)+1)
    start_index_per_level = [0]*(clog2(T)+1)
    ctr = 0

    _, offsets, _ = mtree_offsets_and_nodes()

    remaining_leaves = T
    depth = 0
    level = 0
    root_node = 0
    left_child = l_child(root_node) - 2*offsets[level+depth]

    while (remaining_leaves > 0):
        depth = 1
        subtree_found = False

        while(subtree_found == False):
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
                root_node = r_child(root_node) - 2*offsets[level]
                left_child = l_child(root_node) - 2*offsets[level]
                level += 1
                remaining_leaves -= 2**clog2(remaining_leaves)//2
                subtree_found = True
            else:
                left_child = l_child(left_child) - 2*offsets[level+depth]
                depth += 1

    # Now create array with start idx and number of leaves
    n_leaves = []
    idx = []
    for level in range(len(leaves_per_level)):
        if leaves_per_level[level] > 0:
            n_leaves.append(leaves_per_level[level])
            idx.append(start_index_per_level[level])

    idx = idx[::-1]
    n_leaves = n_leaves[::-1]
    n_subroots = len(n_leaves)

    leaves = []
    for i in range(n_subroots):
        for j in range(n_leaves[i]):
            leaves.append(idx[i] + j)

    return idx, leaves

def compute_children_and_parents():
    _, off, npl = mtree_offsets_and_nodes()
    start_idx, _ = mtree_leaves()

    children = []
    parents = []
    start_node = start_idx[0]
    for lvl in range(clog2(T), 0, -1):
        for node in range(npl[lvl]-2, -1, -2):
            current_node = start_node + node
            parent_node = parent(current_node) + off[lvl-1]

            children.append(current_node)
            children.append(current_node+1)
            parents.append(parent_node)

        start_node = parent(start_node) + off[lvl-1]
    return children, parents

def label_tree_and_proof(ch):
    _, off, npl = mtree_offsets_and_nodes()
    tree = [0]*(2*T-1)

    proof = []
    cnt = 0

    # Place the challenge
    _, leaves = mtree_leaves()
    for idx, l in enumerate(leaves):
        tree[l] = 1 - ch[idx]

    # Now traverse through the tree and label the rest
    start_node = leaves[0]
    for l in range(clog2(T), 0, -1):
        for n in range(npl[l]-2, -1, -2):
            c_node = start_node + n
            p_node = parent(c_node) + off[l-1]
            tree[p_node] = tree[c_node] or tree[sibling(c_node)]

            if tree[c_node] and not tree[sibling(c_node)]:
                proof.append(sibling(c_node))
            if not tree[c_node] and tree[sibling(c_node)]:
                proof.append(c_node)
        start_node = parent(start_node) + off[l-1]

    return tree, proof

def recompute_tree_and_proof(ch):
    _, off, npl = mtree_offsets_and_nodes()
    tree = [0]*(2*T-1)

    parents = []
    children = []
    proof = []

    # Place the challenge
    _, leaves = mtree_leaves()
    for idx, l in enumerate(leaves):
        tree[l] = 1 - ch[idx]

    # Now traverse through the tree and label the rest
    start_node = leaves[0]
    cnt = 0
    for l in range(clog2(T), 0, -1):
        for n in range(npl[l]-2, -1, -2):
            c_node = start_node + n
            p_node = parent(c_node) + off[l-1]
            tree[p_node] = tree[c_node] or tree[sibling(c_node)]

            # For test, store parent node
            if tree[c_node] or tree[sibling(c_node)]:
                parents.append(p_node)

            # Now the child nodes
            if tree[c_node]:
                children.append(c_node)
            if tree[sibling(c_node)]:
                children.append(sibling(c_node))

            # And now the proof nodes
            if tree[c_node] and not tree[sibling(c_node)]:
                proof.append(cnt)
                cnt += 1
            if not tree[c_node] and tree[sibling(c_node)]:
                proof.append(cnt)
                cnt += 1

        start_node = parent(start_node) + off[l-1]

    return parents, children, proof

async def read_proof(dut):
    proof = []
    while(True):
        await cocotb.triggers.RisingEdge(dut.clk)
        if dut.proof_addr_valid.value:
            proof.append(int(dut.proof_addr.value))
        if dut.flag_last.value:
            break
    return proof

async def read_recomputed_tree_and_proof(dut):
    parents = []
    children = []
    proof = []
    cnt = 0
    while(True):
        await cocotb.triggers.RisingEdge(dut.clk)
        if dut.addr_valid.value and dut.addr_ready.value:
            if int(dut.u_mtree_addr.state.value) == S_PARENT_REGEN and dut.addr_we.value:
                parents.append(int(dut.addr.value) // dut.WORDS_PER_HASH.value)
            elif int(dut.u_mtree_addr.state.value) == S_COMPRESS_REGEN and dut.addr_is_proof.value:
                proof.append(cnt // dut.WORDS_PER_HASH.value)
                cnt += 1
            elif int(dut.u_mtree_addr.state.value) == S_COMPRESS_REGEN:
                children.append(int(dut.addr.value) // dut.WORDS_PER_HASH.value)
            if dut.addr_last.value:
                break

    parents = parents[::dut.WORDS_PER_HASH.value]
    children = children[::dut.WORDS_PER_HASH.value]
    proof = proof[::dut.WORDS_PER_HASH.value]
    return parents, children, proof


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_mtree_su_sign(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_ch = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    BYTES_HASH = dut.WORDS_PER_HASH.value * (dut.DATA_WIDTH.value//8)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for _ in range(ITERATIONS):

        root = AxiStreamFrame([0 for i in range(BYTES_HASH)])

        dut.op.value = GEN_TREE
        dut.op_valid.value = 1
        await cocotb.triggers.RisingEdge(dut.clk)
        while(not (dut.op_valid.value and dut.op_ready.value)):
            await cocotb.triggers.RisingEdge(dut.clk)
        dut.op_valid.value = 0

        cmt = AxiStreamFrame([i for i in range(BYTES_HASH)])
        for j in range(T):
            await s_axis.send(cmt)
            await s_axis.wait()

        inner_node = AxiStreamFrame([i for i in range(BYTES_HASH)])
        for j in range(T-1):
            # Read to outputs and check if its correct
            for i in range(2):
                data = await m_axis.recv()
                assert list(data.tdata) == list(inner_node.tdata), "Wrong data received!"
            if ( j == T-2):
                await s_axis.send(root)
                await s_axis.wait()
            else:
                await s_axis.send(inner_node)
                await s_axis.wait()

        # Now read root
        data = await m_axis.recv()
        assert list(data.tdata) == list(root.tdata), "Wrong root received!"

        # Now generate the proof
        chall_b = [0]*(T-W) + [1]*W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]
        await s_axis_ch.send(chall_b)

        while(True):
            await cocotb.triggers.RisingEdge(dut.clk)
            if dut.sig_ctrl_proof_cnt_valid.value:
                break
        await cocotb.triggers.RisingEdge(dut.clk)
        dut.op_valid.value = 0
        dut.sign_done.value = 1
        await cocotb.triggers.RisingEdge(dut.clk)


async def send_proofs(dut, s_axis_sig, chall_b):
    BYTES_HASH = dut.WORDS_PER_HASH.value * (dut.DATA_WIDTH.value//8)
    _, proof = label_tree_and_proof(chall_b)
    # Send some proof nodes, do this without blocking because we also need to send computed hash nodes
    for i in range(len(proof)):
        proof = AxiStreamFrame([i for i in range(BYTES_HASH)])
        await s_axis_sig.send(proof)
        await s_axis_sig.wait()
    return

async def check_output(dut, m_axis):
    test_frame = AxiStreamFrame([i for i in range(BYTES_HASH)])
    while(True):
        data = await m_axis.recv()
        assert (list(data.tdata) == list(test_frame.tdata)), "Wrong data received on m_axis!"

async def send_cmt_and_inner(dut, s_axis, chall_b):
    # Send nodes that verifier computes on his own
    cmt = AxiStreamFrame([i for i in range(BYTES_HASH)])
    for bi in chall_b:
        if not bi:
            await cocotb.triggers.RisingEdge(dut.clk)
            await s_axis.send(cmt)
            await s_axis.wait()

    inner_node = AxiStreamFrame([i for i in range(BYTES_HASH)])
    for j in range(T-1):
        await cocotb.triggers.RisingEdge(dut.clk)
        await s_axis.send(inner_node)
        await s_axis.wait()
    return


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_mtree_su_verify(dut):
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
        dut.op.value = REGEN_TREE
        dut.op_valid.value = 1
        await cocotb.triggers.RisingEdge(dut.clk)
        while(not (dut.op_valid.value and dut.op_ready.value)):
            await cocotb.triggers.RisingEdge(dut.clk)
        dut.op_valid.value = 0


        # Now generate the proof
        chall_b = [0]*(T-W) + [1]*W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]

        # Send commitments and inner nodes in separate thread
        proof_inner = cocotb.start_soon(send_cmt_and_inner(dut, s_axis, chall_b))
        proof_proc = cocotb.start_soon(send_proofs(dut, s_axis_sig, chall_b))
        check_proc = cocotb.start_soon(check_output(dut, m_axis))

        # Now send challenge
        await s_axis_ch.send(chall_b)

        while True:
            await cocotb.triggers.RisingEdge(dut.clk)
            if dut.m_axis_tvalid.value and dut.m_axis_tready.value and dut.m_axis_tlast.value \
                and dut.u_mtree_addr.sig_ctrl_mtree_vrfy_done.value:
                break
