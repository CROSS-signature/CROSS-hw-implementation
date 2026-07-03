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
import logging
import os
import pathlib
import re
import sys
from copy import deepcopy
from xml.etree import ElementTree

import pandas as pd


def parse_performance_results(inputdir: pathlib.Path, clock_freq_mhz: int = 100) -> pd.DataFrame:
    # test source directory containing the synthesis results
    benchmark_dir = os.path.abspath(inputdir)
    if not os.path.isdir(benchmark_dir):
        logging.error("Invalid argument found")
        sys.exit(1)

    param_pattern = re.compile(r".*\[(.*?)\]$")

    perf_results = []
    for sim_result in pathlib.Path(inputdir).rglob("test-cocotb.xml"):
        logging.info(f"Found test result {sim_result}")
        # Parse the XML file
        tree = ElementTree.parse(sim_result)
        root = tree.getroot()

        # Loop through each testcase in the testsuite
        for testsuite in root:
            string = testsuite.attrib.get("package", "")
            match = re.search(param_pattern, string)
            if match:
                parameters = match.group(1).split("-")
                logging.debug(f"Found test with parameters {parameters}")
            else:
                logging.error("Could not find valid test parameters")
                parameters = []
            for testcase in testsuite.iter("testcase"):
                df_row = {}
                df_row["test"] = testcase.attrib.get("name", "")
                sim_time_ns = testcase.attrib.get("sim_time_ns", "N/A")  # Get the simulation time in ns
                classname = testcase.attrib.get("classname", "Unknown Class")  # Get the test class/module name

                # Check if there was a failure
                failure = testcase.find("failure")
                test_status = "Passed" if failure is None else "Failed"

                # Print out the results
                df_row["ID"] = f"{classname.removeprefix('cocotb.tb_')}-{'-'.join(parameters)}"
                df_row["MODULE"] = classname.removeprefix("cocotb.tb_")
                for parameter in parameters:
                    key, val = parameter.split("=")
                    df_row[key] = val
                df_row["Clock cycles"] = int(float(sim_time_ns) / 1000 * clock_freq_mhz)
                df_row["Simulation status"] = test_status

                # Check for defines column, and split it to generate the used parameter settings
                if "defines" in df_row:
                    df_row["VARIANT"], df_row["CATEGORY"], df_row["OPTIMIZATION"] = (
                        df_row["defines"].removeprefix("+define+").split("+")
                    )
                perf_results.append(deepcopy(df_row))

    if len(perf_results) == 0:
        logging.error("Could not parse test results")

    df_performance = pd.DataFrame(perf_results)
    if __name__ == "__main__":
        df_performance.to_html(f"{benchmark_dir}/performance.html")
        df_performance.to_csv(f"{benchmark_dir}/performance.csv")

    return df_performance


def main():
    logging.basicConfig(
        level=logging.DEBUG,
        format="[%(asctime)s] %(levelname)s: %(message)s (%(filename)s:%(lineno)d)",
        handlers=[logging.StreamHandler(sys.stdout)],
    )

    # parse command line arguments
    parser = argparse.ArgumentParser(prog="parse_resource_usage")

    parser.add_argument(
        "--inputdir",
        "-I",
        type=pathlib.Path,
        required=True,
        help="The path to the directory",
    )

    parser.add_argument(
        "--clock-freq-mhz",
        "-f",
        type=int,
        required=False,
        default=100,
        help="The clock frequency, in MHz,  used during the simulation",
    )

    args = parser.parse_args()

    parse_performance_results(args.inputdir, args.clock_freq_mhz)


if __name__ == "__main__":
    main()
