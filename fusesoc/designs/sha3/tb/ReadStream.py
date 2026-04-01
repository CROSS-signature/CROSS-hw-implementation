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

import sys
from copy import deepcopy
from math import ceil, log2
from pathlib import Path

from bitarray import bitarray
from bitarray.util import ba2hex, zeros
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge, Timer
from cocotb.types import Logic, LogicArray, Range
from numpy import random

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import get_ba, get_int, logger, set_ba, set_int, urandom


class ReadStreamProducer:
    def __init__(
        self,
        init: "bitarray",
        reversed_bytes: bool = False,
        name: str = "stream",
        block_sz: int = 32,
        debug: bool = False,
    ):
        self.block_sz = block_sz
        self.bytes = self.block_sz // 8
        self.debug = debug
        self.name = name
        self.endian = "little"  # [0] is least significant bit
        self.r_ctr = 0
        self.addr = 0
        self.ended = False

        logger.info(f"Initializing read stream producer {self.name} of size {len(init)}-bits with blocks of {self.block_sz}-bits")
        if reversed_bytes:
            byte_array = bytearray(init.tobytes())
            byte_array.reverse()
            init.clear()
            init.frombytes(byte_array)
        if self.debug:
            logger.debug(f"[{self.name}] Init content: 0x{ba2hex(init)}")
        self.mem = deepcopy(init)

    def get_performance_counters(self) -> dict:
        res = {"reads": self.r_ctr}

        if self.debug:
            logger.debug(f"[{self.name}] Performance counters: {res}")

        return res

    def read(self) -> "bitarray":
        data = deepcopy(self.mem[self.addr : self.addr + self.block_sz])

        if self.debug:
            logger.debug(f"[{self.name}] Reading block {self.addr//self.block_sz}: 0x{ba2hex(data)}")

        self.r_ctr += 1
        self.addr += self.block_sz

        if self.addr >= len(self.mem):
            logger.info(f"[{self.name}] Served last block")
            self.ended = True

        return data

    def dump(self) -> "bitarray":
        return deepcopy(self.mem)

    def process(self, req: "bitarray") -> dict:
        if req == bitarray("1"):
            data = self.read()
        else:
            data = zeros(self.block_sz, endian="little")

        # DUT INPUT SIGNALS
        is_last = bitarray(str(int(self.ended)), endian="little") & req
        bytes = 0 if not is_last else (len(self.mem) % self.block_sz) // 8

        while len(data) != self.block_sz:
            data.extend("0")

        return {
            "grant": Logic(req.to01()),
            "data": LogicArray(data.to01()[::-1], Range(self.block_sz - 1, 0)),
            "is_last": Logic(is_last.to01()),
            "bytes": LogicArray(bytes, Range(max(ceil(log2(self.bytes)), 1) - 1, 0)),
            "valid": Logic(req.to01()),
        }


class ReadStreamConsumer:
    def __init__(
        self,
        name: str = "stream",
        block_sz: int = 32,
        debug: bool = False,
    ):
        self.block_sz = block_sz
        self.bytes = self.block_sz // 8
        self.debug = debug
        self.name = name
        self.endian = "little"  # [0] is least significant bit
        self.r_ctr = 0
        self.mem = bitarray(endian=self.endian)

        logger.info(f"Initializing read stream consumer {self.name}")

    def get_performance_counters(self) -> dict:
        res = {"reads": self.r_ctr}

        if self.debug:
            logger.debug(f"[{self.name}] Performance counters: {res}")

        return res

    def read(self) -> "bitarray":
        return deepcopy(self.mem)

    def write(self, data: "bitarray"):
        if len(data) != self.block_sz:
            raise Exception(f"Received a {len(data)}-bit block, exceeding the stream size {self.block_sz}-bit")

        if self.debug:
            logger.debug(f"[{self.name}] Appending to stream data 0x{ba2hex(data)}")

        self.mem[self.r_ctr * self.block_sz : self.r_ctr * self.block_sz + len(data)] = deepcopy(data)

        self.r_ctr += 1

    def process(self, grant: "bitarray", data: "bitarray", is_last: "bitarray", bytes: "bitarray", valid: "bitarray") -> dict:
        if valid == bitarray("1"):
            self.write(data=data)

        # DUT INPUT SIGNALS

        return {
            "valid": deepcopy(valid),
        }


async def read_stream_producer_agent(
    dut, stream, name: str, prop_delay_ns: int = 2, init_delay_ns: int = 2, unpacked_idx: int = None
):
    for sig in ["grant", "data", "is_last", "bytes", "valid"]:
        set_int(signal=getattr(dut, f"{name}_r_{sig}_i"), data=0, immediate=True, idx=unpacked_idx)

    # initialization delay
    await Timer(init_delay_ns, units="ns")

    while True:
        await ReadOnly()

        signals = stream.process(
            req=get_ba(getattr(dut, f"{name}_r_request_o"), idx=unpacked_idx),
        )

        # propagation delay
        await Timer(prop_delay_ns, units="ns")

        for sig in ["grant", "data", "is_last", "bytes", "valid"]:
            set_int(signal=getattr(dut, f"{name}_r_{sig}_i"), data=signals[sig], immediate=True, idx=unpacked_idx)

        await RisingEdge(dut.clk_i)


async def read_stream_consumer_agent(
    dut, stream, name: str, req_prob: float = 1.0, n_blocks: int = 0, prop_delay_ns: int = 2, unpacked_idx: int = None
):
    for sig in ["request"]:
        set_int(signal=getattr(dut, f"{name}_r_{sig}_i"), data=0, immediate=True, idx=unpacked_idx)

    idx = 0

    while idx < n_blocks:  # it is an infinite loop if `n_blocks` is zero
        toss = random.randint(0, 16) / 16
        if toss >= req_prob:
            await RisingEdge(dut.clk_i)  # not requesting a block
        else:
            while True:
                await ReadOnly()
                signals = stream.process(
                    grant=get_ba(getattr(dut, f"{name}_r_grant_o"), idx=unpacked_idx),
                    data=get_ba(getattr(dut, f"{name}_r_data_o"), idx=unpacked_idx),
                    is_last=get_ba(getattr(dut, f"{name}_r_is_last_o"), idx=unpacked_idx),
                    bytes=get_ba(getattr(dut, f"{name}_r_bytes_o"), idx=unpacked_idx),
                    valid=get_ba(getattr(dut, f"{name}_r_valid_o"), idx=unpacked_idx),
                )

                if signals["valid"] == bitarray("1"):
                    break

                # propagation delay
                await Timer(prop_delay_ns, units="ns")

                # assert request
                set_int(signal=getattr(dut, f"{name}_r_request_i"), data=1, immediate=True, idx=unpacked_idx)

                await RisingEdge(dut.clk_i)

            idx += 1

            # deassert request
            set_int(signal=getattr(dut, f"{name}_r_request_i"), data=0, immediate=True, idx=unpacked_idx)


async def csprng_agent(
    dut,
    data_width: int,
    name: str,
    prop_delay_ns: int = 2,
    comb_response: bool = True,
    resp_prob: float = 10 / 16,
    init_delay_ns: int = 2,
    debug: bool = False,
    unpacked_idx: int = None,
):
    # infinite stream, no last block and partially empty blocks
    for sig in ["bytes", "is_last"]:
        set_int(getattr(dut, f"{name}_{sig}_i"), 0, idx=unpacked_idx)

    # initialization delay
    await Timer(init_delay_ns, units="ns")

    while True:
        if get_int(getattr(dut, f"{name}_request_o"), idx=unpacked_idx) == 0:
            await RisingEdge(getattr(dut, f"{name}_request_o"))
        await Timer(prop_delay_ns, units="ns")

        toss = random.randint(0, 16) / 16

        if toss >= resp_prob:
            await RisingEdge(dut.clk_i)  # not proving the block
        else:
            if comb_response:
                set_int(getattr(dut, f"{name}_grant_i"), 1, immediate=True, idx=unpacked_idx)
                data = urandom(data_width, endian="little")
                if debug:
                    dut._log.info(f"[CSPRNG] Random data: {ba2hex(data)}")
                set_ba(getattr(dut, f"{name}_data_i"), data, idx=unpacked_idx)
                set_int(getattr(dut, f"{name}_valid_i"), 1)

                await RisingEdge(dut.clk_i)
                await Timer(prop_delay_ns, units="ns")
                set_int(getattr(dut, f"{name}_grant_i"), 0, immediate=True, idx=unpacked_idx)
                set_int(getattr(dut, f"{name}_valid_i"), 0, immediate=True, idx=unpacked_idx)
            else:
                set_int(getattr(dut, f"{name}_grant_i"), 1, immediate=True, idx=unpacked_idx)
                await RisingEdge(dut.clk_i)
                await Timer(prop_delay_ns, units="ns")
                set_int(getattr(dut, f"{name}_grant_i"), 0, immediate=True, idx=unpacked_idx)

                # simulate read delay
                await ClockCycles(dut.clk_i, num_cycles=random.randint(2, 5))
                await Timer(prop_delay_ns, units="ns")

                data = urandom(data_width, endian="little")
                if debug:
                    dut._log.info(f"[CSPRNG] Random data: {ba2hex(data)}")

                set_ba(getattr(dut, f"{name}_data_i"), data, idx=unpacked_idx)
                set_int(getattr(dut, f"{name}_valid_i"), 1, idx=unpacked_idx)

                await RisingEdge(dut.clk_i)
                await Timer(prop_delay_ns, units="ns")
                set_int(getattr(dut, f"{name}_valid_i"), 0, idx=unpacked_idx)
