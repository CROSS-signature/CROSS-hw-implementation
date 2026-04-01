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

import os
import shutil
import subprocess
import time
from pathlib import Path

from dut_nexys import DUT_CROSS
from params import cross_parametrizations

bs_dir = 'bitstreams'
cc_dir = 'cc_results'
Path(bs_dir).mkdir(exist_ok=True)
Path(cc_dir).mkdir(exist_ok=True)


# Check if OpenOCD config file exists
if not os.path.isfile('digilent_nexys_video.cfg'):
    print('Please provide an openocd config file for the nexys video as digilent_nexys_video.cfg and re-run the script.')
    print('Config file downloadable e.g. here: https://github.com/openocd-org/openocd/blob/master/tcl/board/digilent_nexys_video.cfg')
    exit()

# Generate shared libs if not available
if not os.path.isdir('./libs'):
    Path('./libs').mkdir()
    cwd = os.getcwd()
    os.chdir("../fusesoc/designs/misc/ctypes/")
    subprocess.check_call(["bash", "gen_libs.sh"])
    for file in Path(os.getcwd()).glob('*.so'):
        shutil.move(file, f'{cwd}/libs/')
    subprocess.check_call(["make", "clean"])
    os.chdir(cwd)

# Iterate over all parameters
for param in cross_parametrizations:
    print(f'Running {param.name.upper()} CATEGORY_{param.category} {param.optim_corner.upper()}')
    bitstream = f'{param.name.lower()}_cat{param.category}_{param.optim_corner}.bit'

    # Wait until the bitstream is built
    bs_file = Path(f'{bs_dir}/{bitstream}')
    while not bs_file.is_file():
        print(f'Waiting for {bitstream} in dir {bs_dir}')
        time.sleep(10)

    # Flash the bitstream
    subprocess.run([f"openocd -f digilent_nexys_video.cfg \
            -c \"init\" \
            -c \"pld load 0 {bs_file}\" \
            -c \"exit\""], \
            shell=True)

    # Call the evaluation script
    dut = DUT_CROSS(    Port = "/dev/ttyUSB0", # Set this depending on your connection
                        BaudRate = 2000000, # Needs to be also set in vhdl code
                        Timeout = 30,
                        parameterization = param,
                        bench_iter = 100
                    )

    cc_file = Path(f'{cc_dir}/{dut.name}.csv')
    if cc_file.is_file():
        print(f'Already found results: {cc_file} - skipping!\n\n')
        time.sleep(1)
        continue

    dut.benchmark()
    shutil.move(f'{dut.name}.csv', f'{cc_dir}/{dut.name}.csv')
