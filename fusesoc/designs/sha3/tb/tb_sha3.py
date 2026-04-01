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

import hashlib
import sys
from math import ceil
from os import environ, getenv
from pathlib import Path

import cocotb
from bitarray import bitarray
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from numpy import random
from scapy.utils import hexdump

sys.path.insert(0, str(Path(".").resolve()))
from ReadStream import ReadStreamConsumer, read_stream_consumer_agent
from WriteStream import WriteStreamProducer, write_stream_producer_agent

random.seed(cocotb.RANDOM_SEED)

sha3_params = {
    "SHA3_224": {
        "hash": 224,
        "capacity": 448,
        "rate": 1152,
        "py_func": hashlib.sha3_224,
    },
    "SHA3_256": {
        "hash": 256,
        "capacity": 512,
        "rate": 1088,
        "py_func": hashlib.sha3_256,
    },
    "SHA3_384": {
        "hash": 384,
        "capacity": 768,
        "rate": 832,
        "py_func": hashlib.sha3_384,
    },
    "SHA3_512": {
        "hash": 512,
        "capacity": 1024,
        "rate": 576,
        "py_func": hashlib.sha3_512,
    },
    "SHAKE_128": {"capacity": 256, "rate": 1344, "py_func": hashlib.shake_128},
    "SHAKE_256": {"capacity": 512, "rate": 1088, "py_func": hashlib.shake_256},
}


async def reset_dut(dut, duration_ns):
    dut.rst_n.value = 0
    await Timer(duration_ns, units="ns")
    await RisingEdge(dut.clk_i)
    dut.rst_n.value = 1
    dut.rst_n._log.info("Reset complete")


async def run_sha3(dut, data: "bitarray", sha3_alg: str, hash_size: int, rand_read_delay: bool = False):
    """
    Start the simulation of SHA3 core

    Args:
        dut: handle to the design
        data (bitarray): input data to digest
        sha3_alg (str): algorithm to use
        hash_size (int): size of the digest
    """
    dut._log.setLevel(getenv("LOGLEVEL", "DEBUG"))
    dut._log.info("Started simulation")

    stream_word_sz = int(environ["TB_STREAM_WIDTH"])

    dut._log.debug(f"Input data:\n{hexdump(data, dump=True)}")
    if sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256":
        res = sha3_params[sha3_alg]["py_func"](data).digest(hash_size // 8)  # digest takes an input in bytes
    else:
        res = sha3_params[sha3_alg]["py_func"](data).digest()
    dut._log.debug(f"Expected hash:\n{hexdump(res, dump=True)}")
    res_blocks = int(ceil(hash_size / stream_word_sz))

    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    await reset_dut(dut, duration_ns=200)

    payload = bitarray(endian="little")
    payload.frombytes(data)
    # reverse bits in block
    for i in range(0, len(payload), stream_word_sz):
        payload[i : i + stream_word_sz] = payload[i : i + stream_word_sz][::-1]

    write_stream = WriteStreamProducer(name="sha3", block_sz=stream_word_sz, init=payload)
    read_stream = ReadStreamConsumer(name="sha3", block_sz=stream_word_sz, debug=False)

    write_task = cocotb.start_soon(write_stream_producer_agent(dut, stream=write_stream, name="sha3"))
    await cocotb.start_soon(
        read_stream_consumer_agent(
            dut, stream=read_stream, name="sha3", n_blocks=res_blocks, req_prob=0.75 if rand_read_delay else 1.0
        )
    )

    dut_res = read_stream.read()[:hash_size]

    await ClockCycles(signal=dut.clk_i, num_cycles=10, rising=True)

    # drop exceeding bytes if hash_size is not divisible by word size (last word not full)
    dut._log.debug(f"Resulting hash:\n{hexdump(dut_res.tobytes(), dump=True)}")
    assert dut_res.tobytes().hex() == res.hex(), "Result does not match the golden sample"

    write_task.kill()


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_zero_sha3(dut):
    """Test of SHA3 module with no data"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    data = b""

    hash_size = (
        int(random.randint(sha3_params[sha3_alg]["rate"] // 8) * 8)
        if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
        else sha3_params[sha3_alg]["hash"]
    )

    await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_static_sha3(dut):
    """Test of SHA3 module with small fixed data"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    data = b"The quick brown fox jumps over the lazy dog"

    hash_size = (
        int(random.randint(sha3_params[sha3_alg]["rate"] // 8) * 8)
        if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
        else sha3_params[sha3_alg]["hash"]
    )

    await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_small_random_sha3(dut):
    """Test of SHA3 module with small random data"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        max_bytes = sha3_params[sha3_alg]["rate"] // 8
        data = random.bytes(random.randint(max_bytes))

        hash_size = (
            int(random.randint(max_bytes) * 8)
            if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
            else sha3_params[sha3_alg]["hash"]
        )

        await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_large_random_sha3(dut):
    """Test of SHA3 module with large random data"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        min_bytes = sha3_params[sha3_alg]["rate"] // 8
        max_bytes = 3 * (sha3_params[sha3_alg]["rate"] // 8)
        data = random.bytes(random.randint(min_bytes, max_bytes))

        hash_size = (
            int(random.randint(min_bytes, max_bytes) * 8)
            if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
            else sha3_params[sha3_alg]["hash"]
        )

        await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_pad_limit_sha3(dut):
    """Test of SHA3 module with data size in pad range"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    for i in range(sha3_params[sha3_alg]["rate"] // 8, sha3_params[sha3_alg]["rate"] // 8 + 17):
        data = random.bytes(i)

        hash_size = int(i * 8) if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256") else sha3_params[sha3_alg]["hash"]

        await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_random_seed1_sha3(dut):
    """Test of SHA3 module with random seed of specific size"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    seed_sz = int(environ["TB_SEED1_SZ"])
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        data = random.bytes(seed_sz // 8)

        hash_size = seed_sz if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256") else sha3_params[sha3_alg]["hash"]

        await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_random_seed2_sha3(dut):
    """Test of SHA3 module with random seed of specific size"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    seed_sz = int(environ["TB_SEED2_SZ"])
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        data = random.bytes(seed_sz // 8)

        hash_size = seed_sz if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256") else sha3_params[sha3_alg]["hash"]

        await run_sha3(dut, data, sha3_alg, hash_size)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_small_random_read_delay_sha3(dut):
    """Test of SHA3 module with small random data and random non-sequential read requests"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        min_bytes = 16
        max_bytes = 38
        data = random.bytes(random.randint(min_bytes, max_bytes))

        hash_size = (
            int(random.randint(min_bytes, max_bytes) * 8)
            if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
            else sha3_params[sha3_alg]["hash"]
        )

        await run_sha3(dut, data, sha3_alg, hash_size, rand_read_delay=True)


@cocotb.test(timeout_time=100000, timeout_unit="ns")
async def tb_large_random_read_delay_sha3(dut):
    """Test of SHA3 module with large random data and random non-sequential read requests"""
    sha3_alg = environ["TB_SHA3_ALG_NAME"]
    dut._log.info(f"Running simulation of {sha3_alg}")

    for _ in range(10):
        min_bytes = sha3_params[sha3_alg]["rate"] // 8
        max_bytes = 3 * (sha3_params[sha3_alg]["rate"] // 8)
        data = random.bytes(random.randint(min_bytes, max_bytes))

        hash_size = (
            int(random.randint(min_bytes, max_bytes) * 8)
            if (sha3_alg == "SHAKE_128" or sha3_alg == "SHAKE_256")
            else sha3_params[sha3_alg]["hash"]
        )

        await run_sha3(dut, data, sha3_alg, hash_size, rand_read_delay=True)
