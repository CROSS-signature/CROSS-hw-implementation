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

import os
import sys
from pathlib import Path

import pytest
from cocotb_test.simulator import run

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import post_simulation, pre_simulation, pytest_id

WIDTH = [8]
IN_BLOCK_SZ = [7, 9, 21]
OUT_BLOCK_SZ = [7, 9, 21]


@pytest.mark.parametrize("WIDTH", WIDTH, ids=lambda x: pytest_id({"WIDTH": x}))
@pytest.mark.parametrize("IN_BLOCK_SZ", IN_BLOCK_SZ, ids=lambda x: pytest_id({"IN_BLOCK_SZ": x}))
@pytest.mark.parametrize("OUT_BLOCK_SZ", OUT_BLOCK_SZ, ids=lambda x: pytest_id({"OUT_BLOCK_SZ": x}))
def test_axis_asym_fifo(WIDTH, IN_BLOCK_SZ, OUT_BLOCK_SZ):
    args = locals()
    sim_build = "sim_build/" + "+".join([str(k) + "-" + str(v) for (k, v) in args.items()])

    if IN_BLOCK_SZ < OUT_BLOCK_SZ:
        pytest.skip("IN block must be larger than OUT block")

    defines = ["RSDPG", "CATEGORY_1", "FAST"]
    parameters = {"WIDTH": WIDTH, "IN_BLOCK_SZ": IN_BLOCK_SZ, "OUT_BLOCK_SZ": OUT_BLOCK_SZ}
    envs = {f"TB_{k}": str(v) for k, v in parameters.items()}
    for item in defines:
        k, *v = item.split("=")
        envs[f"TB_{k}"] = "true" if len(v) == 0 else v[0]

    sim_files, extra_args, plus_args, make_args = pre_simulation(sim_folder=os.path.abspath(os.path.dirname(__file__)))

    try:
        run(
            verilog_sources=sim_files["rtl_files"],  # sources
            includes=sim_files["include_dirs"],
            toplevel="tb_axis_asym_fifo",  # top level HDL
            module="tb_axis_asym_fifo",  # name of cocotb test module
            defines=defines,
            parameters=parameters,
            toplevel_lang="verilog",
            extra_args=extra_args,
            plus_args=plus_args,
            sim_build=sim_build,
            make_args=make_args,
            extra_env=envs,  # used by python tests
        )

    finally:
        post_simulation(sim_build=sim_build)
