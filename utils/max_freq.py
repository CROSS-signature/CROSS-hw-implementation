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

#
# example:
#   python3 utils/max_freq.py
#     --design cross:arithmetic:add_sub_vector
#     --part xc7a200tsbg484-1
#     --clock-interval 100 300
#     --clock-resolution 15
#     --keyworded-args '{"RSDPG": "true", "CATEGORY_1": "true"}'

import argparse
import json
import logging
import os
import pathlib
import sys
import tempfile
from string import Template

from dse_utils import Runner
from pygit2 import Repository, clone_repository


class MaxFreqRunner(Runner):
    def __init__(self, args: list[str] = None) -> None:
        super().__init__()

        # parse command arguments
        parser = argparse.ArgumentParser(prog="max_freq")

        parser.add_argument(
            "--design",
            "-d",
            type=str,
            required=True,
            help="fusesoc design to synthesize",
        )

        parser.add_argument(
            "--part",
            "-p",
            type=str,
            default="xc7a100tcsg324-1",
            help="Chip part of the synthesis tool",
        )

        parser.add_argument(
            "--clock-interval",
            "-i",
            nargs=2,
            required=True,
            type=int,
            choices=range(1, 2000),
            help="Clock frequency interval",
        )

        parser.add_argument(
            "--clock-resolution",
            "-R",
            type=int,
            default=1,
            choices=range(1, 100),
            help="Clock frequency resolution",
        )

        parser.add_argument(
            "--keyworded-args",
            "-k",
            type=str,
            default="{}",
            help="Keyworded args to pass to fusesoc command",
        )

        parser.add_argument(
            "--outputdir",
            "-o",
            type=pathlib.Path,
            default=pathlib.Path("/tmp/max_freq"),
            help="The path where storing the artifacts",
        )

        parser.add_argument(
            "--repodir",
            "-r",
            type=pathlib.Path,
            default=os.getcwd(),
            help="The path to the repository to clone",
        )

        parser.add_argument(
            "--target",
            "-t",
            type=str,
            default="synth",
            help="Target of the fusesoc command"
        )

        if args is None:
            self.args = parser.parse_args()
        else:
            self.args = parser.parse_args(args)

        # try to access the code repository
        repo = Repository(self.args.repodir)
        if repo is None:
            self.logger.error("Invalid repository path")
            sys.exit(1)
        self.git_branch_name = repo.head.shorthand
        git_commit_hash = str(repo.revparse_single("HEAD").id)
        git_commit_time = str(repo.revparse_single("HEAD").commit_time)

        self.logger.info(f"Using branch {self.git_branch_name} and commit {git_commit_hash}")

        # prepare output folder
        out_dir_path = os.path.abspath(self.args.outputdir)
        if not os.path.exists(out_dir_path):
            os.makedirs(out_dir_path)

        gitignore_path = os.path.join(out_dir_path, ".gitignore")
        if not os.path.exists(gitignore_path):
            with open(gitignore_path, "w") as f:
                f.write("*\n.gitignore\n")

        self.versioned_dir = os.path.join(
            out_dir_path,
            "_".join([str(git_commit_time), git_commit_hash]),
        )

        if not os.path.exists(self.versioned_dir):
            os.makedirs(self.versioned_dir)

        # save logs to file in output folder
        fileHandler = logging.FileHandler(
            filename=f"{self.versioned_dir}/dse.log",
            mode="w",
            encoding="utf-8",
        )
        fileHandler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s (%(filename)s:%(lineno)d)"))
        self.logger.addHandler(fileHandler)

    def run_analysis(self) -> None:
        # clone the repository in a temporary folder to avoid unintended manipulation of the codebase from the referred commit
        with tempfile.TemporaryDirectory(prefix="analysis_", dir="/var/tmp") as tmpdir:
            clone_repository(path=tmpdir, url=self.args.repodir, checkout_branch=self.git_branch_name)

            kwargs = json.loads(self.args.keyworded_args)

            self.logger.info(f"kwargs: {kwargs}")
            param_path = []
            for k, v in kwargs.items():
                safe_key = k
                safe_value = str(v)
                for unsafe_char in [":", "'", "/"]:
                    safe_key = safe_key.replace(unsafe_char, "_")
                    safe_value = safe_value.replace(unsafe_char, "_")
                param_path.append(f"{safe_key}_{safe_value}")

            # compose the output directory for each job product
            output_dir = os.path.join(
                self.versioned_dir,
                "/".join([self.args.part] + [self.args.design.replace(":", "_")] + param_path),
            )
            self.logger.info(f"Output directory: {output_dir}")

            extra_args = ""
            for k, v in kwargs.items():
                if isinstance(v, str):
                    extra_args += f' --{k} "{v}"'  # escape the string
                else:
                    extra_args += f" --{k} {v}"

            # compose the fusesoc command
            cmd = Template(
                "fusesoc run --build"
                + " --build-root '${build_dir}'"
                + " --target ${target} ${design}"
                + " ${extra_args}"
                + " --part ${part}"
            ).safe_substitute(design=self.args.design, extra_args=extra_args, part=self.args.part, target=self.args.target)

            # run the job
            self.run_synthesis(
                repo_dir=tmpdir,
                output_dir=output_dir,
                cmd_template=cmd,
                id=self.args.design,
                params={
                    "Clock interval": self.args.clock_interval,
                    "Clock resolution": self.args.clock_resolution,
                },
            )


if __name__ == "__main__":
    job = MaxFreqRunner()
    job.run_analysis()
