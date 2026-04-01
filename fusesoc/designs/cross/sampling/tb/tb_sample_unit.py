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

import hashlib
import os
from enum import Enum
from math import ceil, log

import numpy as np

ITERATIONS = int(os.getenv("TB_ITERATIONS", 1000))

import cocotb
import cross
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

CLIB_VERSION = os.environ.get("CLIB")

LAMBDA          = int(os.environ.get("LAMBDA"))
N               = int(os.environ.get("N"))
K               = int(os.environ.get("K"))
P               = int(os.environ.get("P"))
BITS_P          = ceil(log(P,2))
Z               = int(os.environ.get("Z"))
BITS_Z          = ceil(log(Z,2))
T               = int(os.environ.get("T"))
W               = int(os.environ.get("W"))

BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8

if LAMBDA == 128:
    cat = 'category_1'
elif LAMBDA == 192:
    cat = 'category_3'
else:
    cat = 'category_5'

if 'RSDPG' in CLIB_VERSION:
    variant = 'rsdpg'
    M = int(os.environ.get("M"))
    RSDPG = True
    RSDP = False
else:
    variant = 'rsdp'
    RSDPG = False
    RSDP = True

if 'SPEED' in CLIB_VERSION:
    tar = 'fast'
elif 'BALANCED' in CLIB_VERSION:
    tar = 'balanced'
else:
    tar = 'small'

with open(f'sample_{variant}_{cat}_{tar}.csv', 'w') as bench_file:
    bench_file.write('iter,fz,fzfp,fzfpseq,vw,vwseq,Nt,chall1,chall2\n')
    bench_file.write(f'{ITERATIONS},')

class OPCODE(Enum):
    SQUEEZE         = 0
    SAMPLE_FZ       = 1
    SAMPLE_FZ_FP    = 2
    SAMPLE_VT_W     = 3
    SAMPLE_B        = 4
    SAMPLE_BETA     = 5

class DIGEST(Enum):
    SEED = 0
    HASH = 1

async def reset(dut):
    await Timer(5, units="ns")
    dut.rst_n.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    return

async def set_mode(dut, op):
    dut.mode.value       = op.value
    dut.mode_valid.value = 1
    while (1):
        await RisingEdge(dut.clk)
        if (dut.mode_valid.value and dut.mode_ready.value):
            break;
    dut.mode_valid.value = 0


async def read_hash(dut, num):
    cnt = 0
    hash_cnt = 0
    out = []
    res = []

    # Read data until m_axis_tlast is detected
    while (hash_cnt < num):
        tmp = 0
        keep = 0
        await RisingEdge(dut.clk)
        cnt = cnt + 1
        # Check for valid output
        if (dut.m_axis_tvalid.value and dut.m_axis_tready.value):
            for i in range(dut.KEEP_OUT.value):
                if dut.m_axis_tkeep.value[i] == 1:
                    tmp |= dut.m_axis_tdata.value[8*i:8*(i+1)-1] << 8*i
                    keep += 1

            # padd to full slice due to shitty big endian and then cut by the amount of bytes received
            out.append(f'{tmp:0{dut.KEEP_OUT.value*2}x}'[:2*keep])

            # If tlast is set, return
            if dut.m_axis_tlast.value:
                hash_cnt = hash_cnt + 1
                res.append(''.join(out))
                out = []
    print(f'hashing took {cnt} cycles')
    return res

async def read_fz(dut, num_vec):
    out = []
    tmp = []
    pad = dut.DATA_WIDTH.value % BITS_Z
    cnt = 0

    # Read data until m_axis_tlast is detected
    while (cnt < num_vec):
        await RisingEdge(dut.clk)
        if (dut.m_axis_1_tvalid.value and dut.m_axis_1_tready.value):
            # Throw away padding bits, as it is padded
            val = dut.m_axis_1_tdata.value.binstr[pad:]
            tmp = [int(val[i:i+BITS_Z],2) for i in range(0, len(val), BITS_Z)]
            tmp = tmp[::-1]
            out += tmp

            # If tlast is set, return
            if dut.m_axis_1_tlast.value:
                cnt += 1
    return out

async def bench_fz(dut):
    cnt = 0

    # Wait until fz_en goes high
    while not dut.u_sample_unit.fz_en.value:
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.fz_en.value:
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def bench_fz_fp(dut):
    cnt = 0

    # Wait until fz_en or fp_en goes high
    while not (dut.u_sample_unit.fz_en.value or dut.u_sample_unit.fp_en.value):
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.fz_en.value or dut.u_sample_unit.fp_en.value:
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def bench_fz_fp_seq(dut):
    fz_cnt = 0
    fp_cnt = 0

    # Wait until fz_en or fp_en goes high
    while not (dut.u_sample_unit.fz_en.value or dut.u_sample_unit.fp_en.value):
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.fz_en.value or dut.u_sample_unit.fp_en.value:
        if dut.u_sample_unit.fz_en.value:
            fz_cnt += 1
        if dut.u_sample_unit.u_fp_sample.bits_in_buf.value.integer > 0:
            fp_cnt += 1
        await RisingEdge(dut.clk)

    return fz_cnt+fp_cnt

async def bench_v_w(dut):
    cnt = 0

    # Wait until v_en or w_en goes high
    while not (dut.u_sample_unit.fp_v_en.value or dut.u_sample_unit.fz_w_en.value):
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.fz_w_en.value or dut.u_sample_unit.fp_v_en.value:
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def bench_v_w_seq(dut):
    fz_cnt = 0
    fp_cnt = 0

    # Wait until v_en or w_en goes high
    while not (dut.u_sample_unit.fp_v_en.value or dut.u_sample_unit.fz_w_en.value):
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.fz_w_en.value or dut.u_sample_unit.fp_v_en.value:
        if dut.u_sample_unit.fz_w_en.value:
            fz_cnt += 1
        if dut.u_sample_unit.u_fp_sample.bits_in_buf.value.integer > 0:
            fp_cnt += 1
        await RisingEdge(dut.clk)

    return fz_cnt+fp_cnt

async def bench_b(dut):
    cnt = 0

    # Wait until b_en is high
    while not dut.u_sample_unit.b_en.value:
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.b_en.value:
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def bench_beta(dut):
    cnt = 0

    # Wait until beta_en is high
    while not dut.u_sample_unit.beta_en.value:
        await RisingEdge(dut.clk)

    # Now count the cycles
    while dut.u_sample_unit.beta_en.value:
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def bench_beta_b(dut):
    cnt = 0

    # Wait until b_en or beta_en is high
    while not (dut.u_sample_unit.beta_en.value or dut.u_sample_unit.b_en.value):
        await RisingEdge(dut.clk)

    # Now count the cycles
    while (dut.u_sample_unit.beta_en.value or dut.u_sample_unit.b_en.value):
        cnt += 1
        await RisingEdge(dut.clk)

    return cnt

async def read_w(dut):
    vec = []
    out = []
    cnt = 0

    # Read data until m_axis_tlast is detected
    while (cnt < M):
        await RisingEdge(dut.clk)
        if (dut.m_axis_w_tvalid.value and dut.m_axis_w_tready.value):
            vec.append(int(dut.m_axis_w_tdata.value))

            # If tlast is set
            if dut.m_axis_w_tlast.value:
                out.append(vec)
                vec = []
                cnt += 1

    return out


async def read_fp(dut, num_vec):
    out = []
    tmp = []
    pad = dut.DATA_WIDTH.value % BITS_P
    cnt = 0

    # Read data until m_axis_tlast is detected
    while (cnt < num_vec):
        await RisingEdge(dut.clk)
        if (dut.m_axis_0_tvalid.value and dut.m_axis_0_tready.value):
            # Throw away padding bits, as it is padded
            val = dut.m_axis_0_tdata.value.binstr[pad:]
            tmp = [int(val[i:i+BITS_P],2) for i in range(0, len(val), BITS_P)]
            out += tmp[::-1]

            # If tlast is set, return
            if dut.m_axis_0_tlast.value:
                cnt += 1

    return out

async def read_beta(dut):
    vec = []

    # Read data until m_axis_tlast is detected
    while (True):
        await RisingEdge(dut.clk)
        if (dut.m_axis_v_beta_tvalid.value and dut.m_axis_v_beta_tready.value):
            vec.append(int(dut.m_axis_v_beta_tdata.value))

            # If tlast is set
            if dut.m_axis_v_beta_tlast.value:
                break
    return vec

async def read_v(dut):
    vec = []
    out = []
    cnt = 0

    # Read data until m_axis_tlast is detected
    while (cnt < K):
        await RisingEdge(dut.clk)
        if (dut.m_axis_v_beta_tvalid.value and dut.m_axis_v_beta_tready.value):
            vec.append(int(dut.m_axis_v_beta_tdata.value))

            # If tlast is set
            if dut.m_axis_v_beta_tlast.value:
                out.append(vec)
                vec = []
                cnt += 1

    return out


async def read_b(dut):
    out = []
    cnt = 0

    # Read data until m_axis_tlast is detected
    while (True):
        await RisingEdge(dut.clk)
        cnt = cnt + 1
        # Check for valid output
        if (dut.m_axis_b_tvalid.value and dut.m_axis_b_tready.value):
            tmp = dut.m_axis_b_tdata.value
            tmp = [str(bit) for bit in tmp]
            tmp = tmp[::-1]
            out.append(('').join(tmp))


            if dut.m_axis_b_tlast.value:
                print(f'sampling took {cnt} cycles')
                break
    return ('').join(out)


async def cnt_hashes(dut):
    cnt = 0

    if RSDPG:
        await RisingEdge(dut.u_sample_unit.fz_w_en)
    else:
        await RisingEdge(dut.u_sample_unit.fp_v_en)

    while (dut.u_sample_unit.fz_w_en.value or dut.u_sample_unit.fp_v_en.value):
        await RisingEdge(dut.clk)
        if (dut.m_axis_1_tvalid.value and dut.m_axis_1_tready.value and dut.m_axis_1_tlast.value):
            cnt += 1

    return cnt


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_seed_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_1 = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_1"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)

    await RisingEdge(dut.clk)
    dut.n_digests.value = 1


    for _ in range(ITERATIONS):
        din = AxiStreamFrame(np.random.bytes(BYTES_SEED))

        if (LAMBDA == 128):
            hash_ref = hashlib.shake_128(bytes(din.tdata))
        else:
            hash_ref = hashlib.shake_256(bytes(din.tdata))

        exp = hash_ref.hexdigest(LAMBDA//8)

        # Set sampler mode
        dut.digest_type.value = DIGEST.SEED.value
        await set_mode(dut, OPCODE.SQUEEZE)

        # Send input
        await s_axis.send(din)
        await s_axis.wait()

        got = await m_axis_1.recv()
        got = got.tdata.hex()

        # Check with reference
        # print(f'got: {got}')
        # print(f'exp: {exp}\n')
        assert got == exp, "Not as expected!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_hash_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_1 = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_1"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)

    await RisingEdge(dut.clk)
    dut.n_digests.value = 1


    for _ in range(ITERATIONS):
        din = AxiStreamFrame(np.random.bytes(BYTES_SEED))

        if (LAMBDA == 128):
            hash_ref = hashlib.shake_128(bytes(din.tdata))
        else:
            hash_ref = hashlib.shake_256(bytes(din.tdata))

        exp = hash_ref.hexdigest(2*LAMBDA//8)

        # Set sampler mode
        dut.digest_type.value = DIGEST.HASH.value
        await set_mode(dut, OPCODE.SQUEEZE)

        # Send input
        await s_axis.send(din)
        await s_axis.wait()

        got = await m_axis_1.recv()
        got = got.tdata.hex()

        # Check with reference
        # print(f'got: {got}')
        # print(f'exp: {exp}\n')
        assert got == exp, "Not as expected!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_double_hash_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_1 = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_1"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)

    await RisingEdge(dut.clk)
    dut.n_digests.value = 2


    for _ in range(ITERATIONS):
        din = AxiStreamFrame(np.random.bytes(BYTES_SEED))

        if (LAMBDA == 128):
            hash_ref = hashlib.shake_128(bytes(din.tdata))
        else:
            hash_ref = hashlib.shake_256(bytes(din.tdata))

        exp_tmp = hash_ref.hexdigest(4*LAMBDA//8)
        exp = []
        exp.append(exp_tmp[:len(exp_tmp)//2])
        exp.append(exp_tmp[len(exp_tmp)//2:])

        # Set sampler mode
        dut.digest_type.value = DIGEST.HASH.value
        await set_mode(dut, OPCODE.SQUEEZE)

        # Send input
        await s_axis.send(din)
        await s_axis.wait()

        got = []
        for _ in range(2):
            got.append(await m_axis_1.recv())
            got[-1] = got[-1].tdata.hex()

        # Check with reference
        # print(f'got: {got}')
        # print(f'exp: {exp}\n')
        assert got == exp, "Not as expected!"


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_fz_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)

    await RisingEdge(dut.clk)
    cc_total = 0

    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        din = np.random.bytes(BYTES_SEED)

        bench_fz_proc = cocotb.start_soon(bench_fz(dut))
        await set_mode(dut, OPCODE.SAMPLE_FZ)

        # Send input
        await s_axis.send(AxiStreamFrame(din + bytes([0, 0])))
        await s_axis.wait()

        got = await read_fz(dut, 1)
        if RSDP:
            got = got[:N]
        elif RSDPG:
            got = got[:M]
        exp = cross.test_zz_vec(din)

        # print("Got:")
        # print(got)
        # print("Exp:")
        # print(exp)
        if RSDP:
            assert len(got) == len(exp) == N, "Vector has wrong length: " +str(len(got)) + " expect " + str(N)
        elif RSDPG:
            assert len(got) == len(exp) == M, "Vector has wrong length: " +str(len(got)) + " expect " + str(M)

        for i in range(len(exp)):
            assert exp[i] == got[i], "Wrong element at index " + str(i)
        for val in got:
            assert val < Z, "Not as expected!"

        cc_total += await bench_fz_proc
    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_fz_fp_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_1_tready.value = 1
    dut.m_axis_0_tready.value = 1

    await RisingEdge(dut.clk)
    cc_total = 0
    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        # sample fz and fp in parallel
        fz_proc = cocotb.start_soon(read_fz(dut, 1))
        fp_proc = cocotb.start_soon(read_fp(dut, 1))
        bench_fz_fp_proc = cocotb.start_soon(bench_fz_fp(dut))

        din = np.random.bytes(BYTES_SEED)
        await set_mode(dut, OPCODE.SAMPLE_FZ_FP)
        await s_axis.send(AxiStreamFrame(din + bytes([0, 0])))
        await s_axis.wait()

        exp_zz, exp_zp = cross.test_zz_zq_vecs(din)


        got_fz = await fz_proc
        if RSDP:
            got_fz = got_fz[:N]
        elif RSDPG:
            got_fz = got_fz[:M]

        # print("Got Fz:")
        # print(got_fz)
        # print("Exp Fz:")
        # print(exp_zz)
        if RSDP:
            assert len(got_fz) == len(exp_zz) == N, "Vector has wrong length: " + str(len(got_fz)) + " expect " + str(N)
        elif RSDPG:
            assert len(got_fz) == len(exp_zz) == M, "Vector has wrong length: " + str(len(got_fz)) + " expect " + str(M)

        for i in range(len(exp_zz)):
            assert got_fz[i] == exp_zz[i], "Wrong zz value at index " + str(i)

        for val in got_fz:
            assert val < Z, "Value >= Z!"

        # sample fp
        got_fp = await fp_proc
        got_fp = got_fp[:N]

        # print("Got Fp:")
        # print(got_fp)
        # print("Exp Fp:")
        # print(exp_zp)
        assert len(got_fp) == len(exp_zp) == N, "Vector has wrong length: " + str(len(got_fp)) + " expect " + str(N)
        for i in range(N):
            assert got_fp[i] == exp_zp[i], "Wrong zp value at index " + str(i)
        for val in got_fp:
            assert val < P, "Value >= P!"

        cc_total += await bench_fz_fp_proc
    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_fz_fp_seq_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_1_tready.value = 1
    dut.m_axis_0_tready.value = 1

    await RisingEdge(dut.clk)
    cc_total = 0
    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        # sample fz and fp in parallel
        fz_proc = cocotb.start_soon(read_fz(dut, 1))
        fp_proc = cocotb.start_soon(read_fp(dut, 1))
        bench_fz_fp_proc = cocotb.start_soon(bench_fz_fp_seq(dut))

        din = np.random.bytes(BYTES_SEED)
        await set_mode(dut, OPCODE.SAMPLE_FZ_FP)
        await s_axis.send(AxiStreamFrame(din + bytes([0, 0])))
        await s_axis.wait()

        exp_zz, exp_zp = cross.test_zz_zq_vecs(din)


        got_fz = await fz_proc
        if RSDP:
            got_fz = got_fz[:N]
        elif RSDPG:
            got_fz = got_fz[:M]

        # print("Got Fz:")
        # print(got_fz)
        # print("Exp Fz:")
        # print(exp_zz)
        if RSDP:
            assert len(got_fz) == len(exp_zz) == N, "Vector has wrong length: " + str(len(got_fz)) + " expect " + str(N)
        elif RSDPG:
            assert len(got_fz) == len(exp_zz) == M, "Vector has wrong length: " + str(len(got_fz)) + " expect " + str(M)

        for i in range(len(exp_zz)):
            assert got_fz[i] == exp_zz[i], "Wrong zz value at index " + str(i)

        for val in got_fz:
            assert val < Z, "Value >= Z!"

        # sample fp
        got_fp = await fp_proc
        got_fp = got_fp[:N]

        # print("Got Fp:")
        # print(got_fp)
        # print("Exp Fp:")
        # print(exp_zp)
        assert len(got_fp) == len(exp_zp) == N, "Vector has wrong length: " + str(len(got_fp)) + " expect " + str(N)
        for i in range(N):
            assert got_fp[i] == exp_zp[i], "Wrong zp value at index " + str(i)
        for val in got_fp:
            assert val < P, "Value >= P!"

        cc_total += await bench_fz_fp_proc
    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_vt_w_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_w_tready.value = 1
    dut.m_axis_v_beta_tready.value = 1

    await RisingEdge(dut.clk)

    cc_total = 0
    for i in range(ITERATIONS):
        print(f'Iteration {i}:')
        bench_vw_proc = cocotb.start_soon(bench_v_w(dut))

        # sample fz and fp in parallel
        if RSDPG:
            w_proc = cocotb.start_soon(read_w(dut))
        v_proc = cocotb.start_soon(read_v(dut))

        dsc = (3*T + 2).to_bytes(2, byteorder='little')
        din = AxiStreamFrame(np.random.bytes(BYTES_HASH) + dsc)
        await set_mode(dut, OPCODE.SAMPLE_VT_W)
        await s_axis.send(din)
        await s_axis.wait()

        if RSDPG:
            got_w = await w_proc
        got_vt = await v_proc
        exp_vt, exp_w = cross.test_vt_w_mat(din.tdata)

        ##############
        # RSDP case
        ##############
        # print("Got vt:")
        # print(got_vt)
        len_vt = 0
        for vec in got_vt:
            len_vt += len(vec)

        assert len(exp_vt) == len(got_vt), "Wrong number of vectors"
        # print("Exp vt:")
        # print(exp_vt)
        for k in range(K):
            for j in range(N-K):
                assert got_vt[k][j] == exp_vt[k][j], "Wrong element at row " + str(k) + " col " + str(j)

        assert len_vt == (N-K)*K, "Matrix has wrong length: " + str(len_vt) + " expect " + str((N-K)*K)
        for vec in got_vt:
            for val in vec:
                assert val < P, "Not as expected!"

        ##############
        # RSDPG case
        ##############
        if RSDPG:
            # print("Got_W:")
            # print(got_w)
            len_w = 0
            for vec in got_w:
                len_w += len(vec)

            assert len(exp_w) == len(got_w), "Wrong number of vectors"
            # print("Exp_W:")
            # print(exp_w)
            for k in range(M):
                for j in range(N-M):
                    assert got_w[k][j] == exp_w[k][j], "Wrong element at row " + str(k) + " col " + str(j)

            assert len_w == M*(N-M), "Matrix has wrong length: " + str(len_w) + " expect " + str(M*(N-M))
            for vec in got_w:
                for val in vec:
                    assert val < Z, "Not as expected!"

        cc_total += await bench_vw_proc
    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_vt_w_seq_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_w_tready.value = 1
    dut.m_axis_v_beta_tready.value = 1

    await RisingEdge(dut.clk)

    cc_total = 0
    if RSDPG:
        for i in range(ITERATIONS):
            print(f'Iteration {i}:')
            bench_vw_proc = cocotb.start_soon(bench_v_w_seq(dut))

            # sample fz and fp in parallel
            w_proc = cocotb.start_soon(read_w(dut))
            v_proc = cocotb.start_soon(read_v(dut))

            dsc = (3*T + 2).to_bytes(2, byteorder='little')
            din = AxiStreamFrame(np.random.bytes(BYTES_HASH) + dsc)
            await set_mode(dut, OPCODE.SAMPLE_VT_W)
            await s_axis.send(din)
            await s_axis.wait()

            got_w = await w_proc
            got_vt = await v_proc
            exp_vt, exp_w = cross.test_vt_w_mat(din.tdata)

            ##############
            # RSDP case
            ##############
            # print("Got vt:")
            # print(got_vt)
            len_vt = 0
            for vec in got_vt:
                len_vt += len(vec)

            assert len(exp_vt) == len(got_vt), "Wrong number of vectors"
            # print("Exp vt:")
            # print(exp_vt)
            for k in range(K):
                for j in range(N-K):
                    assert got_vt[k][j] == exp_vt[k][j], "Wrong element at row " + str(k) + " col " + str(j)

            assert len_vt == (N-K)*K, "Matrix has wrong length: " + str(len_vt) + " expect " + str((N-K)*K)
            for vec in got_vt:
                for val in vec:
                    assert val < P, "Not as expected!"

            ##############
            # RSDPG case
            ##############
            # print("Got_W:")
            # print(got_w)
            len_w = 0
            for vec in got_w:
                len_w += len(vec)

            assert len(exp_w) == len(got_w), "Wrong number of vectors"
            # print("Exp_W:")
            # print(exp_w)
            for k in range(M):
                for j in range(N-M):
                    assert got_w[k][j] == exp_w[k][j], "Wrong element at row " + str(k) + " col " + str(j)

            assert len_w == M*(N-M), "Matrix has wrong length: " + str(len_w) + " expect " + str(M*(N-M))
            for vec in got_w:
                for val in vec:
                    assert val < Z, "Not as expected!"

            cc_total += await bench_vw_proc
    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_vt_w_hash_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_1 = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_1"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_w_tready.value = 1
    dut.m_axis_v_beta_tready.value = 1
    dut.n_digests.value = 1

    await RisingEdge(dut.clk)

    total_cnt_hash = 0
    for i in range(ITERATIONS):
        print(f'Iteration {i}:')
        # sample fz and fp in parallel
        if RSDPG:
            w_proc = cocotb.start_soon(read_w(dut))
        v_proc = cocotb.start_soon(read_v(dut))

        # Now generate some hashs parallel to sampling w and v
        # Spawn another process to count how many hashes can be
        # generated in parallel to matrix generation.
        cnt_hash_proc = cocotb.start_soon(cnt_hashes(dut))

        dsc = (3*T + 2).to_bytes(2, byteorder='little')
        din = AxiStreamFrame(np.random.bytes(BYTES_HASH) + dsc)
        await set_mode(dut, OPCODE.SAMPLE_VT_W)
        await s_axis.send(din)
        await s_axis.wait()


        N_HASHES = 400
        for _ in range(N_HASHES):
            din_hash = AxiStreamFrame(np.random.bytes(BYTES_HASH))

            if (LAMBDA == 128):
                hash_ref = hashlib.shake_128(bytes(din_hash.tdata))
            else:
                hash_ref = hashlib.shake_256(bytes(din_hash.tdata))
            exp_hash = hash_ref.hexdigest(2*LAMBDA//8)

            # Set sampler mode
            dut.digest_type.value = DIGEST.HASH.value
            await set_mode(dut, OPCODE.SQUEEZE)

            # Send input
            await s_axis.send(din_hash)
            await s_axis.wait()

            got_hash = await m_axis_1.recv()
            got_hash = got_hash.tdata.hex()

            # Check with reference
            # print(f'got_hash: {got_hash}')
            # print(f'exp_hash: {exp_hash}\n')
            assert got_hash == exp_hash, "Hash not as expected!"

        if RSDPG:
            got_w = await w_proc
        got_vt = await v_proc
        exp_vt, exp_w = cross.test_vt_w_mat(din.tdata)

        total_cnt_hash += await cnt_hash_proc

        ##############
        # RSDP case
        ##############
        # print("Got vt:")
        # print(got_vt)
        len_vt = 0
        for vec in got_vt:
            len_vt += len(vec)

        assert len(exp_vt) == len(got_vt), "Wrong number of vectors"
        # print("Exp vt:")
        # print(exp_vt)
        for k in range(K):
            for j in range(N-K):
                assert got_vt[k][j] == exp_vt[k][j], "Wrong element at row " + str(k) + " col " + str(j)

        assert len_vt == (N-K)*K, "Matrix has wrong length: " + str(len_vt) + " expect " + str((N-K)*K)
        for vec in got_vt:
            for val in vec:
                assert val < P, "Not as expected!"

        ##############
        # RSDPG case
        ##############
        if RSDPG:
            # print("Got_W:")
            # print(got_w)
            len_w = 0
            for vec in got_w:
                len_w += len(vec)

            assert len(exp_w) == len(got_w), "Wrong number of vectors"
            # print("Exp_W:")
            # print(exp_w)
            for k in range(M):
                for j in range(N-M):
                    assert got_w[k][j] == exp_w[k][j], "Wrong element at row " + str(k) + " col " + str(j)

            assert len_w == M*(N-M), "Matrix has wrong length: " + str(len_w) + " expect " + str(M*(N-M))
            for vec in got_w:
                for val in vec:
                    assert val < Z, "Not as expected!"

    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = total_cnt_hash//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def sample_unit_beta_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    dut.m_axis_v_beta_tready.value = 1

    await RisingEdge(dut.clk)

    cc_total = 0
    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        dsc = (3*T - 1).to_bytes(2, byteorder='little')
        din = AxiStreamFrame(np.random.bytes(BYTES_HASH) + dsc)
        bench_beta_proc = cocotb.start_soon(bench_beta(dut))
        await set_mode(dut, OPCODE.SAMPLE_BETA)

        # Send input
        await s_axis.send(din)
        await s_axis.wait()

        # Read output
        got = await read_beta(dut)

        # print("Got:")
        # print(got)

        exp = cross.test_beta_vec(din.tdata)
        # print("Exp:")
        # print(exp)
        for i in range(T):
            assert got[i] == exp[i], "Wrong element at index " + str(i)

        assert len(got) == len(exp) == T, "Vector has wrong length: " + str(len(got)) + " expect " + str(T)
        for val in got:
            assert val < P and val > 0, "Not as expected!"
        cc_total += await bench_beta_proc

    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg},')
        bench_file.flush()


@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def b_test(dut):
    s_axis = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sha3"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    # Initial reset
    await reset(dut)
    await RisingEdge(dut.clk)

    dut.m_axis_b_tready.value = 1

    cc_total = 0
    for j in range(ITERATIONS):
        print(f'Iteration {j}:')
        dsc = (3*T).to_bytes(2, byteorder='little')
        din = AxiStreamFrame(np.random.bytes(BYTES_HASH) + dsc)
        bench_b_proc = cocotb.start_soon(bench_b(dut))
        await set_mode(dut, OPCODE.SAMPLE_B)


        # Send input
        await s_axis.send(din)
        await s_axis.wait()

        got = await read_b(dut)

        hw = 0
        got = got[:T]
        for bit in got:
            hw += int(bit,2)

        # print(f"HW: {hw}")
        # print(f'Got: {got}')
        exp = cross.test_b_vec(din.tdata)
        hw_exp = 0
        for bit in exp:
            hw_exp += int(bit,2)
        # print(f"HW_Exp: {hw_exp}")
        # print(f"Exp: {exp}")

        assert hw == hw_exp, "different hamming weight"

        for i in range(T):
            assert got[i] == exp[i], "Wrong value at index " + str(i)

        assert len(got) == len(exp) == T, "Vector has wrong length: " + str(len(got)) + " expect " + str(T)
        assert hw == W, "Wrong hamming weight!"
        cc_total += await bench_b_proc

    with open(f'sample_{variant}_{cat}_{tar}.csv', 'a') as bench_file:
        avg = cc_total//ITERATIONS
        bench_file.write(f'{avg}\n')
        bench_file.flush()
