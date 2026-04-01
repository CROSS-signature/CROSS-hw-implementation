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
from enum import Enum
from math import ceil, log2

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamSource

ITERATIONS = int(os.getenv("TB_ITERATIONS", 50))

GEN_TREE = 0
REGEN_TREE = 1

T = int(os.environ.get("T"))
W = int(os.environ.get("W"))
TREE_NODES_TO_STORE = int(os.environ.get("TREE_NODES_TO_STORE"))


class STATE(Enum):
    S_IDLE = 0
    S_STORE_MSEED = 1
    S_PARENT_ADDR = 2
    S_CHILD_ADDR = 3
    S_PROVIDE_SEEDS = 4
    S_PLACE_CH = 5
    S_CHILD_CH = 6
    S_PARENT_CH = 7
    S_PARENT_PATH = 8
    S_CHILD_PATH = 9
    S_WAIT_PATH = 10
    S_WAIT_SIGN_DONE = 11
    S_CURRENT_REGEN = 12
    S_EXPAND_REGEN = 13
    S_LEAF_FLAG_REGEN = 14
    S_PROVIDE_SEEDS_REGEN = 15


def clog2(a):
    return max(int(ceil(log2(a))), 1)


def parent(a):
    return (a - 1) // 2 if a % 2 else (a - 2) // 2


def l_child(a):
    return 2 * a + 1


def r_child(a):
    return 2 * a + 2


def sibling(a):
    return (a + 1) if a % 2 else (a - 1)


# Compute the offsets for the truncated trees required to move between two levels
def tree_offsets_and_nodes(T):
    # Full trees on the left half, so we can already count (i.e. subtract) these values as well as the root node
    missing_nodes_per_level = [2 ** (i - 1) for i in range(1, clog2(T) + 1)]
    missing_nodes_per_level.insert(0, 0)

    remaining_leaves = T - 2 ** (clog2(T) - 1)
    level = 1

    # Starting from the first level, we construct the tree in a way that the left
    # subtree is always a full binary tree.
    while remaining_leaves > 0:
        depth = 0
        stree_found = False
        while not stree_found:
            if remaining_leaves <= 2**depth:
                for i in range(depth, 0, -1):
                    missing_nodes_per_level[level + i] -= 2 ** (i - 1)
                remaining_leaves -= (2 ** clog2(remaining_leaves)) // 2

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

    nodes_per_level = [2**i - missing_nodes_per_level[i] for i in range(clog2(T) + 1)]
    return offsets, nodes_per_level


# Compute the number of subtrees and corresponding start indices of the leaf nodes within
# the full tree.
def tree_leaves(T, offsets):
    leaves = [0] * T
    leaves_per_level = [0] * (clog2(T) + 1)
    start_index_per_level = [0] * (clog2(T) + 1)
    ctr = 0

    remaining_leaves = T
    depth = 0
    level = 0
    root_node = 0
    left_child = l_child(root_node) - offsets[level + depth]

    while remaining_leaves > 0:
        depth = 1
        subtree_found = False
        while not subtree_found:
            if remaining_leaves <= 2**depth:
                for i in range(2 ** clog2(remaining_leaves) // 2):
                    leaves[ctr] = root_node if remaining_leaves == 1 else left_child + i
                    if remaining_leaves == 1:
                        leaves_per_level[level] += 1
                        start_index_per_level[level] = (
                            root_node if start_index_per_level[level] == 0 else start_index_per_level[level]
                        )
                    else:
                        leaves_per_level[level + depth] += 1
                        start_index_per_level[level + depth] = (
                            left_child if start_index_per_level[level + depth] == 0 else start_index_per_level[level + depth]
                        )
                    ctr += 1
                root_node = r_child(root_node) - offsets[level]
                left_child = l_child(root_node) - offsets[level]
                level += 1
                remaining_leaves -= 2 ** clog2(remaining_leaves) // 2
                subtree_found = True
            else:
                left_child = l_child(left_child) - offsets[level + depth]
                depth += 1

    # Now create array with start idx and number of leaves by removing zeros
    cons_leaves = [i for i in leaves_per_level if i != 0]
    start_index_per_level = [i for i in start_index_per_level if i != 0]

    return leaves_per_level, len(cons_leaves), start_index_per_level[::-1], cons_leaves[::-1]


def gen_stree(T):
    off, npl = tree_offsets_and_nodes(T)
    lpl, _, _, _ = tree_leaves(T, off)

    father_arr = []
    child_arr = []

    start = 0
    for lvl in range(clog2(T)):
        for node in range(npl[lvl] - lpl[lvl]):
            father = start + node
            left_child = l_child(father) - off[lvl]
            father_arr.append(father)
            child_arr.append(left_child)
            child_arr.append(left_child + 1)
        start += npl[lvl]
    return father_arr, child_arr


def gen_path(T, ch):
    off, npl = tree_offsets_and_nodes(T)
    lpl, subroots, idc, cons_leaves = tree_leaves(T, off)

    tree = [0] * (2 * T - 1)
    path = []

    # Place the challenge
    cnt = 0
    for i in range(subroots):
        for j in range(cons_leaves[i]):
            tree[idc[i] + j] = ch[cnt]
            cnt += 1

    # Now traverse through the tree and label the rest
    start_node = idc[0]
    for l in range(clog2(T), 0, -1):
        for n in range(npl[l] - 2, -1, -2):
            c_node = start_node + n
            p_node = parent(c_node) + off[l - 1] // 2
            tree[p_node] = tree[c_node] and tree[sibling(c_node)]
        start_node = parent(start_node) + off[l - 1] // 2

    # Now traverse from root to bottom to collect the path nodes
    start_node = 1
    for l in range(1, clog2(T) + 1):
        for n in range(npl[l]):
            c_node = start_node + n
            p_node = parent(c_node) + off[l - 1] // 2
            if tree[c_node] and not tree[p_node]:
                path.append(c_node)
        start_node = l_child(start_node) - off[l]

    return path


def stree_regen(T, ch):
    off, npl = tree_offsets_and_nodes(T)
    lpl, subroots, idc, cons_leaves = tree_leaves(T, off)
    tree = [0] * (2 * T - 1)
    path = []

    # Place the challenge
    cnt = 0
    for i in range(subroots):
        for j in range(cons_leaves[i]):
            tree[idc[i] + j] = ch[cnt]
            cnt += 1

    # Now traverse through the tree and label the rest
    start_node = idc[0]
    for l in range(clog2(T), 0, -1):
        for n in range(npl[l] - 2, -1, -2):
            c_node = start_node + n
            p_node = parent(c_node) + off[l - 1] // 2
            tree[p_node] = tree[c_node] and tree[sibling(c_node)]
        start_node = parent(start_node) + off[l - 1] // 2

    # Now traverse from root to bottom to collect the path nodes
    parents_to_expand = []
    expanded_children = []
    path_cnt = 0
    start_node = 1
    for l in range(1, clog2(T) + 1):
        for n in range(npl[l]):
            c_node = start_node + n
            p_node = parent(c_node) + off[l - 1] // 2
            left_child = l_child(c_node) - off[l]
            # Consider all nodes except for the leaves
            if n < npl[l] - lpl[l]:
                if tree[c_node]:
                    if tree[p_node]:  # Inner node expanded
                        parents_to_expand.append(c_node)
                    else:  # path node expanded
                        parents_to_expand.append(path_cnt)
                        path_cnt += 1
                    expanded_children.append(left_child)
                    expanded_children.append(left_child + 1)
            # Now consider the leaves
            else:
                if tree[c_node] and not tree[p_node]:
                    expanded_children.append(c_node)
        start_node = l_child(start_node) - off[l]

    # Now create a final array for the provided seeds
    round_seeds = []
    for i in range(subroots):
        for j in range(cons_leaves[i]):
            if tree[idc[i] + j]:
                round_seeds.append(idc[i] + j)
                round_seeds.append(idc[i] + j)
    return parents_to_expand, expanded_children, round_seeds


async def read_regen(dut):
    cnt = 0
    seeds = []
    children = []
    child_stored = False
    while True:
        await cocotb.triggers.RisingEdge(dut.clk)
        if dut.addr_valid.value and dut.addr_ready.value and dut.u_stree_addr.state.value == STATE.S_EXPAND_REGEN.value:
            if dut.addr_we.value:
                if not child_stored:
                    children.append(dut.u_stree_addr.addr.value // dut.WORDS_PER_SEED.value)
                    if not dut.regen_fetch_path.value:
                        children.append((dut.u_stree_addr.addr.value + dut.WORDS_PER_SEED.value) // dut.WORDS_PER_SEED.value)
                        child_stored = not child_stored
                else:
                    child_stored = not child_stored
            else:
                seeds.append(dut.addr.value // dut.WORDS_PER_SEED.value)

        if dut.u_stree_addr.addr_last.value:
            break

    return seeds, children


async def read_seeds_regen(dut):
    seeds = []
    while True:
        await RisingEdge(dut.clk)
        if dut.addr_valid.value and dut.addr_ready.value and (dut.u_stree_addr.state.value == STATE.S_PROVIDE_SEEDS_REGEN.value):
            if not dut.addr_we.value:
                seeds.append(dut.u_stree_addr.addr.value // dut.WORDS_PER_SEED.value)
        if len(seeds) == 2 * W:
            break
    return seeds


async def read_stree(dut):
    children = []
    parents = []
    child_stored = False
    while True:
        await RisingEdge(dut.clk)
        if dut.addr_valid.value and dut.addr_ready.value and dut.u_stree_addr.state.value != STATE.S_STORE_MSEED.value:
            if dut.addr_we.value:
                if not child_stored:
                    children.append(dut.u_stree_addr.addr.value // dut.WORDS_PER_SEED.value)
                    children.append((dut.u_stree_addr.addr.value + dut.WORDS_PER_SEED.value) // dut.WORDS_PER_SEED.value)
                    child_stored = not child_stored
                else:
                    child_stored = not child_stored
            elif not dut.addr_we.value:
                parents.append(dut.u_stree_addr.addr.value // dut.WORDS_PER_SEED.value)
            if dut.u_stree_addr.addr_last.value:
                break
    return parents, children


async def read_seeds(dut):
    seeds = []
    while True:
        await RisingEdge(dut.clk)
        if dut.addr_valid.value and dut.addr_ready.value and (dut.u_stree_addr.state.value == STATE.S_PROVIDE_SEEDS.value):
            if not dut.addr_we.value:
                seeds.append(dut.u_stree_addr.addr.value // dut.WORDS_PER_SEED.value)
        if len(seeds) == 2 * T:
            break
    return seeds


async def read_path(dut):
    path = []
    while True:
        await RisingEdge(dut.clk)
        if dut.path_addr_valid.value:
            path.append(int(dut.path_addr.value))
        if dut.path_last.value:
            break
    return path


async def send_opcode(dut, op):
    dut.op.value = op
    dut.op_valid.value = 1

    while not (dut.op_valid.value and dut.op_ready.value):
        await cocotb.triggers.RisingEdge(dut.clk)
    dut.op_valid.value = 0
    return


@cocotb.test(timeout_time=20 * ITERATIONS, timeout_unit="ms")
async def stree_gen_tree(dut):
    s_axis_ch = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    off, npl = tree_offsets_and_nodes(T)
    lpl, subroots, idc, cons_leaves = tree_leaves(T, off)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    dut.sig_ctrl_sign_done.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for i in range(ITERATIONS):
        await cocotb.triggers.RisingEdge(dut.clk)
        dut.addr_ready.value = 1

        await send_opcode(dut, GEN_TREE)

        # Generate and check tree generation
        exp_parents, exp_children = gen_stree(T)
        got_parents, got_children = await read_stree(dut)

        print(T)
        print(f"Children: {got_children}")
        print(f"Exp-Children: {exp_children}")
        print(len(got_children))
        print(len(exp_children))
        for i in range(len(exp_children)):
            assert got_children[i] == exp_children[i], "Indices of children don't match at position " + str(i)

        # print(f'Parents: {got_parents}')
        # print(f'Exp-Parents: {exp_parents}')
        for i in range(len(exp_parents)):
            assert got_parents[i] == exp_parents[i], "Indices of children don't match at position " + str(i)

        # Now read provided seeds
        got_seeds = await read_seeds(dut)
        exp_seeds = []
        for i in range(subroots):
            for j in range(cons_leaves[i]):
                exp_seeds.append(idc[i] + j)
                exp_seeds.append(idc[i] + j)

        # print(f'Got seeds: {got_seeds}')
        # print(f'Exp seeds: {exp_seeds}')
        for i in range(len(exp_seeds)):
            assert got_seeds[i] == exp_seeds[i], "Round seeds don't match at position " + str(i)

        # Now generate the path
        chall_b = [0] * (T - W) + [1] * W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]

        # Send input
        path_proc = cocotb.start_soon(read_path(dut))
        await s_axis_ch.send(chall_b)
        await s_axis_ch.wait()

        exp_path = gen_path(T, chall_b)
        got_path = await path_proc

        print(f"Got path: {got_path}")
        print(f"Exp path: {exp_path}")
        assert len(got_path) <= TREE_NODES_TO_STORE, "Path is too long"
        for i in range(len(exp_path)):
            assert got_path[i] == exp_path[i], "Path nodes don't match at position " + str(i)

        dut.sig_ctrl_sign_done.value = 1
        await RisingEdge(dut.clk)
        dut.sig_ctrl_sign_done.value = 0


@cocotb.test(timeout_time=20 * ITERATIONS, timeout_unit="ms")
async def stree_recompute(dut):
    s_axis_ch = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_ch"), dut.clk, dut.rst_n, reset_active_level=False)
    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    await cocotb.triggers.RisingEdge(dut.clk)
    dut.addr_ready.value = 1

    for i in range(ITERATIONS):
        await send_opcode(dut, REGEN_TREE)

        chall_b = [0] * (T - W) + [1] * W
        chall_b = list(np.random.permutation(chall_b))
        chall_b = [int(a) for a in chall_b]

        # Send input
        await s_axis_ch.send(chall_b)
        await s_axis_ch.wait()

        got_seeds, got_children = await read_regen(dut)
        got_roundseeds = await read_seeds_regen(dut)
        exp_seeds, exp_children, exp_roundseeds = stree_regen(T, chall_b)

        # print(f'Exp seeds: {exp_seeds}')
        # print(f'Got seeds: {got_seeds}')
        # print(f'Exp children: {exp_children}')
        # print(f'Got children: {got_children}')
        # print(f'Exp roundseeds: {exp_roundseeds}')
        # print(f'Got roundseeds: {got_roundseeds}')
        assert len(got_seeds) == len(exp_seeds), "Seed lengths differ!"
        for j in range(len(exp_seeds)):
            assert got_seeds[j] == exp_seeds[j], "Seeds differ at index " + str(j) + " in iteration " + str(i)

        assert len(got_children) == len(exp_children), "Children lengths differ!"
        for j in range(len(exp_children)):
            assert got_children[j] == exp_children[j], "Children differ at index " + str(j) + " in iteration " + str(i)

        assert len(got_roundseeds) == len(exp_roundseeds), "Roundseeds lengths differ!"
        for j in range(len(exp_roundseeds)):
            assert got_roundseeds[j] == exp_roundseeds[j], "Roundseeds differ at index " + str(j) + " in iteration " + str(i)
