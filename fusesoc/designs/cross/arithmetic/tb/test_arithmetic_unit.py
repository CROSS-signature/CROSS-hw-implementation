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

VARIANT = ["RSDP", "RSDPG"]
CATEGORY = ["CATEGORY_1", "CATEGORY_3", "CATEGORY_5"]
STREAM_WIDTH = [64]
MAT_DATA_WIDTH = [64, 192, 712]


@pytest.mark.parametrize("VARIANT", VARIANT, ids=lambda x: pytest_id({"VARIANT": x}))
@pytest.mark.parametrize("CATEGORY", CATEGORY, ids=lambda x: pytest_id({"CATEGORY": x}))
@pytest.mark.parametrize("STREAM_WIDTH", STREAM_WIDTH, ids=lambda x: pytest_id({"STREAM_WIDTH": x}))
@pytest.mark.parametrize("MAT_DATA_WIDTH", MAT_DATA_WIDTH, ids=lambda x: pytest_id({"MAT_DATA_WIDTH": x}))
def test_arithmetic_unit(VARIANT, CATEGORY, STREAM_WIDTH, MAT_DATA_WIDTH):
    args = locals()
    sim_build = "sim_build/" + "+".join([str(k) + "-" + str(v) for (k, v) in args.items()])

    defines = [VARIANT, CATEGORY, "FAST"]
    parameters = {"STREAM_WIDTH": STREAM_WIDTH, "MAT_DATA_WIDTH": MAT_DATA_WIDTH}
    envs = {f"TB_{k}": str(v) for k, v in parameters.items()}
    for item in defines:
        k, *v = item.split("=")
        envs[f"TB_{k}"] = "true" if len(v) == 0 else v[0]

    sim_files, extra_args, plus_args, make_args = pre_simulation(sim_folder=os.path.abspath(os.path.dirname(__file__)))

    try:
        run(
            verilog_sources=sim_files["rtl_files"],  # sources
            includes=sim_files["include_dirs"],
            toplevel="tb_arithmetic_unit",  # top level HDL
            module="tb_arithmetic_unit",  # name of cocotb test module
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
