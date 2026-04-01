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
from cocotb.triggers import ReadOnly, RisingEdge, Timer
from cocotb.types import Logic, LogicArray, Range

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import get_ba, logger, set_int


class WriteStreamProducer:
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
        self.w_ctr = 0
        self.addr = 0
        self.ended = False

        logger.info(f"Initializing empty producer {self.name} of size {len(init)}-bits with blocks of {self.block_sz}-bits")
        if reversed_bytes:
            byte_array = bytearray(init.tobytes())
            byte_array.reverse()
            init.clear()
            init.frombytes(byte_array)
        if self.debug:
            logger.debug(f"[{self.name}] Init content: 0x{ba2hex(init)}")
        self.mem = deepcopy(init)

    def get_performance_counters(self) -> dict:
        res = {"writes": self.w_ctr}

        if self.debug:
            logger.debug(f"[{self.name}] Performance counters: {res}")

        return res

    def write(self, grant: bool) -> tuple["bitarray", int, bool]:
        data = deepcopy(self.mem[self.w_ctr * self.block_sz : (self.w_ctr + 1) * self.block_sz])
        bytes = 0
        is_last = False

        if self.debug:
            logger.debug(f"[{self.name}] Sending to stream data 0x{ba2hex(data)}")

        if grant:
            if (self.w_ctr + 1) * self.block_sz > len(self.mem):
                logger.info(f"[{self.name}] Produced last block")
                self.ended = True
                is_last = True
                bytes = int(ceil(len(data) / 8))
            self.w_ctr += 1

        return data, bytes, is_last

    def dump(self) -> "bitarray":
        return deepcopy(self.mem)

    def process(self, grant: bool) -> dict:
        data = zeros(self.block_sz, endian="little")
        bytes = 0
        is_last = False
        bytes_sz = int(log2(ceil(len(data) / 8)))

        if not self.ended:
            data, bytes, is_last = self.write(grant)
            while len(data) != self.block_sz:
                data.insert(0, 0)

        # DUT INPUT SIGNALS
        return {
            "data": LogicArray(data.to01()),
            "is_last": Logic(f"{int(is_last)}"),
            "bytes": LogicArray(bytes, Range(bytes_sz - 1, 0)),
            "request": Logic(f"{int(is_last or not self.ended)}"),
        }


class WriteStreamConsumer:
    def __init__(
        self,
        name: str = "stream",
        block_sz: int = 32,
        debug: bool = False,
    ):
        self.block_sz = block_sz
        self.debug = debug
        self.name = name
        self.endian = "little"  # [0] is least significant bit
        self.w_ctr = 0

        logger.info(f"Initializing empty consumer stream {self.name} of size {self.block_sz}")
        self.mem = bitarray(endian="little")

    def get_performance_counters(self) -> dict:
        res = {"writes": self.w_ctr}

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

        self.mem[self.w_ctr * self.block_sz : self.w_ctr * self.block_sz + len(data)] = deepcopy(data)

        self.w_ctr += 1

    def process(self, req: "bitarray", data: "bitarray", is_last: bool, bytes: int) -> dict:
        if req == bitarray("1"):
            self.write(data=data)

        # DUT INPUT SIGNALS

        return {
            "grant": Logic(req.to01()),
        }


async def write_stream_producer_agent(dut, stream, name: str, prop_delay_ns: int = 2, unpacked_idx: int = None):
    for sig in ["data", "is_last", "bytes", "request"]:
        set_int(signal=getattr(dut, f"{name}_w_{sig}_i"), data=0, immediate=True, idx=unpacked_idx)

    while True:
        if stream.ended is False:
            set_int(signal=getattr(dut, f"{name}_w_request_i"), data=1, idx=unpacked_idx)
        else:
            set_int(signal=getattr(dut, f"{name}_w_request_i"), data=0, idx=unpacked_idx)

        await ReadOnly()

        grant_signal = get_ba(getattr(dut, f"{name}_w_grant_o"), idx=unpacked_idx)
        signals = stream.process(grant=(grant_signal == bitarray("1")))

        # propagation delay
        await Timer(prop_delay_ns, units="ns")

        for sig in ["data", "is_last", "bytes", "request"]:
            set_int(signal=getattr(dut, f"{name}_w_{sig}_i"), data=signals[sig], immediate=True, idx=unpacked_idx)

        await RisingEdge(dut.clk_i)


async def write_stream_consumer_agent(dut, stream, name: str, prop_delay_ns: int = 2, unpacked_idx: int = None):
    for sig in ["grant"]:
        set_int(signal=getattr(dut, f"{name}_w_{sig}_i"), data=0, immediate=True, idx=unpacked_idx)

    while True:
        await ReadOnly()

        signals = stream.process(
            req=get_ba(getattr(dut, f"{name}_w_request_o"), idx=unpacked_idx),
            data=get_ba(getattr(dut, f"{name}_w_data_o"), idx=unpacked_idx),
            is_last=get_ba(getattr(dut, f"{name}_w_is_last_o"), idx=unpacked_idx),
            bytes=get_ba(getattr(dut, f"{name}_w_bytes_o"), idx=unpacked_idx),
        )

        # propagation delay
        await Timer(prop_delay_ns, units="ns")

        for sig in ["grant"]:
            set_int(signal=getattr(dut, f"{name}_w_{sig}_i"), data=signals[sig], immediate=True, idx=unpacked_idx)

        await RisingEdge(dut.clk_i)
