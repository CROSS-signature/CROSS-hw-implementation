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
import logging
import os
import pathlib
import sys
from typing import Optional

import numpy as np
import pandas as pd
from astropy.io import ascii

resources = {
    "artix": [
        "LUT as Logic",
        "LUT as Memory",
        "Slice LUTs",
        "Register as Flip Flop",
        "Register as Latch",
        "CARRY4",
        "Slice",
        "Block RAM Tile",
        "DSPs",
    ],
    "zynq ultrascale": [
        "LUT as Logic",
        "LUT as Memory",
        "CLB LUTs",
        "Register as Flip Flop",
        "Register as Latch",
        "CARRY8",
        "CLB",
        "Block RAM Tile",
        "URAM",
        "DSPs",
    ],
}

section_names = {
    "artix": ["1. Slice Logic", "2. Slice Logic Distribution", "3. Memory", "4. DSP"],
    "zynq ultrascale": [
        "1. CLB Logic",
        "2. CLB Logic Distribution",
        "3. BLOCKRAM",
        "4. ARITHMETIC",
    ],
}


def resources_to_eslice(lut: pd.Series, ff: pd.Series, bram: pd.Series, dsp: pd.Series) -> pd.Series:
    """
    Args:
        lut (pd.Series): number of used Lookup tables
        ff (pd.Series): number of used flip-flop registers
        bram (pd.Series): number of used block RAMs
        dsp (pd.Series): number of used DSP units

    Returns:
        pd.Series: computed equivalent Slices (eSlice)
    """
    module_resources = {
        "SDPRAM_distributed": {
            "LUT": 848,
            "FF": 548,
            "MUXF7": 64,
            "MUXF8": 32,
        },  # synthesized with (* RAM_STYLE = "distributed" *)
        "SDPRAM_registers": {
            "LUT": 9857,
            "FF": 32832,
            "MUXF7": 4352,
            "MUXF8": 2176,
        },  # synthesized with (* RAM_STYLE = "registers" *)
        "SDPRAM_block": {"BRAM36E1": 1},  # synthesized with (* RAM_STYLE = "block" *)
        "TDPRAM_distributed": {
            "LUT": 86149,
            "FF": 32896,
            "MUXF7": 8704,
            "MUXF8": 4352,
        },  # synthesized with (* RAM_STYLE = "distributed" *)
        "TDPRAM_registers": {
            "LUT": 50789,
            "FF": 32896,
            "MUXF7": 8704,
            "MUXF8": 4352,
        },  # synthesized with (* RAM_STYLE = "registers" *)
        "TDPRAM_block": {"BRAM36E1": 1},  # synthesized with (* RAM_STYLE = "block" *)
        "preadd_mult_add_dsp": {"DSP48E1": 1},  # synthesized with (* use_dsp = "yes" *)
        "preadd_mult_add_logic": {"LUT": 538, "FF": 232},  # synthesized with (* use_dsp = "no" *)
    }
    primitive_map = {"BRAM": module_resources["SDPRAM_distributed"], "DSP": module_resources["preadd_mult_add_logic"]}

    eqv_lut = lut + bram * primitive_map["BRAM"]["LUT"] + dsp * primitive_map["DSP"]["LUT"]
    eqv_ff = ff + bram * primitive_map["BRAM"]["FF"] + dsp * primitive_map["DSP"]["FF"]

    return np.maximum(np.ceil(eqv_lut / 4).astype(int), np.ceil(eqv_ff / 8).astype(int))


def find_table(file_path: pathlib.Path, section: str) -> tuple[int, int]:
    """
    Finds the first ASCII table contained in the required section

    Args:
        file_path (pathlib.Path): the path to the file to parse
        section (str): the string defining the section of interest

    Returns:
        (int,int): tuple containing the start and end indexes compatible with the astropy ascii indexing format
    """

    # https://docs.astropy.org/en/stable/io/ascii/read.html#specifying-header-and-data-location
    section_found = False
    start_idx = 0
    end_idx = 0
    uncounted_lines = 0

    # open ASCII file
    with open(file_path, "r") as file:
        # extract the first table in "Primitives" section
        for num, line in enumerate(file):
            # keep track of the uncounted lines starting with # or blank lines
            if line.startswith("#") or (not line.strip()):
                uncounted_lines = uncounted_lines + 1

            # found the required section
            if section in line:
                section_found = True
                start_idx = 0
                end_idx = 0
                continue

            # update indexes only when section is found
            if section_found:
                # update indexes
                if line.startswith(("|", "+")):
                    # first table line, update start index
                    if start_idx == 0:
                        start_idx = num - uncounted_lines
                    # valid table line
                    end_idx = num - uncounted_lines

                # found a more recent definition of section, restart the process
                if start_idx != 0 and not line.startswith(("|", "+")):
                    section_found = False

    return (start_idx, end_idx)


def instance_resources_usage(synthesis_folder: pathlib.Path, instance: str) -> Optional[list[dict]]:
    """
    Scrapes the resource usage for the specified instance.
    N.B. useful just in case of synthesis without complete or partial flattened hierarchy

    Args:
        synthesis_folder (pathlib.Path): the base path of the synthesis to analyze
        instance (str): the name of the instance to analyze

    Returns:
        dict or None: dictionary with the resources like LUTs, FFs, memories and DSPs
    """
    try:
        report_hierarchical_utilization = synthesis_folder.joinpath("report_hierarchical_utilization.txt")

        # scrape data from section 1 "Utilization by Hierarchy"
        (start_idx, end_idx) = find_table(
            file_path=report_hierarchical_utilization,
            section="1. Utilization by Hierarchy",
        )
        hierarchy_list = ascii.read(
            report_hierarchical_utilization,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        ).to_pandas()

        # try to get instance resources
        query = hierarchy_list.loc[(hierarchy_list["Instance"] == instance)]

        # instance not found
        if len(query) == 0:
            return None

        res = []
        # drop the unnecessary columns
        for idx in range(len(query)):
            res.append(query.drop(columns=["Module"]).iloc[idx].to_dict())

        return res

    except FileNotFoundError:
        logging.warning("Error while parsing instance resources: ")
        pass

    return None


def global_resources(synthesis_folder: pathlib.Path, target: str) -> Optional[dict]:
    """
    Scrapes the main resource utilization of the overall design

    Args:
        synthesis_folder (pathlib.Path): the base path of the synthesis to analyze
        target (str): the target platform

    Returns:
        dict or None: the dictionary with keys of resources like LUT, LUTRAM, FF, CARRY8, BRAM, URAM, DSP
    """

    try:
        report_global_utilization = synthesis_folder.joinpath("report_global_utilization.txt")

        # scrape data from section 1 for global resource usage
        (start_idx, end_idx) = find_table(file_path=report_global_utilization, section=section_names[target][0])
        slice_logic_table = ascii.read(
            report_global_utilization,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        )

        # scrape data from section 2 for global resource usage
        (start_idx, end_idx) = find_table(file_path=report_global_utilization, section=section_names[target][1])
        slice_logic_distribution_table = ascii.read(
            report_global_utilization,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        )

        # scrape data from section 3 for memory related resources
        (start_idx, end_idx) = find_table(file_path=report_global_utilization, section=section_names[target][2])
        memory_table = ascii.read(
            report_global_utilization,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        )

        # scrape data from section 4 for DSP related logic
        (start_idx, end_idx) = find_table(file_path=report_global_utilization, section=section_names[target][3])
        dsp_table = ascii.read(
            report_global_utilization,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        )

        tables = pd.concat(
            [
                slice_logic_table.to_pandas(),
                slice_logic_distribution_table.to_pandas(),
                memory_table.to_pandas(),
                dsp_table.to_pandas(),
            ]
        )
        tables.drop_duplicates(subset="Site Type", keep="first", inplace=True)
        tables.set_index("Site Type", inplace=True)

        res = {}

        for key in resources[target]:
            try:
                value = tables.loc[key]["Used"]
            except KeyError:
                value = 0
            assert type(value) in [
                np.float64,
                np.int64,
                int,
            ], f"\n{tables.loc[key]['Used']}\nType not valid: {type(value)} in {synthesis_folder} with table\n{tables}"
            res[key] = value

        return res

    except FileNotFoundError:
        logging.warning("Missing global resources utilization")
        pass

    return None


def critical_path_analysis(synthesis_folder: pathlib.Path) -> Optional[dict]:
    """
    Scrapes the timing analysis of the overall design

    Args:
        synthesis_folder (pathlib.Path): the base path of the synthesis to analyze

    Returns:
        dict or None: the dict with keys of timing characteristics like Slack,
        number of high fanout nets, and percentage of network delay over logic delay
    """

    try:
        report_design_analysis = synthesis_folder.joinpath("report_design_analysis.txt")

        # scrape data from section 1 "Setup Path Characteristics"
        (start_idx, end_idx) = find_table(
            file_path=report_design_analysis,
            section="1. Setup Path Characteristics 1-1",
        )
        res_table = ascii.read(
            report_design_analysis,
            format="fixed_width_two_line",
            delimiter="+",
            header_start=start_idx + 1,
            position_line=start_idx + 2,
            data_start=start_idx + 3,
            data_end=end_idx,
        )
        res_table.add_index("Characteristics")

        return {
            "Clock period": res_table.loc["Requirement"]["Path #1"],
            "Clock frequency": round(1000 / float(res_table.loc["Requirement"]["Path #1"])),
            "Slack": res_table.loc["Slack"]["Path #1"],
            "High Fanout": res_table.loc["High Fanout"]["Path #1"],
            "Net Delay": res_table.loc["Net Delay"]["Path #1"],
            "Syntesis/Implementation status": f"{'Passed' if float(res_table.loc['Slack']['Path #1']) >= 0 else 'Failed'}",
        }
    except FileNotFoundError:
        logging.warning("Missing critical path analysis report")
        pass

    return None


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
        "--target",
        "-t",
        default="artix",
        type=str,
        choices=[
            "spartan",
            "artix",
            "kintex",
            "zynq",
            "kintex ultrascale",
            "virtex ultrascale",
            "zynq ultrascale",
        ],
        help="Target platform",
    )

    parser.add_argument(
        "--instances",
        "-i",
        nargs="*",
        default=[],
        type=str,
        help="The list of instances to investigate",
    )

    args = parser.parse_args()

    parse_resource_results(args.inputdir, args.target, args.instances)


def parse_resource_results(inputdir: pathlib.Path, target: str, instances: Optional[list[str]] = None) -> pd.DataFrame:
    # test source directory containing the synthesis results
    benchmark_dir = os.path.abspath(inputdir)
    if not os.path.isdir(benchmark_dir):
        logging.error("Invalid argument found")
        sys.exit(1)

    # walk across results tree
    global_results = []
    per_instance_results = []

    for synthesis_folder in pathlib.Path(benchmark_dir).rglob("synth-vivado"):
        p = pathlib.PurePosixPath(synthesis_folder).parent

        path = p.relative_to(pathlib.Path.cwd())
        index = {"ID": str(path)}
        params_str = path.parent.name
        params = {}
        for param in params_str.split("-"):
            if "=" in param:
                k, v = param.split("=")
                params[k] = v
            else:
                params[param] = "true"
        impl_folder = list(pathlib.Path(synthesis_folder).rglob("impl_1"))[0]

        # PER-MODULE RESOURCE UTILIZATION
        if instances is not None:
            for instance in instances:
                instance_resource = instance_resources_usage(synthesis_folder=impl_folder, instance=instance)
                if instance_resource is not None:
                    for instance in instance_resource:
                        table_row = {**index, **params, **instance}
                        per_instance_results.append(table_row)

        # GLOBAL RESOURCES
        resources = global_resources(synthesis_folder=impl_folder, target=target)

        # TIMING ANALYSIS
        timings = critical_path_analysis(synthesis_folder=impl_folder)

        if all(v is not None for v in [index, resources, timings]):
            table_row = {**index, **params, **resources, **timings}
            global_results.append(table_row)

    # compose pandas dataframes and store them
    pd.set_option("display.max_colwidth", None)

    df_global = pd.DataFrame(global_results)
    # Compute extra attributes
    df_global["eSlice"] = resources_to_eslice(
        lut=df_global["Slice LUTs"],
        ff=df_global["Register as Flip Flop"],
        bram=df_global["Block RAM Tile"],
        dsp=df_global["DSPs"],
    )
    if __name__ == "__main__":
        df_global.to_html(f"{benchmark_dir}/global_resources.html")
        df_global.to_csv(f"{benchmark_dir}/global_resources.csv")

    df_per_instance = None
    if instances is not None:
        df_per_instance = pd.DataFrame(per_instance_results)
        # Compute extra attributes
        df_per_instance["eSlice"] = resources_to_eslice(
            lut=df_per_instance["Total LUTs"],
            ff=df_per_instance["FFs"],
            bram=df_per_instance["RAMB36"] + 0.5 * df_per_instance["RAMB18"],
            dsp=df_per_instance["DSP Blocks"],
        )
        if __name__ == "__main__":
            df_per_instance.to_html(f"{benchmark_dir}/per_instance_resources.html")
            df_per_instance.to_csv(f"{benchmark_dir}/per_instance_resources.csv")

    return df_global, df_per_instance


if __name__ == "__main__":
    main()
