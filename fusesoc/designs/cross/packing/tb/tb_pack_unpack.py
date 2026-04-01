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

# import binascii
# import hashlib
import os
from math import ceil, log

import cocotb
import cross
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

PASSTHROUGH = 0
PACK_FZ = 1
PACK_FP = 2
PACK_SYN = 3

CLIB_VERSION    = os.environ.get("CLIB")
N               = int(os.environ.get("N"))
K               = int(os.environ.get("K"))
P               = int(os.environ.get("P"))
BITS_P          = int(ceil(log(P,2)))
Z               = int(os.environ.get("Z"))
BITS_Z          = int(ceil(log(Z,2)))
T               = int(os.environ.get("T"))
W               = int(os.environ.get("W"))

ITERATIONS = int(os.getenv("TB_ITERATIONS", 10*T))

if '_RSDPG_' in CLIB_VERSION:
    M = int(os.environ.get("M"))
    RSDPG = True
    RSDP = False
else:
    RSDPG = False
    RSDP = True

def compress(d, dlen, bits_per_elem, dw):
    tmp = []
    cnt = 0
    elems_per_word = int(dw/bits_per_elem)
    num_words = int( (dlen + elems_per_word-1) / elems_per_word)

    for i in range(num_words):
        word = 0
        for j in range(elems_per_word):
            if (cnt < dlen):
                word |= d[cnt] << bits_per_elem*j
                cnt += 1
        tmp.append(word)

    res = []
    # FULL WORDS
    for i in range(dlen//elems_per_word):
        for j in range(dw//8):
            res.append((tmp[i] >> 8*j) & 0xFF)

    # LAST WORD
    if (dlen % elems_per_word > 0):
        for i in range( ((dlen % elems_per_word)*bits_per_elem+7) // 8 ):
            res.append((tmp[-1] >> 8*i) & 0xFF)

    return res

async def check_restricted_group(dut):
    error = 0
    dut.fz_error_clear.value = 0

    while(1):
        await RisingEdge(dut.clk)
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value and dut.m_axis_tlast.value):
            break

    await RisingEdge(dut.clk)
    error = dut.fz_error.value
    await RisingEdge(dut.clk)
    dut.fz_error_clear.value = 1

    await RisingEdge(dut.clk)
    dut.fz_error_clear.value = 0
    return error


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_pack_test_passthrough(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    await RisingEdge(dut.clk)
    dut.pack_en.value = 1

    for t in range(ITERATIONS):
        n_bytes = np.random.randint(1, 513)
        din = AxiStreamFrame(tdata=np.random.bytes(n_bytes), tuser=PASSTHROUGH<<1)

        s_axis.send_nowait(din)
        got = await m_axis.recv()
        got = got.tdata


        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {din}')
        # print(f'got: {got}')
        assert got == din.tdata, "Results do not match!"
        assert len(got) == len(din.tdata), "Lengths do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_pack_test_fz(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")
    dut.pack_en.value = 1
    await cocotb.triggers.RisingEdge(dut.clk)


    if RSDP:
        n_elems = N
    elif RSDPG:
        n_elems = M

    for t in range(ITERATIONS):
        din = [np.random.randint(0, Z) for _ in range(n_elems)]
        exp = cross.test_pack_fz(din)
        exp = bytes(exp)

        din = compress(din, n_elems, BITS_Z, int(dut.DATA_WIDTH.value))
        s_axis.send_nowait(AxiStreamFrame(tdata=din, tuser=PACK_FZ<<1))

        got = await m_axis.recv()
        got = got.tdata

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'd_in : {[hex(d) for d in din]}')
        # print(f'exp: {binascii.hexlify(exp)}')
        # print(f'got: {binascii.hexlify(got)}')
        assert len(got) == len(exp), "Lenghts do not match!"
        assert got == exp, "Results do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_pack_test_fp(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")
    dut.pack_en.value = 1
    await cocotb.triggers.RisingEdge(dut.clk)

    for t in range(ITERATIONS):
        din = [np.random.randint(0, P) for _ in range(N)]
        exp = cross.test_pack_fp(din)
        exp = bytes(exp)

        din = compress(din, N, BITS_P, int(dut.DATA_WIDTH.value))
        s_axis.send_nowait(AxiStreamFrame(tdata=din, tuser=PACK_FP<<1))

        got = await m_axis.recv()
        got = got.tdata

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'd_in : {[hex(d) for d in din]}')
        # print(f'exp: {exp}')
        # print(f'got: {got}')
        assert got == exp, "Results do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_pack_test_syndrome(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")
    dut.pack_en.value = 1
    await cocotb.triggers.RisingEdge(dut.clk)

    for t in range(ITERATIONS):
        din = [np.random.randint(0, P) for _ in range(N-K)]
        exp = cross.test_pack_syn(din)
        exp = bytes(exp)

        din = compress(din, N-K, BITS_P, int(dut.DATA_WIDTH.value))
        s_axis.send_nowait(AxiStreamFrame(tdata=din, tuser=PACK_SYN<<1))

        got = await m_axis.recv()
        got = got.tdata

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'd_in : {[hex(d) for d in din]}')
        # print(f'exp: {exp}')
        # print(f'got: {got}')
        assert got == exp, "Results do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_test_fz(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    if RSDP:
        n_elems = N
    elif RSDPG:
        n_elems = M

    for t in range(ITERATIONS):
        dut.pack_en.value = 1

        # Prepare data input
        tmp = [np.random.randint(0, Z) for _ in range(n_elems)]
        data_in = compress(tmp, n_elems, BITS_Z, int(dut.DATA_WIDTH.value))

        # double check the packing because why not
        exp = bytes(cross.test_pack_fz(tmp))

        s_axis.send_nowait(AxiStreamFrame(tdata=data_in, tuser=PACK_FZ<<1))
        got = await m_axis.recv()

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'packed_exp: {binascii.hexlify(exp)}')
        # print(f'packed_got: {binascii.hexlify(got.tdata)}')
        assert got.tdata == exp, "Results do not match!"
        dut.pack_en.value = 0
        await RisingEdge(dut.clk)

        # Now set to unpack and feed the received input again to unpack dut
        check_fz_proc = cocotb.start_soon(check_restricted_group(dut))
        s_axis.send_nowait(AxiStreamFrame(tdata=got.tdata, tuser=PACK_FZ<<1))
        got_unp = await m_axis.recv()
        fz_error = await check_fz_proc

        # print(f'exp_unp: {binascii.hexlify(bytearray(data_in))}')
        # print(f'got_unp: {binascii.hexlify(got_unp.tdata)}')
        assert fz_error == 0, "Element is not in the restricted group!"
        assert got_unp.tdata == bytearray(data_in), "Results do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_test_fp(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for t in range(ITERATIONS):
        dut.pack_en.value = 1

        # Prepare data input
        tmp = [np.random.randint(0, P) for _ in range(N)]
        data_in = compress(tmp, N, BITS_P, int(dut.DATA_WIDTH.value))

        # double check the packing because why not
        exp = bytes(cross.test_pack_fp(tmp))

        s_axis.send_nowait(AxiStreamFrame(tdata=data_in, tuser=PACK_FP<<1))
        got = await m_axis.recv()

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {exp}')
        # print(f'got: {got.tdata}')
        assert got.tdata == exp, "Results do not match!"
        dut.pack_en.value = 0
        await RisingEdge(dut.clk)

        # Now set to unpack and feed the received input again to unpack dut
        s_axis.send_nowait(AxiStreamFrame(tdata=got.tdata, tuser=PACK_FP<<1))
        got_unp = await m_axis.recv()

        # print(f'exp_unp: {binascii.hexlify(bytearray(data_in))}')
        # print(f'got_unp: {binascii.hexlify(got_unp.tdata)}')
        assert got_unp.tdata == bytearray(data_in), "Results do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_test_syndrome(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    for t in range(ITERATIONS):
        dut.pack_en.value = 1

        # Prepare data input
        tmp = [np.random.randint(0, P) for _ in range(N-K)]
        data_in = compress(tmp, N-K, BITS_P, int(dut.DATA_WIDTH.value))

        # double check the packing because why not
        exp = bytes(cross.test_pack_syn(tmp))

        s_axis.send_nowait(AxiStreamFrame(tdata=data_in, tuser=PACK_SYN<<1))
        got = await m_axis.recv()

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {exp}')
        # print(f'got: {got.tdata}')
        assert got.tdata == exp, "Results do not match!"
        dut.pack_en.value = 0
        await RisingEdge(dut.clk)

        # Now set to unpack and feed the received input again to unpack dut
        s_axis.send_nowait(AxiStreamFrame(tdata=got.tdata, tuser=PACK_SYN<<1))
        got_unp = await m_axis.recv()

        # print(f'exp_unp: {binascii.hexlify(bytearray(data_in))}')
        # print(f'got_unp: {binascii.hexlify(got_unp.tdata)}')
        assert got_unp.tdata == bytearray(data_in), "Results do not match!"

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_test_fz_not_in_G(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")

    if RSDP:
        n_elems = N
    elif RSDPG:
        n_elems = M

    for t in range(ITERATIONS):
        dut.pack_en.value = 1

        # Prepare data input
        tmp = [np.random.randint(0, Z) for _ in range(n_elems)]

        # Sample a random coefficient that is not in F_z
        error_coeff = np.random.randint(0,n_elems)
        error_val = np.random.randint(Z, 2**BITS_Z)
        tmp[error_coeff] = error_val

        data_in = compress(tmp, n_elems, BITS_Z, int(dut.DATA_WIDTH.value))

        # double check the packing because why not
        exp = bytes(cross.test_pack_fz(tmp))

        s_axis.send_nowait(AxiStreamFrame(tdata=data_in, tuser=PACK_FZ<<1))
        got = await m_axis.recv()

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {exp}')
        # print(f'got: {got.tdata}')
        assert got.tdata == exp, "Results do not match!"
        dut.pack_en.value = 0
        await RisingEdge(dut.clk)

        # Now set to unpack and feed the received input again to unpack dut
        check_fz_proc = cocotb.start_soon(check_restricted_group(dut))
        s_axis.send_nowait(AxiStreamFrame(tdata=got.tdata, tuser=PACK_FZ<<1))
        got_unp = await m_axis.recv()
        fz_error = await check_fz_proc

        # print(f'exp_unp: {binascii.hexlify(bytearray(data_in))}')
        # print(f'got_unp: {binascii.hexlify(got_unp.tdata)}')
        assert fz_error == 1, "All elements are in restricted subgroup although one coeff should not! (idx: " + str(error_coeff) + ", val: " + str(error_val) + ")"
        assert got_unp.tdata == bytearray(data_in), "Results do not match!"
