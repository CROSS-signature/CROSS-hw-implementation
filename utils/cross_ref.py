#!/usr/bin/env python3
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
from math import ceil, log2


class CROSS_REF:
    dll = None
    params = None
    ref = None

    def __init__(self, parameterization=None):
        self.param = parameterization
        self.dll = parameterization.dll

        # Register c reference
        self.ref = ctypes.CDLL("./libs/" + parameterization.dll)

        # Utility for freeing memory
        self.ref.test_free.argtype = ctypes.c_void_p
        self.ref.free.restype = None

        # Keygen
        self.ref.test_keygen.argtype = ctypes.POINTER(ctypes.c_ubyte)
        self.ref.test_keygen.restype = ctypes.POINTER(ctypes.c_ubyte)

        # Sign
        self.ref.test_sign.argtype = [
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.POINTER(ctypes.c_ubyte),
        ]
        self.ref.test_sign.restype = ctypes.POINTER(ctypes.c_ubyte)

        # Verify
        self.ref.test_verify.argtype = [
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.POINTER(ctypes.c_ubyte),
        ]
        self.ref.test_verify.restype = ctypes.c_ubyte

    def test_keygen(self, coins):
        arr = (ctypes.c_ubyte * len(coins))(*coins)
        tmp = self.ref.test_keygen(arr)

        KEYSEED_BYTES = 2 * self.param.sec_margin_lambda // 8
        DENSE_SYN_BYTES = ((self.param.n - self.param.k) * ceil(log2(self.param.p)) + 7) // 8

        sk = [tmp[i] for i in range(KEYSEED_BYTES)]
        pk = tmp[KEYSEED_BYTES : 2 * KEYSEED_BYTES + DENSE_SYN_BYTES]

        self.ref.test_free(tmp)
        return sk, pk

    def test_sign(self, sk, msg, coins):
        sk_tmp = (ctypes.c_ubyte * len(sk))(*sk)
        msg_tmp = (ctypes.c_ubyte * len(msg))(*msg)
        mlen_tmp = ctypes.c_uint64(len(msg))
        coins_tmp = (ctypes.c_ubyte * len(coins))(*coins)

        tmp = self.ref.test_sign(sk_tmp, msg_tmp, mlen_tmp, coins_tmp)
        sig = [tmp[i] for i in range(self.param.sig_size)]
        self.ref.test_free(tmp)
        return sig

    def test_vrfy(self, pk, msg, sig):
        pk_tmp = (ctypes.c_ubyte * len(pk))(*pk)
        msg_tmp = (ctypes.c_ubyte * len(msg))(*msg)
        mlen_tmp = ctypes.c_uint64(len(msg))
        sig_tmp = (ctypes.c_ubyte * len(sig))(*sig)

        return self.ref.test_verify(pk_tmp, msg_tmp, mlen_tmp, sig_tmp)

    def run_test(self, coins_keygen, coins_sign, msg):
        sk, pk = self.test_keygen(coins_keygen)
        sig = self.test_sign(sk, msg, coins_sign)
        vrfy_stat = self.test_vrfy(pk, msg, sig)
        return sk, pk, sig, vrfy_stat
