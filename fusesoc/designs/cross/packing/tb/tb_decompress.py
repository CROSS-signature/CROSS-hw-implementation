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
import os
from enum import Enum
from math import ceil, log

import cocotb
import cross
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


class Opcode(Enum):
    BP = 0
    SYN = 1
    RSP = 2

class TuserMode(Enum):
    BYPASS = 0
    UNPACK_FZ = 1
    UNPACK_FP = 2
    UNPACK_SYN = 3

CLIB_VERSION    = os.environ.get("CLIB")
N               = int(os.environ.get("N"))
K               = int(os.environ.get("K"))
P               = int(os.environ.get("P"))
BITS_P          = int(ceil(log(P,2)))
Z               = int(os.environ.get("Z"))
BITS_Z          = int(ceil(log(Z,2)))
T               = int(os.environ.get("T"))
W               = int(os.environ.get("W"))

ITERATIONS = int(os.getenv("TB_ITERATIONS", 50))

if '_RSDPG_' in CLIB_VERSION:
    M = int(os.environ.get("M"))
    RSDPG = True
    RSDP = False
else:
    RSDPG = False
    RSDP = True

async def set_mode(dut, op):
    dut.mode.value       = op.value
    dut.mode_valid.value = 1
    while (True):
        await RisingEdge(dut.clk)
        if (dut.mode_valid.value and dut.mode_ready.value):
            break;
    dut.mode_valid.value = 0

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
    dut.error_clear.value = 0

    while(1):
        await RisingEdge(dut.clk)
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value and dut.m_axis_tlast.value):
            break

    await RisingEdge(dut.clk)
    error = dut.fz_error.value
    await RisingEdge(dut.clk)
    dut.error_clear.value = 1

    await RisingEdge(dut.clk)
    dut.error_clear.value = 0
    return error

async def check_rsp0_pad_error(dut):
    error = 0
    dut.error_clear.value = 0

    # Check y
    while(1):
        await RisingEdge(dut.clk)
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value and dut.m_axis_tlast.value):
            break

    await RisingEdge(dut.clk)
    error = dut.pad_rsp0_error.value

    # Check delta/sigma
    while(1):
        await RisingEdge(dut.clk)
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value and dut.m_axis_tlast.value):
            break

    await RisingEdge(dut.clk)
    error |= dut.pad_rsp0_error.value

    await RisingEdge(dut.clk)
    dut.error_clear.value = 1

    await RisingEdge(dut.clk)
    dut.error_clear.value = 0
    return error

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_bypass(dut):
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
        await set_mode(dut, Opcode.BP)

        n_bytes = np.random.randint(1, 513)
        user_in = TuserMode.BYPASS.value<<1 | 1
        din = AxiStreamFrame(tdata=np.random.bytes(n_bytes), tuser=user_in)

        s_axis.send_nowait(din)
        got = await m_axis.recv()
        got = got.tdata


        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {din}')
        # print(f'got: {got}')
        assert got == din.tdata, "Results do not match!"
        assert len(got) == len(din.tdata), "Lengths do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_syndrome(dut):
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
        await set_mode(dut, Opcode.SYN)

        # Generate frame and compress it to hw supported format.
        # This is what we expect after decompression.
        tmp = [np.random.randint(0, P) for _ in range(N-K)]
        exp = bytearray(compress(tmp, N-K, BITS_P, int(dut.DATA_WIDTH.value)))

        # Use sw reference to compress the data frame.
        data_in = cross.test_pack_syn(tmp)
        user_in = TuserMode.UNPACK_SYN.value<<1 | 1

        # Send the compressed data frame and wait for the uncompressed output
        s_axis.send_nowait(AxiStreamFrame(tdata=data_in, tuser=user_in))
        got = await m_axis.recv()
        got = got.tdata

        # print(f'Iteration {t+1}/{ITERATIONS}')
        # print(f'exp: {binascii.hexlify(exp)}')
        # print(f'got: {binascii.hexlify(got)}')
        assert got == exp, "Results do not match!"
        assert len(got) == len(exp), "Lengths do not match!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_rsp(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")


    for _ in range(ITERATIONS):
        await set_mode(dut, Opcode.RSP)

        # Generate frames for y_i and \delta_i (rsp. \sigma_i) and compress it to hw supported format.
        # This is what we expect after decompression.
        for i in range(T-W):
            y_tmp = [np.random.randint(0, P) for _ in range(N)]
            exp_y = bytearray(compress(y_tmp, N, BITS_P, int(dut.DATA_WIDTH.value)))
            if RSDP:
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(N)]
                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, N, BITS_Z, int(dut.DATA_WIDTH.value)))
            else:
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(M)]
                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, M, BITS_Z, int(dut.DATA_WIDTH.value)))


            # Use sw reference to compress the data frame.
            rsp0_in = cross.test_pack_fp(y_tmp) + cross.test_pack_fz(delta_sigma_tmp)

            # Encoded bits for vector types don't have a meaning here
            user_in = 0
            if i == T-W-1:
                user_in = 1

            # Send the compressed rsp0 touple and wait for the uncompressed output
            check_rsp0_proc = cocotb.start_soon(check_rsp0_pad_error(dut))
            s_axis.send_nowait(AxiStreamFrame(tdata=rsp0_in, tuser=user_in))
            got_y = await m_axis.recv()

            check_fz_proc = cocotb.start_soon(check_restricted_group(dut))
            got_delta_sigma = await m_axis.recv()
            fz_error = await check_fz_proc
            rsp0_error = await check_rsp0_proc

            got_y = got_y.tdata
            got_delta_sigma = got_delta_sigma.tdata

            # print(f'exp_y: {binascii.hexlify(exp_y)}')
            # print(f'got_y: {binascii.hexlify(got_y)}')
            assert got_y == exp_y, "Results for y do not match!"
            assert len(got_y) == len(exp_y), "Lengths for y do not match!"

            # print(f'exp_delta_sigma: {binascii.hexlify(exp_delta_sigma)}')
            # print(f'got_delta_sigma: {binascii.hexlify(got_delta_sigma)}')
            assert got_delta_sigma == exp_delta_sigma, "Results for delta_sigma do not match!"
            assert len(got_delta_sigma) == len(exp_delta_sigma), "Lengths for delta_sigma do not match!"

            assert rsp0_error == 0, "Padding in rsp0 is wrong (could be forged signature)!"
            assert fz_error == 0, "Some element not in restricted subgroup"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_rsp_not_in_G(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")


    for _ in range(ITERATIONS):
        await set_mode(dut, Opcode.RSP)

        # Generate frames for y_i and \delta_i (rsp. \sigma_i) and compress it to hw supported format.
        # This is what we expect after decompression.
        for i in range(T-W):
            y_tmp = [np.random.randint(0, P) for _ in range(N)]

            exp_y = bytearray(compress(y_tmp, N, BITS_P, int(dut.DATA_WIDTH.value)))
            if RSDP:
                # Sample a random coefficient that is not in F_z
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(N)]
                error_coeff = np.random.randint(0,N)
                error_val = np.random.randint(Z, 2**BITS_Z)
                delta_sigma_tmp[error_coeff] = error_val

                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, N, BITS_Z, int(dut.DATA_WIDTH.value)))
            else:
                # Sample a random coefficient that is not in F_z
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(M)]
                error_coeff = np.random.randint(0,M)
                error_val = np.random.randint(Z, 2**BITS_Z)
                delta_sigma_tmp[error_coeff] = error_val

                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, M, BITS_Z, int(dut.DATA_WIDTH.value)))


            # Use sw reference to compress the data frame.
            rsp0_in = cross.test_pack_fp(y_tmp) + cross.test_pack_fz(delta_sigma_tmp)

            # Encoded bits for vector types don't have a meaning here
            user_in = 0
            if i == T-W-1:
                user_in = 1

            # Send the compressed rsp0 touple and wait for the uncompressed output
            check_rsp0_proc = cocotb.start_soon(check_rsp0_pad_error(dut))
            s_axis.send_nowait(AxiStreamFrame(tdata=rsp0_in, tuser=user_in))
            got_y = await m_axis.recv()

            check_fz_proc = cocotb.start_soon(check_restricted_group(dut))
            got_delta_sigma = await m_axis.recv()
            fz_error = await check_fz_proc
            rsp0_error = await check_rsp0_proc

            got_y = got_y.tdata
            got_delta_sigma = got_delta_sigma.tdata

            # print(f'exp_y: {binascii.hexlify(exp_y)}')
            # print(f'got_y: {binascii.hexlify(got_y)}')
            assert got_y == exp_y, "Results do not match!"
            assert len(got_y) == len(exp_y), "Lengths do not match!"

            # print(f'exp_delta_sigma: {binascii.hexlify(exp_delta_sigma)}')
            # print(f'got_delta_sigma: {binascii.hexlify(got_delta_sigma)}')
            assert got_delta_sigma == exp_delta_sigma, "Results do not match!"
            assert len(got_delta_sigma) == len(exp_delta_sigma), "Lengths do not match!"
            assert rsp0_error == 0, "Padding in rsp0 is wrong (could be forged signature)!"
            assert fz_error == 1, "All elements are in restricted subgroup although one coeff should not! (idx: " + str(error_coeff) + ", val: " + str(error_val) + ")"

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def cross_unpack_rsp_padding_error(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    dut.rst_n.value = 1
    await Timer(100, units="ns")


    for _ in range(ITERATIONS):
        await set_mode(dut, Opcode.RSP)

        # Generate frames for y_i and \delta_i (rsp. \sigma_i) and compress it to hw supported format.
        # This is what we expect after decompression.
        for i in range(T-W):
            y_tmp = [np.random.randint(0, P) for _ in range(N)]
            exp_y = bytearray(compress(y_tmp, N, BITS_P, int(dut.DATA_WIDTH.value)))
            if RSDP:
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(N)]
                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, N, BITS_Z, int(dut.DATA_WIDTH.value)))
            else:
                delta_sigma_tmp = [np.random.randint(0, Z) for _ in range(M)]
                exp_delta_sigma = bytearray(compress(delta_sigma_tmp, M, BITS_Z, int(dut.DATA_WIDTH.value)))


            y_err = y_tmp


            # Use sw reference to compress the data frame
            # Generate padding error for affected parameters and vectors
            # by flipping last bit
            y_err = cross.test_pack_fp(y_tmp)
            if N*BITS_P % 8 > 0:
                y_err[-1] |= (1 << 7)

            delta_sigma_err = cross.test_pack_fz(delta_sigma_tmp)
            if (RSDPG and M*BITS_Z % 8 > 0) or (RSDP and N*BITS_Z % 8 > 0):
                delta_sigma_err[-1] |= (1 << 7)

            rsp0_in = y_err + delta_sigma_err

            # Encoded bits for vector types don't have a meaning here
            user_in = 0
            if i == T-W-1:
                user_in = 1

            # Send the compressed rsp0 touple and wait for the uncompressed output
            check_rsp0_proc = cocotb.start_soon(check_rsp0_pad_error(dut))
            s_axis.send_nowait(AxiStreamFrame(tdata=rsp0_in, tuser=user_in))
            got_y = await m_axis.recv()

            check_fz_proc = cocotb.start_soon(check_restricted_group(dut))
            got_delta_sigma = await m_axis.recv()
            fz_error = await check_fz_proc
            rsp0_error = await check_rsp0_proc

            got_y = got_y.tdata
            got_delta_sigma = got_delta_sigma.tdata

            # print(f'exp_y: {binascii.hexlify(exp_y)}')
            # print(f'got_y: {binascii.hexlify(got_y)}')
            assert got_y == exp_y, "Results do not match!"
            assert len(got_y) == len(exp_y), "Lengths do not match!"

            # print(f'exp_delta_sigma: {binascii.hexlify(exp_delta_sigma)}')
            # print(f'got_delta_sigma: {binascii.hexlify(got_delta_sigma)}')
            assert got_delta_sigma == exp_delta_sigma, "Results do not match!"
            assert len(got_delta_sigma) == len(exp_delta_sigma), "Lengths do not match!"

            assert rsp0_error == 1, "Padding in rsp0 is correct but should be wrong!"
            assert fz_error == 0, "Some element not in restricted subgroup"
