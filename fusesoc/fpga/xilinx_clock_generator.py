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
# @author: Francesco Antognazza <francesco.antognazza@polimi.it>


import fcntl
import os
import pathlib

from fusesoc.capi2.generator import Generator


class XilinxClockGenerator(Generator):
    def run(self):
        frequency = os.getenv("XLX_CLK_FREQ") if os.getenv("XLX_CLK_FREQ") is not None else self.config.get("frequency", "")
        clk_port = self.config.get("clk_port", "")
        clock_buffer = self.config.get("clock_buffer", "")

        print("Working in ", os.getcwd())

        period = (1000) / float(frequency)

        xdc_content = (
            f"create_clock -add -name sys_clk -period {period:.3f}"
            + f" -waveform {{{0:.3f} {(float(period)/2):.3f}}} [get_ports {{ {clk_port} }}];"
        )
        if clock_buffer != "":
            xdc_content += f"set_property HD.CLK_SRC {clock_buffer} [get_ports {{ {clk_port} }}];"

        file_name = "xilinx_clock_source.xdc"

        with open(file_name, "w") as xdc_file:
            xdc_file.write(xdc_content)
            xdc_file.write("\n")

        self.add_files(files=[file_name], targets=["default"], fileset="xdc_clock", file_type="xdc")

    def _is_exe(self, fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)


# creating a file lock shared among other runs to serialize the cache generation process
lock_file = pathlib.Path("/tmp/xilinx_clock_generator.lock")
lock_file.touch(exist_ok=True)
# works reliably only with "r+" access mode
# setting line buffering instead of manually flushing
with open(file=lock_file, mode="r+", buffering=1) as fp:
    # acquiring exclusive access to lock
    fcntl.lockf(fp, fcntl.LOCK_EX)

    # writing PID
    fp.truncate(0)
    fp.write(f"{os.getpid()}\n")

    g = XilinxClockGenerator()
    g.run()
    g.write()

    # clear PID
    fp.truncate(0)
