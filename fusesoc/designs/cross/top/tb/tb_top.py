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

import binascii
import os
from enum import Enum
from math import ceil, log

import cocotb
import cross
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

ITERATIONS = int(os.getenv("TB_ITERATIONS", 2))

class OPCODE(Enum):
    OP_KEYGEN = 0
    OP_SIGN = 1
    OP_VERIFY = 2

class STATE(Enum):
    S_IDLE = 0
    S_STORE_SK = 1
    S_EXPAND_SK = 2
    S_SAMPLE_VT_W = 3
    S_SAMPLE_ETA_ZETA = 4

CLIB_VERSION = os.environ.get("CLIB")
T = int(os.environ.get("T"))
W = int(os.environ.get("W"))
N = int(os.environ.get("N"))
P = int(os.environ.get("P"))
TNODES = int(os.environ.get("TNODES"))
BITS_P = int(ceil(log(P, 2)))
LAMBDA = int(os.environ.get("LAMBDA"))
BYTES_SEED = LAMBDA//8
BYTES_HASH = 2*LAMBDA//8
WPS = (BYTES_SEED+7)//8
WPH = (BYTES_HASH+7)//8

rsdpg = False
variant = 'rsdp'
if 'RSDPG' in CLIB_VERSION:
    rsdpg = True
    variant = 'rsdpg'

if LAMBDA == 128:
    cat = 'cat1'
elif LAMBDA == 192:
    cat = 'cat3'
else:
    cat = 'cat5'

if 'SPEED' in CLIB_VERSION:
    tar = 'fast'
elif 'BALANCED' in CLIB_VERSION:
    tar = 'balanced'
else:
    tar = 'small'


async def read_test_status(dut, m_axis):
    test = await m_axis.recv()
    test = test.tdata

    # extract cc
    cc = 0
    for i in range(3):
        cc += test[i] << (8*i)

    # extract status
    stat = test[3]

    # extract cc of online phase
    cc_online = 0
    for i in range(3):
        cc_online += test[4+i] << (8*i)
    return stat, cc, cc_online

async def reset(dut):
	dut.rst_n.value = 0
	await Timer(22, units="ns")
	dut.rst_n.value = 1
	await Timer(73, units="ns")
	return

async def send_opcode(dut, op):
    dut.cross_op.value = op
    dut.cross_op_valid.value = 1
    await RisingEdge(dut.clk)
    while not (dut.cross_op_valid.value and dut.cross_op_ready.value):
        await RisingEdge(dut.clk)
    dut.cross_op_valid.value = 0
    await RisingEdge(dut.clk)
    return

async def read_keys(dut, m_axis):
    sk_seed = await m_axis.recv()
    pk_seed = await m_axis.recv()
    pk_syn = await m_axis.recv()
    return sk_seed, pk_seed, pk_syn

async def read_sig(dut, m_axis):
    sig = []
    for _ in range(5 + 2*TNODES):
        tmp = await m_axis.recv()
        sig += tmp.tdata
    return sig

async def send_pk_msg_vrfy(dut, pk_seed, pk_syn, msg, s_axis):
    pk = pk_seed + pk_syn
    await s_axis.send(pk)
    await s_axis.send(msg)
    await s_axis.wait()
    return


async def read_vrfy(dut):
    while(True):
        await RisingEdge(dut.clk)
        if (dut.cross_op_done.value):
            return int(dut.cross_op_done_val.value)

@cocotb.test(timeout_time=20*ITERATIONS, timeout_unit="ms")
async def test_keygen(dut):
    s_axis_rng = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_rng"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_sig_keys = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_sig_keys"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    await reset(dut)

    for _ in range(ITERATIONS):
        proc_result = cocotb.start_soon(read_keys(dut, m_axis_sig_keys))
        await send_opcode(dut, OPCODE.OP_KEYGEN.value)

        # Now send sk_seed
        coins = AxiStreamFrame(np.random.bytes(2*BYTES_SEED))
        await s_axis_rng.send(coins)
        await s_axis_rng.wait()

        # C reference keys
        sk_seed_exp, pk_seed_exp, pk_syn_exp = cross.test_keygen(coins)

        # Generated keys
        sk_seed_got, pk_seed_got, pk_syn_got = await proc_result

        assert binascii.hexlify(sk_seed_got.tdata) == binascii.hexlify(bytearray(sk_seed_exp)), "SK_SEED does not match!"
        assert binascii.hexlify(pk_seed_got.tdata) == binascii.hexlify(bytearray(pk_seed_exp)), "PK_SEED does not match!"
        assert binascii.hexlify(pk_syn_got.tdata) == binascii.hexlify(bytearray(pk_syn_exp)), "PK_SYN does not match!"

        status,cc,cc_online = await read_test_status(dut, m_axis_sig_keys)
        if (status == 0):
            dut._log.info(f'Keygen took {cc} cycles!')
            dut._log.info(f'Keygen online phase took {cc_online} cycles!')


@cocotb.test(timeout_time=30*ITERATIONS, timeout_unit="ms")
async def test_sign(dut):
    s_axis_rng = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_rng"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_msg_keys = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_msg_keys"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_sig_keys = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_sig_keys"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    for j in range(ITERATIONS):
        proc_result = cocotb.start_soon(read_sig(dut, m_axis_sig_keys))
        await send_opcode(dut, OPCODE.OP_SIGN.value)


        # C reference keygen, also send sk to hw
        msg = np.random.bytes(16)
        sk_seed,_,_ = cross.test_keygen(np.random.bytes(2*BYTES_SEED))

        # Send sk_seed and msg
        s_axis_msg_keys.send_nowait(sk_seed+list(msg))

        # Now send mseed and salt that are randomly generated
        coins = np.random.bytes(3*BYTES_SEED)
        s_axis_rng.send_nowait(AxiStreamFrame(coins))

        # C reference signature
        sig_exp = cross.test_sign(sk_seed, msg, AxiStreamFrame(coins))

        # Generated sig
        sig_got = await proc_result

        assert len(sig_got) == len(sig_exp), "Signatures have different lengths!"
        for i in range(len(sig_exp)):
            assert sig_got[i] == sig_exp[i], "Signatures do not match in bytes " + str(i) + " in iteration " + str(j) + "!"

        status,cc,cc_online = await read_test_status(dut, m_axis_sig_keys)
        if (status == 0):
            dut._log.info(f'Sign took {cc} cycles!')
            dut._log.info(f'Sign online phase took {cc_online} cycles!')


@cocotb.test(timeout_time=30*ITERATIONS, timeout_unit="ms")
async def test_verify(dut):
    s_axis_msg_keys = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_msg_keys"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_sig_keys = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_sig_keys"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    for _ in range(ITERATIONS):
        proc_result = cocotb.start_soon(read_vrfy(dut))
        await send_opcode(dut, OPCODE.OP_VERIFY.value)

        # C reference keygen and sign
        msg = AxiStreamFrame(np.random.bytes(16))
        sk_seed, pk_seed, pk_syn = cross.test_keygen(AxiStreamFrame(np.random.bytes(2*BYTES_SEED)))
        sig_exp = cross.test_sign(sk_seed, msg, AxiStreamFrame(np.random.bytes(3*BYTES_SEED)))

        # Send the public key and message to be signed
        proc_send_pk = cocotb.start_soon(send_pk_msg_vrfy(dut, pk_seed, pk_syn, msg, s_axis_msg_keys))

        # Send the signature
        await s_axis_sig.send(sig_exp)
        await s_axis_sig.wait()

        # C reference verification, returns 0 if everything is ok (accept), 1 if there's an error (reject)
        vrfy_exp = cross.test_vrfy(pk_seed + pk_syn, msg, sig_exp)

        # HW dut verification
        vrfy_got = await proc_result
        await proc_send_pk

        assert vrfy_got == vrfy_exp, "Verification results do not match!"
        assert vrfy_got == 0, "Verification rejects but should accept!"

        status,cc,cc_online = await read_test_status(dut, m_axis_sig_keys)
        if (status == 0):
            dut._log.info(f'Verification took {cc} cycles!')
            dut._log.info(f'Verification online phase took {cc_online} cycles!')


@cocotb.test(timeout_time=30*ITERATIONS, timeout_unit="ms")
async def test_verify_invalid(dut):
    s_axis_msg_keys = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_msg_keys"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_sig = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_sig"), dut.clk, dut.rst_n, reset_active_level=False)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    for _ in range(ITERATIONS):
        proc_result = cocotb.start_soon(read_vrfy(dut))
        await send_opcode(dut, OPCODE.OP_VERIFY.value)

        # C reference keygen and sign
        msg = AxiStreamFrame(np.random.bytes(16))
        sk_seed, pk_seed, pk_syn = cross.test_keygen(AxiStreamFrame(np.random.bytes(2*BYTES_SEED)))
        sig_exp = cross.test_sign(sk_seed, msg, AxiStreamFrame(np.random.bytes(3*BYTES_SEED)))

        # Send the public key and message to be signed
        proc_send_pk = cocotb.start_soon(send_pk_msg_vrfy(dut, pk_seed, pk_syn, msg, s_axis_msg_keys))

        # Send the signature, but flip a random bit
        rnd_idx = np.random.randint(0, len(sig_exp))
        sig_exp[rnd_idx] = sig_exp[rnd_idx] ^ (1 << np.random.randint(0, 8))
        await s_axis_sig.send(sig_exp)
        await s_axis_sig.wait()

        # C reference verification, returns 0 if everything is ok (accept), 1 if there's an error (reject)
        vrfy_exp = cross.test_vrfy(pk_seed + pk_syn, msg, sig_exp)

        # HW dut verification
        vrfy_got = await proc_result
        await proc_send_pk

        assert vrfy_got == vrfy_exp, "Verification results do not match!"
        assert vrfy_got == 1, "Signature should be rejected but is accepted!"


###############################################################################################
# Benchmarking utilities to analyze the activity of certain submodules
###############################################################################################
def sampler_en(dut):
    fz_w_en = 0
    if rsdpg:
        fz_w_en = (dut.u_top.u_sample_wrapper.u_sample_unit.fz_w_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_fz_sample.bits_in_buf.value) > 0)
    if ((dut.u_top.u_sample_wrapper.u_sample_unit.fz_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_fz_sample.bits_in_buf.value) > 0) \
        or (dut.u_top.u_sample_wrapper.u_sample_unit.fp_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_fp_sample.bits_in_buf.value) > 0) \
        or (dut.u_top.u_sample_wrapper.u_sample_unit.fp_v_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_fp_sample.bits_in_buf.value) > 0) \
        or (fz_w_en) \
        or (dut.u_top.u_sample_wrapper.u_sample_unit.beta_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_fp_sample.bits_in_buf.value) > 0) \
        or (dut.u_top.u_sample_wrapper.u_sample_unit.b_en.value and int(dut.u_top.u_sample_wrapper.u_sample_unit.u_b_sample.state.value) in {1, 2, 3})):
        return 1
    else:
        return 0

def squeeze_en(dut):
    if (int(dut.u_top.u_sample_wrapper.u_sample_unit.u_sha3.state_q.value) in {1, 2, 3} \
        and dut.u_top.u_sample_wrapper.u_sample_unit.squeeze_en.value):
        return 1
    else:
        return 0

async def get_keccak_cnt(dut):
    cnt = 0

    while(True):
        await RisingEdge(dut.clk)
        # Cnt cycles where the Keccak core is padding, permuting or squeezing (pad, permute, squeeze)
        if squeeze_en(dut):
            cnt += 1

        # If keygen, sign or verify terminated, return
        if (dut.cross_op_done.value):
            return cnt

async def get_sample_cnt(dut):
    cnt = 0

    fz_w_en = 0

    while(True):
        await RisingEdge(dut.clk)
        if (sampler_en(dut)):
            cnt += 1

        # If keygen, sign or verify terminated, return
        if (dut.cross_op_done.value):
            return cnt

async def get_alu_cnt(dut):
    cnt0 = cnt1 = 0

    while(True):
        await RisingEdge(dut.clk)
        # Get cycles where alu is not idle but sampling is done
        if (int(dut.u_top.u_alu_wrapper.u_alu.state_q.value) != 0):
            if not ( sampler_en(dut) or squeeze_en(dut) ):
                cnt0 += 1
            else:
                cnt1 += 1

        # If keygen, sign or verify terminated, return
        if (dut.cross_op_done.value):
            return cnt0, cnt1

async def get_rsp2_cnt(dut):
    cnt = 0

    while(True):
        await RisingEdge(dut.clk)
        # Check for packing states
        if rsdpg and int(dut.u_top.state.value) in {17, 18} \
        or not rsdpg and int(dut.u_top.state.value) in {16, 17}:
            cnt += 1

        # If keygen, sign or verify terminated, return
        if (dut.cross_op_done.value):
            return cnt

async def get_stream_cnt(dut):
    cnt = 0

    while(True):
        await RisingEdge(dut.clk)
        # Check for streaming states
        if rsdpg and int(dut.u_top.state.value) in {19} \
        or not rsdpg and int(dut.u_top.state.value) in {18}:
            cnt += 1

        # If keygen, sign or verify terminated, return
        if (dut.cross_op_done.value):
            return cnt

async def get_cnt_ops(dut):
    proc_cc_keccak = cocotb.start_soon(get_keccak_cnt(dut))
    proc_cc_sampling = cocotb.start_soon(get_sample_cnt(dut))
    proc_cc_alu = cocotb.start_soon(get_alu_cnt(dut))
    proc_cc_rsp2 = cocotb.start_soon(get_rsp2_cnt(dut))
    proc_cc_stream = cocotb.start_soon(get_stream_cnt(dut))
    cc_keccak = await proc_cc_keccak
    cc_sample = await proc_cc_sampling
    cc_alu0, cc_alu1 = await proc_cc_alu
    cc_rsp2 = await proc_cc_rsp2
    cc_stream = await proc_cc_stream
    return cc_keccak, cc_sample, cc_alu0, cc_alu1, cc_rsp2, cc_stream



@cocotb.test(timeout_time=30*ITERATIONS, timeout_unit="ms")
async def test_sign_bench_ops(dut):
    s_axis_rng = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_rng"), dut.clk, dut.rst_n, reset_active_level=False)
    s_axis_msg_keys = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis_msg_keys"), dut.clk, dut.rst_n, reset_active_level=False)
    m_axis_sig_keys = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_sig_keys"), dut.clk, dut.rst_n, reset_active_level=False)
    np.random.seed(0)

    """Try accessing the design."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    await reset(dut)

    for j in range(1):
        proc_result = cocotb.start_soon(read_sig(dut, m_axis_sig_keys))
        proc_cc_ops = cocotb.start_soon(get_cnt_ops(dut))
        await send_opcode(dut, OPCODE.OP_SIGN.value)


        # C reference keygen, also send sk to hw
        msg = np.random.bytes(16)
        sk_seed,_,_ = cross.test_keygen(np.random.bytes(2*BYTES_SEED))

        # Send sk_seed and msg
        s_axis_msg_keys.send_nowait(sk_seed+list(msg))

        # Now send mseed and salt that are randomly generated
        coins = np.random.bytes(3*BYTES_SEED)
        s_axis_rng.send_nowait(AxiStreamFrame(coins))

        # C reference signature
        sig_exp = cross.test_sign(sk_seed, msg, AxiStreamFrame(coins))

        # Generated sig
        sig_got = await proc_result
        cc_keccak, cc_sampling, cc_alu, cc_alu_sample, cc_rsp2, cc_stream = await proc_cc_ops
        cc_sum = cc_keccak + cc_sampling + cc_alu + cc_rsp2 + cc_stream

        assert len(sig_got) == len(sig_exp), "Signatures have different lengths!"
        for i in range(len(sig_exp)):
            assert sig_got[i] == sig_exp[i], "Signatures do not match in bytes " + str(i) + " in iteration " + str(j) + "!"

        status,cc,cc_online = await read_test_status(dut, m_axis_sig_keys)
        if (status == 0):
            dut._log.info(f'Sign took {cc} cycles!')
            dut._log.info(f'Sign online phase took {cc_online} cycles!\n')
            dut._log.info(f'Keccak padding, permutation and squeezing took {cc_keccak} cycles - {cc_keccak/cc:.02%}')
            dut._log.info(f'All rejection sampling ops took {cc_sampling} cycles - {cc_sampling/cc:.02%}')
            dut._log.info(f'Total sample unit {cc_keccak+cc_sampling} cycles - {(cc_keccak+cc_sampling)/cc:.02%}')
            dut._log.info(f'ALU active while sampling unit is idle accounts for {cc_alu} cycles - {cc_alu/cc:.02%}')
            dut._log.info(f'Packing the signature depending on chall_2 took {cc_rsp2} cycles - {cc_rsp2/cc:.02%}')
            dut._log.info(f'Streaming sig out took {cc_stream} cycles - {cc_stream/cc:.02%}')
            dut._log.info(f'-----------\nSums up to {cc_sum} cycles - about {cc_sum/cc:.02%} of total cycles!\n')
            dut._log.info(f'-----------\nFurther measurements:\n')
            dut._log.info(f'ALU active while sampling unit is active accounts for {cc_alu_sample} cycles - {cc_alu_sample/cc:.02%}')
            dut._log.info(f'Total ALU activity {cc_alu+cc_alu_sample} cycles - {(cc_alu+cc_alu_sample)/cc:.02%}')
            with open(f'bench_{variant}_{cat}_{tar}.csv', 'w') as f:
                f.write('param,total,cc_keccak,cc_rej,cc_alu_sample_idle,sig_packing,sig_stream,rest\n')
                f.write(f'{variant}_{cat}_{tar},{cc},{cc_keccak},{cc_sampling},{cc_alu},{cc_rsp2},{cc_stream},{cc-cc_sum}\n')
                f.flush()
