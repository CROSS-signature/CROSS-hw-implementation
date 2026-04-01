#!/usr/bin/env python3
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

import shutil
import subprocess
from pathlib import Path

from params import cross_parametrizations

vlnv = 'cross_fpga_test_0.1.0'
build_dir = '/tmp/'
bs_dir = 'bitstreams'
Path(bs_dir).mkdir(exist_ok=True)

# Iterate over all parameters
for param in cross_parametrizations:
    print(f'Running {param.name.upper()} CATEGORY_{param.category} {param.optim_corner.upper()}')
    bitstream = f'{param.name.lower()}_cat{param.category}_{param.optim_corner}.bit'

    # Build the bitstream only if it does not exist yet
    bs_file = Path(f'{bs_dir}/{bitstream}')
    if not bs_file.is_file():
        subprocess.run([f"fusesoc --cores-root ../fusesoc run --build-root {build_dir} --build --target synth cross:fpga:test \
                --{param.name.upper()} --CATEGORY_{param.category} --{param.optim_corner.upper()}"], shell=True)
        shutil.copy(f'{build_dir}/{vlnv}/synth-vivado/{vlnv}.runs/impl_1/test_top.bit', bs_file)
    else:
        print('Found previous bitstream, skipping generation')
