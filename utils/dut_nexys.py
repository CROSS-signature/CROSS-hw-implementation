#!/usr/bin/env python
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


import random
import sys
import time
from enum import Enum
from math import ceil, log2

import serial
from cross_ref import CROSS_REF
from tqdm import tqdm


# Configuration (must correspond to FPGA Design
#############################################################
class TEST_OP(Enum):
    RND      = 0x00
    MSG_KEYS = 0x01
    SIG      = 0x02
    CTRL     = 0x03

# Opcode and start bit
class CROSS_OP(Enum):
    KEYGEN = ( 0x00 | (1 << 2) )
    SIGN   = ( 0x01 | (1 << 2) )
    VERIFY = ( 0x02 | (1 << 2) )


#############################################################

def randombytearray(n):
    return bytearray([random.getrandbits(8) for i in range(n)])


class DUT_CROSS:
    """
    foo
    """
    ser = None
    name = 'FOOO'
    param = None
    sk_len = None
    pk_len = None
    sig_len = None
    bench_iter = 1
    cross_ref = None

    def __init__(self, Port="/dev/ttyUSB0", BaudRate=115200, Timeout=5, parameterization=None, bench_iter=1, seed=None):
        try:
            self.ser = serial.Serial(port=Port, baudrate=BaudRate, timeout=Timeout, stopbits=serial.STOPBITS_ONE, bytesize=serial.EIGHTBITS)
            time.sleep(1)
        except:
            raise Exception("error opening port")

        self.name = f'{parameterization.name.lower()}_cat{parameterization.category}_{parameterization.optim_corner}'
        self.param = parameterization
        self.sk_len = 2*parameterization.sec_margin_lambda//8
        self.pk_len = int(2*parameterization.sec_margin_lambda//8 + ((parameterization.n - parameterization.k)*ceil(log2(parameterization.p))+7)//8)
        self.sig_len = parameterization.sig_size
        self.bench_iter = bench_iter
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        self.cross_ref = CROSS_REF(parameterization)
        if seed != None:
            random.seed(seed)

    def _writeByte(self, byte):
        self.ser.write(byte)

    def flush(self):
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def _read_status(self):
        foo = self.ser.read(7)

        # extract cc
        cc = 0
        for i in range(3):
            cc += int(foo[i]) << (8*i)

        # extract status
        stat = int(foo[3])

        # extract online cc
        cc_online = 0
        for i in range(3):
            cc_online += int(foo[4+i]) << (8*i)
        return stat, cc, cc_online


    def _send_rnd(self, data):
        self.ser.write(bytes([TEST_OP.RND.value]))
        self.ser.write(len(data).to_bytes(4, byteorder='little'))
        self.ser.write(bytes(data))

    def _send_msg_keys(self, data):
        self.ser.write(bytes([TEST_OP.MSG_KEYS.value]))
        self.ser.write(len(data).to_bytes(4, byteorder='little'))
        self.ser.write(bytes(data))

    def _send_sig(self, data):
        self.ser.write(bytes([TEST_OP.SIG.value]))
        self.ser.write(len(data).to_bytes(4, byteorder='little'))
        self.ser.write(bytes(data))

    def _send_ctrl(self, data):
        self.ser.write(bytes([TEST_OP.CTRL.value]))
        self.ser.write(bytes([data]))


    def keygen(self, coins):
        # send input
        self._send_rnd(coins)
        self._send_ctrl(CROSS_OP.KEYGEN.value)

        # read ouput
        sk = self.ser.read(self.sk_len)
        pk = self.ser.read(self.pk_len)
        stat, cc, _ = self._read_status()

        # check if everything is fine
        if (stat == 0):
            return bytearray(sk), bytearray(pk), cc
        else:
            sys.exit("Keygen failed.")

    def sign(self, sk, msg, coins):
        # send input
        self._send_msg_keys(sk)
        self._send_msg_keys(msg)
        self._send_rnd(coins[:self.param.sec_margin_lambda//8])
        self._send_rnd(coins[self.param.sec_margin_lambda//8:])
        self._send_ctrl(CROSS_OP.SIGN.value)

        # read ouput
        sig = self.ser.read(self.sig_len)
        stat, cc, cc_online = self._read_status()

        # check if everything is fine
        if (stat == 0):
            return bytearray(sig), cc, cc_online
        else:
            sys.exit("Sign failed.")


    def vrfy(self, pk, msg, sig):
        # send input
        self._send_msg_keys(pk)
        self._send_msg_keys(msg)
        self._send_sig(sig)
        self._send_ctrl(CROSS_OP.VERIFY.value)

        # read ouput
        stat, cc, _ = self._read_status()

        # check if everything is fine
        if (stat == 0):
            return 0, cc
        else:
            sys.exit("Verify failed.")

    def benchmark(self):
        self.flush()
        with open(self.name + '.csv', 'w') as f:
            f.write('keygen,sign,sign_online,vrfy\n')
            for _ in tqdm(range(self.bench_iter)):
                msg = randombytearray(16)
                coins_keygen = randombytearray(2*self.param.sec_margin_lambda//8)
                coins_sign = randombytearray(3*self.param.sec_margin_lambda//8)

                # Check with reference
                sk_ref, pk_ref, sig_ref, vrfy_ref = self.cross_ref.run_test(coins_keygen, coins_sign, msg)

                # Now run actual hardware implementation
                sk, pk, cc_keygen               = self.keygen(coins_keygen)
                sig, cc_sign, cc_sign_online    = self.sign(sk, msg, coins_sign)
                vrfy, cc_vrfy                   = self.vrfy(pk, msg, sig)

                # Check for compatibility with reference
                assert bytearray(sk_ref) == sk, "SK does not match!"
                assert bytearray(pk_ref) == pk, "PK does not match!"
                assert bytearray(sig_ref) == sig, "SIG does not match!"
                assert vrfy_ref == vrfy, "Vrfy does not match!"

                f.write(f'{cc_keygen},{cc_sign},{cc_sign_online},{cc_vrfy}\n')
                f.flush()
