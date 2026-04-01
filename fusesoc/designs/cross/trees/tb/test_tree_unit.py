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

import json
import os
import sys
from pathlib import Path

import pytest
from cocotb_test.simulator import run

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import post_simulation, pre_simulation, pytest_id

# Creating environment (that's a bit dirty here)
environment = []
with open("params.json", "r") as param_file:
    config = json.load(param_file)

    for idx, ver in enumerate(config):
        for cat in ver["category"]:
            for tar in cat["target"]:
                if "FAST" in tar["defines"]:
                    continue
                if idx == 0: # RSDP
                    environment.append({"P" : ver["P"], "Z": ver["Z"], "LAMBDA" : cat["LAMBDA"], "N" : cat["N"], "K" : cat["K"], \
                        "SIGSIZE" : tar["SIGSIZE"], "TREE_NODES_TO_STORE" : tar["TNODES"], "T" : tar["T"], "W" : tar["W"], \
                        "CLIB" : tar["CLIB"], "defines" : tar["defines"]})
                else: # RSDPG
                    environment.append({"P" : ver["P"], "Z": ver["Z"], "LAMBDA" : cat["LAMBDA"], "N" : cat["N"], "K" : cat["K"], \
                        "SIGSIZE" : tar["SIGSIZE"], "TREE_NODES_TO_STORE" : tar["TNODES"], "M" : cat["M"], "T" : tar["T"], \
                        "W" : tar["W"], "CLIB" : tar["CLIB"], "defines" : tar["defines"]})

# Creating parameters
params = []
params.append({"DATA_WIDTH": str(64)})


@pytest.mark.parametrize("env", environment, ids=[pytest_id(env) for env in environment])
@pytest.mark.parametrize("parameters", params, ids=[pytest_id(param) for param in params])
def test_tree_unit(parameters, env):
    tmp = env.copy()
    defs = tmp.pop("defines")
    sim_build = "sim_build/" + "_".join(("{}={}".format(*i) for i in parameters.items())) + "_" + defs

    sim_files, extra_args, plus_args, make_args = pre_simulation(sim_folder=os.path.abspath(os.path.dirname(__file__)))

    try:
        run(
            verilog_sources=sim_files["rtl_files"],
            includes=sim_files["include_dirs"],
            toplevel="tb_tree_unit",
            module="tb_tree_unit",
            parameters=parameters,
            extra_env=tmp,
            extra_args=extra_args,
            compile_args=[defs],
            plus_args=plus_args,
            sim_build=sim_build,
            make_args=make_args,
        )

    finally:
        post_simulation(sim_build=sim_build)
