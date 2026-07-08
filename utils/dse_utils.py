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


import argparse
import json
import logging
import math
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tempfile
from string import Template

import psutil
import yaml
from pygit2 import Repository
from tqdm import tqdm


def map_part_family(partname: str) -> str:
    """
    Translate chip part name to a user-friendly FPGA family

    Args:
        partname (str): FPGA part name

    Returns:
        str: FPGA family name
    """
    if partname.startswith("xc7s"):
        return "spartan"
    elif partname.startswith("xc7a"):
        return "artix"
    elif partname.startswith("xc7k"):
        return "kintex"
    elif partname.startswith("xc7z"):
        return "zynq"
    elif partname.startswith("xcku"):
        return "kintex ultrascale"
    elif partname.startswith("xcvu"):
        return "virtex ultrascale"
    elif partname.startswith("xczu"):
        return "zynq ultrascale"
    return ""


class Runner:
    def __init__(self) -> None:
        logging.basicConfig(
            level=os.getenv("LOGLEVEL", "INFO").upper(),
            format="[%(asctime)s] %(levelname)s: %(message)s (%(filename)s:%(lineno)d)",
            handlers=[logging.StreamHandler(sys.stdout)],
        )

        self.logger = logging.getLogger()

        # ignore SIGTTIN caused by a background process trying to read from the terminal
        signal.signal(signal.SIGTTIN, signal.SIG_IGN)

    def run_simulation(
        self,
        repo_dir: pathlib.Path,
        output_dir: pathlib.Path,
        cmd_template: str,
        id: str,
        params: dict,
    ) -> int:
        """
        Run the simulation (blocking call)

        Args:
            repo_dir (pathlib.Path): the path to the repository containing the codebase
            output_dir (pathlib.Path): the path where put the output of the simulation
            cmd_template (str): the template of the command to execute
            id (str): the unique name for the configuration
            params (dict): the parameters for the simulation

        Returns:
            int: the return code (0 success, failure otherwise)
        """

        # create a temporary directory for the simulation
        with tempfile.TemporaryDirectory(prefix="-".join(["fusesoc", id]) + "_", dir="/var/tmp") as sim_dir:
            cmd = Template(cmd_template).substitute(build_dir=sim_dir)

            with open(os.path.join(sim_dir, "stdout.txt"), "wb") as out_file, open(
                os.path.join(sim_dir, "stderr.txt"), "wb"
            ) as err_file:
                # write the command executed in the head of stdout file
                out_file.write((cmd + "\n").encode("ascii"))
                out_file.flush()

                # Ensure to disable the generation of waveforms to improve performance and
                # minimize the RAM usage
                env = os.environ.copy()
                env.pop("DUMP_FST", None)
                env["XDG_CACHE_HOME"] = os.path.join(sim_dir, ".cache")

                try:
                    # run the command logging both stdout and stderr to files
                    shell_call = subprocess.run(
                        [cmd],
                        shell=True,
                        cwd=repo_dir,
                        env=env,
                        timeout=10800,  # 3 hours
                        stdin=subprocess.DEVNULL,
                        stdout=out_file,
                        stderr=err_file,
                    )
                except Exception:
                    logging.error("Error starting the new process", exc_info=True)

            with open(os.path.join(sim_dir, "conf.json"), "w") as conf_file:
                json.dump(params, conf_file)

            # clean the output directory
            if os.path.exists(output_dir):
                shutil.rmtree(output_dir)
            os.makedirs(output_dir)

            # move the simulation product to the output directory
            try:
                shutil.copytree(sim_dir, output_dir, dirs_exist_ok=True)
            except Exception:
                logging.error("Error copying the result folder", exc_info=True)

            logging.info(f"Simulation of {id} succeeded") if (shell_call.returncode == 0) else logging.debug(
                f"Simulation of {id} failed"
            )

        return shell_call.returncode

    def run_synthesis(
        self,
        repo_dir: pathlib.Path,
        output_dir: pathlib.Path,
        cmd_template: str,
        id: str,
        params: dict,
    ) -> int:
        """
        Run the synthesis (blocking call)

        Args:
            repo_dir (pathlib.Path): the path to the repository containing the codebase
            output_dir (pathlib.Path): the path where put the output of the synthesis
            cmd_template (str): the template of the command to execute
            id (str): the unique name for the configuration
            params (dict): the parameters for the synthesis

        Returns:
            int: the return code (0 success, failure otherwise)
        """

        if "Clock frequency" not in params.keys() and "Clock interval" not in params.keys():
            self.logger.error(f"[{id}] No target frequency received, aborting")
            return -1

        if "Clock frequency" in params.keys():  # no bisection algorithm
            clk_freq = float(params["Clock frequency"])
            self.logger.debug(f"[{id}] Start synthesis at frequency {round(clk_freq)}")

            with tempfile.TemporaryDirectory(prefix="-".join(["fusesoc", id.replace(":", "_")]) + "_", dir="/var/tmp") as synth_dir:
                cmd = Template(cmd_template).substitute(build_dir=synth_dir)

                with open(os.path.join(synth_dir, "stdout.txt"), "wb") as out_file, open(
                    os.path.join(synth_dir, "stderr.txt"), "wb"
                ) as err_file:
                    # write the command executed in the head of stdout file
                    out_file.write((cmd + "\n").encode("ascii"))
                    out_file.flush()

                    # add clock frequency to the environment variables to be read by clock generator utility
                    # there is not a direct way to pass a parameter from CLI to the generator
                    env = os.environ.copy()
                    env["XLX_CLK_FREQ"] = str(round(clk_freq))
                    env["XLX_SYNTH_OOC"] = "true"
                    # env["XLX_SYNTH_STRAT"] = "Flow_AlternateRoutability"
                    # env["XLX_IMPL_STRAT"] = "Performance_NetDelay_high"

                    # override home to private directory to avoid sharing cached data
                    env["HOME"] = synth_dir
                    env["XDG_CACHE_HOME"] = os.path.join(synth_dir, ".cache")

                    try:
                        # run the command logging both stdout and stderr to files
                        shell_call = subprocess.run(
                            [cmd],
                            shell=True,
                            cwd=repo_dir,
                            env=env,
                            timeout=32400,  # 9 hours
                            stdin=subprocess.DEVNULL,
                            stdout=out_file,
                            stderr=err_file,
                        )
                    except Exception:
                        self.logger.error(f"[{id}] Error starting the new process", exc_info=True)

                with open(os.path.join(synth_dir, "conf.json"), "w") as conf_file:
                    json.dump(params, conf_file)

                self.logger.debug(f"[{id}] Synthesis successful") if (shell_call.returncode == 0) else self.logger.debug(
                    f"[{id}] Synthesis failed"
                )

                # clean the output directory
                if os.path.exists(output_dir):
                    shutil.rmtree(output_dir)
                os.makedirs(output_dir)

                # move the synthesis product to the output directory
                try:
                    shutil.copytree(synth_dir, output_dir, dirs_exist_ok=True)
                except Exception:
                    self.logger.error(f"[{id}] Error copying the result folder", exc_info=True)

        else:  # bisection algorithm
            if len(params["Clock interval"]) != 2:
                self.logger.error("Invalid clock interval provided in configuration file")
                return -2
            else:
                min_freq = float(params["Clock interval"][0])
                max_freq = float(params["Clock interval"][1])

            if "Clock resolution" not in params.keys():
                self.logger.error("Invalid clock resolution provided in configuration file")
                return -3
            else:
                clk_resolution = params["Clock resolution"]

            synth_results = []
            # list of {"success": bool, "freq": int} dictionaries
            # last result: synth_results[-1]
            num_iterations = math.ceil(math.log2((max_freq - min_freq) / clk_resolution))

            with tqdm(total=num_iterations, desc=f"{id}", leave=False, dynamic_ncols=True) as pbar:
                for _ in range(num_iterations):
                    clk_freq = (max_freq + min_freq) / 2
                    self.logger.debug(f"[{id}] Start synthesis at frequency {round(clk_freq)}")

                    with tempfile.TemporaryDirectory(prefix="-".join(["fusesoc", id.replace(":", "_")]) + "_", dir="/var/tmp") as synth_dir:
                        cmd = Template(cmd_template).substitute(build_dir=synth_dir)

                        with open(os.path.join(synth_dir, "stdout.txt"), "wb") as out_file, open(
                            os.path.join(synth_dir, "stderr.txt"), "wb"
                        ) as err_file:
                            # write the command executed in the head of stdout file
                            out_file.write((cmd + "\n").encode("ascii"))
                            out_file.flush()

                            # add clock frequency to the environment variables to be read by clock generator utility
                            # there is not a direct way to pass a parameter from CLI to the generator
                            env = os.environ.copy()
                            env["XLX_CLK_FREQ"] = str(round(clk_freq))
                            env["XLX_SYNTH_OOC"] = "true"
                            # env["XLX_SYNTH_STRAT"] = "Flow_AlternateRoutability"
                            # env["XLX_IMPL_STRAT"] = "Performance_NetDelay_high"

                            # override home to private directory to avoid sharing cached data
                            env["HOME"] = synth_dir
                            env["XDG_CACHE_HOME"] = os.path.join(synth_dir, ".cache")

                            try:
                                # run the command logging both stdout and stderr to files
                                shell_call = subprocess.run(
                                    [cmd],
                                    shell=True,
                                    cwd=repo_dir,
                                    env=env,
                                    timeout=32400,  # 9 hours
                                    stdin=subprocess.DEVNULL,
                                    stdout=out_file,
                                    stderr=err_file,
                                )
                            except Exception:
                                self.logger.error(
                                    f"[{id}] Error starting the new process",
                                    exc_info=True,
                                )
                            finally:
                                pbar.update(1)

                        with open(os.path.join(synth_dir, "conf.json"), "w") as conf_file:
                            json.dump(params, conf_file)

                        synth_results += [
                            {
                                "success": (shell_call.returncode == 0),
                                "freq": round(clk_freq),
                            }
                        ]

                        if synth_results[-1]["success"]:  # write the most recent success result
                            self.logger.debug(f"[{id}] Synthesis successful at frequency {synth_results[-1]['freq']}")

                            # clean the output directory
                            if os.path.exists(output_dir):
                                shutil.rmtree(output_dir)
                            os.makedirs(output_dir)

                            # move the synthesis product to the output directory
                            try:
                                shutil.copytree(synth_dir, output_dir, dirs_exist_ok=True)
                            except Exception:
                                self.logger.error(
                                    f"[{id}] Error copying the result folder",
                                    exc_info=True,
                                )

                            # retry with a higher clock frequency
                            min_freq = clk_freq
                            pbar.set_postfix({"max_freq": clk_freq})
                        else:
                            self.logger.debug(f"[{id}] Synthesis failed at frequency {synth_results[-1]['freq']}")
                            # retry with a lower target frequency
                            max_freq = clk_freq

                            # save latest result if no successful runs are available yet
                            if not any(result["success"] for result in synth_results):
                                try:
                                    if os.path.exists(path=output_dir):
                                        shutil.rmtree(path=output_dir)
                                    # Keep the intermediate DBs for further inspection
                                    shutil.copytree(src=synth_dir, dst=output_dir, dirs_exist_ok=False, ignore_dangling_symlinks=True)
                                except Exception:
                                    self.logger.error(
                                        f"[{id}] Error copying the failed result folder",
                                        exc_info=True,
                                    )

                if any(result["success"] for result in synth_results):
                    max_freq = max(result["freq"] for result in synth_results if result["success"])
                    self.logger.info(f"[{id}] Max frequency: {round(max_freq)} MHz")
                else:
                    self.logger.warning(f"[{id}] Last attempt failed at frequency {round(clk_freq)} MHz")

        return shell_call.returncode


class DSERunner(Runner):
    def __init__(self) -> None:
        super().__init__()

        n_cpus = psutil.cpu_count()
        mem_available_gb = (psutil.virtual_memory().available) / 1024 / 1024 / 1024

        self.logger.info(f"{n_cpus} CPUs and {mem_available_gb:.2f} GB RAM available")

        # parse command arguments
        parser = argparse.ArgumentParser(prog="run_design_space_exploration")

        parser.add_argument(
            "--jobs",
            "-j",
            type=int,
            default=n_cpus,
            choices=range(1, n_cpus + 1),
            nargs="?",
            help="Number of parallel jobs (determined automatically if not provided)",
        )

        parser.add_argument(
            "--outputdir",
            "-o",
            type=pathlib.Path,
            required=True,
            help="The path where storing the artifacts",
        )

        parser.add_argument(
            "--repodir",
            "-r",
            type=pathlib.Path,
            required=True,
            help="The path to the repository to clone",
        )

        parser.add_argument(
            "--config",
            "-c",
            type=argparse.FileType("r"),
            required=True,
            help="Configuration file",
        )

        parser.add_argument(
            "--revision",
            "-R",
            type=str,
            default="HEAD",
            help="Repo objects revision (e.g., SHA-1 commit ID or tag)",
        )

        parser.add_argument(
            "--skip_dse",
            "-s",
            action="store_true",
            help="Do not run DSE benchmarks and just parse previous results contained in the specified outputdir",
        )

        self.args = parser.parse_args()

        self.cpus_per_job = math.floor(n_cpus / self.args.jobs)

        # try to access the code repository
        repo = Repository(self.args.repodir)
        if repo is None:
            self.logger.error("Invalid repository path")
            sys.exit(1)
        self.git_branch_name = repo.head.shorthand
        git_commit_hash = str(repo.revparse_single(self.args.revision).id)
        git_commit_time = str(repo.revparse_single(self.args.revision).commit_time)

        # load DSE configurations
        self.config = yaml.safe_load(self.args.config)

        self.logger.info(f"Using branch {self.git_branch_name} and commit {git_commit_hash}")
        if not self.args.skip_dse:
            self.logger.info(f"Creating {self.args.jobs} parallel jobs with {self.cpus_per_job} CPUs each")

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

        if self.args.skip_dse:
            if not os.path.exists(f"{os.path.join(self.versioned_dir,self.config['name'])}/"):
                self.logger.error("Skip DSE flag detected, but the DSE results directory does not exists")
                sys.exit()
        else:
            if os.path.exists(os.path.join(self.versioned_dir, self.config["name"])):
                self.logger.error("Found previous DSE results, archive and manually remove them before running this script")
                sys.exit()
            else:
                os.makedirs(os.path.join(self.versioned_dir, self.config["name"]))

        # save logs to file in output folder
        fileHandler = logging.FileHandler(
            filename=f"{os.path.join(self.versioned_dir,self.config['name'])}/dse.log",
            mode="w",
            encoding="utf-8",
        )
        fileHandler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s (%(filename)s:%(lineno)d)"))
        self.logger.addHandler(fileHandler)

    def run_job(
        self,
        repo_dir: pathlib.Path,
        output_dir: pathlib.Path,
        cmd_template: str,
        metric: str,
        id: str,
        params: dict,
    ):
        if metric == "resources":
            return self.run_synthesis(repo_dir, output_dir, cmd_template, id, params)
        elif metric == "performance":
            return self.run_simulation(repo_dir, output_dir, cmd_template, id, params)
        else:
            self.logger.error(f"[{id}] Unrecognized job type")
