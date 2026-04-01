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

from fusesoc.capi2.generator import Generator


class LibCrossGenerator(Generator):
    def run(self):
        makefile_path = self.config.get("Makefile")
        if not makefile_path:
            raise Exception("Makefile parameter missing from generator configuration")

        script_dir = os.path.dirname(os.path.abspath(__file__))
        src_dir = os.path.join(script_dir, "ctypes")

        if not os.path.exists(os.path.join(src_dir, "Makefile")):
            raise Exception(f"Could not find source directory with Makefile at {src_dir}")

        # Staging directory for the build
        staging_dir = os.getcwd()
        build_tmp = os.path.join(staging_dir, "build_tmp")
        if os.path.exists(build_tmp):
            shutil.rmtree(build_tmp)

        # Copy sources to staging area to perform the build
        shutil.copytree(src_dir, build_tmp)

        os.chdir(build_tmp)

        versions = ["RSDP", "RSDPG"]
        categories = ["CATEGORY_1", "CATEGORY_3", "CATEGORY_5"]
        corners = ["SPEED", "BALANCED", "SIG_SIZE"]

        output_files = []

        for ver in versions:
            for cat in categories:
                for cor in corners:
                    lib_name = f"libcross_{ver}_{cat}_{cor}.so"
                    print(f"Generating {lib_name}...")
                    subprocess.check_call(["make", "clean"])
                    subprocess.check_call(["make", f"version={ver}", f"category={cat}", f"corner={cor}"])
                    # Move result up to the staging root
                    shutil.move("libcross.so", os.path.join(staging_dir, lib_name))
                    output_files.append(lib_name)

        os.chdir(staging_dir)

        print(f"Registering {len(output_files)} files to FuseSoC")
        files_dict = []
        for f in output_files:
            files_dict.append({f: {"copyto": "ctypes/" + f, "file_type": "user"}})

        self.add_files(files_dict, fileset="rtl", targets=["default"])


if __name__ == "__main__":
    g = LibCrossGenerator()
    g.run()
    g.write()
