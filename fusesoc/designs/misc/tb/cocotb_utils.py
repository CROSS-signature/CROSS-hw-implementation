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
from pathlib import Path
from typing import Union

import cocotb
import numpy as np
import yaml
from bitarray import bitarray
from bitarray.util import ba2int, zeros
from cocotb.triggers import ClockCycles
from cocotb.types import LogicArray
from numpy import random

logging.basicConfig(level=logging.NOTSET)
logger = logging.getLogger()
logger.setLevel(os.getenv("LOGLEVEL", "INFO"))


def get_sim_files(dir: str) -> dict[str, list[str]]:
    res: dict = {"rtl_files": [], "vlt_files": [], "include_dirs": []}

    eda_yaml_file = [file for file in os.listdir(dir) if file.endswith(".eda.yml")]
    with open(eda_yaml_file[0]) as eda_yaml_f:
        eda_yaml = yaml.safe_load(eda_yaml_f)

        for f in eda_yaml["files"]:
            if f["file_type"] in ["systemVerilogSource", "verilogSource"]:
                if "is_include_file" in f:
                    if f["is_include_file"]:
                        path = Path(f["name"])
                        res["include_dirs"].append(path.parent)
                else:
                    res["rtl_files"].append(f["name"])
            if f["file_type"] in ["vlt"]:
                res["vlt_files"].append(os.path.abspath(dir + "/" + f["name"]))

    return res


def pre_simulation(sim_folder: str) -> tuple[dict[str, list[str]], list[str], list[str], list[str]]:
    sim_files = get_sim_files(sim_folder)

    extra_args = [""]
    plus_args = [""]
    make_args = [""]
    sim = os.getenv("SIM", None)
    if sim is None:
        # set a default simulator
        os.environ["SIM"] = "verilator"
        sim = "verilator"
    match sim:
        case "verilator":
            extra_args = (
                sim_files["vlt_files"]
                + ["-Wno-ENUMVALUE"]
                + ["--assert"]
                + ["--timing"]
                + (["--trace-fst", "--trace-structs", "--trace-params"] if (os.environ.get("DUMP_FST") is not None) else [""])
            )
            plus_args = ["--trace"] if (os.environ.get("DUMP_FST") is not None) else [""]
            make_args = ["-j", os.getenv("TB_MAKE_PARALLELISM", str(os.cpu_count()))]
        case "xcelium":
            if os.environ.get("DUMP_FST") is not None:
                for root, _, files in os.walk(sim_folder):
                    for file in files:
                        if file.endswith("xcelium_utils.tcl"):
                            extra_args = [
                                "-mcdump",
                                "-input",
                                os.path.join(root, file),
                            ]
        case _:
            raise RuntimeWarning(f"Unsupported simulator back-end: {sim}")
    return sim_files, extra_args, plus_args, make_args


def post_simulation(sim_build: str):
    sim = os.getenv("SIM", "verilator")
    match sim:
        case "verilator":
            pass
        case "xcelium":
            for root, _, files in os.walk(sim_build):
                for file in files:
                    if file.endswith(".vcd.gz"):
                        vcd_gz_file = os.path.join(root, file)
                        fst_file = vcd_gz_file.replace(".vcd.gz", ".fst")

                        try:
                            extract_gzip_command = subprocess.Popen(["gzip", "-dc", vcd_gz_file], stdout=subprocess.PIPE)
                            vcd2fst_command = subprocess.Popen(
                                ["vcd2fst", "-", fst_file], stdin=extract_gzip_command.stdout, stdout=subprocess.PIPE
                            )
                            vcd2fst_command.communicate()
                            os.remove(vcd_gz_file)
                        except subprocess.CalledProcessError as e:
                            print(f"Error executing command: {e}")
        case _:
            raise RuntimeWarning(f"Unsupported simulator back-end: {sim}")


async def cycle_reset(dut):
    dut.rst_n.value = 0
    await ClockCycles(dut.clk_i, 5)
    dut.rst_n.value = 1


def get_ba(signal, idx: int = None):
    try:
        value = signal.value if idx is None else signal[idx].value
        if value.is_resolvable:  # does not contain X or Z
            ba_val = bitarray(value.binstr[::-1], endian="little")
        else:
            ba_val = zeros(value.n_bits, endian="little")
    except ValueError:
        logger.error(f"get_ba({signal._path}, {idx}): ValueError ({value})")
        ba_val = bitarray()
    return ba_val


def set_ba(
    signal: Union[cocotb.handle.NonHierarchyIndexableObject, cocotb.handle.ModifiableObject],
    data: "bitarray",
    immediate: bool = False,
    idx: int = None,
):
    sig = signal if idx is None else signal[idx]
    if immediate:
        # setimmediatevalue only accepts integers
        try:
            sig.setimmediatevalue(ba2int(data, signed=False))
        except ValueError:
            sig.setimmediatevalue(0)
    else:
        try:
            sig.value = LogicArray(data.to01()[::-1])
        except ValueError:
            sig.value = 0


def get_int(signal: cocotb.handle.ModifiableObject, idx: int = None) -> int:
    """
    Reads a signal value to an integer, turning X and Z values to 0

    Args:
        signal (cocotb.handle.ModifiableObject): the signal from DUT

    Returns:
        int: the integer value corresponding to the signal
    """
    try:
        int_val = signal.value if idx is None else signal[idx].value
    except ValueError:
        int_val = 0
    return int_val


def set_int(
    signal: Union[cocotb.handle.NonHierarchyIndexableObject, cocotb.handle.ModifiableObject],
    data: Union[int, cocotb.binary.BinaryValue, cocotb.types.LogicArray, cocotb.types.Logic],
    immediate: bool = False,
    idx: int = None,
):
    sig = signal if idx is None else signal[idx]
    if immediate:
        sig.setimmediatevalue(data)
    else:
        sig.value = data


def urandom(len: int, /, endian=None) -> "bitarray":
    """
    We need to "re-implement" the urandom utility
    using numpy random instead of os.urandom()
    in order to have a reproducible generation
    of a random vector during debug
    """
    return bitarray(random.randint(2, size=len).tolist(), endian=endian)


def sampler_generator(modval: int, pack_quantity: int = 1):
    """
    Generator for pause signal called each clock cycle.
    Mimicking the behavior of a rejection sampler
    """
    pow2 = int(2 ** np.ceil(np.log2(modval)))
    count = 0
    while True:
        if random.randint(0, pow2) >= modval:
            yield True  # Pause signal
        else:
            count += 1
            if count == pack_quantity:
                count = 0
                yield False  # Data block ready
            else:
                yield True  # Pause signal


def memory_generator():
    """
    Generator for pause signal called each clock cycle.
    Mimicking the behavior of data coming from memory
    """
    while True:
        yield False  # Data block ready


def random_generator(yield_prob: float = 0.5):
    """
    Generator for pause signal called each clock cycle.
    Random behavior
    """
    while True:
        yield random.random() < yield_prob


def pytest_id(param):
    match param:
        case dict():
            # Create a string ID based on the dictionary keys and values
            # Exclude CLIB because of "OSError: [Errno 63] File name too long"
            return "-".join([f"{key}={value}" for key, value in param.items() if key != "CLIB"])
        case _:
            return str(param)
