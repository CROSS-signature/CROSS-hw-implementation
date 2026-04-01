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

# reverse map of enum used in RTL
SHA3_ALG_ENUM = {
    "SHAKE_128": 4,
    "SHAKE_256": 5,
}

SHA3_ALG = SHA3_ALG_ENUM.keys()
STREAM_WIDTH = [64]
UNROLL_FACTOR = [i for i in range(1, 25) if 24 % i == 0]
LAMBDA = [128, 192, 256]


@pytest.mark.parametrize("SHA3_ALG", SHA3_ALG, ids=lambda x: pytest_id({"SHA3_ALG": x}))
@pytest.mark.parametrize("STREAM_WIDTH", STREAM_WIDTH, ids=lambda x: pytest_id({"STREAM_WIDTH": x}))
@pytest.mark.parametrize("UNROLL_FACTOR", UNROLL_FACTOR, ids=lambda x: pytest_id({"UNROLL_FACTOR": x}))
@pytest.mark.parametrize("LAMBDA", LAMBDA, ids=lambda x: pytest_id({"LAMBDA": x}))
def test_sha3(SHA3_ALG, STREAM_WIDTH, UNROLL_FACTOR, LAMBDA):
    args = locals()
    sim_build = "sim_build/" + "+".join([str(k) + "-" + str(v) for (k, v) in args.items()])

    defines = []
    parameters = {
        "SHA3_ALG": SHA3_ALG_ENUM[SHA3_ALG],
        "STREAM_WIDTH": STREAM_WIDTH,
        "UNROLL_FACTOR": UNROLL_FACTOR,
        "SEED1_SZ": 3 * LAMBDA + 16,
        "SEED2_SZ": 4 * LAMBDA + 16,
    }
    envs = {f"TB_{k}": str(v) for k, v in parameters.items()}
    envs["TB_SHA3_ALG_NAME"] = SHA3_ALG
    for item in defines:
        k, *v = item.split("=")
        envs[f"TB_{k}"] = "true" if len(v) == 0 else v[0]

    sim_files, extra_args, plus_args, make_args = pre_simulation(sim_folder=os.path.abspath(os.path.dirname(__file__)))

    try:
        run(
            verilog_sources=sim_files["rtl_files"],  # sources
            includes=sim_files["include_dirs"],
            toplevel="tb_sha3",  # top level HDL
            module="tb_sha3",  # name of cocotb test module
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
