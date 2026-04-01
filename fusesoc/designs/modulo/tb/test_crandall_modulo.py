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

MODULO = [509]
STAGES = [0, 1]


@pytest.mark.parametrize("MODULO", MODULO, ids=lambda x: pytest_id({"MODULO": x}))
@pytest.mark.parametrize("STAGES", STAGES, ids=lambda x: pytest_id({"STAGES": x}))
def test_crandall_modulo(MODULO, STAGES):
    args = locals()
    sim_build = "sim_build/" + "+".join([str(k) + "-" + str(v) for (k, v) in args.items()])

    defines = ["RSDP", "CATEGORY_1", "FAST"]
    parameters = {
        "MODULO": MODULO,
        "MAX_INPUT": (MODULO - 1) ** 2,
        "STAGES": STAGES,
    }
    envs = {}

    sim_files, extra_args, plus_args, make_args = pre_simulation(sim_folder=os.path.abspath(os.path.dirname(__file__)))

    try:
        run(
            verilog_sources=sim_files["rtl_files"],  # sources
            includes=sim_files["include_dirs"],
            toplevel="crandall_modulo",  # top level HDL
            module="tb_modulo",  # name of cocotb test module
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
