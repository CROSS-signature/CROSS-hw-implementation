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

"""
Parametrizations for different variants of CROSS
"""
from dataclasses import dataclass
from typing import Literal
from functools import cached_property

""" Dataclass wrapper for parameters """
@dataclass
class CROSSParameters:
    name: str
    category: Literal[1, 3, 5]
    optim_corner: Literal["fast", "balanced", "small"]
    dll: str
    p: int
    z: int
    n: int
    k: int
    t: int
    w: int
    sig_size: int
    stree_nodes: int
    tree_nodes_to_store: int
    m: int | None = None

    @cached_property
    def sec_margin_lambda(self) -> int:
        if self.category == 1:
            return 128
        elif self.category == 3:
            return 192
        return 256

    """ Utility functions """
    def __str__(self) -> str:
        return (
            f"{self.name} {self.category} ({self.optim_corner}) "
            f"[p={self.p}, z={self.z}, n={self.n}, k={self.k}"
            f"{f', m={self.m}' if self.m else ''} | t={self.t} w={self.w}]"
        )


""" List of all CROSS-parametrizations """
cross_parametrizations = [
    # CROSS-R-SDP Category 1
    CROSSParameters(
        name="RSDP", category=1, optim_corner="fast", p=127, z=7, n=127, k=76, t=157, w=82, m=None,\
                sig_size=18432, tree_nodes_to_store=82, stree_nodes=157, dll='libcross_RSDP_CATEGORY_1_SPEED.so'
    ),
    CROSSParameters(
        name="RSDP", category=1, optim_corner="balanced", p=127, z=7, n=127, k=76, t=256, w=215, m=None,\
                sig_size=13152, tree_nodes_to_store=108, stree_nodes=511, dll='libcross_RSDP_CATEGORY_1_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDP", category=1, optim_corner="small", p=127, z=7, n=127, k=76, t=520, w=488, m=None,\
                sig_size=12432, tree_nodes_to_store=129, stree_nodes=1039, dll='libcross_RSDP_CATEGORY_1_SIG_SIZE.so'
    ),
    # CROSS-R-SDP Category 3
    CROSSParameters(
        name="RSDP", category=3, optim_corner="fast", p=127, z=7, n=187, k=111, t=239, w=125, m=None,\
                sig_size=41406, tree_nodes_to_store=125, stree_nodes=239, dll='libcross_RSDP_CATEGORY_3_SPEED.so'
    ),
    CROSSParameters(
        name="RSDP", category=3, optim_corner="balanced", p=127, z=7, n=187, k=111, t=384, w=321, m=None,\
                sig_size=29853, tree_nodes_to_store=165, stree_nodes=767, dll='libcross_RSDP_CATEGORY_3_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDP", category=3, optim_corner="small", p=127, z=7, n=187, k=111, t=580, w=527, m=None,\
                sig_size=28391, tree_nodes_to_store=184, stree_nodes=1159, dll='libcross_RSDP_CATEGORY_3_SIG_SIZE.so'
    ),
    # CROSS-R-SDP Category 5
    CROSSParameters(
        name="RSDP", category=5, optim_corner="fast", p=127, z=7, n=251, k=150, t=321, w=167, m=None,\
                sig_size=74590, tree_nodes_to_store=167, stree_nodes=321, dll='libcross_RSDP_CATEGORY_5_SPEED.so'
    ),
    CROSSParameters(
        name="RSDP", category=5, optim_corner="balanced", p=127, z=7, n=251, k=150, t=512, w=427, m=None,\
                sig_size=53527, tree_nodes_to_store=220, stree_nodes=1023, dll='libcross_RSDP_CATEGORY_5_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDP", category=5, optim_corner="small", p=127, z=7, n=251, k=150, t=832, w=762, m=None,\
                sig_size=50818, tree_nodes_to_store=251, stree_nodes=1663, dll='libcross_RSDP_CATEGORY_5_SIG_SIZE.so'
    ),
    # CROSS-R-SDP(G) Category 1
    CROSSParameters(
        name="RSDPG", category=1, optim_corner="fast", p=509, z=127, n=55, k=36, t=147, w=76, m=25,\
                sig_size=11980, tree_nodes_to_store=76, stree_nodes=147, dll='libcross_RSDPG_CATEGORY_1_SPEED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=1, optim_corner="balanced", p=509, z=127, n=55, k=36, t=256, w=220, m=25,\
                sig_size=9120, tree_nodes_to_store=101, stree_nodes=511, dll='libcross_RSDPG_CATEGORY_1_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=1, optim_corner="small", p=509, z=127, n=55, k=36, t=512, w=484, m=25,\
                sig_size=8960, tree_nodes_to_store=117, stree_nodes=1023, dll='libcross_RSDPG_CATEGORY_1_SIG_SIZE.so'
    ),
    # CROSS-R-SDP(G) Category 3
    CROSSParameters(
        name="RSDPG", category=3, optim_corner="fast", p=509, z=127, n=79, k=48, t=224, w=119, m=40,\
                sig_size=26772, tree_nodes_to_store=119, stree_nodes=224, dll='libcross_RSDPG_CATEGORY_3_SPEED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=3, optim_corner="balanced", p=509, z=127, n=79, k=48, t=268, w=196, m=40,\
                sig_size=22464, tree_nodes_to_store=138, stree_nodes=535, dll='libcross_RSDPG_CATEGORY_3_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=3, optim_corner="small", p=509, z=127, n=79, k=48, t=512, w=463, m=40,\
                sig_size=20452, tree_nodes_to_store=165, stree_nodes=1023, dll='libcross_RSDPG_CATEGORY_3_SIG_SIZE.so'
    ),
    # CROSS-R-SDP(G) Category 5
    CROSSParameters(
        name="RSDPG", category=5, optim_corner="fast", p=509, z=127, n=106, k=69, t=300, w=153, m=48,\
                sig_size=48102, tree_nodes_to_store=153, stree_nodes=300, dll='libcross_RSDPG_CATEGORY_5_SPEED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=5, optim_corner="balanced", p=509, z=127, n=106, k=69, t=356, w=258, m=48,\
                sig_size=40100, tree_nodes_to_store=185, stree_nodes=711, dll='libcross_RSDPG_CATEGORY_5_BALANCED.so'
    ),
    CROSSParameters(
        name="RSDPG", category=5, optim_corner="small", p=509, z=127, n=106, k=69, t=642, w=575, m=48,\
                sig_size=36454, tree_nodes_to_store=220, stree_nodes=1283, dll='libcross_RSDPG_CATEGORY_5_SIG_SIZE.so'
    ),
]
