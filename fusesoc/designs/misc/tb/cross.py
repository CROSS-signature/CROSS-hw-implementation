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

import ctypes
import os
from pathlib import Path
import re
from math import log, ceil

# Will be set by pytest
CLIB_VERSION = os.environ.get("CLIB")
N = int(os.environ.get("N"))
K = int(os.environ.get("K"))
T = int(os.environ.get("T"))
Z = int(os.environ.get("Z"))
P = int(os.environ.get("P"))
LAMBDA = int(os.environ.get("LAMBDA"))
SIGSIZE = int(os.environ.get("SIGSIZE"))
BITS_P = int(ceil(log(P, 2)))


cwd = Path(__file__).cwd().parents[1]
_cross = ctypes.CDLL(str(cwd) + '/ctypes/' + CLIB_VERSION)

_cross.test_free.argtype = ctypes.c_void_p
_cross.free.restype = None

if '_RSDP_' in CLIB_VERSION:
    RSDPG = False
    RSDP = True
    _cross.test_zz_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_zz_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_zz_zq_vecs.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_zz_zq_vecs.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_vt_w_mat.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_vt_w_mat.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_beta_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_beta_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_b_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_b_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fz_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_pack_fz_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fq_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_pack_fq_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fq_syn.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_pack_fq_syn.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_keygen.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_keygen.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_sign.argtype = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte)]
    _cross.test_sign.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_verify.argtype = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte)]
    _cross.test_verify.restype = ctypes.c_ubyte


    DENSE_FZ_BYTES = ( (N*ceil(log(Z,2)) +7) // 8 )
    DENSE_FP_BYTES = ( (N*ceil(log(P,2)) +7) // 8 )
    DENSE_SYN_BYTES = ( ((N-K)*ceil(log(P,2)) +7) // 8 )

elif '_RSDPG_' in CLIB_VERSION:
    M = int(os.environ.get("M"))
    RSDPG = True
    RSDP = False

    _cross.test_zz_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_zz_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_zz_zq_vecs.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_zz_zq_vecs.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_vt_w_mat.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_vt_w_mat.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_beta_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_beta_vec.restype = ctypes.POINTER(ctypes.c_ushort)

    _cross.test_b_vec.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_b_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fz_vec_rsdpg.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_pack_fz_vec_rsdpg.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fq_vec.argtype = ctypes.POINTER(ctypes.c_ushort)
    _cross.test_pack_fq_vec.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_pack_fq_syn.argtype = ctypes.POINTER(ctypes.c_ushort)
    _cross.test_pack_fq_syn.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_keygen.argtype = ctypes.POINTER(ctypes.c_ubyte)
    _cross.test_keygen.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_sign.argtype = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte)]
    _cross.test_sign.restype = ctypes.POINTER(ctypes.c_ubyte)

    _cross.test_verify.argtype = [ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_ubyte)]
    _cross.test_verify.restype = ctypes.c_ubyte

    DENSE_FZ_BYTES = ( (M*ceil(log(Z,2)) +7) // 8 )
    DENSE_FP_BYTES = ( (N*ceil(log(P,2)) +7) // 8 )
    DENSE_SYN_BYTES = ( ((N-K)*ceil(log(P,2)) +7) // 8 )


def test_zz_vec(seed):
    seed_type = ctypes.c_ubyte * len(seed)
    tmp = _cross.test_zz_vec(seed_type(*seed))

    if RSDPG:
        res = [tmp[i] for i in range(M)]
    else:
        res = [tmp[i] for i in range(N)]
    _cross.test_free(tmp)
    return res

def test_zz_zq_vecs(seed):
    seed_type = ctypes.c_ubyte * len(seed)
    tmp = _cross.test_zz_zq_vecs(seed_type(*seed))
    if RSDPG:
        res_zz = [tmp[i] for i in range(M)]
        res_zq = [tmp[M+2*i] + tmp[M+2*i+1]*256 for i in range(N)]
    else:
        res_zz = [tmp[i] for i in range(N)]
        res_zq = [tmp[N+i] for i in range(N)]
    _cross.test_free(tmp)
    return res_zz, res_zq

def test_vt_w_mat(seed):
    seed_type = ctypes.c_ubyte * len(seed)
    tmp = _cross.test_vt_w_mat(seed_type(*seed))
    res_vt = []
    res_w = []

    if RSDP:
        for i in range(K):
            res_vt.append([tmp[i*(N-K)+j] for j in range(N-K)])
    elif RSDPG:
        for i in range(K):
            res_vt.append([tmp[2*i*(N-K)+2*j] + tmp[2*i*(N-K)+2*j+1]*256 for j in range(N-K)])
        for i in range(M):
            res_w.append([tmp[2*K*(N-K)+i*(N-M)+j] for j in range(N-M)])
    _cross.test_free(tmp)
    return res_vt, res_w

def test_beta_vec(seed):
    seed_type = ctypes.c_ubyte * len(seed)
    tmp = _cross.test_beta_vec(seed_type(*seed))
    res = [tmp[j] for j in range(T)]
    _cross.test_free(tmp)
    return res

def test_b_vec(seed):
    seed_type = ctypes.c_ubyte * len(seed)
    tmp = _cross.test_b_vec(seed_type(*seed))
    res = ('').join([str(tmp[j]) for j in range(T)])
    _cross.test_free(tmp)
    return res

def test_pack_fz(din):
    arr = (ctypes.c_ubyte * len(din))(*din)
    if RSDP:
        tmp = _cross.test_pack_fz_vec(arr)
    elif RSDPG:
        tmp = _cross.test_pack_fz_vec_rsdpg(arr)

    res = [tmp[i] for i in range(DENSE_FZ_BYTES)]
    _cross.test_free(tmp)
    return res

def test_pack_fp(din):
    if RSDP:
        arr = (ctypes.c_ubyte * len(din))(*din)
    elif RSDPG:
        arr = (ctypes.c_ushort * len(din))(*din)

    tmp = _cross.test_pack_fq_vec(arr)
    res = [tmp[i] for i in range(DENSE_FP_BYTES)]
    _cross.test_free(tmp)
    return res

def test_pack_syn(din):
    if RSDP:
        arr = (ctypes.c_ubyte * len(din))(*din)
    elif RSDPG:
        arr = (ctypes.c_ushort * len(din))(*din)

    tmp = _cross.test_pack_fq_syn(arr)
    res = [tmp[i] for i in range(DENSE_SYN_BYTES)]
    _cross.test_free(tmp)
    return res

def test_keygen(coins):
    arr = (ctypes.c_ubyte * len(coins))(*coins)
    tmp = _cross.test_keygen(arr)

    KEYSEED_BYTES = 2*LAMBDA//8
    sk_seed = [tmp[i] for i in range(KEYSEED_BYTES)]
    pk_seed = [tmp[i+KEYSEED_BYTES] for i in range(KEYSEED_BYTES)]
    syn = [tmp[i+2*KEYSEED_BYTES] for i in range(DENSE_SYN_BYTES)]

    _cross.test_free(tmp)
    return sk_seed, pk_seed, syn

def test_sign(sk, msg, coins):
    sk_tmp = (ctypes.c_ubyte * len(sk))(*sk)
    msg_tmp = (ctypes.c_ubyte * len(msg))(*msg)
    mlen_tmp = ctypes.c_uint64(len(msg))
    coins_tmp = (ctypes.c_ubyte * len(coins))(*coins)

    tmp = _cross.test_sign(sk_tmp, msg_tmp, mlen_tmp, coins_tmp)
    res = [tmp[i] for i in range(SIGSIZE)]
    _cross.test_free(tmp)
    return res

def test_vrfy(pk, msg, sig):
    pk_tmp = (ctypes.c_ubyte * len(pk))(*pk)
    msg_tmp = (ctypes.c_ubyte * len(msg))(*msg)
    mlen_tmp = ctypes.c_uint64(len(msg))
    sig_tmp = (ctypes.c_ubyte * len(sig))(*sig)

    return _cross.test_verify(pk_tmp, msg_tmp, mlen_tmp, sig_tmp)
