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
import random
import sys
from enum import IntEnum, auto
from os import environ, getenv
from pathlib import Path
from typing import Optional

import cocotb
import galois
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Combine, RisingEdge
from cocotb.utils import get_sim_time
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource

sys.path.insert(0, str(Path(".").resolve()))
from cocotb_utils import cycle_reset, memory_generator, random_generator, sampler_generator

random.seed(cocotb.RANDOM_SEED)
np.random.seed(cocotb.RANDOM_SEED)

log = logging.getLogger("cocotb.tb")
log.setLevel(logging.DEBUG)


class ArithOp(IntEnum):
    ARITH_OP_INIT = 0
    ARITH_OP_KEYGEN = auto()
    ARITH_OP_SIGN_EXPAND_ETA = auto()
    ARITH_OP_SIGN_COMMITMENTS_PREPARATION = auto()
    ARITH_OP_SIGN_FIRST_ROUND_RESPONSES = auto()
    ARITH_OP_VERIFY_CASE_B0 = auto()
    ARITH_OP_VERIFY_CASE_B1 = auto()


async def arith_op_keygen(
    rsdpg: bool,
    GEN: int,
    P: int,
    Z: int,
    N: int,
    K: int,
    V: np.typing.NDArray,
    eta_or_zeta: np.typing.NDArray,
    M: int = 0,
    W: Optional[np.typing.NDArray] = None,
) -> np.typing.NDArray:
    # Setup objects and expand elements
    GF_p = galois.GF(P)
    H = np.concatenate([V, np.identity(N - K, dtype=np.int32)], axis=0)
    if rsdpg:
        zeta = eta_or_zeta
        Mg = np.concatenate([W, np.identity(M, dtype=np.int32)], axis=1)
        log.debug(f"W: {W}")
    else:
        eta = eta_or_zeta

    # Begin algorithm
    if rsdpg:
        eta = np.mod(np.matmul(zeta, Mg), Z)
    e = [int(GF_p(GEN) ** i) for i in eta]
    log.debug(f"e: {e}")
    s = np.mod(np.matmul(e, H), P)
    log.debug(f"s: {s}")

    return s


async def arith_op_sign_commitments_preparation(
    rsdpg: bool,
    GEN: int,
    P: int,
    Z: int,
    N: int,
    K: int,
    T: int,
    V: np.typing.NDArray,
    eta_or_zeta: np.typing.NDArray,
    eta_or_zeta_prime: list[np.typing.NDArray],
    u_prime: list[np.typing.NDArray],
    M: int = 0,
    W: Optional[np.typing.NDArray] = None,
) -> tuple[list[np.typing.NDArray], list[np.typing.NDArray]]:
    assert len(eta_or_zeta_prime) == T, "Incorrect number of eta_prime/zeta_prime vectors"
    assert len(u_prime) == T, "Incorrect number of u_prime vectors"

    # Setup objects and expand elements
    GF_p = galois.GF(P)
    H = np.concatenate([V, np.identity(N - K, dtype=np.int32)], axis=0)
    if rsdpg:
        Mg = np.concatenate([W, np.identity(M, dtype=np.int32)], axis=1)
        zeta = eta_or_zeta
        zeta_prime = eta_or_zeta_prime
    else:
        eta = eta_or_zeta
        eta_prime = eta_or_zeta_prime

    # Begin algorithm
    if rsdpg:
        eta = np.mod(np.matmul(zeta, Mg), Z)  # this is done in a separate FSM state
        eta_prime = []
        delta = []
        for k in range(T):
            assert len(zeta_prime[k]) == M, "Incorrect size of zeta_prime vector"

            eta_prime += [np.mod(np.matmul(zeta_prime[k], Mg), Z)]
            delta += [np.mod(zeta - zeta_prime[k], Z)]
        log.debug(f"delta: {delta}")

    sigma: list[np.typing.NDArray] = []
    s_tilde: list[np.typing.NDArray] = []
    for k in range(T):
        assert len(u_prime[k]) == N, "Incorrect size of u_prime vector"

        sigma += [np.mod(eta - eta_prime[k], Z)]
        v = [int(GF_p(GEN) ** i) for i in sigma[k]]
        log.debug(f"v[{k}]: {v}")
        u = np.mod(np.multiply(v, u_prime[k]), P)
        log.debug(f"u[{k}]: {u}")
        s_tilde += [np.mod(np.matmul(u, H), P)]
    log.debug(f"sigma: {sigma}")
    log.debug(f"s tilde: {s_tilde}")

    return s_tilde, (delta if rsdpg else sigma)


async def arith_op_sign_first_round_responses(
    GEN: int,
    P: int,
    N: int,
    T: int,
    beta: np.typing.NDArray,
    eta_prime: list[np.typing.NDArray],
    u_prime: list[np.typing.NDArray],
) -> list[np.typing.NDArray]:
    assert len(beta) == T, "Incorrect size of beta vector"
    assert len(eta_prime) == T, "Incorrect number of eta_prime vectors"
    assert len(u_prime) == T, "Incorrect number of u_prime vectors"

    # Setup objects and expand elements
    GF_p = galois.GF(P)

    # Begin algorithm
    y: list[np.typing.NDArray] = []
    for k in range(T):
        assert isinstance(beta[k], np.int32)
        assert len(eta_prime[k]) == N, "Incorrect size of eta_prime vector"
        assert len(u_prime[k]) == N, "Incorrect size of u_prime vector"

        e_prime = [int(GF_p(GEN) ** i) for i in eta_prime[k]]
        log.debug(f"e prime[{k}]: {e_prime}")
        be = np.mod(np.multiply(np.resize(beta[k], N), e_prime), P)
        log.debug(f"beta[{k}]*e prime[{k}]: {be}")
        y += [np.mod(u_prime[k] + be, P)]
    log.debug(f"y: {y}")

    return y


async def arith_op_verify_case_b0(
    rsdpg: bool,
    GEN: int,
    P: int,
    Z: int,
    N: int,
    K: int,
    T: int,
    V: np.typing.NDArray,
    beta: np.typing.NDArray,
    delta_or_sigma: list[np.typing.NDArray],
    y: list[np.typing.NDArray],
    s: np.typing.NDArray,
    M: int = 0,
    W: Optional[np.typing.NDArray] = None,
) -> list[np.typing.NDArray]:
    assert len(beta) == T, "Incorrect size of beta vector"
    assert len(y) == T, "Incorrect number of y vectors"
    assert len(delta_or_sigma) == T, "Incorrect number of delta/sigma vectors"

    # Setup objects and expand elements
    GF_p = galois.GF(P)
    H = np.concatenate([V, np.identity(N - K, dtype=np.int32)], axis=0)
    if rsdpg:
        Mg = np.concatenate([W, np.identity(M, dtype=np.int32)], axis=1)

    # Begin algorithm
    s_tilde: list[np.typing.NDArray] = []
    for k in range(T):
        assert isinstance(beta[k], np.int32)
        assert len(y[k]) == N, "Incorrect size of y vector"

        if rsdpg:
            assert len(delta_or_sigma[k]) == M, "Incorrect size of delta vector"
            sigma = np.mod(np.matmul(delta_or_sigma[k], Mg), Z)
        else:
            assert len(delta_or_sigma[k]) == N, "Incorrect size of sigma vector"
            sigma = delta_or_sigma[k]

        v = [int(GF_p(GEN) ** i) for i in sigma]
        log.debug(f"v[{k}]: {v}")
        y_prime = np.mod(np.multiply(v, y[k]), P)
        log.debug(f"y prime[{k}]: {y_prime}")
        bs = np.mod(np.multiply(np.resize(beta[k], N - K), s), P)
        log.debug(f"beta[{k}] * s: {bs}")
        yph = np.mod(np.matmul(y_prime, H), P)
        log.debug(f"y prime[{k}] * V: {yph}")
        s_tilde += [np.mod(yph - bs, P)]
        log.debug(f"s tilde[{k}]: {s_tilde}")

    return s_tilde


async def arith_op_verify_case_b1(
    rsdpg: bool,
    GEN: int,
    P: int,
    Z: int,
    N: int,
    T: int,
    beta: np.typing.NDArray,
    eta_or_zeta_prime: list[np.typing.NDArray],
    u_prime: list[np.typing.NDArray],
    M: int = 0,
    W: Optional[np.typing.NDArray] = None,
) -> list[np.typing.NDArray]:
    assert len(beta) == T, "Incorrect size of beta vector"
    assert len(eta_or_zeta_prime) == T, "Incorrect number of eta_prime/zeta_prime vectors"
    assert len(u_prime) == T, "Incorrect number of u_prime vectors"

    # Setup objects and expand elements
    GF_p = galois.GF(P)
    if rsdpg:
        Mg = np.concatenate([W, np.identity(M, dtype=np.int32)], axis=1)

    # Begin algorithm
    y: list[np.typing.NDArray] = []
    for k in range(T):
        assert isinstance(beta[k], np.int32)
        assert len(u_prime[k]) == N, "Incorrect size of u_prime vector"

        if rsdpg:
            assert len(eta_or_zeta_prime[k]) == M, "Incorrect size of zeta_prime vector"
            eta_prime = np.mod(np.matmul(eta_or_zeta_prime[k], Mg), Z)
        else:
            assert len(eta_or_zeta_prime[k]) == N, "Incorrect size of eta_prime vector"
            eta_prime = eta_or_zeta_prime[k]

        e_prime = [int(GF_p(GEN) ** i) for i in eta_prime]
        log.debug(f"e prime[{k}]: {e_prime}")
        be = np.mod(np.multiply(np.resize(beta[k], N), e_prime), P)
        log.debug(f"beta[{k}] * e prime[{k}]: {be}")
        y += [np.mod(u_prime[k] + be, P)]
        log.debug(f"y[{k}]: {y}")

    return y


async def run_test(
    dut,
    arith_op: ArithOp,
    eta: np.typing.NDArray,
    eta_prime: list[np.typing.NDArray],
    u_prime: list[np.typing.NDArray],
    beta: np.typing.NDArray,
    s: np.typing.NDArray,
    y: list[np.typing.NDArray],
    s_tilde: list[np.typing.NDArray],
    V: np.typing.NDArray,
    iteration: int = 0,
    zeta: Optional[np.typing.NDArray] = None,
    zeta_prime: Optional[list[np.typing.NDArray]] = None,
    delta: Optional[list[np.typing.NDArray]] = None,
    sigma: Optional[list[np.typing.NDArray]] = None,
    W: Optional[np.typing.NDArray] = None,
):
    log.info(f"Running test for arithmetic operation {arith_op.name}")

    if zeta_prime is None:
        zeta_prime = []
    if delta is None:
        delta = []
    if sigma is None:
        sigma = []
    if zeta is None:
        zeta = np.empty(0, np.int32)
    if W is None:
        W = np.empty(0, np.int32)

    # waiting for cocotb/cocotb#3536 to land in v2.0
    # MODULO = int(cocotb.packages.cross_pkg.Z.value)
    # N = int(cocotb.packages.cross_pkg.N.value)
    # K = int(cocotb.packages.cross_pkg.K.value)
    # M = int(cocotb.packages.cross_pkg.M.value)

    RSDPG = int(dut.RSDPG.value)
    P = int(dut.P.value)
    Z = int(dut.Z.value)

    in_0_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "in_0"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    in_1_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "in_1"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    in_2_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "in_2"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    in_3_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "in_3"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    if RSDPG:
        in_4_source = AxiStreamSource(
            bus=AxiStreamBus.from_prefix(dut, "in_4"),
            clock=dut.clk_i,
            reset=dut.rst_n,
            reset_active_level=False,
        )
    in_5_source = AxiStreamSource(
        bus=AxiStreamBus.from_prefix(dut, "in_5"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )

    out_0_sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "out_0"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    out_1_sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "out_1"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )
    out_2_sink = AxiStreamSink(
        bus=AxiStreamBus.from_prefix(dut, "out_2"),
        clock=dut.clk_i,
        reset=dut.rst_n,
        reset_active_level=False,
    )

    # Assemble the expected outputs
    expected_outputs: list[np.typing.NDArray] = []
    if arith_op == ArithOp.ARITH_OP_INIT:
        expected_outputs = []
    elif arith_op == ArithOp.ARITH_OP_KEYGEN:
        expected_outputs += [s.flatten()]
    elif arith_op == ArithOp.ARITH_OP_SIGN_EXPAND_ETA:
        if RSDPG:
            expected_outputs += [eta.flatten()]
    elif arith_op == ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION:
        if RSDPG:
            expected_outputs += [s_tilde[iteration].flatten(), delta[iteration].flatten()]
        else:
            expected_outputs += [s_tilde[iteration].flatten(), sigma[iteration].flatten()]
    elif arith_op == ArithOp.ARITH_OP_SIGN_FIRST_ROUND_RESPONSES:
        expected_outputs += [y[iteration].flatten()]
    elif arith_op == ArithOp.ARITH_OP_VERIFY_CASE_B0:
        expected_outputs += [s_tilde[iteration].flatten()]
    elif arith_op == ArithOp.ARITH_OP_VERIFY_CASE_B1:
        expected_outputs += [y[iteration].flatten()]

    #######################
    ### DUT computation ###
    #######################
    await ClockCycles(dut.clk_i, 5)
    dut.op_i.value = arith_op.value
    dut.start_i.value = 1

    await ClockCycles(dut.clk_i, 1)
    dut.start_i.value = 0
    dut.op_i.value = ArithOp.ARITH_OP_INIT

    input_tasks: list[cocotb.task.Task] = []
    output_tasks: list[cocotb.task.Task] = []

    # send all the operand vectors in parallel
    if arith_op == ArithOp.ARITH_OP_INIT:
        in_0_source.set_pause_generator(sampler_generator(P, in_0_source.byte_lanes))
        for row in V.tolist():
            in_0_source.send_nowait(AxiStreamFrame(tdata=row))
        input_tasks += [
            cocotb.start_soon(in_0_source.wait()),
        ]
        if RSDPG:
            in_4_source.set_pause_generator(sampler_generator(Z, in_4_source.byte_lanes))
            for row in W.tolist():
                in_4_source.send_nowait(AxiStreamFrame(tdata=row))
            input_tasks += [
                cocotb.start_soon(in_4_source.wait()),
            ]

        output_tasks += []

    elif arith_op == ArithOp.ARITH_OP_KEYGEN:
        in_1_source.set_pause_generator(sampler_generator(Z, in_1_source.byte_lanes))

        if RSDPG:
            in_1_source.send_nowait(AxiStreamFrame(tdata=zeta.tolist()))
        else:
            in_1_source.send_nowait(AxiStreamFrame(tdata=eta.tolist()))

        out_0_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

        input_tasks += [
            cocotb.start_soon(in_1_source.wait()),
        ]
        output_tasks += [cocotb.start_soon(out_0_sink.recv())]

    elif arith_op == ArithOp.ARITH_OP_SIGN_EXPAND_ETA:
        if RSDPG:
            in_1_source.send_nowait(AxiStreamFrame(tdata=zeta.tolist()))
            out_2_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
            input_tasks += [
                cocotb.start_soon(in_1_source.wait()),
            ]
            output_tasks += [cocotb.start_soon(out_2_sink.recv())]

    elif arith_op == ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION:
        in_1_source.set_pause_generator(sampler_generator(Z, in_1_source.byte_lanes))
        in_3_source.set_pause_generator(sampler_generator(P, in_3_source.byte_lanes))
        in_5_source.set_pause_generator(memory_generator())

        if RSDPG:
            in_1_source.send_nowait(AxiStreamFrame(tdata=zeta_prime[iteration].tolist()))
            in_5_source.send_nowait(AxiStreamFrame(tdata=zeta.tolist()))
        else:
            in_1_source.send_nowait(AxiStreamFrame(tdata=eta_prime[iteration].tolist()))
            in_5_source.send_nowait(AxiStreamFrame(tdata=eta.tolist()))
        in_3_source.send_nowait(AxiStreamFrame(tdata=u_prime[iteration].tolist()))

        if RSDPG:
            in_5_source.send_nowait(AxiStreamFrame(tdata=eta.tolist()))

        out_0_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation
        out_2_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

        input_tasks += [
            cocotb.start_soon(in_1_source.wait()),
            cocotb.start_soon(in_5_source.wait()),
            cocotb.start_soon(in_3_source.wait()),
        ]
        output_tasks += [cocotb.start_soon(out_0_sink.recv()), cocotb.start_soon(out_2_sink.recv())]

    elif arith_op == ArithOp.ARITH_OP_SIGN_FIRST_ROUND_RESPONSES:
        in_0_source.set_pause_generator(sampler_generator(P, in_0_source.byte_lanes))
        in_2_source.set_pause_generator(memory_generator())

        in_0_source.send_nowait(AxiStreamFrame(tdata=[beta[iteration].item()]))
        in_2_source.send_nowait(AxiStreamFrame(tdata=u_prime[iteration].tolist()))

        out_1_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

        input_tasks += [
            cocotb.start_soon(in_0_source.wait()),
            cocotb.start_soon(in_2_source.wait()),
        ]
        output_tasks += [cocotb.start_soon(out_1_sink.recv())]

    elif arith_op == ArithOp.ARITH_OP_VERIFY_CASE_B0:
        in_0_source.set_pause_generator(sampler_generator(P, in_0_source.byte_lanes))
        in_1_source.set_pause_generator(memory_generator())
        in_2_source.set_pause_generator(memory_generator())
        in_3_source.set_pause_generator(memory_generator())

        in_0_source.send_nowait(AxiStreamFrame(tdata=[beta[iteration].item()]))
        if RSDPG:
            in_1_source.send_nowait(AxiStreamFrame(tdata=delta[iteration].tolist()))
        else:
            in_1_source.send_nowait(AxiStreamFrame(tdata=sigma[iteration].tolist()))
        in_2_source.send_nowait(AxiStreamFrame(tdata=s.tolist()))
        in_3_source.send_nowait(AxiStreamFrame(tdata=y[iteration].tolist()))

        out_0_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

        input_tasks += [
            cocotb.start_soon(in_1_source.wait()),
            cocotb.start_soon(in_2_source.wait()),
            cocotb.start_soon(in_3_source.wait()),
        ]
        output_tasks += [cocotb.start_soon(out_0_sink.recv())]

    elif arith_op == ArithOp.ARITH_OP_VERIFY_CASE_B1:
        in_0_source.set_pause_generator(sampler_generator(P, in_0_source.byte_lanes))
        in_1_source.set_pause_generator(sampler_generator(Z, in_1_source.byte_lanes))
        in_2_source.set_pause_generator(sampler_generator(P, in_2_source.byte_lanes))

        in_0_source.send_nowait(AxiStreamFrame(tdata=[beta[iteration].item()]))
        if RSDPG:
            in_1_source.send_nowait(AxiStreamFrame(tdata=zeta_prime[iteration].tolist()))
        else:
            in_1_source.send_nowait(AxiStreamFrame(tdata=eta_prime[iteration].tolist()))
        in_2_source.send_nowait(AxiStreamFrame(tdata=u_prime[iteration].tolist()))

        out_1_sink.set_pause_generator(random_generator(0))  # random pauses currently breaks the simulation

        input_tasks += [
            cocotb.start_soon(in_0_source.wait()),
            cocotb.start_soon(in_1_source.wait()),
            cocotb.start_soon(in_2_source.wait()),
        ]
        output_tasks += [cocotb.start_soon(out_1_sink.recv())]

    if len(input_tasks) != 0:
        await Combine(RisingEdge(dut.done_o), *output_tasks, *input_tasks)

        await ClockCycles(dut.clk_i, 5)

        for idx, otask in enumerate(output_tasks):
            assert (
                expected_outputs[idx].flatten().tolist() == otask.result().tdata
            ), f"{expected_outputs[idx].flatten().tolist()} != {otask.result().tdata}"

    log.info("Test succeeded!")


async def gen_test_vectors(dut, iterations: int = 1) -> dict:
    RSDPG = int(dut.RSDPG.value)
    P = int(dut.P.value)
    Z = int(dut.Z.value)
    GEN = int(dut.GEN.value)
    N = int(dut.N.value)
    K = int(dut.K.value)
    T = iterations

    if RSDPG:
        M = int(dut.M.value)

    # Sample all the random inputs
    V = np.random.randint(P, size=(K, N - K), dtype=np.int32)  # sampled row-wise (we are streaming V transposed)
    log.debug(f"V: {V}")
    if RSDPG:
        W = np.random.randint(Z, size=(M, N - M), dtype=np.int32)  # sampled column-wise
        zeta = np.random.randint(Z, size=M, dtype=np.int32)
        log.debug(f"zeta: {zeta}")
        zeta_prime = []
    else:
        eta = np.random.randint(Z, size=N, dtype=np.int32)
        log.debug(f"zeta: {eta}")
    eta_prime = []
    for _ in range(T):
        if RSDPG:
            zeta_prime += [np.random.randint(Z, size=M, dtype=np.int32)]
        else:
            eta_prime += [np.random.randint(Z, size=N, dtype=np.int32)]
    if RSDPG:
        log.debug(f"zeta prime: {zeta_prime}")
    else:
        log.debug(f"eta prime: {eta_prime}")
    beta = np.random.randint(P, size=T, dtype=np.int32)
    log.debug(f"beta: {beta}")
    u_prime = []
    for _ in range(T):
        u_prime += [np.random.randint(P, size=N, dtype=np.int32)]
    log.debug(f"u prime: {u_prime}")

    # Compute the associated variables
    H = np.concatenate([V, np.identity(N - K, dtype=np.int32)], axis=0)
    log.debug(f"H: {H}")
    if RSDPG:
        Mg = np.concatenate([W, np.identity(M, dtype=np.int32)], axis=1)
        log.debug(f"Mg: {Mg}")
        eta = np.mod(np.matmul(zeta, Mg), Z)
        log.debug(f"eta: {eta}")
        for k in range(T):
            eta_prime += [np.mod(np.matmul(zeta_prime[k], Mg), Z)]  # stored internally in DUT on first computation
        log.debug(f"eta prime: {eta_prime}")

    # Keygen and Sign
    if RSDPG:
        s = await arith_op_keygen(rsdpg=True, GEN=GEN, P=P, Z=Z, N=N, M=M, K=K, V=V, eta_or_zeta=zeta, W=W)
        s_tilde, delta = await arith_op_sign_commitments_preparation(
            rsdpg=True,
            GEN=GEN,
            P=P,
            Z=Z,
            N=N,
            M=M,
            K=K,
            T=T,
            V=V,
            u_prime=u_prime,
            eta_or_zeta=zeta,
            eta_or_zeta_prime=zeta_prime,
            W=W,
        )
    else:
        s = await arith_op_keygen(rsdpg=False, GEN=GEN, P=P, Z=Z, N=N, K=K, V=V, eta_or_zeta=eta)
        s_tilde, sigma = await arith_op_sign_commitments_preparation(
            rsdpg=False, GEN=GEN, P=P, Z=Z, N=N, K=K, T=T, V=V, u_prime=u_prime, eta_or_zeta=eta, eta_or_zeta_prime=eta_prime
        )
    y = await arith_op_sign_first_round_responses(GEN=GEN, P=P, N=N, T=T, beta=beta, eta_prime=eta_prime, u_prime=u_prime)

    # Verify
    if RSDPG:
        s_tilde_ver = await arith_op_verify_case_b0(
            rsdpg=True,
            GEN=GEN,
            P=P,
            N=N,
            K=K,
            V=V,
            Z=Z,
            M=M,
            T=T,
            beta=beta,
            delta_or_sigma=delta,
            y=y,
            s=s,
            W=W,
        )
        y_ver = await arith_op_verify_case_b1(
            rsdpg=True,
            GEN=GEN,
            P=P,
            N=N,
            Z=Z,
            M=M,
            T=T,
            beta=beta,
            eta_or_zeta_prime=zeta_prime,
            u_prime=u_prime,
            W=W,
        )
    else:
        s_tilde_ver = await arith_op_verify_case_b0(
            rsdpg=False,
            GEN=GEN,
            P=P,
            Z=Z,
            N=N,
            K=K,
            V=V,
            T=T,
            beta=beta,
            delta_or_sigma=sigma,
            y=y,
            s=s,
        )
        y_ver = await arith_op_verify_case_b1(
            rsdpg=False, GEN=GEN, P=P, Z=Z, N=N, T=T, beta=beta, eta_or_zeta_prime=eta_prime, u_prime=u_prime
        )
    np.testing.assert_array_equal(s_tilde, s_tilde_ver)
    np.testing.assert_array_equal(y, y_ver)

    result = {
        "eta": eta,
        "eta_prime": eta_prime,
        "u_prime": u_prime,
        "beta": beta,
        "s": s,
        "y": y,
        "s_tilde": s_tilde,
        "V": V,
    }
    if RSDPG:
        return {
            **result,
            "zeta": zeta,
            "zeta_prime": zeta_prime,
            "delta": delta,
            "W": W,
        }
    else:
        return {
            **result,
            "sigma": sigma,
        }


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_init(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    tv = await gen_test_vectors(dut)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    start_time = get_sim_time("ns")
    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)
    # 10: 5 CC init delay + 5 CC final delay
    print(f"Execution time ARITH_OP_INIT (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_keygen(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    tv = await gen_test_vectors(dut)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    start_time = get_sim_time("ns")
    await run_test(dut, ArithOp.ARITH_OP_KEYGEN, **tv)
    # 10: 5 CC init delay + 5 CC final delay
    print(f"Execution time ARITH_OP_KEYGEN (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_sign_expand_eta(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    tv = await gen_test_vectors(dut)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    start_time = get_sim_time("ns")
    await run_test(dut, ArithOp.ARITH_OP_SIGN_EXPAND_ETA, **tv)
    # 10: 5 CC init delay + 5 CC final delay
    print(f"Execution time ARITH_OP_SIGN_EXPAND_ETA (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_sign_commitments_preparation(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    T = int(getenv("TB_ITERATIONS", 3)) # Limit the number of iterations
    tv = await gen_test_vectors(dut, iterations=T)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    for k in range(T):
        start_time = get_sim_time("ns")
        await run_test(dut, ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION, iteration=k, **tv)
        # 10: 5 CC init delay + 5 CC final delay
        print(
            f"Execution time ARITH_OP_SIGN_COMMITMENTS_PREPARATION (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}"
        )


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_sign_first_round_responses(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    T = int(getenv("TB_ITERATIONS", 3)) # Limit the number of iterations
    tv = await gen_test_vectors(dut, iterations=T)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    for k in range(T):
        await run_test(dut, ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION, iteration=k, **tv)

    for k in range(T):
        start_time = get_sim_time("ns")
        await run_test(dut, ArithOp.ARITH_OP_SIGN_FIRST_ROUND_RESPONSES, iteration=k, **tv)
        # 10: 5 CC init delay + 5 CC final delay
        print(
            f"Execution time ARITH_OP_SIGN_FIRST_ROUND_RESPONSES (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}"
        )


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_verify_b0(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    T = int(getenv("TB_ITERATIONS", 3)) # Limit the number of iterations
    tv = await gen_test_vectors(dut, iterations=T)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    for k in range(T):
        start_time = get_sim_time("ns")
        await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B0, iteration=k, **tv)
        # 10: 5 CC init delay + 5 CC final delay
        print(f"Execution time ARITH_OP_VERIFY_CASE_B0 (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def test_verify_b1(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    T = int(getenv("TB_ITERATIONS", 3)) # Limit the number of iterations
    tv = await gen_test_vectors(dut, iterations=T)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)

    for k in range(T):
        start_time = get_sim_time("ns")
        await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B1, iteration=k, **tv)
        # 10: 5 CC init delay + 5 CC final delay
        print(f"Execution time ARITH_OP_VERIFY_CASE_B1 (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=100, timeout_unit="ms", skip=environ.get("TB_EXTENDED") is None)
async def test_multiple_full_runs(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    clock = Clock(dut.clk_i, clock_period, units="ns")
    T = int(dut.T.value)
    W = int(dut.W.value)  # this is the param, not the matrix!
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    for _ in range(3):
        start_time = get_sim_time("ns")
        tv = await gen_test_vectors(dut, iterations=T)
        await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)
        await run_test(dut, ArithOp.ARITH_OP_KEYGEN, **tv)
        await run_test(dut, ArithOp.ARITH_OP_SIGN_EXPAND_ETA, **tv)
        for k in range(T):
            await run_test(dut, ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION, iteration=k, **tv)
        for k in range(T):
            await run_test(dut, ArithOp.ARITH_OP_SIGN_FIRST_ROUND_RESPONSES, iteration=k, **tv)

        # Generate a random second challenge
        ch_b = [0] * (T - W) + [1] * W
        ch_b = list(np.random.permutation(ch_b))
        ch_b = [int(b) for b in ch_b]

        for k, b_i in enumerate(ch_b):
            if b_i == 0:
                await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B0, iteration=k, **tv)
            elif b_i == 1:
                await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B1, iteration=k, **tv)
            else:
                raise RuntimeError("Invalid generation of second challenge")
        # 10: 5 CC init delay + 5 CC final delay
        print(f"Execution time (KeyGeneration + Sign + Verify) (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def test_all_opcodes(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    total_time = 0
    tv = await gen_test_vectors(dut)

    clock = Clock(dut.clk_i, clock_period, units="ns")
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    for arith_op in ArithOp:
        # We rely on the fact that the operations
        # are executed in the same definition sequence
        start_time = get_sim_time("ns")
        await run_test(dut, arith_op, **tv)
        # 10: 5 CC init delay + 5 CC final delay
        total_time += int(get_sim_time("ns") - start_time) // clock_period - 10
    print(f"Execution time (CC): {total_time}")


@cocotb.test(timeout_time=100, timeout_unit="ms", skip=environ.get("TB_EXTENDED") is None)
async def test_sign(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    clock = Clock(dut.clk_i, clock_period, units="ns")
    T = int(dut.T.value)
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    start_time = get_sim_time("ns")
    tv = await gen_test_vectors(dut, iterations=T)
    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)
    await run_test(dut, ArithOp.ARITH_OP_SIGN_EXPAND_ETA, **tv)
    for k in range(T):
        await run_test(dut, ArithOp.ARITH_OP_SIGN_COMMITMENTS_PREPARATION, iteration=k, **tv)
    for k in range(T):
        await run_test(dut, ArithOp.ARITH_OP_SIGN_FIRST_ROUND_RESPONSES, iteration=k, **tv)
    # 10: 5 CC init delay + 5 CC final delay
    print(f"Execution time Sign (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")


@cocotb.test(timeout_time=100, timeout_unit="ms", skip=environ.get("TB_EXTENDED") is None)
async def test_verify(dut):
    random.seed(cocotb.RANDOM_SEED)
    np.random.seed(cocotb.RANDOM_SEED)

    clock_period = 10
    clock = Clock(dut.clk_i, clock_period, units="ns")
    T = int(dut.T.value)
    W = int(dut.W.value)  # this is the param, not the matrix!
    cocotb.start_soon(clock.start())
    await cycle_reset(dut)  # Reset the DUT

    start_time = get_sim_time("ns")
    tv = await gen_test_vectors(dut, iterations=T)
    # Generate a random second challenge
    ch_b = [0] * (T - W) + [1] * W
    ch_b = list(np.random.permutation(ch_b))
    ch_b = [int(b) for b in ch_b]

    await run_test(dut, ArithOp.ARITH_OP_INIT, **tv)
    for k, b_i in enumerate(ch_b):
        if b_i == 0:
            await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B0, iteration=k, **tv)
        elif b_i == 1:
            await run_test(dut, ArithOp.ARITH_OP_VERIFY_CASE_B1, iteration=k, **tv)
        else:
            raise RuntimeError("Invalid generation of second challenge")
    # 10: 5 CC init delay + 5 CC final delay
    print(f"Execution time Verify (CC): {int(get_sim_time('ns') - start_time) // clock_period - 10}")
