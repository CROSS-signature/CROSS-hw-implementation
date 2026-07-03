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

import logging
import os
import subprocess
import tempfile
from concurrent import futures
from itertools import product
from string import Template

import pandas as pd
from dse_utils import DSERunner, map_part_family
from parse_performance_figures import parse_performance_results
from parse_resource_figures import parse_resource_results
from pygit2 import clone_repository
from tqdm import tqdm
from tqdm.contrib.logging import logging_redirect_tqdm


class CROSSRunner(DSERunner):
    def run_analysis(self) -> None:
        # clone the repository in a temporary folder to avoid unintended manipulation of the codebase from the referred commit
        with tempfile.TemporaryDirectory(prefix="analysis_", dir="/var/tmp") as tmpdir:
            clone_repository(path=tmpdir, url=self.args.repodir, checkout_branch=self.git_branch_name)

            if not self.args.skip_dse:
                if "init_commands" in self.config:
                    try:
                        for command in self.config["init_commands"]:
                            subprocess.run(
                                command,
                                shell=True,
                                check=True,
                                cwd=tmpdir,
                                timeout=1800,  # 30 min
                            )
                    except Exception:
                        logging.error("Error while running the init command", exc_info=True)
                        return

                with futures.ThreadPoolExecutor(max_workers=self.args.jobs) as executor:
                    # run simulation
                    if "performance" in self.config:
                        processes = []
                        # parameters are generated directly in pytest
                        # the combinations selected in config file should be validated in the tests
                        for module in self.config["modules"].items():
                            id = module[0]
                            # compose the output directory for each job product
                            output_dir = os.path.join(
                                self.versioned_dir,
                                self.config["name"],
                                "performance",
                                id,
                            )

                            # compose the fusesoc command
                            cmd = Template(self.config["performance"]["cmd_template"]).safe_substitute(
                                module=module[0], jobs=self.cpus_per_job
                            )

                            # run the job
                            processes.append(
                                executor.submit(
                                    self.run_job,
                                    repo_dir=tmpdir,
                                    output_dir=output_dir,
                                    cmd_template=cmd,
                                    metric="performance",
                                    id=id,
                                    params={},
                                )
                            )

                        self.logger.info(f"Queuing {len(processes)} jobs")
                        with tqdm(total=len(processes), desc="Completed simulations", dynamic_ncols=True) as pbar:
                            for process in futures.as_completed(processes):
                                try:
                                    process.result()
                                except Exception:
                                    self.logger.error("Error while executing the job", exc_info=True)
                                finally:
                                    pbar.update(1)

                    # run synthesis
                    if "resources" in self.config:
                        processes = []
                        for part in self.config["resources"]["parts"].items():
                            for module in self.config["modules"].items():
                                module_name = module[0]
                                module_configs = module[1]
                                if "parameter_set" in self.config:
                                    param_keys = list(self.config["parameter_set"].keys())
                                    param_values = list(self.config["parameter_set"].values())
                                    params = list(product(*param_values))
                                else:
                                    param_keys = []
                                    params = [tuple("")]
                                for parameter_set in params:
                                    extra_args = []
                                    args_str = []
                                    id_param = ""
                                    id_param += "-".join([f"{param_keys[i]}={parameter_set[i]}" for i in range(len(param_keys))])
                                    if module_configs is not None:
                                        for m_config in module_configs:
                                            m_params = []
                                            param_str = []
                                            for m_parameter in m_config.items():
                                                m_params += [f" --{m_parameter[0]} {m_parameter[1]}"]
                                                param_str += [f"{m_parameter[0]}={m_parameter[1]}"]
                                            extra_args += [" ".join(m_params)]
                                            args_str += ["-".join(param_str)]
                                    else:
                                        extra_args += [""]
                                        args_str += [""]

                                    for idx, args in enumerate(extra_args):
                                        id = "-".join(
                                            [
                                                f"MODULE={module_name}",
                                                args_str[idx],
                                                id_param,
                                            ]
                                        )

                                        # compose the output directory for each job product
                                        output_dir = os.path.join(
                                            self.versioned_dir,
                                            self.config["name"],
                                            "resources",
                                            part[0],
                                            module_name,
                                            id,
                                        )

                                        # compose the fusesoc command
                                        if len(param_keys) == 0:
                                            cmd = Template(self.config["resources"]["cmd_template"]).safe_substitute(
                                                module=module_name,
                                                extra_args=args,
                                                jobs=self.cpus_per_job,
                                                part=part[0],
                                            )
                                        else:
                                            cmd = Template(self.config["resources"]["cmd_template"]).safe_substitute(
                                                parameter_set=" ".join([f"--{p}" for p in parameter_set]),
                                                module=module_name,
                                                extra_args=args,
                                                jobs=self.cpus_per_job,
                                                part=part[0],
                                            )

                                        # run the job
                                        processes.append(
                                            executor.submit(
                                                self.run_job,
                                                repo_dir=tmpdir,
                                                output_dir=output_dir,
                                                cmd_template=cmd,
                                                metric="resources",
                                                id=id,
                                                params={
                                                    "Clock interval": part[1]["clock"]["interval"],
                                                    "Clock resolution": part[1]["clock"]["resolution"],
                                                },
                                            )
                                        )

                        self.logger.info(f"Queuing {len(processes)} jobs")
                        with tqdm(total=len(processes), desc="Completed synthesis", dynamic_ncols=True) as pbar:
                            for process in futures.as_completed(processes):
                                try:
                                    process.result()
                                except Exception:
                                    self.logger.error("Error while executing the job", exc_info=True)
                                finally:
                                    pbar.update(1)

            # parsing of results
            if "performance" in self.config:
                df_performance = parse_performance_results(self.versioned_dir)
                # View the result
                df_performance.sort_values(by=["ID"]).to_html(f"{self.versioned_dir}/performance.html", index=False)
                df_performance.sort_values(by=["ID"]).to_csv(f"{self.versioned_dir}/performance.csv", index=False)
            if "resources" in self.config:
                for part in self.config["resources"]["parts"].items():
                    df_resources, _ = parse_resource_results(self.versioned_dir, map_part_family(part[0]))

                    # View the result
                    df_resources.sort_values(by=["ID"]).to_html(f"{self.versioned_dir}/resources_{part[0]}.html", index=False)
                    df_resources.sort_values(by=["ID"]).to_csv(f"{self.versioned_dir}/resources_{part[0]}.csv", index=False)

                    if "performance" in self.config:
                        common_columns = df_performance.columns.intersection(df_resources.columns).tolist()
                        common_columns.remove("ID")
                        self.logger.info(f"Merging on columns {common_columns}")
                        merged_df = pd.merge(df_performance, df_resources, how="inner", on=common_columns)

                        # Compute combined metrics
                        merged_df["Latency (us)"] = merged_df["Clock cycles"] / merged_df["Clock frequency"]
                        merged_df["Efficiency (Latency * eSlice)"] = merged_df["Latency (us)"] * merged_df["eSlice"]

                        # View the result
                        merged_df.to_html(f"{self.versioned_dir}/merged.html", index=False)
                        merged_df.to_csv(f"{self.versioned_dir}/merged.csv", index=False)


if __name__ == "__main__":
    job = CROSSRunner()
    with logging_redirect_tqdm():
        job.run_analysis()
